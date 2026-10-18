import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Upgrades a database built at EVERY schema version to the current one with
/// realistic user data and checks that nothing is lost or duplicated.
///
/// Version sources:
///  * v5  = `_onCreate` of the first repository commit (fa88326), unchanged in
///          b6037e5 and 6e80f47 (git history has only version 5).
///  * v1-v4 = reconstructed from the `onUpgrade` branches of that file
///          (columns added at v2/v3/v5 removed, routine tables absent before v4).
///          RECONSTRUCTED, not extracted from a published build.
///  * v6  = the current schema with every v7 artefact stripped again.
///  * v7  = current (covered by the other tests and by the upgrade-twice runs).

const _mg = '''
  CREATE TABLE muscle_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    image_path TEXT,
    is_custom INTEGER DEFAULT 0,
    created_at TEXT NOT NULL
  )''';

// (column ddl, version that added it)
const _exerciseCols = <(String, int)>[
  ('id INTEGER PRIMARY KEY AUTOINCREMENT', 1),
  ('muscle_group_id INTEGER NOT NULL', 1),
  ('muscle_group_name TEXT', 1),
  ('secondary_muscles TEXT', 3),
  ('name TEXT NOT NULL', 1),
  ('target TEXT', 1),
  ('description TEXT', 1),
  ('starting_position TEXT', 3),
  ('instructions TEXT', 1),
  ('breathing_guidance TEXT', 3),
  ('beginner_modification TEXT', 3),
  ('equipment TEXT', 1),
  ("difficulty TEXT DEFAULT 'Intermediate'", 2),
  ('suggested_sets_reps TEXT', 1),
  ('common_mistakes TEXT', 1),
  ('default_sets INTEGER DEFAULT 3', 1),
  ('default_reps INTEGER DEFAULT 10', 1),
  ('default_weight_kg REAL DEFAULT 15.0', 1),
  ('rest_seconds INTEGER DEFAULT 90', 1),
  ('image_path TEXT', 1),
  ('personal_photo_path TEXT', 1),
  ('personal_notes TEXT', 1),
  ('trainer_instructions TEXT', 1),
  ('is_compound INTEGER DEFAULT 0', 3),
  ('is_custom INTEGER DEFAULT 0', 1),
  ('is_recommended INTEGER DEFAULT 1', 2),
  ('is_favourite INTEGER DEFAULT 0', 2),
  ('created_at TEXT NOT NULL', 1),
  ('updated_at TEXT', 2),
];

const _routineCols = <(String, int)>[
  ('id INTEGER PRIMARY KEY AUTOINCREMENT', 4),
  ('title TEXT NOT NULL', 4),
  ('category TEXT NOT NULL', 4),
  ('start_time TEXT NOT NULL', 4),
  ('end_time TEXT NOT NULL', 4),
  ('repeat_days TEXT NOT NULL', 4),
  ('notes TEXT', 4),
  ('food_details TEXT', 5),
  ('is_reminder_enabled INTEGER DEFAULT 1', 4),
  ('reminder_minutes_before INTEGER DEFAULT 10', 4),
  ("alarm_type TEXT DEFAULT 'notification'", 5),
  ('is_alarm_enabled INTEGER DEFAULT 1', 5),
  ("sound_name TEXT DEFAULT 'Digital Beep'", 5),
  ('is_vibration_enabled INTEGER DEFAULT 1', 5),
  ('snooze_minutes INTEGER DEFAULT 10', 5),
  ('is_enabled INTEGER DEFAULT 1', 4),
  ('color_hex TEXT', 4),
  ('created_at TEXT NOT NULL', 4),
  ('updated_at TEXT NOT NULL', 4),
];

String _table(String name, List<(String, int)> cols, int version) =>
    'CREATE TABLE $name (${[for (final c in cols)
      if (c.$2 <= version) c.$1].join(', ')}'
    '${name == 'exercises' ? ', FOREIGN KEY (muscle_group_id) REFERENCES muscle_groups(id) ON DELETE CASCADE' : ''})';

