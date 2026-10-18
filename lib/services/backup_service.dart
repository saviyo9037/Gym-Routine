import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app_info.dart';
import '../core/clock.dart';
import '../data/db_helper.dart';
import 'database_service.dart';
import 'routine_service.dart';

/// Why a backup file was refused. [code] is stable for UI/tests.
class BackupException implements Exception {
  const BackupException(this.code, this.message);

  /// `not_json`, `not_a_backup`, `unsupported_format`, `schema_too_new`,
  /// `missing_table`, `bad_rows`, `checksum_mismatch`.
  final String code;
  final String message;

  @override
  String toString() => 'BackupException($code): $message';
}

/// A parsed, structurally validated backup (nothing has touched the DB yet).
class BackupFile {
  BackupFile({
    required this.formatVersion,
    required this.schemaVersion,
    required this.tables,
    this.appVersion,
    this.exportedAt,
    this.legacy = false,
  });

  /// 3 for files written by [BackupService.exportJson]; 1/2 for legacy files.
  final int formatVersion;
  final int schemaVersion;
  final String? appVersion;
  final String? exportedAt;
  final bool legacy;
  final Map<String, List<Map<String, Object?>>> tables;

  int rowCount(String table) => tables[table]?.length ?? 0;
}

class TableChange {
  int added = 0;
  int updated = 0;
  int skipped = 0;

  bool get isEmpty => added == 0 && updated == 0;

  @override
  String toString() => '+$added ~$updated =$skipped';
}

/// Dry-run summary of what a merge would do (also returned after applying).
class ImportPlan {
  final Map<String, TableChange> tables = {};
  final List<String> warnings = [];

  TableChange of(String table) => tables.putIfAbsent(table, TableChange.new);

  int get totalAdded => tables.values.fold(0, (n, t) => n + t.added);
  int get totalUpdated => tables.values.fold(0, (n, t) => n + t.updated);
  int get totalSkipped => tables.values.fold(0, (n, t) => n + t.skipped);
  bool get hasChanges => totalAdded + totalUpdated > 0;
}

class ImportResult {
  const ImportResult({required this.ok, required this.plan, this.error});
  final bool ok;
  final ImportPlan plan;
  final String? error;
}

/// Versioned local backup: export, validated import (replace or merge).
///
/// * Export (format 3) = envelope with `format_version`, `schema_version`,
///   `app_version`, per-table `counts` and a SHA-256 `checksum` of `tables`.
/// * Legacy files (flat, `version` 1/2) are still accepted.
/// * **Merge** never deletes anything and never overwrites a local row unless
///   the backup copy is strictly newer (`updated_at`); ids are remapped through
///   natural keys, so existing plans/sessions/routines are never clobbered.
/// * **Replace** swaps all user tables in one transaction (all-or-nothing).
/// * Both require `confirmed: true` so a UI cannot import silently; show
///   [planMerge] first.
class BackupService {
  BackupService({DatabaseHelper? helper})
    : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  static const String formatName = 'reptrack-backup';
  static const int formatVersion = 3;

  static const List<String> tableOrder = DatabaseService.backupTables;

  static const _requiredTables = [
    'muscle_groups',
    'exercises',
    'workout_plans',
    'planned_exercises',
    'workout_sessions',
    'workout_sets',
  ];

  /// Columns never written from a backup in merge mode.
  static const _syncCols = {'sync_id', 'sync_updated_at', 'sync_dirty'};

  /// Settings that describe this install and must not be imported.
  static const _internalSettings = {'default_routines_seeded'};

  // ------------------------------------------------------------- export

  Future<String> exportJson() async {
    final db = await _helper.database;
    final tables = <String, Object?>{};
    final counts = <String, int>{};
    for (final t in tableOrder) {
      final rows = await db.query(t);
      tables[t] = [
        for (final r in rows)
          {
            for (final e in r.entries)
              if (e.key != 'sync_dirty') e.key: e.value,
          },
      ];
      counts[t] = rows.length;
    }
    final tablesJson = jsonEncode(tables);
    final schema = (await db.rawQuery('PRAGMA user_version'))
        .first
        .values
        .first;
    return jsonEncode({
      'format': formatName,
      'format_version': formatVersion,
      'schema_version': schema is int ? schema : DatabaseHelper.schemaVersion,
      'app_version': kAppVersion,
      'exported_at': AppClock.now().toIso8601String(),
      'counts': counts,
      'checksum': 'sha256:${sha256.convert(utf8.encode(tablesJson))}',
      'tables': tables,
    });
  }

