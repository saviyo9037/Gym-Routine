import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

/// Regression: a custom exercise created while the catalogue was smaller used
/// to be overwritten when a later catalogue release claimed the same id.
void main() {
  late Database db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() => closeTestDatabase(db));

  Future<void> makeCollision() async {
    final cat = (await db.query('exercises', where: 'id = 150')).single;
    await db.delete('exercises', where: 'id = 150');
    await db.insert('exercises', {
      'id': 150,
      'muscle_group_id': 1,
      'muscle_group_name': 'Chest',
      'name': 'My Cable Crush',
      'target': 'Chest',
      'description': 'mine',
      'instructions': 'mine',
      'equipment': 'Cable',
      'is_custom': 1,
      'personal_notes': 'mine only',
      'created_at': '2026-01-01T00:00:00',
    });
    await db.insert('planned_exercises', {
      'plan_id': 1,
      'exercise_id': 150,
      'exercise_name': 'My Cable Crush',
    });
    await db.insert('workout_sets', {
      'session_id': 1,
      'exercise_id': 150,
      'exercise_name': 'My Cable Crush',
      'set_number': 1,
      'reps': 10,
      'weight_kg': 20,
      'completed_at': 'x',
    });
    await db.insert('media_attachments', {
      'entity_type': 'exercise',
      'entity_id': 150,
      'media_type': 'photo',
      'file_path': '/p.jpg',
      'created_at': 'x',
    });
    expect(cat['name'], isNot('My Cable Crush'));
  }

  test('custom exercise on a catalogue id is moved, not overwritten', () async {
    await makeCollision();
    await DatabaseHelper.instance.syncCatalogue(db);

    final custom = (await db.query(
      'exercises',
      where: "name = 'My Cable Crush'",
    )).single;
    expect(custom['id'], greaterThan(100000));
    expect(custom['is_custom'], 1);
    expect(custom['description'], 'mine');
    expect(custom['personal_notes'], 'mine only');
    final newId = custom['id'];

    final catalogue = await db.query('exercises', where: 'id = 150');
    expect(catalogue.single['is_custom'], 0);
    expect(catalogue.single['name'], isNot('My Cable Crush'));
    expect((await db.query('exercises')).length, 202);

    expect(
      (await db.query(
        'planned_exercises',
        where: "exercise_name = 'My Cable Crush'",
      )).single['exercise_id'],
      newId,
    );
    expect(
      (await db.query(
        'workout_sets',
        where: "exercise_name = 'My Cable Crush'",
      )).single['exercise_id'],
      newId,
    );
    expect((await db.query('media_attachments')).single['entity_id'], newId);

    // Idempotent: syncing again moves nothing and duplicates nothing.
    await DatabaseHelper.instance.syncCatalogue(db);
    expect((await db.query('exercises')).length, 202);
    expect(
      (await db.query(
        'exercises',
        where: "name = 'My Cable Crush'",
      )).single['id'],
      newId,
    );
  });

  test(
    'a custom exercise named like a catalogue exercise is left alone',
    () async {
      final name =
          (await db.query('exercises', where: 'id = 10')).single['name']
              as String;
      await db.insert('exercises', {
        'muscle_group_id': 1,
        'muscle_group_name': 'Chest',
        'name': name,
        'target': 'x',
        'description': 'my version',
        'instructions': 'my version',
        'equipment': 'x',
        'is_custom': 1,
        'created_at': '2026-01-01T00:00:00',
      });
      await DatabaseHelper.instance.syncCatalogue(db);
      final rows = await db.query(
        'exercises',
        where: 'name = ?',
        whereArgs: [name],
      );
      expect(rows.length, 2);
      expect(
        rows.where((r) => r['is_custom'] == 1).single['description'],
        'my version',
      );
      expect(rows.where((r) => r['is_custom'] == 0).length, 1);
    },
  );
}