const _common = [
  '''CREATE TABLE workout_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL UNIQUE,
    primary_muscle_id INTEGER, primary_muscle_name TEXT, secondary_muscle_id INTEGER,
    secondary_muscle_name TEXT, notes TEXT, trainer_instructions TEXT,
    is_completed INTEGER DEFAULT 0, is_rest_day INTEGER DEFAULT 0,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
  '''CREATE TABLE planned_exercises (
    id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL, exercise_id INTEGER NOT NULL,
    exercise_name TEXT NOT NULL, muscle_group_name TEXT, exercise_order INTEGER DEFAULT 0,
    target_sets INTEGER DEFAULT 3, target_reps INTEGER DEFAULT 10, target_weight_kg REAL DEFAULT 15.0,
    rest_seconds INTEGER DEFAULT 90, notes TEXT, image_path TEXT,
    FOREIGN KEY (plan_id) REFERENCES workout_plans(id) ON DELETE CASCADE,
    FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)''',
  '''CREATE TABLE workout_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER, date TEXT NOT NULL,
    start_time TEXT NOT NULL, end_time TEXT, duration_seconds INTEGER DEFAULT 0,
    primary_muscle TEXT NOT NULL, secondary_muscle TEXT, notes TEXT, created_at TEXT NOT NULL)''',
  '''CREATE TABLE workout_sets (
    id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER NOT NULL, exercise_id INTEGER NOT NULL,
    exercise_name TEXT NOT NULL, set_number INTEGER NOT NULL, reps INTEGER NOT NULL,
    weight_kg REAL NOT NULL, is_completed INTEGER DEFAULT 1, completed_at TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE)''',
  '''CREATE TABLE media_attachments (
    id INTEGER PRIMARY KEY AUTOINCREMENT, entity_type TEXT NOT NULL, entity_id INTEGER NOT NULL,
    media_type TEXT NOT NULL, file_path TEXT NOT NULL, title TEXT, description TEXT,
    duration_seconds INTEGER, created_at TEXT NOT NULL)''',
  '''CREATE TABLE plan_change_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL, plan_date TEXT NOT NULL,
    change_description TEXT NOT NULL, reason TEXT, changed_at TEXT NOT NULL)''',
  'CREATE TABLE user_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
];

const _completions = '''CREATE TABLE routine_completions (
    id INTEGER PRIMARY KEY AUTOINCREMENT, routine_id INTEGER NOT NULL, date TEXT NOT NULL,
    status TEXT NOT NULL, notes TEXT, completed_at TEXT NOT NULL,
    FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE,
    UNIQUE(routine_id, date))''';

Future<Database> _openLegacy(int version) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute(_mg);
  await db.execute(_table('exercises', _exerciseCols, version));
  for (final ddl in _common) {
    await db.execute(ddl);
  }
  if (version >= 4) {
    await db.execute(_table('routines', _routineCols, version));
    await db.execute(_completions);
  }
  return db;
}

/// A real v6 database: the current schema with every v7 artefact removed.
Future<Database> _openV6() async {
  sqfliteFfiInit();
  final db = await DatabaseHelper.instance.openForTesting(
    databaseFactoryFfi,
    inMemoryDatabasePath,
  );
  final triggers = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'trg_sync_%'",
  );
  for (final t in triggers) {
    await db.execute('DROP TRIGGER ${t['name']}');
  }
  final idx = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%_sync_id'",
  );
  for (final i in idx) {
    await db.execute('DROP INDEX ${i['name']}');
  }
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  for (final t in tables) {
    final name = t['name'] as String;
    if (name.startsWith('sync_')) continue;
    final info = await db.rawQuery('PRAGMA table_info($name)');
    for (final c in info) {
      final col = c['name'] as String;
      if (col == 'sync_id' ||
          col == 'sync_updated_at' ||
          col == 'sync_dirty' ||
          (name == 'exercises' && col == 'catalogue_archived')) {
        await db.execute('ALTER TABLE $name DROP COLUMN $col');
      }
    }
  }
  for (final t in ['sync_meta', 'sync_tombstones', 'sync_conflicts']) {
    await db.execute('DROP TABLE $t');
  }
  // Wipe seeded data so only the test's "user" data exists.
  for (final t in [
    'planned_exercises',
    'workout_plans',
    'routine_completions',
    'routines',
    'user_settings',
  ]) {
    await db.delete(t);
  }
  return db;
}

Future<void> _insertAvailable(
  Database db,
  String table,
  Map<String, Object?> row,
) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  final cols = {for (final c in info) c['name'] as String};
  final values = {
    for (final e in row.entries)
      if (cols.contains(e.key)) e.key: e.value,
  };
  // v6 databases already contain the seeded catalogue: customise those rows.
  if ((table == 'exercises' || table == 'muscle_groups') &&
      values['id'] != null) {
    final existing = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [values['id']],
    );
    if (existing.isNotEmpty) {
      final patch = {...values}..remove('id');
      if (table == 'muscle_groups') return;
      await db.update(table, patch, where: 'id = ?', whereArgs: [values['id']]);
      return;
    }
  }
  await db.insert(table, values);
}

/// Realistic user data written with only the columns that exist at [version].
Future<void> _seedUserData(Database db, int version) async {
  const now = '2026-09-01T07:00:00';
  // Muscle groups the user data points at (catalogue ids).
  for (final (id, name) in [(1, 'Chest'), (6, 'Biceps'), (9, 'Quadriceps')]) {
    await _insertAvailable(db, 'muscle_groups', {
      'id': id,
      'name': name,
      'created_at': now,
    });
  }
  // Catalogue rows (stable ids) the user has customised + two custom exercises.
  for (final (id, name, mg, group) in [
    (1, 'Barbell Bench Press', 1, 'Chest'),
    (69, 'Standing Dumbbell Curl', 6, 'Biceps'),
    (119, 'Barbell Back Squat', 9, 'Quadriceps'),
  ]) {
    await _insertAvailable(db, 'exercises', {
      'id': id,
      'muscle_group_id': mg,
      'muscle_group_name': group,
      'name': name,
      'target': group,
      'description': 'd',
      'instructions': 'i',
      'equipment': 'Barbell',
      'is_favourite': id == 1 ? 1 : 0,
      'personal_notes': id == 69 ? 'elbows in, slow negative' : null,
      'created_at': now,
      'updated_at': now,
    });
  }
  for (final (name, mg, group) in [
    ('Zercher Squat (mine)', 9, 'Quadriceps'),
    ('Farmer Curl (mine)', 6, 'Biceps'),
  ]) {
    await _insertAvailable(db, 'exercises', {
      'muscle_group_id': mg,
      'muscle_group_name': group,
      'name': name,
      'target': group,
      'description': 'my own',
      'instructions': 'my own',
      'equipment': 'Barbell',
      'is_custom': 1,
      'personal_notes': 'custom note for $name',
      'created_at': now,
      'updated_at': now,
    });
  }
  // Plans
  final p1 = await db.insert('workout_plans', {
    'date': '2026-09-02',
    'primary_muscle_id': 1,
    'primary_muscle_name': 'Chest',
    'notes': 'push day',
    'is_completed': 1,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('workout_plans', {
    'date': '2026-09-03',
    'is_rest_day': 1,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('planned_exercises', {
    'plan_id': p1,
    'exercise_id': 1,
    'exercise_name': 'Barbell Bench Press',
    'muscle_group_name': 'Chest',
    'target_sets': 4,
    'target_reps': 6,
    'target_weight_kg': 62.5,
  });
  await db.insert('planned_exercises', {
    'plan_id': p1,
    'exercise_id': 69,
    'exercise_name': 'Standing Dumbbell Curl',
    'exercise_order': 1,
    'target_weight_kg': 12.5,
  });
  await db.insert('plan_change_logs', {
    'plan_id': p1,
    'plan_date': '2026-09-02',
    'change_description': 'swapped incline for flat',
    'changed_at': now,
  });
  // Sessions + sets (one partially completed)
  final s1 = await db.insert('workout_sessions', {
    'plan_id': p1,
    'date': '2026-09-02',
    'start_time': '18:00',
    'end_time': '19:05',
    'duration_seconds': 3900,
    'primary_muscle': 'Chest',
    'created_at': '2026-09-02T19:05:00',
  });
  for (var i = 1; i <= 3; i++) {
    await db.insert('workout_sets', {
      'session_id': s1,
      'exercise_id': 1,
      'exercise_name': 'Barbell Bench Press',
      'set_number': i,
      'reps': 6,
      'weight_kg': 62.5 + i,
      'is_completed': i == 3 ? 0 : 1,
      'completed_at': '2026-09-02T18:1$i:00',
    });
  }
  final s2 = await db.insert('workout_sessions', {
    'date': '2026-09-05',
    'start_time': '07:00',
    'duration_seconds': 1800,
    'primary_muscle': 'Biceps',
    'created_at': '2026-09-05T07:30:00',
  });
  await db.insert('workout_sets', {
    'session_id': s2,
    'exercise_id': 69,
    'exercise_name': 'Standing Dumbbell Curl',
    'set_number': 1,
    'reps': 10,
    'weight_kg': 12.5,
    'completed_at': '2026-09-05T07:10:00',
  });
  await db.insert('media_attachments', {
    'entity_type': 'session',
    'entity_id': s1,
    'media_type': 'photo',
    'file_path': '/data/user/0/app/files/p1.jpg',
    'created_at': now,
  });
  await db.insert('media_attachments', {
    'entity_type': 'exercise',
    'entity_id': 69,
    'media_type': 'audio',
    'file_path': '/data/user/0/app/files/cue.m4a',
    'duration_seconds': 12,
    'created_at': now,
  });
  await db.insert('user_settings', {'key': 'weight_unit', 'value': 'kg'});
  await db.insert('user_settings', {'key': 'theme_mode', 'value': 'dark'});
  await db.insert('user_settings', {'key': 'my_custom_setting', 'value': 'x'});
  if (version >= 4) {
    final r1 = await db.insert(
      'routines',
      _routineRow('My morning stretch', '06:30', '06:45', '1,2,3,4,5'),
    );
    await db.insert(
      'routines',
      _routineRow('Sleep', '22:30', '06:30', '1,2,3,4,5,6,7'),
    );
    await db.insert(
      'routines',
      _routineRow('Creatine', '09:00', '09:05', '1,2,3,4,5,6,7'),
    );
    await db.insert('routine_completions', {
      'routine_id': r1,
      'date': '2026-09-02',
      'status': 'completed',
      'completed_at': '2026-09-02T06:50:00',
    });
    await db.insert('routine_completions', {
      'routine_id': r1,
      'date': '2026-09-03',
      'status': 'skipped',
      'completed_at': '2026-09-03T08:00:00',
    });
  }
}

Map<String, Object?> _routineRow(
  String title,
  String start,
  String end,
  String days,
) => {
  'title': title,
  'category': 'Personal',
  'start_time': start,
  'end_time': end,
  'repeat_days': days,
  'created_at': '2026-09-01T07:00:00',
  'updated_at': '2026-09-01T07:00:00',
};

const _userTables = [
  'workout_plans',
  'planned_exercises',
  'workout_sessions',
  'workout_sets',
  'media_attachments',
  'plan_change_logs',
  'user_settings',
  'routines',
  'routine_completions',
];

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  Database db,
  int version,
) async {
  final out = <String, List<Map<String, Object?>>>{};
  for (final t in _userTables) {
    if ((t == 'routines' || t == 'routine_completions') && version < 4) {
      continue;
    }
    final rows = await db.query(
      t,
      orderBy: t == 'user_settings' ? 'key' : 'id',
    );
    out[t] = [
      for (final r in rows)
        // the seeding flag is bookkeeping written by the app, not user data
        if (!(t == 'user_settings' && r['key'] == 'default_routines_seeded'))
          {
            for (final e in r.entries)
              if (!e.key.startsWith('sync_')) e.key: e.value,
          },
    ];
  }
  return out;
}

Future<Map<String, int>> _counts(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
    "AND name NOT IN ('sync_meta','sync_tombstones','sync_conflicts') ORDER BY name",
  );
  return {
    for (final t in tables)
      t['name'] as String: (await db.query(t['name'] as String)).length,
  };
}

Future<void> _upgradeAndCheck(Database db, int from) async {
  final before = await _snapshot(db, from);
  final favBefore = from >= 2;
  final helper = DatabaseHelper.instance;

  await helper.upgradeForTesting(db, from, DatabaseHelper.schemaVersion);
  // The app runs this on every open (see DatabaseHelper._initDatabase).
  await helper.syncCatalogue(db);

  // -- nothing lost or changed in user tables (compare old columns only)
  final after = await _snapshot(db, from < 4 ? 4 : from);
  for (final t in before.keys) {
    expect(
      after[t]!.length,
      before[t]!.length,
      reason: '$t row count (v$from)',
    );
    for (var i = 0; i < before[t]!.length; i++) {
      for (final e in before[t]![i].entries) {
        expect(
          after[t]![i][e.key],
          e.value,
          reason: '$t[$i].${e.key} (v$from)',
        );
      }
    }
  }

  // -- exercises: favourites / notes / custom rows kept, no duplicates
  final ex = await db.query('exercises');
  expect(ex.where((r) => r['name'] == 'Barbell Bench Press').length, 1);
  expect(ex.where((r) => r['id'] == 69).length, 1);
  final byName = {for (final r in ex) r['name']: r};
  if (favBefore) {
    expect(byName['Barbell Bench Press']!['is_favourite'], 1);
  }
  expect(
    byName['Standing Dumbbell Curl']!['personal_notes'],
    'elbows in, slow negative',
  );
  final custom = ex.where((r) => r['is_custom'] == 1).toList();
  expect(custom.map((r) => r['name']).toSet(), {
    'Zercher Squat (mine)',
    'Farmer Curl (mine)',
  });
  expect(
    custom.firstWhere(
      (r) => r['name'] == 'Zercher Squat (mine)',
    )['personal_notes'],
    'custom note for Zercher Squat (mine)',
  );
  expect(ex.length, 201 + 2, reason: '201 catalogue + 2 custom (v$from)');
  expect((await db.query('muscle_groups')).length, 15);

  // -- v6/v7 artefacts exist
  for (final t in [
    'training_plans',
    'training_plan_days',
    'active_sessions',
    'sync_tombstones',
  ]) {
    final found = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      [t],
    );
    expect(found.length, 1, reason: 'table $t exists (v$from)');
  }
  final sessions = await db.query('workout_sessions');
  expect(sessions.every((r) => r['client_ref'] == null), isTrue);
  expect(
    sessions.every((r) => r['sync_id'] != null && r['sync_dirty'] == 1),
    isTrue,
    reason: 'existing history is queued for the first premium sync (v$from)',
  );

  // -- seeding twice and upgrading twice change nothing
  final snap1 = await _counts(db);
  final data1 = await _snapshot(db, 4);
  await helper.syncCatalogue(db);
  await helper.syncCatalogue(db);
  await helper.upgradeForTesting(db, from, DatabaseHelper.schemaVersion);
  await helper.upgradeForTesting(
    db,
    DatabaseHelper.schemaVersion - 1,
    DatabaseHelper.schemaVersion,
  );
  expect(
    await _counts(db),
    snap1,
    reason: 'row counts after re-seed/re-upgrade (v$from)',
  );
  final data2 = await _snapshot(db, 4);
  expect(data2, data1, reason: 'user data after re-seed/re-upgrade (v$from)');
}

void main() {
  for (final v in [1, 2, 3, 4, 5]) {
    test(
      'upgrade from schema v$v${v == 5 ? ' (as in repository history)' : ' (reconstructed)'} '
      'keeps all user data and is idempotent',
      () async {
        final db = await _openLegacy(v);
        await _seedUserData(db, v);
        await _upgradeAndCheck(db, v);
        if (v < 4) {
          // Routine tables did not exist: the 9 starter routines are seeded once.
          expect((await db.query('routines')).length, 9);
        } else {
          // The user's own routines are exactly what they were: no starter set.
          expect((await db.query('routines')).length, 3);
        }
        await db.close();
      },
    );
  }

  test(
    'upgrade from schema v6 (current schema minus v7) keeps all user data',
    () async {
      final db = await _openV6();
      await _seedUserData(db, 6);
      // v6-only data: a training plan and an active workout.
      final tp = await db.insert('training_plans', {
        'name': 'My PPL',
        'is_active': 1,
        'created_at': '2026-09-01T07:00:00',
        'updated_at': '2026-09-01T07:00:00',
      });
      final day = await db.insert('training_plan_days', {
        'plan_id': tp,
        'weekday': 1,
        'is_rest': 0,
      });
      await db.insert('training_plan_day_exercises', {
        'day_id': day,
        'exercise_id': 1,
        'exercise_name': 'Barbell Bench Press',
        'target_sets': 4,
        'target_reps': 6,
        'target_weight_kg': 62.5,
      });
      await db.insert('active_sessions', {
        'id': 1,
        'client_ref': 'abc',
        'state_json': '{}',
        'started_at': 'x',
        'updated_at': 'x',
      });
      await db.insert('workout_sessions', {
        'date': '2026-09-06',
        'start_time': '08:00',
        'primary_muscle': 'Legs',
        'created_at': '2026-09-06T08:30:00',
        'client_ref': 'ref-1',
      });
      final sessionsBefore = (await db.query('workout_sessions')).length;

      await _upgradeAndCheckV6(db);

      expect((await db.query('training_plans')).single['name'], 'My PPL');
      expect((await db.query('training_plan_days')).length, 1);
      expect((await db.query('training_plan_day_exercises')).length, 1);
      expect((await db.query('active_sessions')).single['client_ref'], 'abc');
      final s = await db.query('workout_sessions');
      expect(s.length, sessionsBefore);
      expect(s.where((r) => r['client_ref'] == 'ref-1').length, 1);
      await db.close();
    },
  );

  test('current schema v7 reopened (upgrade 7 -> 7) changes nothing', () async {
    final db = await _openV6();
    await DatabaseHelper.instance.upgradeForTesting(db, 6, 7);
    await _seedUserData(db, 7);
    final before = await _counts(db);
    final data = await _snapshot(db, 7);
    await DatabaseHelper.instance.upgradeForTesting(db, 7, 7);
    await DatabaseHelper.instance.syncCatalogue(db);
    await DatabaseHelper.instance.syncCatalogue(db);
    expect((await _counts(db))['workout_sessions'], before['workout_sessions']);
    expect(await _snapshot(db, 7), data);
    await db.close();
  });
}

/// v6 variant of the shared checks (user tables already carry v6 columns).
Future<void> _upgradeAndCheckV6(Database db) async {
  final before = await _snapshot(db, 6);
  final helper = DatabaseHelper.instance;
  await helper.upgradeForTesting(db, 6, DatabaseHelper.schemaVersion);
  await helper.syncCatalogue(db);
  final after = await _snapshot(db, 6);
  for (final t in before.keys) {
    expect(after[t]!.length, before[t]!.length, reason: '$t row count (v6)');
    for (var i = 0; i < before[t]!.length; i++) {
      for (final e in before[t]![i].entries) {
        expect(after[t]![i][e.key], e.value, reason: '$t[$i].${e.key} (v6)');
      }
    }
  }
  final ex = await db.query('exercises');
  expect(ex.length, 201 + 2);
  expect(ex.firstWhere((r) => r['id'] == 1)['is_favourite'], 1);
  expect(
    ex.firstWhere((r) => r['id'] == 69)['personal_notes'],
    'elbows in, slow negative',
  );
  expect((await db.query('routines')).length, 3);
  final counts1 = await _counts(db);
  await helper.syncCatalogue(db);
  await helper.upgradeForTesting(db, 6, DatabaseHelper.schemaVersion);
  expect(await _counts(db), counts1);
}
