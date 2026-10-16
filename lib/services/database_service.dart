import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

import '../data/db_helper.dart';
import '../models/muscle_group.dart';
import '../models/exercise.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import '../models/media_attachment.dart';
import '../models/plan_change_log.dart';
import '../models/weekly_summary.dart';

class DatabaseService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // ------------------- MUSCLE GROUPS -------------------
  Future<List<MuscleGroup>> getAllMuscleGroups() async {
    final db = await _dbHelper.database;
    final maps = await db.query('muscle_groups', orderBy: 'id ASC');
    return maps.map((m) => MuscleGroup.fromMap(m)).toList();
  }

  Future<MuscleGroup?> getMuscleGroupById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'muscle_groups',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return MuscleGroup.fromMap(maps.first);
  }

  Future<int> insertMuscleGroup(MuscleGroup mg) async {
    final db = await _dbHelper.database;
    return await db.insert('muscle_groups', mg.toMap());
  }

  Future<int> updateMuscleGroup(MuscleGroup mg) async {
    final db = await _dbHelper.database;
    return await db.update(
      'muscle_groups',
      mg.toMap(),
      where: 'id = ?',
      whereArgs: [mg.id],
    );
  }

  Future<int> deleteMuscleGroup(int id) async {
    final db = await _dbHelper.database;
    return await db.delete('muscle_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<int, int>> getExerciseCountsByMuscleGroup() async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT muscle_group_id, COUNT(*) as count 
      FROM exercises 
      GROUP BY muscle_group_id
    ''');
    final Map<int, int> counts = {};
    for (final row in results) {
      final mgId = row['muscle_group_id'] as int;
      final count = row['count'] as int;
      counts[mgId] = count;
    }
    return counts;
  }

  // ------------------- EXERCISES -------------------
  Future<Exercise?> getExerciseById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Exercise.fromMap(maps.first);
  }

  Future<List<Exercise>> getAllExercises() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      orderBy: 'muscle_group_id ASC, id ASC',
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<List<Exercise>> getExercisesByMuscleGroup(int muscleGroupId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      where: 'muscle_group_id = ?',
      whereArgs: [muscleGroupId],
      orderBy: 'id ASC',
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<List<Exercise>> getBicepsRecommendations() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      where: "muscle_group_name = 'Biceps' OR muscle_group_id = 6",
      orderBy: 'id ASC',
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<List<Exercise>> getFavouriteExercises() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      where: 'is_favourite = ?',
      whereArgs: [1],
      orderBy: 'muscle_group_id ASC, name ASC',
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<List<Exercise>> getRecommendedExercises() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      where: 'is_recommended = ?',
      whereArgs: [1],
      orderBy: 'muscle_group_id ASC, name ASC',
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<List<Exercise>> getUserCreatedExercises() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'exercises',
      where: 'is_custom = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<void> toggleExerciseFavourite(int id, bool isFavourite) async {
    final db = await _dbHelper.database;
    await db.update(
      'exercises',
      {
        'is_favourite': isFavourite ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Exercise>> getCatalogueExercises(
    String catalogueName, {
    String sortBy = 'name_asc',
    String? subCategory,
    String? secondaryMuscle,
    bool includeSecondary = false,
  }) async {
    final db = await _dbHelper.database;
    String whereClause;
    List<dynamic> whereArgs = [];

    final nameLower = catalogueName.toLowerCase().trim();

    if (nameLower.contains('compound')) {
      whereClause = 'is_compound = 1';
    } else if (nameLower.contains('bodyweight')) {
      whereClause = "equipment LIKE '%Bodyweight%'";
    } else if (nameLower.contains('cable')) {
      whereClause = "equipment LIKE '%Cable%'";
    } else if (nameLower.contains('machine')) {
      whereClause = "(equipment LIKE '%Machine%' OR equipment LIKE '%Smith%')";
    } else if (nameLower.contains('dumbbell')) {
      whereClause = "equipment LIKE '%Dumbbell%'";
    } else if (nameLower.contains('barbell')) {
      whereClause = "(equipment LIKE '%Barbell%' OR equipment LIKE '%EZ-Bar%' OR equipment LIKE '%Trap Bar%')";
    } else if (nameLower == 'chest') {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Chest' OR secondary_muscles LIKE '%Chest%' OR secondary_muscles LIKE '%Pectoral%')";
      } else {
        whereClause = "muscle_group_name = 'Chest'";
      }
    } else if (nameLower == 'triceps') {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Triceps' OR secondary_muscles LIKE '%Tricep%')";
      } else {
        whereClause = "muscle_group_name = 'Triceps'";
      }
    } else if (nameLower == 'biceps') {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Biceps' OR secondary_muscles LIKE '%Bicep%' OR secondary_muscles LIKE '%Brachialis%')";
      } else {
        whereClause = "muscle_group_name = 'Biceps'";
      }
    } else if (nameLower.contains('shoulder')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Shoulders' OR secondary_muscles LIKE '%Deltoid%' OR secondary_muscles LIKE '%Shoulder%')";
      } else {
        whereClause = "muscle_group_name = 'Shoulders'";
      }
    } else if (nameLower == 'legs') {
      if (subCategory != null &&
          subCategory.isNotEmpty &&
          subCategory.toLowerCase() != 'all') {
        final subLower = subCategory.toLowerCase();
        if (subLower.contains('quad')) {
          whereClause = "muscle_group_name = 'Quadriceps'";
        } else if (subLower.contains('hamstring')) {
          whereClause = "muscle_group_name = 'Hamstrings'";
        } else if (subLower.contains('glute')) {
          whereClause = "muscle_group_name = 'Glutes'";
        } else if (subLower.contains('calve') || subLower.contains('calf')) {
          whereClause = "muscle_group_name = 'Calves'";
        } else {
          whereClause = "muscle_group_name IN ('Quadriceps', 'Hamstrings', 'Glutes', 'Calves')";
        }
      } else if (includeSecondary) {
        whereClause = "(muscle_group_name IN ('Quadriceps', 'Hamstrings', 'Glutes', 'Calves') OR secondary_muscles LIKE '%Quad%' OR secondary_muscles LIKE '%Hamstring%' OR secondary_muscles LIKE '%Glute%' OR secondary_muscles LIKE '%Calf%')";
      } else {
        whereClause = "muscle_group_name IN ('Quadriceps', 'Hamstrings', 'Glutes', 'Calves')";
      }
    } else if (nameLower.contains('quad')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Quadriceps' OR secondary_muscles LIKE '%Quad%')";
      } else {
        whereClause = "muscle_group_name = 'Quadriceps'";
      }
    } else if (nameLower.contains('hamstring')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Hamstrings' OR secondary_muscles LIKE '%Hamstring%')";
      } else {
        whereClause = "muscle_group_name = 'Hamstrings'";
      }
    } else if (nameLower.contains('glute')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Glutes' OR secondary_muscles LIKE '%Glute%')";
      } else {
        whereClause = "muscle_group_name = 'Glutes'";
      }
    } else if (nameLower.contains('calve') || nameLower.contains('calf')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Calves' OR secondary_muscles LIKE '%Calf%' OR secondary_muscles LIKE '%Soleus%')";
      } else {
        whereClause = "muscle_group_name = 'Calves'";
      }
    } else if (nameLower == 'back') {
      if (subCategory != null &&
          subCategory.isNotEmpty &&
          subCategory.toLowerCase() != 'all') {
        final subLower = subCategory.toLowerCase();
        if (subLower == 'lats') {
          whereClause = "muscle_group_name = 'Lats'";
        } else if (subLower.contains('upper back') ||
            subLower.contains('trap')) {
          whereClause = "muscle_group_name = 'Upper Back and Traps'";
        } else if (subLower.contains('mid') || subLower == 'back') {
          whereClause = "muscle_group_name = 'Back'";
        } else {
          whereClause =
              "muscle_group_name IN ('Back', 'Lats', 'Upper Back and Traps')";
        }
      } else if (includeSecondary) {
        whereClause = "(muscle_group_name IN ('Back', 'Lats', 'Upper Back and Traps') OR secondary_muscles LIKE '%Back%' OR secondary_muscles LIKE '%Lat%' OR secondary_muscles LIKE '%Rhomboid%' OR secondary_muscles LIKE '%Trap%')";
      } else {
        whereClause =
            "muscle_group_name IN ('Back', 'Lats', 'Upper Back and Traps')";
      }
    } else if (nameLower == 'lats') {
      if (includeSecondary) {
        whereClause =
            "(muscle_group_name = 'Lats' OR secondary_muscles LIKE '%Lat%')";
      } else {
        whereClause = "muscle_group_name = 'Lats'";
      }
    } else if (nameLower.contains('upper back') || nameLower.contains('trap')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Upper Back and Traps' OR secondary_muscles LIKE '%Trap%' OR secondary_muscles LIKE '%Rhomboid%' OR secondary_muscles LIKE '%Upper Back%')";
      } else {
        whereClause = "muscle_group_name = 'Upper Back and Traps'";
      }
    } else if (nameLower.contains('forearm') || nameLower.contains('grip')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Forearms' OR secondary_muscles LIKE '%Forearm%' OR secondary_muscles LIKE '%Grip%')";
      } else {
        whereClause = "muscle_group_name = 'Forearms'";
      }
    } else if (nameLower.contains('ab') || nameLower.contains('core')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Abs and Core' OR secondary_muscles LIKE '%Core%' OR secondary_muscles LIKE '%Abdominal%' OR secondary_muscles LIKE '%Oblique%')";
      } else {
        whereClause = "muscle_group_name = 'Abs and Core'";
      }
    } else if (nameLower == 'cardio') {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Cardio' OR secondary_muscles LIKE '%Cardio%' OR secondary_muscles LIKE '%Cardiovascular%')";
      } else {
        whereClause = "muscle_group_name = 'Cardio'";
      }
    } else if (nameLower.contains('full body')) {
      if (includeSecondary) {
        whereClause = "(muscle_group_name = 'Full Body' OR (is_compound = 1 AND (name LIKE '%Deadlift%' OR name LIKE '%Clean%' OR name LIKE '%Snatch%' OR name LIKE '%Burpee%' OR name LIKE '%Swing%' OR name LIKE '%Carry%')))";
      } else {
        whereClause = "muscle_group_name = 'Full Body'";
      }
    } else {
      whereClause = "muscle_group_name LIKE ?";
      whereArgs = ['%$catalogueName%'];
    }

    if (secondaryMuscle != null &&
        secondaryMuscle.isNotEmpty &&
        secondaryMuscle.toLowerCase() != 'all') {
      whereClause = "($whereClause) AND (secondary_muscles LIKE ?)";
      whereArgs.add('%$secondaryMuscle%');
    }

    String orderSql;
    switch (sortBy) {
      case 'name_desc':
        orderSql = 'name DESC';
        break;
      case 'difficulty':
        orderSql = "CASE difficulty WHEN 'Beginner' THEN 1 WHEN 'Intermediate' THEN 2 WHEN 'Advanced' THEN 3 ELSE 4 END ASC, name ASC";
        break;
      case 'recommended':
        orderSql = 'is_recommended DESC, name ASC';
        break;
      case 'name_asc':
      default:
        orderSql = 'name ASC';
        break;
    }

    final maps = await db.query(
      'exercises',
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderSql,
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<int> getCatalogueCount(
    String catalogueName, {
    String? subCategory,
    String? secondaryMuscle,
    bool includeSecondary = false,
  }) async {
    final exs = await getCatalogueExercises(
      catalogueName,
      subCategory: subCategory,
      secondaryMuscle: secondaryMuscle,
      includeSecondary: includeSecondary,
    );
    return exs.length;
  }

  Future<Map<String, int>> getAllCatalogueCounts() async {
    const allCatalogues = [
      'Chest',
      'Triceps',
      'Back',
      'Biceps',
      'Legs',
      'Abs / Core',
      'Abs and Core',
      'Shoulders',
      'Cardio',
      'Forearms',
      'Upper Back and Traps',
      'Lats',
      'Quadriceps',
      'Hamstrings',
      'Glutes',
      'Calves',
      'Full Body',
      'Compound Exercises',
      'Bodyweight Exercises',
      'Cable Exercises',
      'Machine Exercises',
      'Dumbbell Exercises',
      'Barbell Exercises',
    ];
    final Map<String, int> counts = {};
    for (final cat in allCatalogues) {
      counts[cat] = await getCatalogueCount(cat);
    }
    return counts;
  }

  Future<List<Exercise>> searchAndFilterExercises({
    int? muscleGroupId,
    String? categoryName,
    String? subCategory,
    String? secondaryMuscle,
    bool includeSecondary = false,
    String? equipment,
    String? searchQuery,
    bool? onlyFavourites,
    bool? onlyRecommended,
    bool? onlyCustom,
    String? difficulty,
    String sortBy = 'name_asc',
  }) async {
    final db = await _dbHelper.database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (categoryName != null &&
        categoryName.isNotEmpty &&
        categoryName.toLowerCase() != 'all') {
      final nameLower = categoryName.toLowerCase().trim();
      if (nameLower.contains('compound')) {
        whereClauses.add('is_compound = 1');
      } else if (nameLower.contains('bodyweight')) {
        whereClauses.add("equipment LIKE '%Bodyweight%'");
      } else if (nameLower.contains('cable')) {
        whereClauses.add("equipment LIKE '%Cable%'");
      } else if (nameLower.contains('machine')) {
        whereClauses.add(
          "(equipment LIKE '%Machine%' OR equipment LIKE '%Smith%')",
        );
      } else if (nameLower.contains('dumbbell')) {
        whereClauses.add("equipment LIKE '%Dumbbell%'");
      } else if (nameLower.contains('barbell')) {
        whereClauses.add(
          "(equipment LIKE '%Barbell%' OR equipment LIKE '%EZ-Bar%' OR equipment LIKE '%Trap Bar%')",
        );
      } else if (nameLower == 'chest') {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Chest' OR secondary_muscles LIKE '%Chest%' OR secondary_muscles LIKE '%Pectoral%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Chest'");
        }
      } else if (nameLower == 'triceps') {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Triceps' OR secondary_muscles LIKE '%Tricep%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Triceps'");
        }
      } else if (nameLower == 'biceps') {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Biceps' OR secondary_muscles LIKE '%Bicep%' OR secondary_muscles LIKE '%Brachialis%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Biceps'");
        }
      } else if (nameLower.contains('shoulder')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Shoulders' OR secondary_muscles LIKE '%Deltoid%' OR secondary_muscles LIKE '%Shoulder%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Shoulders'");
        }
      } else if (nameLower == 'legs') {
        if (subCategory != null &&
            subCategory.isNotEmpty &&
            subCategory.toLowerCase() != 'all') {
          final s = subCategory.toLowerCase();
          if (s.contains('quad')) {
            whereClauses.add("muscle_group_name = 'Quadriceps'");
          } else if (s.contains('hamstring')) {
            whereClauses.add("muscle_group_name = 'Hamstrings'");
          } else if (s.contains('glute')) {
            whereClauses.add("muscle_group_name = 'Glutes'");
          } else if (s.contains('calve') || s.contains('calf')) {
            whereClauses.add("muscle_group_name = 'Calves'");
          } else {
            whereClauses.add(
              "muscle_group_name IN ('Quadriceps', 'Hamstrings', 'Glutes', 'Calves')",
            );
          }
        } else if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name IN ('Quadriceps', 'Hamstrings', 'Glutes', 'Calves') OR secondary_muscles LIKE '%Quad%' OR secondary_muscles LIKE '%Hamstring%' OR secondary_muscles LIKE '%Glute%' OR secondary_muscles LIKE '%Calf%')",
          );
        } else {
          whereClauses.add(
            "muscle_group_name IN ('Quadriceps', 'Hamstrings', 'Glutes', 'Calves')",
          );
        }
      } else if (nameLower.contains('quad')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Quadriceps' OR secondary_muscles LIKE '%Quad%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Quadriceps'");
        }
      } else if (nameLower.contains('hamstring')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Hamstrings' OR secondary_muscles LIKE '%Hamstring%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Hamstrings'");
        }
      } else if (nameLower.contains('glute')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Glutes' OR secondary_muscles LIKE '%Glute%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Glutes'");
        }
      } else if (nameLower.contains('calve') || nameLower.contains('calf')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Calves' OR secondary_muscles LIKE '%Calf%' OR secondary_muscles LIKE '%Soleus%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Calves'");
        }
      } else if (nameLower == 'back') {
        if (subCategory != null &&
            subCategory.isNotEmpty &&
            subCategory.toLowerCase() != 'all') {
          final s = subCategory.toLowerCase();
          if (s == 'lats') {
            whereClauses.add("muscle_group_name = 'Lats'");
          } else if (s.contains('upper back') || s.contains('trap')) {
            whereClauses.add("muscle_group_name = 'Upper Back and Traps'");
          } else if (s.contains('mid') || s == 'back') {
            whereClauses.add("muscle_group_name = 'Back'");
          } else {
            whereClauses.add(
              "muscle_group_name IN ('Back', 'Lats', 'Upper Back and Traps')",
            );
          }
        } else if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name IN ('Back', 'Lats', 'Upper Back and Traps') OR secondary_muscles LIKE '%Back%' OR secondary_muscles LIKE '%Lat%' OR secondary_muscles LIKE '%Rhomboid%' OR secondary_muscles LIKE '%Trap%')",
          );
        } else {
          whereClauses.add(
            "muscle_group_name IN ('Back', 'Lats', 'Upper Back and Traps')",
          );
        }
      } else if (nameLower == 'lats') {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Lats' OR secondary_muscles LIKE '%Lat%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Lats'");
        }
      } else if (nameLower.contains('upper back') ||
          nameLower.contains('trap')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Upper Back and Traps' OR secondary_muscles LIKE '%Trap%' OR secondary_muscles LIKE '%Rhomboid%' OR secondary_muscles LIKE '%Upper Back%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Upper Back and Traps'");
        }
      } else if (nameLower.contains('forearm') || nameLower.contains('grip')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Forearms' OR secondary_muscles LIKE '%Forearm%' OR secondary_muscles LIKE '%Grip%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Forearms'");
        }
      } else if (nameLower.contains('ab') || nameLower.contains('core')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Abs and Core' OR secondary_muscles LIKE '%Core%' OR secondary_muscles LIKE '%Abdominal%' OR secondary_muscles LIKE '%Oblique%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Abs and Core'");
        }
      } else if (nameLower == 'cardio') {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Cardio' OR secondary_muscles LIKE '%Cardio%' OR secondary_muscles LIKE '%Cardiovascular%')",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Cardio'");
        }
      } else if (nameLower.contains('full body')) {
        if (includeSecondary) {
          whereClauses.add(
            "(muscle_group_name = 'Full Body' OR (is_compound = 1 AND (name LIKE '%Deadlift%' OR name LIKE '%Clean%' OR name LIKE '%Snatch%' OR name LIKE '%Burpee%' OR name LIKE '%Swing%' OR name LIKE '%Carry%')))",
          );
        } else {
          whereClauses.add("muscle_group_name = 'Full Body'");
        }
      } else {
        whereClauses.add('muscle_group_name LIKE ?');
        whereArgs.add('%$categoryName%');
      }
    } else if (muscleGroupId != null && muscleGroupId > 0) {
      whereClauses.add('muscle_group_id = ?');
      whereArgs.add(muscleGroupId);
    }

    if (secondaryMuscle != null &&
        secondaryMuscle.isNotEmpty &&
        secondaryMuscle.toLowerCase() != 'all') {
      whereClauses.add('secondary_muscles LIKE ?');
      whereArgs.add('%$secondaryMuscle%');
    }

    if (equipment != null &&
        equipment.isNotEmpty &&
        equipment.toLowerCase() != 'all') {
      whereClauses.add('equipment LIKE ?');
      whereArgs.add('%$equipment%');
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClauses.add(
        '(name LIKE ? OR target LIKE ? OR description LIKE ? OR instructions LIKE ? OR secondary_muscles LIKE ?)',
      );
      final q = '%${searchQuery.trim()}%';
      whereArgs.addAll([q, q, q, q, q]);
    }
    if (onlyFavourites == true) {
      whereClauses.add('is_favourite = 1');
    }
    if (onlyRecommended == true) {
      whereClauses.add('is_recommended = 1');
    }
    if (onlyCustom == true) {
      whereClauses.add('is_custom = 1');
    }
    if (difficulty != null &&
        difficulty.isNotEmpty &&
        difficulty.toLowerCase() != 'all') {
      whereClauses.add('difficulty = ?');
      whereArgs.add(difficulty);
    }

    String orderSql;
    switch (sortBy) {
      case 'name_desc':
        orderSql = 'name DESC';
        break;
      case 'difficulty':
        orderSql = "CASE difficulty WHEN 'Beginner' THEN 1 WHEN 'Intermediate' THEN 2 WHEN 'Advanced' THEN 3 ELSE 4 END ASC, name ASC";
        break;
      case 'recommended':
        orderSql = 'is_recommended DESC, name ASC';
        break;
      case 'name_asc':
      default:
        orderSql = 'name ASC';
        break;
    }

    final whereString = whereClauses.isNotEmpty
        ? whereClauses.join(' AND ')
        : null;
    final maps = await db.query(
      'exercises',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: orderSql,
    );
    return maps.map((m) => Exercise.fromMap(m)).toList();
  }

  Future<int> insertExercise(Exercise ex) async {
    final db = await _dbHelper.database;
    return await db.insert('exercises', ex.toMap());
  }

  Future<int> updateExercise(Exercise ex) async {
    final db = await _dbHelper.database;
    return await db.update(
      'exercises',
      ex.toMap(),
      where: 'id = ?',
      whereArgs: [ex.id],
    );
  }

  Future<int> deleteExercise(int id) async {
    final db = await _dbHelper.database;
    return await db.delete('exercises', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------- WORKOUT PLANS -------------------
  Future<WorkoutPlan?> getPlanForDate(String date) async {
    final db = await _dbHelper.database;
    final planMaps = await db.query(
      'workout_plans',
      where: 'date = ?',
      whereArgs: [date],
    );
    if (planMaps.isEmpty) return null;

    final planMap = planMaps.first;
    final planId = planMap['id'] as int;

    final peMaps = await db.query(
      'planned_exercises',
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'exercise_order ASC',
    );

    final exercises = peMaps.map((m) => PlannedExercise.fromMap(m)).toList();
    return WorkoutPlan.fromMap(planMap, exercises: exercises);
  }

  Future<WorkoutPlan?> getTodayPlan() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return await getPlanForDate(today);
  }

  Future<WorkoutPlan?> getTomorrowPlan() async {
    final tomorrow = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().add(const Duration(days: 1)));
    return await getPlanForDate(tomorrow);
  }

  Future<int> saveOrUpdatePlan(WorkoutPlan plan) async {
    final db = await _dbHelper.database;
    int planId;

    final existing = await db.query(
      'workout_plans',
      where: 'date = ?',
      whereArgs: [plan.date],
    );
    if (existing.isNotEmpty) {
      planId = existing.first['id'] as int;
      await db.update(
        'workout_plans',
        plan.copyWith(id: planId).toMap(),
        where: 'id = ?',
        whereArgs: [planId],
      );
      // Remove old planned exercises
      await db.delete(
        'planned_exercises',
        where: 'plan_id = ?',
        whereArgs: [planId],
      );
    } else {
      planId = await db.insert('workout_plans', plan.toMap());
    }

    // Insert planned exercises
    for (int i = 0; i < plan.exercises.length; i++) {
      final pe = plan.exercises[i].copyWith(planId: planId, exerciseOrder: i);
      await db.insert('planned_exercises', pe.toMap());
    }

    return planId;
  }

  Future<void> updateTomorrowPlanWithLog(
    WorkoutPlan revisedPlan, {
    required String changeDescription,
    String reason = 'Trainer-driven change',
  }) async {
    final planId = await saveOrUpdatePlan(revisedPlan);

    // Log the change
    await addChangeLog(
      PlanChangeLog(
        planId: planId,
        planDate: revisedPlan.date,
        changeDescription: changeDescription,
        reason: reason,
        changedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  Future<void> addExerciseToDatePlan(
    String date,
    Exercise exercise, {
    int targetSlot = 1,
    bool replaceSlotIfFull = false,
    int? customSets,
    int? customReps,
    double? customWeight,
    int? customRest,
  }) async {
    var plan = await getPlanForDate(date);
    if (plan == null) {
      plan = WorkoutPlan(
        date: date,
        primaryMuscleId: exercise.muscleGroupId,
        primaryMuscleName: exercise.muscleGroupName,
        exercises: [],
      );
    } else {
      // Manage slot allocation non-destructively
      if (plan.primaryMuscleId == null || plan.primaryMuscleId == 0) {
        plan = plan.copyWith(
          primaryMuscleId: exercise.muscleGroupId,
          primaryMuscleName: exercise.muscleGroupName,
        );
      } else if (plan.primaryMuscleId == exercise.muscleGroupId) {
        // Already matches primary slot
      } else if (plan.secondaryMuscleId == null ||
          plan.secondaryMuscleId == 0) {
        plan = plan.copyWith(
          secondaryMuscleId: exercise.muscleGroupId,
          secondaryMuscleName: exercise.muscleGroupName,
        );
      } else if (plan.secondaryMuscleId == exercise.muscleGroupId) {
        // Already matches secondary slot
      } else {
        // Both slots occupied by other groups: only replace if user explicitly agreed
        if (replaceSlotIfFull) {
          if (targetSlot == 1) {
            plan = plan.copyWith(
              primaryMuscleId: exercise.muscleGroupId,
              primaryMuscleName: exercise.muscleGroupName,
            );
          } else {
            plan = plan.copyWith(
              secondaryMuscleId: exercise.muscleGroupId,
              secondaryMuscleName: exercise.muscleGroupName,
            );
          }
        }
      }
    }

    final newPe = PlannedExercise(
      planId: plan.id ?? 0,
      exerciseId: exercise.id ?? 0,
      exerciseName: exercise.name,
      muscleGroupName: exercise.muscleGroupName,
      exerciseOrder: plan.exercises.length,
      targetSets: customSets ?? exercise.defaultSets,
      targetReps: customReps ?? exercise.defaultReps,
      targetWeightKg: customWeight ?? exercise.defaultWeightKg,
      restSeconds: customRest ?? exercise.restSeconds,
      imagePath: exercise.imagePath,
      exercise: exercise,
    );

    final updatedExercises = List<PlannedExercise>.from(plan.exercises)
      ..add(newPe);
    await saveOrUpdatePlan(plan.copyWith(exercises: updatedExercises));
  }

  Future<List<WorkoutPlan>> getWeeklyPlans(DateTime anchorDate) async {
    // Find Monday of the anchor week
    final int diff = anchorDate.weekday - DateTime.monday;
    final monday = anchorDate.subtract(Duration(days: diff));

    final splitDefaults = [
      {'primary': 'Chest', 'secondary': 'Triceps', 'rest': false}, // Mon
      {'primary': 'Back', 'secondary': 'Biceps', 'rest': false}, // Tue
      {
        'primary': 'Shoulders',
        'secondary': 'Abs and Core',
        'rest': false,
      }, // Wed
      {
        'primary': 'Quadriceps',
        'secondary': 'Hamstrings',
        'rest': false,
      }, // Thu
      {'primary': 'Chest', 'secondary': 'Back', 'rest': false}, // Fri
      {'primary': 'Biceps', 'secondary': 'Cardio', 'rest': false}, // Sat
      {'primary': 'Rest', 'secondary': null, 'rest': true}, // Sun
    ];

    final List<WorkoutPlan> result = [];
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final p = await getPlanForDate(dateStr);
      if (p != null) {
        result.add(p);
      } else {
        final def = splitDefaults[i];
        final isRest = def['rest'] as bool;
        result.add(
          WorkoutPlan(
            date: dateStr,
            isRestDay: isRest,
            primaryMuscleName: isRest ? null : (def['primary'] as String?),
            secondaryMuscleName: isRest ? null : (def['secondary'] as String?),
          ),
        );
      }
    }
    return result;
  }

  /// Configurable Six-Day Weekly Workout Split generator:
  /// Mon: Chest + Triceps
  /// Tue: Back + Biceps
  /// Wed: Shoulders + Abs
  /// Thu: Legs (Quads + Hamstrings)
  /// Fri: Chest + Back (Upper Body Hypertrophy)
  /// Sat: Arms + Cardio & Conditioning
  /// Sun: Rest & Active Recovery
  static const List<Map<String, dynamic>> sixDaySplitConfig = [
    // Day 1: Monday - Chest + Triceps
    {
      'day': 'Monday',
      'title': 'Chest & Triceps',
      'primaryId': 1,
      'primary': 'Chest',
      'secondaryId': 7,
      'secondary': 'Triceps',
      'isRest': false,
      'notes': 'Upper body push hypertrophy focusing on barbell press and triceps lockout.',
      'exerciseIds': [1, 2, 91, 95],
    },
    // Day 2: Tuesday - Back + Biceps
    {
      'day': 'Tuesday',
      'title': 'Back & Biceps',
      'primaryId': 2,
      'primary': 'Back',
      'secondaryId': 6,
      'secondary': 'Biceps',
      'isRest': false,
      'notes': 'Pull chain strength: Lat pulldown width and bent-over rowing thickness paired with dumbbell curls.',
      'exerciseIds': [26, 31, 69, 73],
    },
    // Day 3: Wednesday - Shoulders + Abs
    {
      'day': 'Wednesday',
      'title': 'Shoulders & Abs',
      'primaryId': 5,
      'primary': 'Shoulders',
      'secondaryId': 13,
      'secondary': 'Abs and Core',
      'isRest': false,
      'notes': 'Overhead shoulder capping with lateral delt raises and core stability.',
      'exerciseIds': [53, 58, 161, 176],
    },
    // Day 4: Thursday - Legs
    {
      'day': 'Thursday',
      'title': 'Legs & Calves',
      'primaryId': 9,
      'primary': 'Quadriceps',
      'secondaryId': 10,
      'secondary': 'Hamstrings',
      'isRest': false,
      'notes': 'Lower body power foundation: Heavy back squats, Romanian deadlifts, lunges, and calf raises.',
      'exerciseIds': [119, 134, 126, 154],
    },
    // Day 5: Friday - Chest + Back
    {
      'day': 'Friday',
      'title': 'Chest & Back',
      'primaryId': 1,
      'primary': 'Chest',
      'secondaryId': 2,
      'secondary': 'Back',
      'isRest': false,
      'notes': 'Antagonist upper body volume: Dumbbell pressing paired with seated cable rows.',
      'exerciseIds': [4, 10, 35, 26],
    },
    // Day 6: Saturday - Arms + Cardio
    {
      'day': 'Saturday',
      'title': 'Arms & Cardio',
      'primaryId': 6,
      'primary': 'Biceps',
      'secondaryId': 15,
      'secondary': 'Cardio',
      'isRest': false,
      'notes': 'Arm hypertrophy pump coupled with heart-pumping aerobic cardio conditioning.',
      'exerciseIds': [69, 73, 91, 192, 199],
    },
    // Day 7: Sunday - Rest & Recovery
    {
      'day': 'Sunday',
      'title': 'Rest & Recovery',
      'primaryId': null,
      'primary': null,
      'secondaryId': null,
      'secondary': null,
      'isRest': true,
      'notes': 'Scheduled full rest & recovery day. Focus on hydration, mobility, and complete muscle replenishment.',
      'exerciseIds': <int>[],
    },
  ];

  Future<void> applySixDaySplitPreset(
    DateTime anchorDate, {
    bool overwriteExisting = false,
  }) async {
    final int diff = anchorDate.weekday - DateTime.monday;
    final monday = anchorDate.subtract(Duration(days: diff));

    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final existingPlan = await getPlanForDate(dateStr);

      if (existingPlan != null &&
          existingPlan.exercises.isNotEmpty &&
          !overwriteExisting) {
        continue; // Preserve existing user-customized plan
      }

      final cfg = sixDaySplitConfig[i];
      final isRest = cfg['isRest'] as bool;

      final plan = WorkoutPlan(
        id: existingPlan?.id,
        date: dateStr,
        isRestDay: isRest,
        primaryMuscleId: cfg['primaryId'] as int?,
        primaryMuscleName: cfg['primary'] as String?,
        secondaryMuscleId: cfg['secondaryId'] as int?,
        secondaryMuscleName: cfg['secondary'] as String?,
        notes: cfg['notes'] as String?,
      );

      await saveOrUpdatePlan(plan);

      final exerciseIds = cfg['exerciseIds'] as List<int>;
      if (!isRest && exerciseIds.isNotEmpty) {
        for (int order = 0; order < exerciseIds.length; order++) {
          final exId = exerciseIds[order];
          final ex = await getExerciseById(exId);
          if (ex != null) {
            await addExerciseToDatePlan(dateStr, ex);
          }
        }
      }
    }
  }

  // ------------------- CHANGE LOGS -------------------
  Future<int> addChangeLog(PlanChangeLog log) async {
    final db = await _dbHelper.database;
    return await db.insert('plan_change_logs', log.toMap());
  }

  Future<List<PlanChangeLog>> getLogsForPlan(int planId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'plan_change_logs',
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'changed_at DESC',
    );
    return maps.map((m) => PlanChangeLog.fromMap(m)).toList();
  }

  // ------------------- WORKOUT SESSIONS & HISTORY -------------------
  Future<int> createWorkoutSession(WorkoutSession session) async {
    final db = await _dbHelper.database;
    final sessionId = await db.insert('workout_sessions', session.toMap());

    for (final s in session.sets) {
      await db.insert('workout_sets', s.toMap()..['session_id'] = sessionId);
    }

    // Mark plan as completed if planId matches
    if (session.planId != null) {
      await db.update(
        'workout_plans',
        {'is_completed': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [session.planId],
      );
    }

    return sessionId;
  }

  Future<List<WorkoutSession>> getAllSessions() async {
    final db = await _dbHelper.database;
    final sessionMaps = await db.query(
      'workout_sessions',
      orderBy: 'date DESC, id DESC',
    );
    final List<WorkoutSession> sessions = [];

    for (final sm in sessionMaps) {
      final sessionId = sm['id'] as int;
      final setMaps = await db.query(
        'workout_sets',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final sets = setMaps.map((m) => WorkoutSetRecord.fromMap(m)).toList();
      sessions.add(WorkoutSession.fromMap(sm, sets: sets));
    }
    return sessions;
  }

  Future<List<WorkoutSession>> getRecentSessions(int limit) async {
    final db = await _dbHelper.database;
    final sessionMaps = await db.query(
      'workout_sessions',
      orderBy: 'date DESC, id DESC',
      limit: limit,
    );
    final List<WorkoutSession> sessions = [];

    for (final sm in sessionMaps) {
      final sessionId = sm['id'] as int;
      final setMaps = await db.query(
        'workout_sets',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      final sets = setMaps.map((m) => WorkoutSetRecord.fromMap(m)).toList();
      sessions.add(WorkoutSession.fromMap(sm, sets: sets));
    }
    return sessions;
  }

  Future<List<WorkoutSession>> getSessionsForDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await _dbHelper.database;
    final sessionMaps = await db.query(
      'workout_sessions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date DESC, id DESC',
    );
    final List<WorkoutSession> sessions = [];

    for (final sm in sessionMaps) {
      final sessionId = sm['id'] as int;
      final setMaps = await db.query(
        'workout_sets',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'id ASC',
      );
      final sets = setMaps.map((m) => WorkoutSetRecord.fromMap(m)).toList();
      sessions.add(WorkoutSession.fromMap(sm, sets: sets));
    }
    return sessions;
  }

  Future<List<WorkoutSession>> getSessionsForDate(String date) async {
    final db = await _dbHelper.database;
    final sessionMaps = await db.query(
      'workout_sessions',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id DESC',
    );
    final List<WorkoutSession> sessions = [];

    for (final sm in sessionMaps) {
      final sessionId = sm['id'] as int;
      final setMaps = await db.query(
        'workout_sets',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'id ASC',
      );
      final sets = setMaps.map((m) => WorkoutSetRecord.fromMap(m)).toList();
      sessions.add(WorkoutSession.fromMap(sm, sets: sets));
    }
    return sessions;
  }

  Future<WeeklySummary> getWeeklySummary(DateTime anchorDate) async {
    // 1. Calculate Monday (start) and Sunday (end) of anchor week
    final anchorMidnight = DateTime(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
    );
    final monday = anchorMidnight.subtract(
      Duration(days: anchorDate.weekday - DateTime.monday),
    );
    final sunday = monday.add(const Duration(days: 6));
    final mondayStr = DateFormat('yyyy-MM-dd').format(monday);
    final sundayStr = DateFormat('yyyy-MM-dd').format(sunday);
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // 2. Fetch plans & sessions for the 7 days
    final weeklyPlans = await getWeeklyPlans(anchorDate);
    final weeklySessions = await getSessionsForDateRange(mondayStr, sundayStr);

    final List<DayWorkoutSummary> days = [];
    int totalCompletedWorkouts = 0;
    int totalPlannedWorkouts = 0;
    int totalRestDays = 0;
    double totalVolumeKg = 0;
    int totalDurationSeconds = 0;
    final Set<String> distinctExercisesCompletedThisWeek = {};

    for (int i = 0; i < 7; i++) {
      final dayDate = monday.add(Duration(days: i));
      final dayStr = DateFormat('yyyy-MM-dd').format(dayDate);
      final dayName = DateFormat('E').format(dayDate); // Mon, Tue, etc.
      final isToday = (dayStr == todayStr);

      // Find plan for this day
      final plan = weeklyPlans.firstWhere(
        (p) => p.date == dayStr,
        orElse: () => WorkoutPlan(date: dayStr, isRestDay: (i == 6)),
      );

      // Find sessions on this day
      final daySessions = weeklySessions
          .where((s) => s.date == dayStr)
          .toList();

      DayStatus dayStatus;
      String? primaryMuscle;
      String? secondaryMuscle;
      int plannedExCount = plan.exercises.length;
      int completedExCount = 0;

      if (daySessions.isNotEmpty) {
        totalCompletedWorkouts += daySessions.length;
        for (final s in daySessions) {
          totalDurationSeconds += s.durationSeconds;
          totalVolumeKg += s.totalVolumeKg;
          final names = s.completedExerciseNames;
          distinctExercisesCompletedThisWeek.addAll(names);
          completedExCount += names.length;
        }

        primaryMuscle = daySessions.first.primaryMuscle;
        secondaryMuscle =
            daySessions.first.secondaryMuscle ?? plan.secondaryMuscleName;

        // Check if any set was incomplete or planned exercises skipped
        if (daySessions.any(
          (s) => s.completionStatus == 'Partially Completed',
        )) {
          dayStatus = DayStatus.partiallyCompleted;
        } else if (plan.exercises.isNotEmpty &&
            completedExCount < plan.exercises.length) {
          dayStatus = DayStatus.partiallyCompleted;
        } else {
          dayStatus = DayStatus.completed;
        }
      } else {
        // No sessions recorded for this day
        primaryMuscle = plan.primaryMuscleName;
        secondaryMuscle = plan.secondaryMuscleName;

        if (plan.isRestDay) {
          dayStatus = DayStatus.restDay;
          totalRestDays++;
        } else if (plan.exercises.isNotEmpty) {
          totalPlannedWorkouts++;
          if (dayStr.compareTo(todayStr) < 0) {
            dayStatus = DayStatus.missed;
          } else {
            dayStatus = DayStatus.planned;
          }
        } else {
          // No exercises configured and not explicitly a workout day -> default rest
          dayStatus = DayStatus.restDay;
          totalRestDays++;
        }
      }

      days.add(
        DayWorkoutSummary(
          date: dayDate,
          dateStr: dayStr,
          dayName: dayName,
          status: dayStatus,
          primaryMuscle: primaryMuscle,
          secondaryMuscle: secondaryMuscle,
          plannedExerciseCount: plannedExCount,
          completedExerciseCount: completedExCount,
          plan: plan,
          sessions: daySessions,
          isToday: isToday,
        ),
      );
    }

    return WeeklySummary(
      startOfWeek: monday,
      endOfWeek: sunday,
      days: days,
      workoutsCompleted: totalCompletedWorkouts,
      exercisesCompleted: distinctExercisesCompletedThisWeek.length,
      plannedWorkouts: totalPlannedWorkouts,
      restDays: totalRestDays,
      totalVolumeKg: totalVolumeKg,
      totalDurationSeconds: totalDurationSeconds,
    );
  }

  Future<Map<String, int>> getMuscleFrequencyStats({
    String? startDate,
    String? endDate,
  }) async {
    final List<WorkoutSession> sessions;
    if (startDate != null && endDate != null) {
      sessions = await getSessionsForDateRange(startDate, endDate);
    } else {
      sessions = await getAllSessions();
    }

    final Map<String, int> counts = {
      'Chest': 0,
      'Back': 0,
      'Shoulders': 0,
      'Biceps': 0,
      'Triceps': 0,
      'Legs': 0,
      'Abs': 0,
      'Full Body': 0,
    };

    for (final s in sessions) {
      final musclesToTest = [
        s.primaryMuscle,
        if (s.secondaryMuscle != null) s.secondaryMuscle!,
      ];

      final Set<String> matchedCategories = {};

      for (final m in musclesToTest) {
        final lower = m.toLowerCase();
        if (lower.contains('chest')) matchedCategories.add('Chest');
        if (lower.contains('back') ||
            lower.contains('lat') ||
            lower.contains('trap')) {
          matchedCategories.add('Back');
        }
        if (lower.contains('shoulder') || lower.contains('delt')) {
          matchedCategories.add('Shoulders');
        }
        if (lower.contains('bicep')) matchedCategories.add('Biceps');
        if (lower.contains('tricep')) matchedCategories.add('Triceps');
        if (lower.contains('leg') ||
            lower.contains('quad') ||
            lower.contains('hamstring') ||
            lower.contains('glute') ||
            lower.contains('calv') ||
            lower.contains('calf')) {
          matchedCategories.add('Legs');
        }
        if (lower.contains('ab') || lower.contains('core')) {
          matchedCategories.add('Abs');
        }
        if (lower.contains('full body') || lower.contains('compound')) {
          matchedCategories.add('Full Body');
        }
      }

      if (matchedCategories.isEmpty) {
        counts[s.primaryMuscle] = (counts[s.primaryMuscle] ?? 0) + 1;
      } else {
        for (final cat in matchedCategories) {
          counts[cat] = (counts[cat] ?? 0) + 1;
        }
      }
    }

    return counts;
  }

  Future<List<WorkoutSession>> getSessionsForMuscle(
    String muscleCategory, {
    String? startDate,
    String? endDate,
  }) async {
    final List<WorkoutSession> all;
    if (startDate != null && endDate != null) {
      all = await getSessionsForDateRange(startDate, endDate);
    } else {
      all = await getAllSessions();
    }

    final target = muscleCategory.toLowerCase();
    return all.where((s) {
      final p = s.primaryMuscle.toLowerCase();
      final sec = (s.secondaryMuscle ?? '').toLowerCase();

      if (target == 'all') {
        return true;
      }
      if (target == 'chest') {
        return p.contains('chest') || sec.contains('chest');
      }
      if (target == 'back') {
        return p.contains('back') ||
            p.contains('lat') ||
            p.contains('trap') ||
            sec.contains('back') ||
            sec.contains('lat') ||
            sec.contains('trap');
      }
      if (target == 'shoulders') {
        return p.contains('shoulder') ||
            p.contains('delt') ||
            sec.contains('shoulder') ||
            sec.contains('delt');
      }
      if (target == 'biceps') {
        return p.contains('bicep') || sec.contains('bicep');
      }
      if (target == 'triceps') {
        return p.contains('tricep') || sec.contains('tricep');
      }
      if (target == 'legs') {
        return p.contains('leg') ||
            p.contains('quad') ||
            p.contains('hamstring') ||
            p.contains('glute') ||
            p.contains('calv') ||
            p.contains('calf') ||
            sec.contains('leg') ||
            sec.contains('quad') ||
            sec.contains('hamstring') ||
            sec.contains('glute') ||
            sec.contains('calv') ||
            sec.contains('calf');
      }
      if (target == 'abs') {
        return p.contains('ab') ||
            p.contains('core') ||
            sec.contains('ab') ||
            sec.contains('core');
      }
      if (target == 'full body') {
        return p.contains('full body') || sec.contains('full body');
      }

      return p.contains(target) || sec.contains(target);
    }).toList();
  }

  Future<void> deleteWorkoutSession(int sessionId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'workout_sets',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    await db.delete(
      'media_attachments',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['session', sessionId],
    );
    await db.delete(
      'workout_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // ------------------- MEDIA ATTACHMENTS -------------------
  Future<int> insertMediaAttachment(MediaAttachment attachment) async {
    final db = await _dbHelper.database;
    return await db.insert('media_attachments', attachment.toMap());
  }

  Future<int> updateMediaAttachment(MediaAttachment attachment) async {
    final db = await _dbHelper.database;
    return await db.update(
      'media_attachments',
      attachment.toMap(),
      where: 'id = ?',
      whereArgs: [attachment.id],
    );
  }

  Future<List<MediaAttachment>> getMediaAttachments(
    String entityType,
    int entityId,
  ) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'media_attachments',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => MediaAttachment.fromMap(m)).toList();
  }

  Future<List<MediaAttachment>> getAllMedia() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'media_attachments',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => MediaAttachment.fromMap(m)).toList();
  }

  Future<int> deleteMediaAttachment(int id) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'media_attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ------------------- SETTINGS -------------------
  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'user_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return defaultValue;
    return maps.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _dbHelper.database;
    await db.insert('user_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------- BACKUP & EXPORT -------------------
  Future<String> exportBackupJson() async {
    final db = await _dbHelper.database;
    final muscleGroups = await db.query('muscle_groups');
    final exercises = await db.query('exercises');
    final workoutPlans = await db.query('workout_plans');
    final plannedExercises = await db.query('planned_exercises');
    final workoutSessions = await db.query('workout_sessions');
    final workoutSets = await db.query('workout_sets');
    final mediaAttachments = await db.query('media_attachments');
    final planChangeLogs = await db.query('plan_change_logs');
    final userSettings = await db.query('user_settings');

    final backup = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'muscle_groups': muscleGroups,
      'exercises': exercises,
      'workout_plans': workoutPlans,
      'planned_exercises': plannedExercises,
      'workout_sessions': workoutSessions,
      'workout_sets': workoutSets,
      'media_attachments': mediaAttachments,
      'plan_change_logs': planChangeLogs,
      'user_settings': userSettings,
    };

    return jsonEncode(backup);
  }

  Future<bool> restoreBackupJson(String jsonStr) async {
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final db = await _dbHelper.database;

      await db.transaction((txn) async {
        // Clear tables
        await txn.delete('workout_sets');
        await txn.delete('workout_sessions');
        await txn.delete('planned_exercises');
        await txn.delete('workout_plans');
        await txn.delete('plan_change_logs');
        await txn.delete('media_attachments');
        await txn.delete('exercises');
        await txn.delete('muscle_groups');
        await txn.delete('user_settings');

        for (final item in (data['muscle_groups'] as List? ?? [])) {
          await txn.insert('muscle_groups', Map<String, dynamic>.from(item));
        }
        for (final item in (data['exercises'] as List? ?? [])) {
          await txn.insert('exercises', Map<String, dynamic>.from(item));
        }
        for (final item in (data['workout_plans'] as List? ?? [])) {
          await txn.insert('workout_plans', Map<String, dynamic>.from(item));
        }
        for (final item in (data['planned_exercises'] as List? ?? [])) {
          await txn.insert(
            'planned_exercises',
            Map<String, dynamic>.from(item),
          );
        }
        for (final item in (data['workout_sessions'] as List? ?? [])) {
          await txn.insert('workout_sessions', Map<String, dynamic>.from(item));
        }
        for (final item in (data['workout_sets'] as List? ?? [])) {
          await txn.insert('workout_sets', Map<String, dynamic>.from(item));
        }
        for (final item in (data['media_attachments'] as List? ?? [])) {
          await txn.insert(
            'media_attachments',
            Map<String, dynamic>.from(item),
          );
        }
        for (final item in (data['plan_change_logs'] as List? ?? [])) {
          await txn.insert('plan_change_logs', Map<String, dynamic>.from(item));
        }
        for (final item in (data['user_settings'] as List? ?? [])) {
          await txn.insert('user_settings', Map<String, dynamic>.from(item));
        }
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> clearAllData() async {
    await _dbHelper.clearAllData();
  }
}
