import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/db_helper.dart';
import 'sync_remote.dart';
import 'sync_tables.dart';

class SyncReport {
  int pushed = 0;
  int pulled = 0;

  /// Rows actually inserted/updated locally (rows we just pushed are skipped).
  int applied = 0;
  int tombstonesPushed = 0;
  int removedLocal = 0;
  int conflicts = 0;
  int skipped = 0;
  final List<String> notes = [];

  /// Tables that failed in this run (table -> short reason). A run with
  /// failures keeps every change that did succeed and is retried later.
  final Map<String, String> failures = {};

  @override
  String toString() =>
      'pushed=$pushed pulled=$pulled tombstones=$tombstonesPushed '
      'removedLocal=$removedLocal conflicts=$conflicts skipped=$skipped';
}

/// The device's data was last synced with a DIFFERENT account. Nothing is
/// pushed or pulled until the user confirms (see [SyncEngine.linkAccount]).
class SyncAccountMismatch implements Exception {
  const SyncAccountMismatch();
  @override
  String toString() => 'This device was synced with another account.';
}

/// Some tables synced, some did not. Local data is untouched; retry later.
class SyncPartialFailure implements Exception {
  SyncPartialFailure(this.report);
  final SyncReport report;
  @override
  String toString() => 'Sync incomplete: ${report.failures.keys.join(', ')}';
}

/// Last-write-wins sync between the local SQLite database and a [SyncRemote].
///
/// Rules:
///  * only dirty rows / pending tombstones are pushed (idempotent upserts by
///    uuid, so a retry after a crash writes the same rows again);
///  * before pushing, the server's `client_updated_at` is checked: if the
///    server copy is newer the local copy loses (no blind overwrite);
///  * pulled rows are applied page by page inside one transaction together
///    with the cursor, so a failure leaves the database exactly as it was and
///    the next run resumes from the saved cursor;
///  * a locally edited (dirty) row that is newer than the incoming remote row
///    is kept and pushed; deletes lose against newer edits and vice versa;
///  * local data is never touched by an engine error.
///
/// Clock rule (skew guard): timestamps are compared in SERVER time. At the
/// start of every run the engine asks the server for its time and measures the
/// phone clock's offset; local edit times are shifted by that offset (and never
/// beyond "now" on the server) before they are compared with, or written as,
/// `client_updated_at`. The database additionally clamps any client timestamp
/// to now()+5 min (migration 0007). Equal timestamps: the server copy wins on
/// every device, so all devices converge on the same row.
const String _epoch = '1970-01-01T00:00:00.000Z';

class SyncEngine {
  SyncEngine({
    required this.remote,
    required this.userId,
    DatabaseHelper? helper,
    this.pageSize = 200,
    this.batchSize = 100,
    DateTime Function()? clock,
  }) : _helper = helper ?? DatabaseHelper.instance,
       _clock = clock ?? DateTime.now;

  final SyncRemote remote;
  final String userId;
  final int pageSize;
  final int batchSize;
  final DatabaseHelper _helper;
  final DateTime Function() _clock;

  final Map<String, Set<String>> _columnCache = {};
  Duration _skew = Duration.zero;

  /// Offset applied to device timestamps (visible for tests/diagnostics).
  Duration get clockSkew => _skew;

  DateTime _norm(DateTime local) {
    final shifted = local.toUtc().add(_skew);
    final ceiling = _clock().toUtc().add(_skew);
    return shifted.isAfter(ceiling) ? ceiling : shifted;
  }

  String? _normIso(Object? v) {
    final t = parseTs(v);
    return t == null ? null : _norm(t).toIso8601String();
  }

