import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:reptrack/services/sync_tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

/// Turns a freshly created (v7) database back into a v6-shaped one.
Future<void> downgradeToV6(Database db) async {
  for (final r in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'trg_sync_%'",
  )) {
    await db.execute('DROP TRIGGER ${r['name']}');
  }
  for (final spec in syncTables) {
    await db.execute('DROP INDEX IF EXISTS idx_${spec.local}_sync_id');
    for (final c in ['sync_id', 'sync_updated_at', 'sync_dirty']) {
      await db.execute('ALTER TABLE ${spec.local} DROP COLUMN $c');
    }
  }
  await db.execute('ALTER TABLE exercises DROP COLUMN catalogue_archived');
  for (final t in ['sync_meta', 'sync_tombstones', 'sync_conflicts']) {
    await db.execute('DROP TABLE $t');
  }
}

void main() {
  late Database db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() async => closeTestDatabase(db));

  test('v6 -> v7 keeps every existing row and is idempotent', () async {
    await downgradeToV6(db);
    final routinesBefore = await db.query('routines', orderBy: 'id');
    final exercisesBefore = (await db.query('exercises')).length;
    final plansBefore = await db.query('workout_plans', orderBy: 'id');
    final sid = await db.insert('workout_sessions', {
      'date': '2026-01-05',
      'start_time': '07:00',
      'duration_seconds': 3000,
      'primary_muscle': 'Chest',
      'created_at': '2026-01-05T07:00:00',
    });
    await db.insert('workout_sets', {
      'session_id': sid,
      'exercise_id': 1,
      'exercise_name': 'Barbell Bench Press',
      'set_number': 1,
      'reps': 8,
      'weight_kg': 62.5,
      'is_completed': 1,
      'completed_at': '2026-01-05T07:10:00',
    });

    await DatabaseHelper.instance.upgradeForTesting(db, 6, 7);
    await DatabaseHelper.instance.upgradeForTesting(db, 6, 7); // twice

    // data untouched
    final routinesAfter = await db.query('routines', orderBy: 'id');
    expect(routinesAfter.length, routinesBefore.length);
    for (var i = 0; i < routinesBefore.length; i++) {
      for (final k in routinesBefore[i].keys) {
        expect(routinesAfter[i][k], routinesBefore[i][k], reason: k);
      }
    }
    expect((await db.query('exercises')).length, exercisesBefore);
    expect((await db.query('workout_plans')).length, plansBefore.length);
    final set = (await db.query('workout_sets')).single;
    expect(set['weight_kg'], 62.5);

    // bookkeeping: everything is queued for the first premium sync
    expect(
      routinesAfter.every((r) => r['sync_id'] != null && r['sync_dirty'] == 1),
      isTrue,
    );
    final ids = routinesAfter.map((r) => r['sync_id']).toSet();
    expect(ids.length, routinesAfter.length, reason: 'ids are unique');
    // deterministic-id tables keep a null id until the engine derives it
    expect(
      (await db.query('workout_plans'))
          .every((r) => r['sync_id'] == null && r['sync_dirty'] == 1),
      isTrue,
    );
    // catalogue exercises are not tracked
    expect(
      (await db.query(
        'exercises',
        where: 'is_custom = 0',
      )).every((r) => r['sync_dirty'] == 0),
      isTrue,
    );
    // triggers are alive again
    await db.update(
      'routines',
      {'title': 'x'},
      where: 'id = ?',
      whereArgs: [routinesAfter.first['id']],
    );
    expect((await db.query('sync_tombstones')), isEmpty);
    await db.delete(
      'routines',
      where: 'id = ?',
      whereArgs: [routinesAfter.first['id']],
    );
    expect((await db.query('sync_tombstones')).length, 1);
  });

  test(
    'fresh installs already have the v7 schema and working triggers',
    () async {
      final cols = (await db.rawQuery('PRAGMA table_info(routines)'))
          .map((r) => r['name']);
      expect(cols, containsAll(['sync_id', 'sync_updated_at', 'sync_dirty']));
      expect(DatabaseHelper.schemaVersion, 7);
    },
  );
}
