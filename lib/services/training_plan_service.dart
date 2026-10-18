import 'package:sqflite/sqflite.dart';

import '../core/clock.dart';
import '../data/db_helper.dart';
import '../models/training_plan.dart';
import '../models/workout_plan.dart';
import 'access_guard.dart';

/// Named weekly training plans (CRUD, duplicate, activate) and the bridge that
/// turns the active plan's weekday into a dated [WorkoutPlan].
///
/// Existing dated plans (`workout_plans`) are never overwritten unless the
/// caller explicitly asks and the day is not completed.
class TrainingPlanService {
  TrainingPlanService({DatabaseHelper? helper})
    : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  // ---------------------------------------------------------------- reads

  Future<List<TrainingPlan>> listPlans() async {
    final db = await _db;
    final rows = await db.query(
      'training_plans',
      where: 'deleted_at IS NULL',
      orderBy: 'is_active DESC, updated_at DESC',
    );
    final plans = <TrainingPlan>[];
    for (final r in rows) {
      plans.add(await _hydrate(db, r));
    }
    return plans;
  }

  Future<TrainingPlan?> getPlan(int id) async {
    final db = await _db;
    final rows = await db.query(
      'training_plans',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _hydrate(db, rows.first);
  }

  Future<TrainingPlan?> getActivePlan() async {
    final db = await _db;
    final rows = await db.query(
      'training_plans',
      where: 'is_active = 1 AND deleted_at IS NULL',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _hydrate(db, rows.first);
  }

  Future<int> countPlans() async {
    final db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM training_plans WHERE deleted_at IS NULL',
          ),
        ) ??
        0;
  }

  Future<TrainingPlan> _hydrate(
    DatabaseExecutor db,
    Map<String, Object?> r,
  ) async {
    final planId = r['id'] as int;
    final dayRows = await db.query(
      'training_plan_days',
      where: 'plan_id = ?',
      whereArgs: [planId],
    );
    final byWeekday = {for (final d in dayRows) d['weekday'] as int: d};
    final days = <TrainingPlanDay>[];
    for (var wd = 1; wd <= 7; wd++) {
      final d = byWeekday[wd];
      if (d == null) {
        days.add(TrainingPlanDay(weekday: wd, isRest: true));
        continue;
      }
      final exRows = await db.query(
        'training_plan_day_exercises',
        where: 'day_id = ?',
        whereArgs: [d['id']],
        orderBy: 'exercise_order ASC, id ASC',
      );
      days.add(
        TrainingPlanDay(
          id: d['id'] as int,
          weekday: wd,
          isRest: (d['is_rest'] as int? ?? 0) == 1,
          title: d['title'] as String?,
          notes: d['notes'] as String?,
          exercises: exRows.map(TrainingPlanExercise.fromMap).toList(),
        ),
      );
    }
    return TrainingPlan(
      id: planId,
      name: r['name'] as String,
      notes: r['notes'] as String?,
      isActive: (r['is_active'] as int? ?? 0) == 1,
      createdAt: r['created_at'] as String?,
      updatedAt: r['updated_at'] as String?,
      days: days,
    );
  }

  // --------------------------------------------------------------- writes