  Future<void> _measureSkew(DatabaseExecutor db) async {
    try {
      final before = _clock();
      final server = await remote.serverTime();
      final after = _clock();
      if (server == null) {
        _skew = Duration.zero;
      } else {
        final mid = before.add(after.difference(before) ~/ 2);
        _skew = server.toUtc().difference(mid.toUtc());
        // Network round-trip jitter is not a clock error: ignore tiny offsets
        // so equal timestamps stay exactly equal.
        if (_skew.abs() < const Duration(seconds: 2)) _skew = Duration.zero;
      }
    } catch (_) {
      _skew = Duration.zero;
    }
    await _setMeta(db, 'clock_skew_ms', '${_skew.inMilliseconds}');
  }

  // ------------------------------------------------------- account binding

  /// First sync binds the data to the signed-in user; a different user later
  /// needs an explicit [linkAccount] (so one person's data never silently
  /// lands in another account).
  Future<void> _bindAccount(DatabaseExecutor db) async {
    final bound = await getMeta(db, 'account_user_id');
    if (bound == null) {
      await _setMeta(db, 'account_user_id', userId);
    } else if (bound != userId) {
      throw const SyncAccountMismatch();
    }
  }

  /// Re-uploads this device's data to [userId]'s cloud: every synced row is
  /// marked dirty, tombstones and cursors of the previous account are dropped.
  static Future<void> linkAccount(DatabaseHelper helper, String? userId) async {
    final db = await helper.database;
    await db.transaction((txn) async {
      await resetSyncState(txn);
      if (userId != null) {
        await txn.insert('sync_meta', {
          'key': 'account_user_id',
          'value': userId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Forgets everything about a previous cloud account (used after account
  /// deletion and when linking another account). Local data is untouched.
  static Future<void> resetSyncState(DatabaseExecutor txn) async {
    await txn.insert('sync_meta', {
      'key': 'applying',
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      for (final spec in syncTables) {
        final cond = spec.localCondition == null
            ? ''
            : ' AND ${spec.localCondition}';
        await txn.execute(
          'UPDATE ${spec.local} SET sync_dirty = 1 '
          'WHERE sync_id IS NOT NULL$cond',
        );
      }
      await txn.delete('sync_tombstones');
      await txn.delete('sync_conflicts');
      await txn.delete('sync_meta', where: "key LIKE 'cursor:%'");
      await txn.delete(
        'sync_meta',
        where: "key IN ('last_synced_at','account_user_id','clock_skew_ms')",
      );
      await txn.execute(
        'UPDATE favourite_sync SET dirty = 1 '
        "WHERE EXISTS (SELECT 1 FROM sqlite_master WHERE name = 'favourite_sync')",
      );
    } finally {
      await txn.delete('sync_meta', where: "key = 'applying'");
    }
  }

  /// Number of local changes waiting to be uploaded.
  static Future<int> pendingChanges(DatabaseExecutor db) async {
    var n = 0;
    for (final spec in syncTables) {
      final cond = spec.localCondition == null
          ? ''
          : ' AND ${spec.localCondition}';
      n +=
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${spec.local} '
              'WHERE sync_dirty = 1 AND sync_id IS NOT NULL$cond',
            ),
          ) ??
          0;
    }
    n +=
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sync_tombstones WHERE pushed = 0',
          ),
        ) ??
        0;
    return n;
  }

  Future<SyncReport> run({bool Function()? shouldCancel}) async {
    final report = SyncReport();
    final db = await _helper.database;
    bool cancelled() => shouldCancel?.call() ?? false;

    await _bindAccount(db);
    await _measureSkew(db);
    await _assignDeterministicIds(db);

    bool parentFailed(SyncTableSpec spec, Set<String> failed) =>
        spec.parents.any((p) => failed.contains(p.parentTable));

    // PUSH (parents before children). A table that fails does not stop the
    // others, but its children are skipped (they would reference a parent that
    // is not in the cloud).
    final failed = <String>{};
    for (final spec in syncTables) {
      if (cancelled()) return report;
      if (parentFailed(spec, failed)) {
        failed.add(spec.local);
        report.failures[spec.local] = 'parent table failed';
        continue;
      }
      try {
        await _pushDirty(db, spec, report);
        await _pushTombstones(db, spec, report);
      } catch (e) {
        failed.add(spec.local);
        report.failures[spec.local] = _shortError(e);
      }
    }

    // PULL (parents before children).
    for (final spec in syncTables) {
      if (cancelled()) return report;
      if (failed.contains(spec.local) || parentFailed(spec, failed)) {
        failed.add(spec.local);
        report.failures.putIfAbsent(spec.local, () => 'parent table failed');
        continue;
      }
      try {
        await _pull(db, spec, report, cancelled);
      } catch (e) {
        failed.add(spec.local);
        report.failures[spec.local] = _shortError(e);
      }
    }

    // Two devices may both have marked a plan active: keep exactly one.
    if (!failed.contains('training_plans')) {
      try {
        if (await _enforceSingleActivePlan(db, report)) {
          await _pushDirty(db, specFor('training_plans'), report);
        }
      } catch (e) {
        report.failures['training_plans'] = _shortError(e);
      }
    }

    // Catalogue favourites (soft: an older backend without the RPC only
    // leaves a note, it never fails the whole sync).
    try {
      await _syncFavourites(db, report);
    } catch (e) {
      report.notes.add('favourites not synced: ${_shortError(e)}');
    }

    if (report.failures.isNotEmpty) {
      throw SyncPartialFailure(report);
    }

    await remote.markSynced(_clock());
    await _setMeta(db, 'last_synced_at', _clock().toUtc().toIso8601String());
    await _pruneConflictLog(db);
    return report;
  }

  String _shortError(Object e) {
    final t = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 120 ? '${t.substring(0, 120)}...' : t;
  }

  /// Returns true when a plan was deactivated (and needs pushing).
  Future<bool> _enforceSingleActivePlan(Database db, SyncReport report) async {
    final active = [
      ...await db.query(
        'training_plans',
        where: 'is_active = 1 AND deleted_at IS NULL',
      ),
    ];
    if (active.length <= 1) return false;
    active.sort((a, b) {
      final ta = parseTs(a['sync_updated_at']);
      final tb = parseTs(b['sync_updated_at']);
      final c = (tb ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        ta ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
      if (c != 0) return c; // newest first
      return '${b['sync_id']}'.compareTo('${a['sync_id']}');
    });
    final winner = active.first;
    for (final loser in active.skip(1)) {
      // A normal update (not "applying"): the trigger marks it dirty so the
      // deactivation reaches the other devices too.
      await db.update(
        'training_plans',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: [loser['id']],
      );
      await _logConflict(
        db,
        report,
        'training_plans',
        loser['sync_id'] as String?,
        'two-active-plans',
        'kept ${winner['sync_id']} active',
      );
    }
    return true;
  }

  // ------------------------------------------------------------ favourites

  Future<void> _syncFavourites(Database db, SyncReport report) async {
    if (!remote.supportsFavourites) return;
    final exists = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='favourite_sync'",
    );
    if (exists.isEmpty) return;

    final dirty = await db.query('favourite_sync', where: 'dirty = 1');
    final items = <String, dynamic>{
      for (final r in dirty)
        '${r['exercise_id']}': {
          'f': (r['is_favourite'] as int? ?? 0) == 1,
          't': _normIso(r['updated_at']),
        },
    };
    final merged = await remote.mergeFavourites(items);

    await db.transaction((txn) async {
      await _setApplying(txn, true);
      try {
        for (final e in merged.entries) {
          final id = int.tryParse(e.key);
          final v = e.value;
          if (id == null || v is! Map) continue;
          final fav = v['f'] == true ? 1 : 0;
          final ex = await txn.query(
            'exercises',
            columns: ['is_favourite', 'is_custom'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (ex.isEmpty || (ex.first['is_custom'] as int? ?? 0) == 1) continue;
          // The merged map is authoritative (newest write per exercise wins).
          if ((ex.first['is_favourite'] as int? ?? 0) != fav) {
            await txn.update(
              'exercises',
              {'is_favourite': fav},
              where: 'id = ?',
              whereArgs: [id],
            );
            report.applied++;
          }
          await txn.insert('favourite_sync', {
            'exercise_id': id,
            'is_favourite': fav,
            'updated_at': '${v['t']}',
            'dirty': 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } finally {
        await _setApplying(txn, false);
      }
    });
  }

  // ------------------------------------------------------------------ meta

  static Future<String?> getMeta(DatabaseExecutor db, String key) async {
    final r = await db.query(
      'sync_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> _setMeta(DatabaseExecutor db, String key, String? value) async {
    if (value == null) {
      await db.delete('sync_meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('sync_meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _logConflict(
    DatabaseExecutor db,
    SyncReport report,
    String table,
    String? syncId,
    String kind,
    String detail,
  ) async {
    report.conflicts++;
    await db.insert('sync_conflicts', {
      'table_name': table,
      'sync_id': syncId,
      'kind': kind,
      'detail': detail,
      'at': _clock().toUtc().toIso8601String(),
    });
  }

  Future<void> _pruneConflictLog(DatabaseExecutor db) => db.execute(
    'DELETE FROM sync_conflicts WHERE id NOT IN '
    '(SELECT id FROM sync_conflicts ORDER BY id DESC LIMIT 200)',
  );

  Future<RemoteCursor?> _cursor(DatabaseExecutor db, SyncTableSpec s) async {
    final raw = await getMeta(db, 'cursor:${s.local}');
    if (raw == null) return null;
    try {
      return RemoteCursor.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCursor(
    DatabaseExecutor db,
    SyncTableSpec s,
    RemoteCursor? c,
  ) => _setMeta(
    db,
    'cursor:${s.local}',
    c == null ? null : jsonEncode(c.toJson()),
  );

  // -------------------------------------------------------- local helpers

  Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    return _columnCache[table] ??= {
      for (final r in await db.rawQuery('PRAGMA table_info($table)'))
        r['name'] as String,
    };
  }

  Future<String?> _parentSyncId(
    DatabaseExecutor db,
    ParentRef p,
    Object? localId,
  ) async {
    if (localId == null) return null;
    final r = await db.query(
      p.parentTable,
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    return r.isEmpty ? null : r.first['sync_id'] as String?;
  }

  Future<void> _assignDeterministicIds(DatabaseExecutor db) async {
    for (final spec in syncTables) {
      final f = spec.deterministicId;
      if (f == null) continue;
      final rows = await db.query(spec.local, where: 'sync_id IS NULL');
      for (final row in rows) {
        final parents = <String, String?>{};
        var ok = true;
        for (final p in spec.parents) {
          final pid = await _parentSyncId(db, p, row[p.localCol]);
          parents[p.localCol] = pid;
          if (pid == null && !p.optional) ok = false;
        }
        if (!ok) continue;
        await db.update(
          spec.local,
          {'sync_id': deterministicUuid(f(row, parents))},
          where: 'id = ? AND sync_id IS NULL',
          whereArgs: [row['id']],
        );
      }
    }
  }

  // --------------------------------------------------------------- mapping

  Object? _toRemoteValue(ColMap c, Object? v) {
    if (v == null) return null;
    switch (c.type) {
      case ColType.boolean:
        return v == 1 || v == true;
      case ColType.real:
        return (v as num).toDouble();
      case ColType.integer:
        return (v as num).toInt();
      case ColType.timestamp:
        return tsToRemote(v);
      case ColType.text:
        return v.toString();
    }
  }

  Object? _toLocalValue(ColMap c, Object? v) {
    if (v == null) return null;
    switch (c.type) {
      case ColType.boolean:
        return (v == true || v == 1) ? 1 : 0;
      case ColType.real:
        return (v as num).toDouble();
      case ColType.integer:
        return (v as num).toInt();
      case ColType.timestamp:
        return tsFromRemote(v);
      case ColType.text:
        return v.toString();
    }
  }

  /// Returns null when a required parent has no cloud id yet.
  Future<Map<String, dynamic>?> _buildRemoteRow(
    DatabaseExecutor db,
    SyncTableSpec spec,
    Map<String, Object?> row,
  ) async {
    final remoteRow = <String, dynamic>{
      'id': row['sync_id'],
      'user_id': userId,
      'client_updated_at': _normIso(row['sync_updated_at']),
      'deleted_at': null,
    };
    for (final c in spec.cols) {
      remoteRow[c.remote] = _toRemoteValue(c, row[c.local]);
    }
    for (final p in spec.parents) {
      final pid = await _parentSyncId(db, p, row[p.localCol]);
      if (pid == null && !p.optional) return null;
      remoteRow[p.remoteCol] = pid;
    }
    await spec.toRemoteExtra?.call(db, Map.of(row), remoteRow);
    return remoteRow;
  }

  // ------------------------------------------------------------------ push

  Future<void> _pushDirty(
    Database db,
    SyncTableSpec spec,
    SyncReport report,
  ) async {
    final attempted = <Object?>{};
    final cond = spec.localCondition == null
        ? ''
        : ' AND ${spec.localCondition}';
    while (true) {
      final notIn = attempted.isEmpty
          ? ''
          : ' AND id NOT IN (${attempted.join(',')})';
      final rows = await db.query(
        spec.local,
        where: 'sync_dirty = 1 AND sync_id IS NOT NULL$cond$notIn',
        orderBy: 'id ASC',
        limit: batchSize,
      );
      if (rows.isEmpty) return;
      attempted.addAll(rows.map((r) => r['id']));

      final payload = <Map<String, dynamic>>[];
      final sources = <Map<String, Object?>>[];
      for (final r in rows) {
        final built = await _buildRemoteRow(db, spec, r);
        if (built == null) {
          report.skipped++; // parent not yet in the cloud: stays dirty
          continue;
        }
        payload.add(built);
        sources.add(r);
      }
      if (payload.isEmpty) continue;

      final meta = await remote.fetchMeta(spec.remote, [
        for (final p in payload) p['id'] as String,
      ]);
      final toUpsert = <Map<String, dynamic>>[];
      final upserted = <Map<String, Object?>>[];
      for (var i = 0; i < payload.length; i++) {
        final id = payload[i]['id'] as String;
        final src = sources[i];
        final m = meta[id];
        final localTs = parseTs(src['sync_updated_at']);
        final localN = localTs == null ? null : _norm(localTs);
        final remoteTs = m?.effective;
        if (m != null &&
            remoteTs != null &&
            localN != null &&
            !remoteTs.isBefore(localN)) {
          // Server copy is newer (or exactly as new: ties go to the server on
          // every device so they all converge). It wins: mark clean, re-pull.
          await _logConflict(
            db,
            report,
            spec.local,
            id,
            remoteTs.isAfter(localN) ? 'remote-newer' : 'tie-remote-wins',
            'local ${localN.toIso8601String()} vs remote ${remoteTs.toIso8601String()}',
          );
          // Clean, but stamped older than the cloud row so the pull below
          // really applies the cloud copy (equal stamps would look "current").
          await _markClean(db, spec, src, _epoch);
          await _saveCursor(db, spec, null);
          continue;
        }
        toUpsert.add(payload[i]);
        upserted.add(src);
      }
      if (toUpsert.isNotEmpty) {
        await remote.upsert(spec.remote, toUpsert);
        for (var i = 0; i < upserted.length; i++) {
          await _markClean(
            db,
            spec,
            upserted[i],
            toUpsert[i]['client_updated_at'] as String?,
          );
        }
        report.pushed += toUpsert.length;
      }
    }
  }

  /// Clears the dirty flag only if the row was not edited during the sync.
  Future<void> _markClean(
    Database db,
    SyncTableSpec spec,
    Map<String, Object?> src,
    String? pushedTimestamp,
  ) async {
    await db.transaction((txn) async {
      await _setApplying(txn, true);
      await txn.update(
        spec.local,
        {'sync_dirty': 0, 'sync_updated_at': ?pushedTimestamp},
        where: 'id = ? AND sync_updated_at = ?',
        whereArgs: [src['id'], src['sync_updated_at']],
      );
      await _setApplying(txn, false);
    });
  }

  Future<void> _setApplying(DatabaseExecutor db, bool on) => on
      ? db.insert('sync_meta', {
          'key': 'applying',
          'value': '1',
        }, conflictAlgorithm: ConflictAlgorithm.replace)
      : db.delete('sync_meta', where: "key = 'applying'");

  Future<void> _pushTombstones(
    Database db,
    SyncTableSpec spec,
    SyncReport report,
  ) async {
    final tombs = await db.query(
      'sync_tombstones',
      where: 'table_name = ? AND pushed = 0',
      whereArgs: [spec.local],
      limit: 500,
    );
    if (tombs.isEmpty) return;
    final ids = [for (final t in tombs) t['sync_id'] as String];
    final meta = await remote.fetchMeta(spec.remote, ids);
    for (final t in tombs) {
      final id = t['sync_id'] as String;
      final at = _norm(parseTs(t['deleted_at']) ?? _clock());
      final m = meta[id];
      if (m == null || m.deletedAt != null) {
        // Never reached the cloud, or already deleted there.
      } else if (m.effective != null && m.effective!.isAfter(at)) {
        await _logConflict(
          db,
          report,
          spec.local,
          id,
          'edit-over-delete',
          'remote edit ${m.effective!.toIso8601String()} is newer than local delete',
        );
        await _saveCursor(db, spec, null); // bring the surviving row back
      } else {
        await remote.softDelete(spec.remote, id, at);
        report.tombstonesPushed++;
      }
      await db.delete(
        'sync_tombstones',
        where: 'table_name = ? AND sync_id = ?',
        whereArgs: [spec.local, id],
      );
    }
  }

  // ------------------------------------------------------------------ pull

  Future<void> _pull(
    Database db,
    SyncTableSpec spec,
    SyncReport report,
    bool Function() cancelled,
  ) async {
    var cursor = await _cursor(db, spec);
    while (!cancelled()) {
      final page = await remote.pull(
        spec.remote,
        after: cursor,
        limit: pageSize,
      );
      if (page.rows.isEmpty) return;

      // Deletions first so replace-style updates (unique keys) apply cleanly.
      final rows = [...page.rows]
        ..sort((a, b) {
          final ad = a['deleted_at'] != null ? 0 : 1;
          final bd = b['deleted_at'] != null ? 0 : 1;
          return ad.compareTo(bd);
        });
      final last = page.rows.last;
      final next = RemoteCursor(
        last['updated_at'].toString(),
        last['id'].toString(),
      );

      await db.transaction((txn) async {
        await _setApplying(txn, true);
        try {
          for (final r in rows) {
            try {
              await _applyRow(txn, spec, r, report);
            } catch (e) {
              report.skipped++;
              await _logConflict(
                txn,
                report,
                spec.local,
                r['id']?.toString(),
                'apply-error',
                e.toString(),
              );
            }
          }
          await _saveCursor(txn, spec, next);
        } finally {
          await _setApplying(txn, false);
        }
      });
      cursor = next;
      report.pulled += rows.length;
      if (!page.hasMore) return;
    }
  }

  Future<void> _applyRow(
    DatabaseExecutor db,
    SyncTableSpec spec,
    Map<String, dynamic> r,
    SyncReport report,
  ) async {
    final id = r['id'] as String;
    final remoteTs =
        parseTs(r['client_updated_at']) ?? parseTs(r['updated_at']);
    final deleted = r['deleted_at'] != null;

    var local = (await db.query(
      spec.local,
      where: 'sync_id = ?',
      whereArgs: [id],
      limit: 1,
    )).firstOrNull;

    bool localIsNewer(Map<String, Object?> row) {
      if ((row['sync_dirty'] as int? ?? 0) != 1) return false;
      final lt = parseTs(row['sync_updated_at']);
      return lt != null && remoteTs != null && _norm(lt).isAfter(remoteTs);
    }

    if (deleted) {
      if (local == null) return;
      if (localIsNewer(local)) {
        await _logConflict(
          db,
          report,
          spec.local,
          id,
          'edit-over-delete',
          'local edit is newer than remote delete; keeping local',
        );
        return;
      }
      await db.delete(spec.local, where: 'id = ?', whereArgs: [local['id']]);
      report.removedLocal++;
      return;
    }

    // Build local values from the remote row.
    final values = <String, Object?>{};
    for (final c in spec.cols) {
      values[c.local] = _toLocalValue(c, r[c.remote]);
    }
    for (final p in spec.parents) {
      final remoteParent = r[p.remoteCol] as String?;
      if (remoteParent == null) {
        if (p.optional) {
          values[p.localCol] = null;
          continue;
        }
        throw StateError('missing parent ${p.remoteCol}');
      }
      final pr = await db.query(
        p.parentTable,
        columns: ['id'],
        where: 'sync_id = ?',
        whereArgs: [remoteParent],
        limit: 1,
      );
      if (pr.isEmpty) {
        if (p.optional) {
          values[p.localCol] = null;
          continue;
        }
        await _logConflict(
          db,
          report,
          spec.local,
          id,
          'orphan',
          'parent ${p.parentTable} $remoteParent not present locally',
        );
        return;
      }
      values[p.localCol] = pr.first['id'];
    }
    await spec.fromRemoteExtra?.call(db, values, r);

    // Natural-key collision (same date / same weekday ...).
    if (local == null && spec.uniqueKey.isNotEmpty) {
      final where = spec.uniqueKey.map((k) => '$k = ?').join(' AND ');
      final hit = (await db.query(
        spec.local,
        where: where,
        whereArgs: [for (final k in spec.uniqueKey) values[k]],
        limit: 1,
      )).firstOrNull;
      if (hit != null) {
        if (hit['sync_id'] == null) {
          local = hit; // adopt the cloud id for the existing local row
        } else if (localIsNewer(hit)) {
          await _logConflict(
            db,
            report,
            spec.local,
            id,
            'unique-key-local-newer',
            'kept local row for ${spec.uniqueKey.join('+')}',
          );
          return;
        } else {
          await db.delete(spec.local, where: 'id = ?', whereArgs: [hit['id']]);
          report.removedLocal++;
        }
      }
    }

    // Already current (typically the row we pushed a moment ago): skip.
    if (local != null &&
        (local['sync_dirty'] as int? ?? 0) == 0 &&
        remoteTs != null &&
        parseTs(local['sync_updated_at']) == remoteTs.toUtc()) {
      return;
    }

    final cols = await _columns(db, spec.local);
    final nowIso = _clock().toIso8601String();
    values['sync_id'] = id;
    values['sync_dirty'] = 0;
    values['sync_updated_at'] = (remoteTs ?? _clock())
        .toUtc()
        .toIso8601String();
    if (cols.contains('updated_at')) values['updated_at'] = nowIso;
    values.removeWhere((k, _) => !cols.contains(k));

    if (local != null) {
      if (localIsNewer(local)) {
        await _logConflict(
          db,
          report,
          spec.local,
          id,
          'local-newer',
          'kept local edit; will be pushed',
        );
        return;
      }
      await db.update(
        spec.local,
        values,
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      report.applied++;
    } else {
      if (cols.contains('created_at')) values['created_at'] ??= nowIso;
      await db.insert(spec.local, values);
      report.applied++;
    }
  }
}
