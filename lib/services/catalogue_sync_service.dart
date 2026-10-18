import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/db_helper.dart';

/// Source of the admin-managed catalogue.
abstract class CatalogueRemote {
  /// Highest published catalogue version.
  Future<int> latestVersion();

  /// Catalogue rows after the keyset position (`catalogue_version`, `id`):
  /// `version > afterVersion OR (version = afterVersion AND id > afterId)`
  /// (archived rows included so removals propagate), ordered by version then
  /// id, at most [limit]. A keyset (not just a version) is required because a
  /// single published version can hold more rows than one page.
  Future<List<Map<String, dynamic>>> fetchDelta(
    int afterVersion, {
    int afterId = 0,
    int limit = 500,
  });

  /// Published media rows for one exercise (metadata only).
  Future<List<Map<String, dynamic>>> mediaFor(int exerciseId);

  Future<String?> signedUrl(String storagePath);
}

class CatalogueSyncResult {
  int applied = 0;
  int inserted = 0;
  int archived = 0;
  int skippedCustomCollision = 0;
  int fromVersion = 0;
  int toVersion = 0;
  bool get changed => applied > 0 || archived > 0;
}

/// Merges catalogue deltas into the local `exercises` table.
///
/// Guarantees (tested): rows are matched by the stable integer exercise id;
/// user-created exercises (`is_custom = 1`) and plans/sessions are never
/// touched; favourites, personal notes/photos and local images are preserved;
/// the stored version only advances after the whole delta was applied in one
/// transaction. Media is never downloaded here.
class CatalogueSyncService {
  CatalogueSyncService(this._remote, {DatabaseHelper? helper})
    : _helper = helper ?? DatabaseHelper.instance;

  static const versionKey = 'catalogue_version';

  /// SQL fragment for list/picker queries: catalogue exercises the admin has
  /// archived are hidden from NEW choices (plans/history that already use
  /// them keep working).
  static const visibleExercisesWhere = 'catalogue_archived = 0';
  static const _pageSize = 500;
  static int get pageSize => _pageSize;
  final CatalogueRemote _remote;
  final DatabaseHelper _helper;

  Future<int> localVersion() async {
    final db = await _helper.database;
    final r = await db.query(
      'sync_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [versionKey],
      limit: 1,
    );
    return r.isEmpty ? 0 : int.tryParse('${r.first['value']}') ?? 0;
  }

