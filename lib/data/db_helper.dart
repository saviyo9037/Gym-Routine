import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

import 'seed_data.dart';
import 'sync_schema.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static const int schemaVersion = 7;

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'reptrack.db');

    final db = await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: SyncSchema.ensureCurrent,
    );
    await syncCatalogue(db);
    return db;
  }

  /// Test hook: use an already opened database (for example an in-memory
  /// sqflite_common_ffi database created with [createSchemaForTesting]).
  void useDatabaseForTesting(Database? db) {
    _database = db;
  }

  /// Test hook: run the production create/upgrade callbacks on [factory].
  Future<Database> openForTesting(
    DatabaseFactory factory,
    String path, {
    int version = schemaVersion,
    int? upgradeFrom,
  }) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: SyncSchema.ensureCurrent,
        singleInstance: false,
      ),
    );
  }

  /// Test hook: run the production upgrade path against an existing database.
  Future<void> upgradeForTesting(Database db, int from, int to) =>
      _onUpgrade(db, from, to);

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN difficulty TEXT DEFAULT 'Intermediate'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN is_recommended INTEGER DEFAULT 1",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN is_favourite INTEGER DEFAULT 0",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE exercises ADD COLUMN updated_at TEXT");
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN secondary_muscles TEXT",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN starting_position TEXT",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN breathing_guidance TEXT",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN beginner_modification TEXT",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE exercises ADD COLUMN is_compound INTEGER DEFAULT 0",
        );
      } catch (_) {}
    }
    if (oldVersion < 4) {
      await _createRoutineTables(db);
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          "ALTER TABLE routines ADD COLUMN alarm_type TEXT DEFAULT 'notification'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE routines ADD COLUMN is_alarm_enabled INTEGER DEFAULT 1",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE routines ADD COLUMN sound_name TEXT DEFAULT 'Digital Beep'",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE routines ADD COLUMN is_vibration_enabled INTEGER DEFAULT 1",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE routines ADD COLUMN snooze_minutes INTEGER DEFAULT 10",
        );
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE routines ADD COLUMN food_details TEXT");
      } catch (_) {}
    }
    if (oldVersion < 6) {
      await _migrateToV6(db);
    }
    if (oldVersion < 7) {
      // Additive change tracking for cloud sync (no data is modified except
      // adding bookkeeping columns).
      await SyncSchema.install(db);
    }
  }

  /// v6 (additive only, never touches existing rows):
  ///  - named weekly training plans (+ days + per-day exercises)
  ///  - persisted in-progress workout (crash/kill recovery)
  ///  - cardio time/distance columns and an idempotency key on sessions
  Future<void> _migrateToV6(Database db) async {
    await _createTrainingPlanTables(db);
    for (final stmt in const [
      'ALTER TABLE planned_exercises ADD COLUMN target_duration_seconds INTEGER',
      'ALTER TABLE planned_exercises ADD COLUMN target_distance_km REAL',
      'ALTER TABLE workout_sets ADD COLUMN duration_seconds INTEGER',
      'ALTER TABLE workout_sets ADD COLUMN distance_km REAL',
      'ALTER TABLE workout_sessions ADD COLUMN client_ref TEXT',
    ]) {
      try {
        await db.execute(stmt);
      } catch (_) {
        // Column already present (idempotent migration).
      }
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_client_ref '
      'ON workout_sessions(client_ref) WHERE client_ref IS NOT NULL',
    );
  }

  Future<void> _createTrainingPlanTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_plan_days (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        weekday INTEGER NOT NULL,
        is_rest INTEGER NOT NULL DEFAULT 0,
        title TEXT,
        notes TEXT,
        UNIQUE(plan_id, weekday)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_plan_day_exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_id INTEGER NOT NULL,
        exercise_id INTEGER NOT NULL,
        exercise_name TEXT NOT NULL,
        muscle_group_name TEXT,
        exercise_order INTEGER NOT NULL DEFAULT 0,
        target_sets INTEGER NOT NULL DEFAULT 3,
        target_reps INTEGER NOT NULL DEFAULT 10,
        target_weight_kg REAL NOT NULL DEFAULT 0,
        rest_seconds INTEGER NOT NULL DEFAULT 90,
        target_duration_seconds INTEGER,
        target_distance_km REAL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS active_sessions (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        client_ref TEXT NOT NULL,
        state_json TEXT NOT NULL,
        started_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Muscle Groups table
    await db.execute('''
      CREATE TABLE muscle_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        image_path TEXT,
        is_custom INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 2. Exercises table
    await db.execute('''
      CREATE TABLE exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        muscle_group_id INTEGER NOT NULL,
        muscle_group_name TEXT,
        secondary_muscles TEXT,
        name TEXT NOT NULL,
        target TEXT,
        description TEXT,
        starting_position TEXT,
        instructions TEXT,
        breathing_guidance TEXT,
        beginner_modification TEXT,
        equipment TEXT,
        difficulty TEXT DEFAULT 'Intermediate',
        suggested_sets_reps TEXT,
        common_mistakes TEXT,
        default_sets INTEGER DEFAULT 3,
        default_reps INTEGER DEFAULT 10,
        default_weight_kg REAL DEFAULT 15.0,
        rest_seconds INTEGER DEFAULT 90,
        image_path TEXT,
        personal_photo_path TEXT,
        personal_notes TEXT,
        trainer_instructions TEXT,
        is_compound INTEGER DEFAULT 0,
        is_custom INTEGER DEFAULT 0,
        is_recommended INTEGER DEFAULT 1,
        is_favourite INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (muscle_group_id) REFERENCES muscle_groups(id) ON DELETE CASCADE
      )
    ''');

    // 3. Workout Plans table
    await db.execute('''
      CREATE TABLE workout_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        primary_muscle_id INTEGER,
        primary_muscle_name TEXT,
        secondary_muscle_id INTEGER,
        secondary_muscle_name TEXT,
        notes TEXT,
        trainer_instructions TEXT,
        is_completed INTEGER DEFAULT 0,
        is_rest_day INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 4. Planned Exercises table
    await db.execute('''
      CREATE TABLE planned_exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        exercise_id INTEGER NOT NULL,
        exercise_name TEXT NOT NULL,
        muscle_group_name TEXT,
        exercise_order INTEGER DEFAULT 0,
        target_sets INTEGER DEFAULT 3,
        target_reps INTEGER DEFAULT 10,
        target_weight_kg REAL DEFAULT 15.0,
        rest_seconds INTEGER DEFAULT 90,
        notes TEXT,
        image_path TEXT,
        target_duration_seconds INTEGER,
        target_distance_km REAL,
        FOREIGN KEY (plan_id) REFERENCES workout_plans(id) ON DELETE CASCADE,
        FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
      )
    ''');

    // 5. Workout Sessions table
    await db.execute('''
      CREATE TABLE workout_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_seconds INTEGER DEFAULT 0,
        primary_muscle TEXT NOT NULL,
        secondary_muscle TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        client_ref TEXT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_client_ref '
      'ON workout_sessions(client_ref) WHERE client_ref IS NOT NULL',
    );

    // 6. Workout Sets table
    await db.execute('''
      CREATE TABLE workout_sets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        exercise_id INTEGER NOT NULL,
        exercise_name TEXT NOT NULL,
        set_number INTEGER NOT NULL,
        reps INTEGER NOT NULL,
        weight_kg REAL NOT NULL,
        is_completed INTEGER DEFAULT 1,
        completed_at TEXT NOT NULL,
        duration_seconds INTEGER,
        distance_km REAL,
        FOREIGN KEY (session_id) REFERENCES workout_sessions(id) ON DELETE CASCADE
      )
    ''');

    // 7. Media Attachments table
    await db.execute('''
      CREATE TABLE media_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        media_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        title TEXT,
        description TEXT,
        duration_seconds INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    // 8. Plan Change Logs table
    await db.execute('''
      CREATE TABLE plan_change_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        plan_date TEXT NOT NULL,
        change_description TEXT NOT NULL,
        reason TEXT,
        changed_at TEXT NOT NULL
      )
    ''');

    // 9. User Settings table
    await db.execute('''
      CREATE TABLE user_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 10. Routine tables
    await _createRoutineTables(db);

    // 11. Training plans + in-progress workout recovery (schema v6)
    await _createTrainingPlanTables(db);

    // 12. Cloud-sync change tracking (schema v7)
    await SyncSchema.install(db);

    // Populate initial seed data
    await _seedInitialData(db);
  }

  Future<void> _createRoutineTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS routines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        repeat_days TEXT NOT NULL,
        notes TEXT,
        food_details TEXT,
        is_reminder_enabled INTEGER DEFAULT 1,
        reminder_minutes_before INTEGER DEFAULT 10,
        alarm_type TEXT DEFAULT 'notification',
        is_alarm_enabled INTEGER DEFAULT 1,
        sound_name TEXT DEFAULT 'Digital Beep',
        is_vibration_enabled INTEGER DEFAULT 1,
        snooze_minutes INTEGER DEFAULT 10,
        is_enabled INTEGER DEFAULT 1,
        color_hex TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS routine_completions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        routine_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        completed_at TEXT NOT NULL,
        FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE,
        UNIQUE(routine_id, date)
      )
    ''');
  }

  /// Custom exercises whose id collides with a catalogue id get a fresh id
  /// (>= 100001) and every reference that carried the old id AND the
  /// exercise's name is repointed. Idempotent; a no-op on healthy databases.
  Future<void> _relocateCustomExerciseIds(Database db) async {
    final catalogueIds = {
      for (final e in SeedData.exercises)
        if (e.id != null) e.id!,
    };
    final customs = await db.query(
      'exercises',
      columns: ['id', 'name'],
      where: 'COALESCE(is_custom, 0) = 1',
    );
    final clashing = [
      for (final r in customs)
        if (catalogueIds.contains(r['id'] as int)) r,
    ];
    if (clashing.isEmpty) return;
    await db.transaction((txn) async {
      final maxRow = await txn.rawQuery('SELECT MAX(id) AS m FROM exercises');
      var next = (maxRow.first['m'] as int? ?? 0);
      if (next < 100000) next = 100000;
      for (final r in clashing) {
        final oldId = r['id'] as int;
        final name = r['name'] as String;
        next++;
        await txn.update(
          'exercises',
          {'id': next},
          where: 'id = ? AND COALESCE(is_custom, 0) = 1',
          whereArgs: [oldId],
        );
        for (final t in const [
          'planned_exercises',
          'workout_sets',
          'training_plan_day_exercises',
        ]) {
          await txn.update(
            t,
            {'exercise_id': next},
            where: 'exercise_id = ? AND exercise_name = ?',
            whereArgs: [oldId, name],
          );
        }
        await txn.update(
          'media_attachments',
          {'entity_id': next},
          where: "entity_type = 'exercise' AND entity_id = ?",
          whereArgs: [oldId],
        );
      }
    });
  }

  Future<void> syncCatalogue(Database db) async {
    // 1. Sync muscle groups
    for (final mg in SeedData.muscleGroups) {
      final existing = await db.query(
        'muscle_groups',
        where: 'id = ? OR name = ?',
        whereArgs: [mg.id, mg.name],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('muscle_groups', mg.toMap());
      } else {
        await db.update(
          'muscle_groups',
          {
            'name': mg.name,
            'description': mg.description,
            'image_path': mg.imagePath,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      }
    }

    // 2. Sync exercises
    // A custom exercise created while the catalogue was smaller may sit on an
    // id the catalogue now uses. Move it out of the way first so it is never
    // overwritten and the real catalogue exercise is still inserted.
    await _relocateCustomExerciseIds(db);
    for (final ex in SeedData.exercises) {
      // Only catalogue rows are matched: a user's custom exercise that happens
      // to share a name with a catalogue exercise is left untouched.
      final existing = await db.query(
        'exercises',
        where: '(id = ? OR name = ?) AND COALESCE(is_custom, 0) = 0',
        whereArgs: [ex.id, ex.name],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('exercises', ex.toMap());
      } else {
        final existingRow = existing.first;
        final existingFav = existingRow['is_favourite'] as int? ?? 0;
        final existingNotes = existingRow['personal_notes'] as String?;
        final existingPhoto = existingRow['personal_photo_path'] as String?;

        final updateData = <String, dynamic>{
          'muscle_group_id': ex.muscleGroupId,
          'muscle_group_name': ex.muscleGroupName,
          'secondary_muscles': ex.secondaryMuscles,
          'target': ex.target,
          'description': ex.description,
          'starting_position': ex.startingPosition,
          'instructions': ex.instructions,
          'breathing_guidance': ex.breathingGuidance,
          'beginner_modification': ex.beginnerModification,
          'equipment': ex.equipment,
          'difficulty': ex.difficulty,
          'suggested_sets_reps': ex.suggestedSetsReps,
          'common_mistakes': ex.commonMistakes,
          'default_sets': ex.defaultSets,
          'default_reps': ex.defaultReps,
          'default_weight_kg': ex.defaultWeightKg,
          'rest_seconds': ex.restSeconds,
          'image_path': ex.imagePath,
          'is_compound': ex.isCompound ? 1 : 0,
          'is_recommended': ex.isRecommended ? 1 : 0,
          'is_favourite': existingFav,
        };
        if (existingNotes != null && existingNotes.isNotEmpty) {
          updateData['personal_notes'] = existingNotes;
        }
        if (existingPhoto != null && existingPhoto.isNotEmpty) {
          updateData['personal_photo_path'] = existingPhoto;
        }

        await db.update(
          'exercises',
          updateData,
          where: 'id = ?',
          whereArgs: [existingRow['id']],
        );
      }
    }

    // 3. Sync default personalized routines (9 core suggested routines)
    final now = DateTime.now().toIso8601String();
    final defaultRoutines = [
      {
        'title': 'Wake up & Morning Preparation',
        'category': 'Personal',
        'start_time': '07:15',
        'end_time': '07:30',
        'repeat_days': '1,2,3,4,5,6,7',
        'notes': 'Hydrate with 500ml water, light mobility and morning prep',
        'food_details': null,
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 0,
        'alarm_type': 'alarm',
        'is_alarm_enabled': 1,
        'sound_name': 'Sunrise Bell',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#E84393',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Breakfast',
        'category': 'Meals',
        'start_time': '07:30',
        'end_time': '08:00',
        'repeat_days': '1,2,3,4,5,6,7',
        'notes': 'Energizing balanced breakfast',
        'food_details':
            'Oats or boiled eggs, banana, peanut butter toast, milk / tea',
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 10,
        'alarm_type': 'notification',
        'is_alarm_enabled': 1,
        'sound_name': 'Digital Beep',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#E17055',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Office / Work Start',
        'category': 'Work',
        'start_time': '09:00',
        'end_time': '10:30',
        'repeat_days': '1,2,3,4,5',
        'notes': 'High-priority focus tasks and morning work sprint',
        'food_details': null,
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 5,
        'alarm_type': 'notification',
        'is_alarm_enabled': 1,
        'sound_name': 'Digital Beep',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#00CEC9',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Tea & Morning Snack',
        'category': 'Meals',
        'start_time': '10:30',
        'end_time': '11:00',
        'repeat_days': '1,2,3,4,5',
        'notes': 'Mid-morning hydration and recharge snack',
        'food_details':
            'Green tea / coffee, roasted chana, almonds, or fresh fruit',
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 5,
        'alarm_type': 'notification',
        'is_alarm_enabled': 1,
        'sound_name': 'Digital Beep',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#E17055',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Lunch',
        'category': 'Meals',
        'start_time': '13:30',
        'end_time': '14:15',
        'repeat_days': '1,2,3,4,5,6,7',
        'notes': 'Nutritious lunch with quality complex carbs and protein',
        'food_details': 'Rice or chapati, dal / lentils, chicken breast or paneer, fresh salad',
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 10,
        'alarm_type': 'notification',
        'is_alarm_enabled': 1,
        'sound_name': 'Digital Beep',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#E17055',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Evening Snack',
        'category': 'Meals',
        'start_time': '16:30',
        'end_time': '17:00',
        'repeat_days': '1,2,3,4,5,6,7',
        'notes': 'Pre-workout carb replenishment and focus snack',
        'food_details':
            'Banana, boiled eggs, black coffee, or sprouted legumes',
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 10,
        'alarm_type': 'notification',
        'is_alarm_enabled': 1,
        'sound_name': 'Digital Beep',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#E17055',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Gym / Workout',
        'category': 'Gym',
        'start_time': '19:00',
        'end_time': '20:30',
        'repeat_days': '1,2,3,4,5,6',
        'notes': 'RepTrack programmed resistance training & muscle hypertrophy workout',
        'food_details': null,
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 15,
        'alarm_type': 'alarm',
        'is_alarm_enabled': 1,
        'sound_name': 'Gym Siren',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#FF8A00',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Dinner (Post-Gym Recovery)',
        'category': 'Meals',
        'start_time': '20:45',
        'end_time': '21:30',
        'repeat_days': '1,2,3,4,5,6,7',
        'notes': 'Calculated 15m after gym workout end time (20:30)',
        'food_details':
            'High protein dinner: grilled chicken / paneer / dal, rice or roti',
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 10,
        'alarm_type': 'notification',
        'is_alarm_enabled': 1,
        'sound_name': 'Digital Beep',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#E17055',
        'created_at': now,
        'updated_at': now,
      },
      {
        'title': 'Sleep Preparation & Wind Down',
        'category': 'Sleep',
        'start_time': '22:30',
        'end_time': '07:15',
        'repeat_days': '1,2,3,4,5,6,7',
        'notes': 'Cool dark room, zero screens, recovery sleep for peak hormone release',
        'food_details': null,
        'is_reminder_enabled': 1,
        'reminder_minutes_before': 30,
        'alarm_type': 'alarm',
        'is_alarm_enabled': 1,
        'sound_name': 'Sunrise Bell',
        'is_vibration_enabled': 1,
        'snooze_minutes': 10,
        'is_enabled': 1,
        'color_hex': '#6C5CE7',
        'created_at': now,
        'updated_at': now,
      },
    ];

    // Seed the starter routines exactly once. A routine the user deletes or
    // renames must never come back on the next launch.
    final seeded = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['default_routines_seeded'],
      limit: 1,
    );
    if (seeded.isEmpty) {
      final existingCount =
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM routines'),
          ) ??
          0;
      // Existing installs that already have routines keep exactly what they have.
      if (existingCount == 0) {
        for (final r in defaultRoutines) {
          await db.insert('routines', r);
        }
      }
      await db.insert('user_settings', {
        'key': 'default_routines_seeded',
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _seedInitialData(Database db) async {
    await syncCatalogue(db);

    // Insert Default Settings
    // No default settings are seeded: nothing reads a missing key without a
    // default (theme_mode / weight_unit / reminders_enabled were dead values).

    final planCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM workout_plans'),
        ) ??
        0;
    if (planCount > 0) return;

    // Create starter Today's and Tomorrow's workout plan
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tomorrowStr = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().add(const Duration(days: 1)));

    // Today: Biceps (3) & Chest (1)
    final todayPlanId = await db.insert('workout_plans', {
      'date': todayStr,
      'primary_muscle_id': 6,
      'primary_muscle_name': 'Biceps',
      'secondary_muscle_id': 1,
      'secondary_muscle_name': 'Chest',
      'notes': 'Upper body focus: Peak bicep curl hypertrophy coupled with heavy chest press.',
      'trainer_instructions':
          'Strict form on Dumbbell curls. Avoid elbow flare on bench press.',
      'is_completed': 0,
      'is_rest_day': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Exercises for Today (Biceps & Chest)
    await db.insert('planned_exercises', {
      'plan_id': todayPlanId,
      'exercise_id': 69, // Standing Dumbbell Curl
      'exercise_name': 'Standing Dumbbell Curl',
      'muscle_group_name': 'Biceps',
      'exercise_order': 0,
      'target_sets': 3,
      'target_reps': 10,
      'target_weight_kg': 12.5,
      'rest_seconds': 90,
      'notes': 'Control the eccentric phase for 3 seconds.',
      'image_path': 'assets/images/exercises/standing_dumbbell_curl.jpg',
    });

    await db.insert('planned_exercises', {
      'plan_id': todayPlanId,
      'exercise_id': 73, // Hammer Curl
      'exercise_name': 'Hammer Curl',
      'muscle_group_name': 'Biceps',
      'exercise_order': 1,
      'target_sets': 3,
      'target_reps': 10,
      'target_weight_kg': 14.0,
      'rest_seconds': 90,
      'notes': 'Neutral grip, drive thumbs upward.',
      'image_path': 'assets/images/exercises/hammer_curl.jpg',
    });

    await db.insert('planned_exercises', {
      'plan_id': todayPlanId,
      'exercise_id': 1, // Barbell Bench Press
      'exercise_name': 'Barbell Bench Press',
      'muscle_group_name': 'Chest',
      'exercise_order': 2,
      'target_sets': 4,
      'target_reps': 8,
      'target_weight_kg': 60.0,
      'rest_seconds': 120,
      'notes': 'Solid leg drive and scapular retraction.',
      'image_path': 'assets/images/exercises/barbell_bench_press.jpg',
    });

    await db.insert('planned_exercises', {
      'plan_id': todayPlanId,
      'exercise_id': 2, // Incline Barbell Bench Press
      'exercise_name': 'Incline Barbell Bench Press',
      'muscle_group_name': 'Chest',
      'exercise_order': 3,
      'target_sets': 3,
      'target_reps': 10,
      'target_weight_kg': 50.0,
      'rest_seconds': 90,
      'notes': 'Control the bar to upper chest clavicular angle.',
      'image_path': 'assets/images/exercises/incline_barbell_bench_press.jpg',
    });

    // Tomorrow: Back (2) & Triceps (7)
    final tomorrowPlanId = await db.insert('workout_plans', {
      'date': tomorrowStr,
      'primary_muscle_id': 2,
      'primary_muscle_name': 'Back',
      'secondary_muscle_id': 7,
      'secondary_muscle_name': 'Triceps',
      'notes': 'Pull day volume paired with tricep extension pump.',
      'trainer_instructions':
          'Emphasize full lat stretch at the top of pulldowns.',
      'is_completed': 0,
      'is_rest_day': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    await db.insert('planned_exercises', {
      'plan_id': tomorrowPlanId,
      'exercise_id': 26, // Lat Pulldown
      'exercise_name': 'Lat Pulldown',
      'muscle_group_name': 'Back',
      'exercise_order': 0,
      'target_sets': 4,
      'target_reps': 10,
      'target_weight_kg': 50.0,
      'rest_seconds': 90,
      'notes': 'Pull down to clavicle, squeeze shoulder blades.',
      'image_path': 'assets/images/exercises/lat_pulldown.jpg',
    });

    await db.insert('planned_exercises', {
      'plan_id': tomorrowPlanId,
      'exercise_id': 31, // Barbell Bent-Over Row
      'exercise_name': 'Barbell Bent-Over Row',
      'muscle_group_name': 'Back',
      'exercise_order': 1,
      'target_sets': 4,
      'target_reps': 8,
      'target_weight_kg': 50.0,
      'rest_seconds': 90,
      'notes': 'Hinge hips 45 degrees, pull to lower ribs.',
      'image_path': 'assets/images/exercises/barbell_bent_over_row.jpg',
    });

    await db.insert('planned_exercises', {
      'plan_id': tomorrowPlanId,
      'exercise_id': 91, // Cable Triceps Pushdown
      'exercise_name': 'Cable Triceps Pushdown',
      'muscle_group_name': 'Triceps',
      'exercise_order': 2,
      'target_sets': 3,
      'target_reps': 12,
      'target_weight_kg': 20.0,
      'rest_seconds': 75,
      'notes': 'Spread rope ends at the bottom lockout.',
      'image_path': 'assets/images/exercises/cable_triceps_pushdown.jpg',
    });
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('workout_sets');
    await db.delete('workout_sessions');
    await db.delete('planned_exercises');
    await db.delete('workout_plans');
    await db.delete('plan_change_logs');
    await db.delete('media_attachments');
    await db.delete('exercises');
    await db.delete('muscle_groups');
    await db.delete('routine_completions');
    await db.delete('routines');
    await db.delete(
      'user_settings',
      where: 'key = ?',
      whereArgs: ['default_routines_seeded'],
    );
    await db.delete('training_plan_day_exercises');
    await db.delete('training_plan_days');
    await db.delete('training_plans');
    await db.delete('active_sessions');
    // A local reset must never be mirrored to the cloud as mass deletion:
    // forget pending tombstones/cursors (the cloud copy stays untouched).
    await db.delete('sync_tombstones');
    await db.delete('sync_meta', where: "key LIKE 'cursor:%'");
    await _seedInitialData(db);
  }
}