  // -------------------------------------------------------------- parse

  /// Structural validation only; throws [BackupException].
  BackupFile parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const BackupException('not_json', 'The file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupException(
        'not_a_backup',
        'This is not a RepTrack backup.',
      );
    }

    Map<String, dynamic> rawTables;
    int fmt;
    int schema;
    String? appVersion;
    String? exportedAt;
    var legacy = false;

    if (decoded['format'] == formatName) {
      final f = decoded['format_version'];
      if (f is! int || f < 3) {
        throw const BackupException(
          'unsupported_format',
          'Unknown backup format.',
        );
      }
      if (f > formatVersion) {
        throw BackupException(
          'unsupported_format',
          'This backup was made by a newer version of RepTrack (format $f).',
        );
      }
      fmt = f;
      final s = decoded['schema_version'];
      schema = s is int ? s : 0;
      if (schema > DatabaseHelper.schemaVersion) {
        throw BackupException(
          'schema_too_new',
          'This backup uses database version $schema; this app supports '
              '${DatabaseHelper.schemaVersion}. Update RepTrack first.',
        );
      }
      final t = decoded['tables'];
      if (t is! Map<String, dynamic>) {
        throw const BackupException(
          'bad_rows',
          'The backup has no data section.',
        );
      }
      rawTables = t;
      final checksum = decoded['checksum'];
      if (checksum is String) {
        final actual =
            'sha256:${sha256.convert(utf8.encode(jsonEncode(rawTables)))}';
        if (checksum != actual) {
          throw const BackupException(
            'checksum_mismatch',
            'The backup is damaged or was edited (checksum does not match).',
          );
        }
      } else {
        throw const BackupException(
          'checksum_mismatch',
          'The backup has no checksum.',
        );
      }
      appVersion = decoded['app_version'] as String?;
      exportedAt = decoded['exported_at'] as String?;
    } else if (decoded['version'] is int) {
      // Legacy flat file (formats 1 and 2).
      final v = decoded['version'] as int;
      if (v < 1 || v > 2) {
        throw const BackupException(
          'unsupported_format',
          'Unknown backup version.',
        );
      }
      legacy = true;
      fmt = v;
      schema = v == 1 ? 5 : 6;
      rawTables = decoded;
      exportedAt = decoded['exported_at'] as String?;
    } else {
      throw const BackupException(
        'not_a_backup',
        'This is not a RepTrack backup.',
      );
    }

    for (final t in _requiredTables) {
      if (rawTables[t] is! List) {
        throw BackupException('missing_table', 'The backup is missing "$t".');
      }
    }

    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in tableOrder) {
      final raw = rawTables[t];
      if (raw == null) {
        tables[t] = const [];
        continue;
      }
      if (raw is! List) {
        throw BackupException('bad_rows', 'Table "$t" is malformed.');
      }
      final rows = <Map<String, Object?>>[];
      for (final item in raw) {
        if (item is! Map) {
          throw BackupException('bad_rows', 'Table "$t" has an invalid row.');
        }
        final row = <String, Object?>{};
        for (final e in item.entries) {
          final v = e.value;
          if (e.key is! String || (v != null && v is! num && v is! String)) {
            throw BackupException(
              'bad_rows',
              'Table "$t" has an unsupported value.',
            );
          }
          row[e.key as String] = v;
        }
        rows.add(row);
      }
      tables[t] = rows;
    }

    return BackupFile(
      formatVersion: fmt,
      schemaVersion: schema,
      appVersion: appVersion,
      exportedAt: exportedAt,
      legacy: legacy,
      tables: tables,
    );
  }

  // ---------------------------------------------------------- replace

  /// Destroys the current user data and installs the backup, atomically.
  /// [confirmed] must be true (the UI must have asked the user).
  Future<ImportResult> applyReplace(
    BackupFile file, {
    required bool confirmed,
  }) async {
    final plan = ImportPlan();
    if (!confirmed) {
      return ImportResult(ok: false, plan: plan, error: 'not confirmed');
    }
    try {
      final db = await _helper.database;
      final columns = await _columns(db, tableOrder);
      await db.transaction((txn) async {
        for (final t in tableOrder.reversed) {
          await txn.delete(t);
        }
        for (final t in tableOrder) {
          for (final row in file.tables[t] ?? const []) {
            final clean = <String, Object?>{
              for (final e in row.entries)
                if (columns[t]!.contains(e.key) && e.key != 'sync_dirty')
                  e.key: e.value,
            };
            await txn.insert(
              t,
              clean,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            plan.of(t).added++;
          }
        }
        // Rows that came back with their old sync_id are not deletions.
        await _dropTombstonesForLiveRows(txn);
      });
      await _rescheduleAlarms();
      return ImportResult(ok: true, plan: plan);
    } catch (e) {
      return ImportResult(ok: false, plan: ImportPlan(), error: '$e');
    }
  }

  Future<void> _dropTombstonesForLiveRows(Transaction txn) async {
    try {
      for (final t in tableOrder) {
        final info = await txn.rawQuery('PRAGMA table_info($t)');
        if (!info.any((c) => c['name'] == 'sync_id')) continue;
        await txn.execute(
          'DELETE FROM sync_tombstones WHERE table_name = ? AND sync_id IN '
          '(SELECT sync_id FROM $t WHERE sync_id IS NOT NULL)',
          [t],
        );
      }
    } catch (_) {
      // Sync tables do not exist (very old schema): nothing to clean.
    }
  }

  Future<void> _rescheduleAlarms() async {
    try {
      await RoutineService().rescheduleAllRoutines();
    } catch (_) {}
  }

  // ------------------------------------------------------------ merge

  /// Dry run: what [applyMerge] would add / update / skip. Writes nothing.
  Future<ImportPlan> planMerge(BackupFile file) async {
    final db = await _helper.database;
    final plan = ImportPlan();
    await db.transaction((txn) async {
      await _merge(txn, file, plan, apply: false);
    });
    return plan;
  }

  /// Merges the backup into the current data (see class docs). Idempotent:
  /// importing the same file twice changes nothing the second time.
  Future<ImportResult> applyMerge(
    BackupFile file, {
    required bool confirmed,
  }) async {
    if (!confirmed) {
      return ImportResult(
        ok: false,
        plan: ImportPlan(),
        error: 'not confirmed',
      );
    }
    final plan = ImportPlan();
    try {
      final db = await _helper.database;
      await db.transaction((txn) async {
        await _merge(txn, file, plan, apply: true);
      });
      await _rescheduleAlarms();
      return ImportResult(ok: true, plan: plan);
    } catch (e) {
      return ImportResult(ok: false, plan: ImportPlan(), error: '$e');
    }
  }

  Future<Map<String, Set<String>>> _columns(
    DatabaseExecutor db,
    List<String> tables,
  ) async {
    final out = <String, Set<String>>{};
    for (final t in tables) {
      final info = await db.rawQuery('PRAGMA table_info($t)');
      out[t] = {for (final c in info) c['name'] as String};
    }
    return out;
  }

  static DateTime _ts(Object? v) {
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool _newer(Object? incoming, Object? existing) =>
      _ts(incoming).isAfter(_ts(existing));

  static String _s(Object? v) => (v as String? ?? '').trim().toLowerCase();

  Future<void> _merge(
    Transaction txn,
    BackupFile f,
    ImportPlan plan, {
    required bool apply,
  }) async {
    final cols = await _columns(txn, tableOrder);
    var placeholder = 0; // fake ids while only planning

    Map<String, Object?> clean(
      String table,
      Map<String, Object?> row, {
      Set<String> drop = const {},
    }) => {
      for (final e in row.entries)
        if (cols[table]!.contains(e.key) &&
            e.key != 'id' &&
            !_syncCols.contains(e.key) &&
            !drop.contains(e.key))
          e.key: e.value,
    };

    Future<int> insert(String table, Map<String, Object?> values) async {
      if (!apply) return --placeholder;
      return txn.insert(table, values);
    }

    Future<void> update(
      String table,
      Map<String, Object?> values,
      int id,
    ) async {
      if (!apply || values.isEmpty) return;
      await txn.update(table, values, where: 'id = ?', whereArgs: [id]);
    }

    final exerciseMap = <int, int>{};
    final planMap = <int, int>{};
    final sessionMap = <int, int>{};
    final routineMap = <int, int>{};

    // ---- catalogue tables: never merged (the app's own seed data) ----
    plan.of('muscle_groups').skipped += f.rowCount('muscle_groups');

    // ---- exercises ----
    final localEx = await txn.query('exercises');
    final localById = {for (final r in localEx) r['id'] as int: r};
    final localCustomByName = {
      for (final r in localEx)
        if ((r['is_custom'] as int? ?? 0) == 1) _s(r['name']): r,
    };
    for (final b in f.tables['exercises'] ?? const []) {
      final bid = b['id'] as int?;
      final custom = (b['is_custom'] as num? ?? 0) == 1;
      if (!custom) {
        // Catalogue exercise: ids are stable. Only the user's own fields merge.
        final local = bid == null ? null : localById[bid];
        if (bid != null) exerciseMap[bid] = bid;
        if (local == null) {
          plan.of('exercises').skipped++;
          continue;
        }
        final patch = <String, Object?>{};
        final favB = (b['is_favourite'] as num? ?? 0).toInt();
        final favL = (local['is_favourite'] as num? ?? 0).toInt();
        if (favB == 1 && favL == 0) patch['is_favourite'] = 1;
        final noteB = (b['personal_notes'] as String? ?? '').trim();
        final noteL = (local['personal_notes'] as String? ?? '').trim();
        if (noteB.isNotEmpty &&
            noteB != noteL &&
            (noteL.isEmpty || _newer(b['updated_at'], local['updated_at']))) {
          patch['personal_notes'] = noteB;
        }
        if (patch.isEmpty) {
          plan.of('exercises').skipped++;
        } else {
          await update('exercises', patch, bid!);
          plan.of('exercises').updated++;
        }
        continue;
      }
      final match = localCustomByName[_s(b['name'])];
      if (match != null) {
        exerciseMap[bid ?? -1] = match['id'] as int;
        if (_newer(b['updated_at'], match['updated_at'])) {
          await update(
            'exercises',
            clean('exercises', b, drop: {'created_at'}),
            match['id'] as int,
          );
          plan.of('exercises').updated++;
        } else {
          plan.of('exercises').skipped++;
        }
      } else {
        final id = await insert('exercises', clean('exercises', b));
        if (bid != null) exerciseMap[bid] = id;
        plan.of('exercises').added++;
        localCustomByName[_s(b['name'])] = {'id': id, 'name': b['name']};
      }
    }
    int? remapEx(Object? v) {
      final id = (v as num?)?.toInt();
      if (id == null) return null;
      return exerciseMap[id] ?? id;
    }

    // ---- dated workout plans (+ exercises) ----
    final backupPlanEx = <int, List<Map<String, Object?>>>{};
    for (final pe in f.tables['planned_exercises'] ?? const []) {
      final pid = (pe['plan_id'] as num?)?.toInt();
      if (pid != null) backupPlanEx.putIfAbsent(pid, () => []).add(pe);
    }
    Future<void> writePlanExercises(int newPlanId, int bPlanId) async {
      for (final pe in backupPlanEx[bPlanId] ?? const []) {
        final row = clean(
          'planned_exercises',
          pe,
          drop: {'plan_id', 'exercise_id'},
        );
        row['plan_id'] = newPlanId;
        row['exercise_id'] = remapEx(pe['exercise_id']) ?? 0;
        await insert('planned_exercises', row);
        plan.of('planned_exercises').added++;
      }
    }

    final localPlans = await txn.query('workout_plans');
    final localPlanByDate = {
      for (final r in localPlans) r['date'] as String: r,
    };
    for (final b in f.tables['workout_plans'] ?? const []) {
      final bid = (b['id'] as num?)?.toInt() ?? -1;
      final date = b['date'] as String?;
      if (date == null) {
        plan.of('workout_plans').skipped++;
        continue;
      }
      final local = localPlanByDate[date];
      if (local == null) {
        final id = await insert('workout_plans', clean('workout_plans', b));
        planMap[bid] = id;
        plan.of('workout_plans').added++;
        await writePlanExercises(id, bid);
      } else {
        planMap[bid] = local['id'] as int;
        final completedB = (b['is_completed'] as num? ?? 0) == 1;
        final completedL = (local['is_completed'] as num? ?? 0) == 1;
        if (_newer(b['updated_at'], local['updated_at'])) {
          await update(
            'workout_plans',
            clean('workout_plans', b, drop: {'date', 'created_at'}),
            local['id'] as int,
          );
          if (apply) {
            await txn.delete(
              'planned_exercises',
              where: 'plan_id = ?',
              whereArgs: [local['id']],
            );
          }
          await writePlanExercises(local['id'] as int, bid);
          plan.of('workout_plans').updated++;
        } else {
          if (completedB && !completedL) {
            // A finished day is never "un-finished" or lost: mark it done.
            await update('workout_plans', {
              'is_completed': 1,
            }, local['id'] as int);
            plan.of('workout_plans').updated++;
          } else {
            plan.of('workout_plans').skipped++;
          }
        }
      }
    }
    int? remapPlan(Object? v) {
      final id = (v as num?)?.toInt();
      if (id == null) return null;
      return planMap[id];
    }

    // ---- sessions (+ sets): history is immutable, new ones only ----
    final localSessions = await txn.query('workout_sessions');
    final knownRefs = <String, int>{
      for (final r in localSessions)
        if (r['client_ref'] != null) r['client_ref'] as String: r['id'] as int,
    };
    final knownKeys = <String, int>{
      for (final r in localSessions)
        '${r['date']}|${r['start_time']}|${r['created_at']}': r['id'] as int,
    };
    final newSessionIds = <int>{};
    final backupSets = <int, List<Map<String, Object?>>>{};
    for (final s in f.tables['workout_sets'] ?? const []) {
      final sid = (s['session_id'] as num?)?.toInt();
      if (sid != null) backupSets.putIfAbsent(sid, () => []).add(s);
    }
    for (final b in f.tables['workout_sessions'] ?? const []) {
      final bid = (b['id'] as num?)?.toInt() ?? -1;
      final ref = b['client_ref'] as String?;
      final key = '${b['date']}|${b['start_time']}|${b['created_at']}';
      final existingId =
          (ref != null ? knownRefs[ref] : null) ?? knownKeys[key];
      if (existingId != null) {
        // Already here: never touched, but later rows (media) must still map to it.
        sessionMap[bid] = existingId;
        plan.of('workout_sessions').skipped++;
        continue;
      }
      final row = clean('workout_sessions', b, drop: {'plan_id'});
      row['plan_id'] = remapPlan(b['plan_id']);
      final id = await insert('workout_sessions', row);
      sessionMap[bid] = id;
      newSessionIds.add(bid);
      if (ref != null) knownRefs[ref] = id;
      knownKeys[key] = id;
      plan.of('workout_sessions').added++;
      for (final s in backupSets[bid] ?? const []) {
        final srow = clean(
          'workout_sets',
          s,
          drop: {'session_id', 'exercise_id'},
        );
        srow['session_id'] = id;
        srow['exercise_id'] = remapEx(s['exercise_id']) ?? 0;
        await insert('workout_sets', srow);
        plan.of('workout_sets').added++;
      }
    }
    // sets of sessions that already existed are not touched
    for (final e in backupSets.entries) {
      if (!newSessionIds.contains(e.key)) {
        plan.of('workout_sets').skipped += e.value.length;
      }
    }

    // ---- routines + completions ----
    final localRoutines = await txn.query('routines');
    final routineByKey = {
      for (final r in localRoutines) '${_s(r['title'])}|${r['start_time']}': r,
    };
    for (final b in f.tables['routines'] ?? const []) {
      final bid = (b['id'] as num?)?.toInt() ?? -1;
      final key = '${_s(b['title'])}|${b['start_time']}';
      final local = routineByKey[key];
      if (local == null) {
        final id = await insert('routines', clean('routines', b));
        routineMap[bid] = id;
        routineByKey[key] = {
          'id': id,
          'title': b['title'],
          'start_time': b['start_time'],
        };
        plan.of('routines').added++;
      } else {
        routineMap[bid] = local['id'] as int;
        if (_newer(b['updated_at'], local['updated_at'])) {
          await update(
            'routines',
            clean('routines', b, drop: {'created_at'}),
            local['id'] as int,
          );
          plan.of('routines').updated++;
        } else {
          plan.of('routines').skipped++;
        }
      }
    }
    final localCompletions = await txn.query('routine_completions');
    final completionByKey = {
      for (final r in localCompletions) '${r['routine_id']}|${r['date']}': r,
    };
    for (final b in f.tables['routine_completions'] ?? const []) {
      final rid = routineMap[(b['routine_id'] as num?)?.toInt() ?? -1];
      if (rid == null) {
        plan.of('routine_completions').skipped++;
        continue;
      }
      final key = '$rid|${b['date']}';
      final local = completionByKey[key];
      if (local == null) {
        final row = clean('routine_completions', b, drop: {'routine_id'});
        row['routine_id'] = rid;
        await insert('routine_completions', row);
        completionByKey[key] = {'routine_id': rid, 'date': b['date']};
        plan.of('routine_completions').added++;
      } else if (_newer(b['completed_at'], local['completed_at']) &&
          (b['status'] != local['status'])) {
        await update('routine_completions', {
          'status': b['status'],
          'notes': b['notes'],
          'completed_at': b['completed_at'],
        }, local['id'] as int);
        plan.of('routine_completions').updated++;
      } else {
        plan.of('routine_completions').skipped++;
      }
    }

    // ---- training plans (+ days + exercises) ----
    final localTp = await txn.query(
      'training_plans',
      where: 'deleted_at IS NULL',
    );
    final tpByName = {for (final r in localTp) _s(r['name']): r};
    final bDays = <int, List<Map<String, Object?>>>{};
    for (final d in f.tables['training_plan_days'] ?? const []) {
      final pid = (d['plan_id'] as num?)?.toInt();
      if (pid != null) bDays.putIfAbsent(pid, () => []).add(d);
    }
    final bDayEx = <int, List<Map<String, Object?>>>{};
    for (final e in f.tables['training_plan_day_exercises'] ?? const []) {
      final did = (e['day_id'] as num?)?.toInt();
      if (did != null) bDayEx.putIfAbsent(did, () => []).add(e);
    }
    Future<void> writeTpChildren(int newPlanId, int bPlanId) async {
      for (final d in bDays[bPlanId] ?? const []) {
        final drow = clean('training_plan_days', d, drop: {'plan_id'});
        drow['plan_id'] = newPlanId;
        final newDay = await insert('training_plan_days', drow);
        plan.of('training_plan_days').added++;
        for (final e in bDayEx[(d['id'] as num?)?.toInt() ?? -1] ?? const []) {
          final erow = clean(
            'training_plan_day_exercises',
            e,
            drop: {'day_id', 'exercise_id'},
          );
          erow['day_id'] = newDay;
          erow['exercise_id'] = remapEx(e['exercise_id']) ?? 0;
          await insert('training_plan_day_exercises', erow);
          plan.of('training_plan_day_exercises').added++;
        }
      }
    }

    for (final b in f.tables['training_plans'] ?? const []) {
      final bid = (b['id'] as num?)?.toInt() ?? -1;
      if (b['deleted_at'] != null) {
        plan.of('training_plans').skipped++; // deleted plans are not imported
        continue;
      }
      final local = tpByName[_s(b['name'])];
      if (local == null) {
        final row = clean(
          'training_plans',
          b,
          drop: {'is_active', 'deleted_at'},
        );
        row['is_active'] = 0; // never silently change the active plan
        final id = await insert('training_plans', row);
        await writeTpChildren(id, bid);
        tpByName[_s(b['name'])] = {'id': id, 'name': b['name']};
        plan.of('training_plans').added++;
      } else if (_newer(b['updated_at'], local['updated_at'])) {
        final lid = local['id'] as int;
        await update(
          'training_plans',
          clean(
            'training_plans',
            b,
            drop: {'is_active', 'deleted_at', 'created_at'},
          ),
          lid,
        );
        if (apply) {
          final oldDays = await txn.query(
            'training_plan_days',
            columns: ['id'],
            where: 'plan_id = ?',
            whereArgs: [lid],
          );
          for (final d in oldDays) {
            await txn.delete(
              'training_plan_day_exercises',
              where: 'day_id = ?',
              whereArgs: [d['id']],
            );
          }
          await txn.delete(
            'training_plan_days',
            where: 'plan_id = ?',
            whereArgs: [lid],
          );
        }
        await writeTpChildren(lid, bid);
        plan.of('training_plans').updated++;
      } else {
        plan.of('training_plans').skipped++;
      }
    }

    // ---- change logs, media, settings ----
    final localLogs = await txn.query('plan_change_logs');
    final logKeys = {
      for (final r in localLogs)
        '${r['plan_date']}|${r['changed_at']}|${r['change_description']}',
    };
    for (final b in f.tables['plan_change_logs'] ?? const []) {
      final key =
          '${b['plan_date']}|${b['changed_at']}|${b['change_description']}';
      if (logKeys.contains(key)) {
        plan.of('plan_change_logs').skipped++;
        continue;
      }
      final row = clean('plan_change_logs', b, drop: {'plan_id'});
      row['plan_id'] =
          remapPlan(b['plan_id']) ?? (b['plan_id'] as num?)?.toInt() ?? 0;
      await insert('plan_change_logs', row);
      logKeys.add(key);
      plan.of('plan_change_logs').added++;
    }

    final localMedia = await txn.query('media_attachments');
    final mediaKeys = {
      for (final r in localMedia)
        '${r['entity_type']}|${r['entity_id']}|${r['file_path']}',
    };
    for (final b in f.tables['media_attachments'] ?? const []) {
      final type = b['entity_type'] as String? ?? '';
      final oldId = (b['entity_id'] as num?)?.toInt() ?? 0;
      final newId = switch (type) {
        'exercise' => exerciseMap[oldId] ?? oldId,
        'session' => sessionMap[oldId] ?? oldId,
        'plan' => planMap[oldId] ?? oldId,
        'routine' => routineMap[oldId] ?? oldId,
        _ => oldId,
      };
      final key = '$type|$newId|${b['file_path']}';
      if (mediaKeys.contains(key)) {
        plan.of('media_attachments').skipped++;
        continue;
      }
      final row = clean('media_attachments', b, drop: {'entity_id'});
      row['entity_id'] = newId;
      await insert('media_attachments', row);
      mediaKeys.add(key);
      plan.of('media_attachments').added++;
    }
    if ((f.tables['media_attachments'] ?? const []).isNotEmpty) {
      plan.warnings.add(
        'Attachment records are imported, but the photo/video/audio files '
        'themselves live on the other device and are not part of the backup.',
      );
    }

    final localSettings = await txn.query('user_settings');
    final settingKeys = {for (final r in localSettings) r['key'] as String};
    for (final b in f.tables['user_settings'] ?? const []) {
      final k = b['key'] as String?;
      if (k == null ||
          _internalSettings.contains(k) ||
          settingKeys.contains(k)) {
        plan.of('user_settings').skipped++;
        continue;
      }
      if (apply) {
        await txn.insert('user_settings', {'key': k, 'value': b['value']});
      }
      settingKeys.add(k);
      plan.of('user_settings').added++;
    }
  }
}
