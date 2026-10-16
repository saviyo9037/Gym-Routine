import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

import 'seed_data.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'reptrack.db');

    final db = await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await syncCatalogue(db);
    return db;
  }

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
        created_at TEXT NOT NULL
      )
    ''');

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
    for (final ex in SeedData.exercises) {
      final existing = await db.query(
        'exercises',
        where: 'name = ?',
        whereArgs: [ex.name],
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

    for (final r in defaultRoutines) {
      final existing = await db.query(
        'routines',
        where: 'title = ?',
        whereArgs: [r['title']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('routines', r);
      }
    }
  }

  Future<void> _seedInitialData(Database db) async {
    await syncCatalogue(db);

    // Insert Default Settings
    await db.insert('user_settings', {'key': 'theme_mode', 'value': 'dark'});
    await db.insert('user_settings', {'key': 'weight_unit', 'value': 'kg'});
    await db.insert('user_settings', {
      'key': 'reminders_enabled',
      'value': 'false',
    });

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
      'primary_muscle_id': 3,
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
    await _seedInitialData(db);
  }
}