  Future<CatalogueSyncResult> sync() async {
    final result = CatalogueSyncResult();
    final db = await _helper.database;
    final local = await localVersion();
    result.fromVersion = local;
    result.toVersion = local;
    final latest = await _remote.latestVersion();
    if (latest <= local) return result;

    // Page by (version, id) until a short page: a 500-row cap can never drop
    // rows, and nothing is applied until every page arrived.
    final rows = <Map<String, dynamic>>[];
    var afterVersion = local;
    var afterId = 0;
    while (true) {
      final page = await _remote.fetchDelta(
        afterVersion,
        afterId: afterId,
        limit: _pageSize,
      );
      if (page.isEmpty) break;
      rows.addAll(page);
      final last = page.last;
      afterVersion = (last['catalogue_version'] as num).toInt();
      afterId = (last['id'] as num).toInt();
      if (page.length < _pageSize) break;
    }

    await db.transaction((txn) async {
      for (final r in rows) {
        await _merge(txn, r, result);
      }
      var newVersion = latest;
      for (final r in rows) {
        final v = (r['catalogue_version'] as num?)?.toInt() ?? 0;
        if (v > newVersion) newVersion = v;
      }
      await txn.insert('sync_meta', {
        'key': versionKey,
        'value': '$newVersion',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      result.toVersion = newVersion;
    });
    return result;
  }

  Future<void> _merge(
    DatabaseExecutor txn,
    Map<String, dynamic> r,
    CatalogueSyncResult result,
  ) async {
    final id = (r['id'] as num).toInt();
    final existing = (await txn.query(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    )).firstOrNull;

    if (existing != null && (existing['is_custom'] as int? ?? 0) == 1) {
      // A user-created exercise already owns this id: never overwrite it.
      result.skippedCustomCollision++;
      return;
    }

    if (r['status'] == 'archived') {
      if (existing != null) {
        await txn.update(
          'exercises',
          {'catalogue_archived': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        result.archived++;
      }
      return;
    }

    final group = r['primary_muscle_group'] as String?;
    var groupId = (existing?['muscle_group_id'] as int?) ?? 0;
    if (group != null) {
      final g = await txn.query(
        'muscle_groups',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [group],
        limit: 1,
      );
      if (g.isNotEmpty) groupId = g.first['id'] as int;
    }

    final now = DateTime.now().toIso8601String();
    // Deliberately absent: is_favourite, personal_notes, personal_photo_path,
    // trainer_instructions, image_path and is_custom keep the user's values.
    final values = <String, Object?>{
      'muscle_group_id': groupId,
      'muscle_group_name': group,
      'name': r['name'],
      'secondary_muscles': r['secondary_muscles'] ?? '',
      'target': r['target'] ?? '',
      'description': r['description'] ?? '',
      'starting_position': r['starting_position'] ?? '',
      'instructions': r['instructions'] ?? '',
      'breathing_guidance': r['breathing_guidance'] ?? '',
      'beginner_modification': r['beginner_modification'] ?? '',
      'equipment': r['equipment'] ?? '',
      'difficulty': r['difficulty'] ?? 'Intermediate',
      'suggested_sets_reps': r['suggested_sets_reps'] ?? '',
      'common_mistakes': r['common_mistakes'] ?? '',
      'default_sets': (r['default_sets'] as num?)?.toInt() ?? 3,
      'default_reps': (r['default_reps'] as num?)?.toInt() ?? 10,
      'default_weight_kg': (r['default_weight_kg'] as num?)?.toDouble() ?? 15.0,
      'rest_seconds': (r['rest_seconds'] as num?)?.toInt() ?? 90,
      'is_compound': r['is_compound'] == true ? 1 : 0,
      'is_recommended': r['is_recommended'] == false ? 0 : 1,
      'catalogue_archived': 0,
      'updated_at': now,
    };

    if (existing == null) {
      await txn.insert('exercises', {
        'id': id,
        ...values,
        'is_custom': 0,
        'is_favourite': 0,
        'created_at': now,
      });
      result.inserted++;
    } else {
      await txn.update('exercises', values, where: 'id = ?', whereArgs: [id]);
    }
    result.applied++;
  }

  // -------------------------------------------------- media (on demand only)

  Future<List<Map<String, dynamic>>> mediaFor(int exerciseId) =>
      _remote.mediaFor(exerciseId);

  /// Downloads ONE media file when the user asks for it. Returns the local
  /// path, or null when it could not be fetched. Never called automatically.
  Future<String?> downloadMedia(Map<String, dynamic> media) async {
    final path = media['storage_path'] as String?;
    if (path == null) return null;
    final url = await _remote.signedUrl(path);
    // Never fetch media over plain http.
    if (url == null || !url.startsWith('https://')) {
      return null;
    }
    final dir = await getApplicationDocumentsDirectory();
    final target = File(
      p.join(
        dir.path,
        'cloud_media',
        '${int.tryParse('${media['exercise_id']}') ?? 0}', // numeric only: no path tricks
        p.basename(path),
      ),
    );
    await target.parent.create(recursive: true);
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final tmp = File('${target.path}.part');
      await res.pipe(tmp.openWrite());
      await tmp.rename(target.path);
      return target.path;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}

class SupabaseCatalogueRemote implements CatalogueRemote {
  SupabaseCatalogueRemote(this._client);
  final SupabaseClient _client;

  @override
  Future<int> latestVersion() async {
    final rows = await _client
        .from('catalogue_versions')
        .select('version')
        .order('version', ascending: false)
        .limit(1);
    if (rows.isEmpty) return 0;
    return (rows.first['version'] as num).toInt();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDelta(
    int afterVersion, {
    int afterId = 0,
    int limit = 500,
  }) async {
    final rows = await _client
        .from('exercises_catalog')
        .select()
        .or(
          'catalogue_version.gt.$afterVersion,'
          'and(catalogue_version.eq.$afterVersion,id.gt.$afterId)',
        )
        .order('catalogue_version', ascending: true)
        .order('id', ascending: true)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> mediaFor(int exerciseId) async {
    final rows = await _client
        .from('exercise_media')
        .select()
        .eq('exercise_id', exerciseId)
        .eq('status', 'published');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<String?> signedUrl(String storagePath) async {
    try {
      return await _client.storage
          .from('exercise-media')
          .createSignedUrl(storagePath, 3600);
    } catch (_) {
      return null;
    }
  }
}