  /// Inserts (id == null) or fully replaces the plan with its days/exercises
  /// in one transaction. Returns the plan id. Throws [ArgumentError] on
  /// invalid data so a bad editor state can never be half-saved.
  Future<int> savePlan(TrainingPlan plan) async {
    AccessGuard.ensureWritable();
    final nameError = TrainingPlanValidator.validateName(plan.name);
    if (nameError != null) throw ArgumentError(nameError);
    for (final d in plan.days) {
      if (d.isRest) continue;
      for (final e in d.exercises) {
        final err = TrainingPlanValidator.validateExercise(e);
        if (err != null) {
          throw ArgumentError('${e.exerciseName}: $err');
        }
      }
    }

    final db = await _db;
    final now = AppClock.now().toIso8601String();
    return db.transaction((txn) async {
      int planId;
      if (plan.id == null) {
        planId = await txn.insert('training_plans', {
          'name': plan.name.trim(),
          'notes': plan.notes,
          'is_active': 0,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        planId = plan.id!;
        final updated = await txn.update(
          'training_plans',
          {'name': plan.name.trim(), 'notes': plan.notes, 'updated_at': now},
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [planId],
        );
        if (updated == 0) throw StateError('Plan $planId no longer exists');
        final oldDays = await txn.query(
          'training_plan_days',
          columns: ['id'],
          where: 'plan_id = ?',
          whereArgs: [planId],
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
          whereArgs: [planId],
        );
      }

      for (final day in plan.days) {
        final dayId = await txn.insert('training_plan_days', {
          'plan_id': planId,
          'weekday': day.weekday,
          'is_rest': day.isRest ? 1 : 0,
          'title': day.title,
          'notes': day.notes,
        });
        if (day.isRest) continue;
        for (var i = 0; i < day.exercises.length; i++) {
          final e = day.exercises[i].copyWith(exerciseOrder: i);
          await txn.insert('training_plan_day_exercises', {
            ...e.toMap()..remove('id'),
            'day_id': dayId,
          });
        }
      }
      return planId;
    });
  }

  /// Copies a plan (days + exercises) under a unique "Copy of ..." name.
  /// The copy is never active.
  Future<int> duplicatePlan(int id) async {
    final src = await getPlan(id);
    if (src == null) throw StateError('Plan $id not found');
    final names = (await listPlans()).map((p) => p.name).toSet();
    var candidate = 'Copy of ${src.name}';
    var n = 2;
    while (names.contains(candidate)) {
      candidate = 'Copy of ${src.name} ($n)';
      n++;
    }
    final copy = TrainingPlan(
      name: candidate.length > TrainingPlanValidator.maxNameLength
          ? candidate.substring(0, TrainingPlanValidator.maxNameLength)
          : candidate,
      notes: src.notes,
      days: [
        for (final d in src.days)
          TrainingPlanDay(
            weekday: d.weekday,
            isRest: d.isRest,
            title: d.title,
            notes: d.notes,
            exercises: [
              for (final e in d.exercises)
                TrainingPlanExercise(
                  exerciseId: e.exerciseId,
                  exerciseName: e.exerciseName,
                  muscleGroupName: e.muscleGroupName,
                  exerciseOrder: e.exerciseOrder,
                  targetSets: e.targetSets,
                  targetReps: e.targetReps,
                  targetWeightKg: e.targetWeightKg,
                  restSeconds: e.restSeconds,
                  targetDurationSeconds: e.targetDurationSeconds,
                  targetDistanceKm: e.targetDistanceKm,
                  notes: e.notes,
                ),
            ],
          ),
      ],
    );
    return savePlan(copy);
  }

  /// Soft delete: the plan disappears from the app, dated plans and past
  /// sessions that came from it are untouched.
  Future<void> deletePlan(int id) async {
    AccessGuard.ensureWritable();
    final db = await _db;
    await db.update(
      'training_plans',
      {
        'deleted_at': AppClock.now().toIso8601String(),
        'is_active': 0,
        'updated_at': AppClock.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Makes [id] the only active plan (null deactivates all).
  Future<void> setActivePlan(int? id) async {
    AccessGuard.ensureWritable();
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('training_plans', {'is_active': 0});
      if (id != null) {
        await txn.update(
          'training_plans',
          {'is_active': 1, 'updated_at': AppClock.now().toIso8601String()},
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [id],
        );
      }
    });
  }

  // ------------------------------------------------- plan -> dated workout

  /// Dated plan for [date] built from [plan]'s weekday. Pure, no I/O.
  WorkoutPlan buildDatedPlan(TrainingPlan plan, DateTime date) {
    final day = plan.dayFor(date.weekday);
    final key = AppClock.dateKey(date);
    if (day.isRest) {
      return WorkoutPlan(
        date: key,
        isRestDay: true,
        notes: day.notes ?? day.title,
      );
    }
    final counts = <String, int>{};
    for (final e in day.exercises) {
      if (e.muscleGroupName.isEmpty) continue;
      counts[e.muscleGroupName] = (counts[e.muscleGroupName] ?? 0) + 1;
    }
    final muscles = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return WorkoutPlan(
      date: key,
      primaryMuscleName: muscles.isNotEmpty ? muscles[0] : null,
      secondaryMuscleName: muscles.length > 1 ? muscles[1] : null,
      notes: day.notes ?? day.title,
    );
  }

  /// Creates the dated plan for [date] from the active plan **only if none
  /// exists yet** and [date] is today or later. Returns the dated plan row id
  /// (existing or new) or null when nothing applies. Idempotent.
  Future<int?> materializeDate(DateTime date, {bool overwrite = false}) async {
    if (AccessGuard.locked) return null; // reading must not write while locked
    final db = await _db;
    final today = DateTime(
      AppClock.now().year,
      AppClock.now().month,
      AppClock.now().day,
    );
    final dayOnly = DateTime(date.year, date.month, date.day);
    if (dayOnly.isBefore(today)) return null;

    final key = AppClock.dateKey(dayOnly);
    final existing = await db.query(
      'workout_plans',
      where: 'date = ?',
      whereArgs: [key],
    );
    if (existing.isNotEmpty) {
      final completed = (existing.first['is_completed'] as int? ?? 0) == 1;
      if (!overwrite || completed) return existing.first['id'] as int;
    }

    final plan = await getActivePlan();
    if (plan == null) {
      return existing.isNotEmpty ? existing.first['id'] as int : null;
    }

    final dated = buildDatedPlan(plan, dayOnly);
    final day = plan.dayFor(dayOnly.weekday);
    final now = AppClock.now().toIso8601String();

    return db.transaction((txn) async {
      int planId;
      if (existing.isNotEmpty) {
        planId = existing.first['id'] as int;
        await txn.delete(
          'planned_exercises',
          where: 'plan_id = ?',
          whereArgs: [planId],
        );
        await txn.update(
          'workout_plans',
          {..._planRow(dated), 'updated_at': now},
          where: 'id = ?',
          whereArgs: [planId],
        );
      } else {
        planId = await txn.insert('workout_plans', {
          ..._planRow(dated),
          'created_at': now,
          'updated_at': now,
        });
      }
      await _fillMuscleIds(txn, planId, dated);
      if (!day.isRest) {
        for (var i = 0; i < day.exercises.length; i++) {
          final pe = day.exercises[i].toPlanned(planId, i);
          await txn.insert('planned_exercises', pe.toMap()..remove('id'));
        }
      }
      return planId;
    });
  }

  Map<String, Object?> _planRow(WorkoutPlan p) => {
    'date': p.date,
    'primary_muscle_name': p.primaryMuscleName,
    'secondary_muscle_name': p.secondaryMuscleName,
    'notes': p.notes,
    'is_completed': 0,
    'is_rest_day': p.isRestDay ? 1 : 0,
  };

  Future<void> _fillMuscleIds(
    DatabaseExecutor txn,
    int planId,
    WorkoutPlan dated,
  ) async {
    Future<int?> idFor(String? name) async {
      if (name == null) return null;
      final r = await txn.query(
        'muscle_groups',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      return r.isEmpty ? null : r.first['id'] as int;
    }

    await txn.update(
      'workout_plans',
      {
        'primary_muscle_id': await idFor(dated.primaryMuscleName),
        'secondary_muscle_id': await idFor(dated.secondaryMuscleName),
      },
      where: 'id = ?',
      whereArgs: [planId],
    );
  }
}
