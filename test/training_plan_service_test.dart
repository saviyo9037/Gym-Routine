import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:reptrack/models/training_plan.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/services/training_plan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

TrainingPlanExercise ex(
  int id,
  String name,
  String group, {
  int sets = 3,
  int reps = 10,
  double kg = 20,
  int? seconds,
  double? km,
}) => TrainingPlanExercise(
  exerciseId: id,
  exerciseName: name,
  muscleGroupName: group,
  targetSets: sets,
  targetReps: reps,
  targetWeightKg: kg,
  targetDurationSeconds: seconds,
  targetDistanceKm: km,
);

TrainingPlan sixDayPlan(String name) {
  // Mon..Sat training, Sun rest. Day 1 deliberately has 12 exercises.
  final days = <TrainingPlanDay>[
    TrainingPlanDay(
      weekday: 1,
      title: 'Push',
      exercises: [
        for (var i = 0; i < 12; i++) ex(100 + i, 'Press $i', 'Chest'),
      ],
    ),
    TrainingPlanDay(weekday: 2, exercises: [ex(2, 'Row', 'Back')]),
    TrainingPlanDay(weekday: 3, exercises: [ex(3, 'OHP', 'Shoulders')]),
    TrainingPlanDay(weekday: 4, exercises: [ex(4, 'Squat', 'Quadriceps')]),
    TrainingPlanDay(weekday: 5, exercises: [ex(5, 'Curl', 'Biceps')]),
    TrainingPlanDay(
      weekday: 6,
      exercises: [ex(6, 'Treadmill Running', 'Cardio', seconds: 1200, km: 3)],
    ),
    const TrainingPlanDay(weekday: 7, isRest: true),
  ];
  return TrainingPlan(name: name, days: days);
}

void main() {
  late Database db;
  late TrainingPlanService svc;

  setUp(() async {
    db = await openTestDatabase();
    // The factory seeds starter dated plans for the real "today"; start empty.
    await db.delete('planned_exercises');
    await db.delete('workout_plans');
    svc = TrainingPlanService();
  });

  tearDown(() async {
    AppClock.reset();
    await closeTestDatabase(db);
  });

  group('schema v6 migration', () {
    test(
      'upgrade from v5 keeps existing user data and is idempotent',
      () async {
        // Rebuild a v5-shaped database: drop everything v6 added.
        await db.execute('DROP TABLE training_plan_day_exercises');
        await db.execute('DROP TABLE training_plan_days');
        await db.execute('DROP TABLE training_plans');
        await db.execute('DROP TABLE active_sessions');
        await db.execute('DROP INDEX idx_sessions_client_ref');
        await db.execute('ALTER TABLE workout_sessions DROP COLUMN client_ref');
        await db.execute(
          'ALTER TABLE workout_sets DROP COLUMN duration_seconds',
        );
        await db.execute('ALTER TABLE workout_sets DROP COLUMN distance_km');
        await db.execute(
          'ALTER TABLE planned_exercises DROP COLUMN target_duration_seconds',
        );
        await db.execute(
          'ALTER TABLE planned_exercises DROP COLUMN target_distance_km',
        );

        final sessionId = await db.insert('workout_sessions', {
          'date': '2026-01-05',
          'start_time': '07:00',
          'duration_seconds': 3000,
          'primary_muscle': 'Chest',
          'created_at': '2026-01-05T07:00:00',
        });
        await db.insert('workout_sets', {
          'session_id': sessionId,
          'exercise_id': 1,
          'exercise_name': 'Barbell Bench Press',
          'set_number': 1,
          'reps': 8,
          'weight_kg': 62.5,
          'is_completed': 1,
          'completed_at': '2026-01-05T07:10:00',
        });

        await DatabaseHelper.instance.upgradeForTesting(db, 5, 6);
        await DatabaseHelper.instance.upgradeForTesting(db, 5, 6); // twice

        final sets = await db.query('workout_sets');
        expect(sets.length, 1);
        expect(sets.first['weight_kg'], 62.5);
        expect(sets.first['duration_seconds'], isNull);
        final sessions = await db.query('workout_sessions');
        expect(sessions.length, 1);
        expect(sessions.first['client_ref'], isNull);
        // New tables are usable.
        expect(await svc.listPlans(), isEmpty);
      },
    );

    test('catalogue seeding stays idempotent across repeated syncs', () async {
      final before = (await db.query('exercises')).length;
      await DatabaseHelper.instance.syncCatalogue(db);
      await DatabaseHelper.instance.syncCatalogue(db);
      expect((await db.query('exercises')).length, before);
      expect(before, 201);
    });
  });

  group('plan CRUD', () {
    test(
      'six training days; day 1 holds 12 exercises (no artificial limit)',
      () async {
        final id = await svc.savePlan(sixDayPlan('PPL'));
        final plan = (await svc.getPlan(id))!;
        expect(plan.trainingDayCount, 6);
        expect(plan.dayFor(1).exercises.length, 12);
        expect(plan.dayFor(7).isRest, isTrue);
        expect(plan.dayFor(6).exercises.single.targetDistanceKm, 3);
        expect(plan.dayFor(6).exercises.single.targetDurationSeconds, 1200);
        // order preserved
        expect(plan.dayFor(1).exercises.map((e) => e.exerciseId).toList(), [
          for (var i = 0; i < 12; i++) 100 + i,
        ]);
      },
    );

    test('very large plan (60 exercises per day) saves and reloads', () async {
      final days = [
        for (var d = 1; d <= 7; d++)
          TrainingPlanDay(
            weekday: d,
            exercises: [for (var i = 0; i < 60; i++) ex(i + 1, 'E$i', 'Chest')],
          ),
      ];
      final id = await svc.savePlan(TrainingPlan(name: 'Huge', days: days));
      final plan = (await svc.getPlan(id))!;
      expect(plan.exerciseCount, 420);
    });

    test('edit replaces days and exercises, keeps the id', () async {
      final id = await svc.savePlan(sixDayPlan('A'));
      final plan = (await svc.getPlan(id))!;
      final edited = plan.copyWith(
        name: 'A v2',
        days: [
          for (final d in plan.days)
            d.weekday == 1
                ? d.copyWith(exercises: [ex(1, 'Only', 'Chest')])
                : d,
        ],
      );
      expect(await svc.savePlan(edited), id);
      final back = (await svc.getPlan(id))!;
      expect(back.name, 'A v2');
      expect(back.dayFor(1).exercises.single.exerciseName, 'Only');
      expect(await svc.countPlans(), 1);
    });

    test(
      'duplicate copies everything under a unique name, never active',
      () async {
        final id = await svc.savePlan(sixDayPlan('PPL'));
        await svc.setActivePlan(id);
        final c1 = await svc.duplicatePlan(id);
        final c2 = await svc.duplicatePlan(id);
        final p1 = (await svc.getPlan(c1))!;
        final p2 = (await svc.getPlan(c2))!;
        expect(p1.name, 'Copy of PPL');
        expect(p2.name, 'Copy of PPL (2)');
        expect(p1.isActive, isFalse);
        expect(p1.dayFor(1).exercises.length, 12);
        expect((await svc.getActivePlan())!.id, id);
      },
    );

    test('delete is soft: hidden everywhere, dated plans untouched', () async {
      final id = await svc.savePlan(sixDayPlan('PPL'));
      await svc.setActivePlan(id);
      AppClock.setForTesting(() => DateTime(2026, 10, 19, 8)); // Monday
      await svc.materializeDate(AppClock.now());
      await svc.deletePlan(id);
      expect(await svc.getPlan(id), isNull);
      expect(await svc.listPlans(), isEmpty);
      expect(await svc.getActivePlan(), isNull);
      final dated = await DatabaseService().getPlanForDate('2026-10-19');
      expect(dated!.exercises.length, 12);
      // row kept for sync/undo
      expect(
        (await db.query('training_plans')).single['deleted_at'],
        isNotNull,
      );
    });

    test('only one plan can be active', () async {
      final a = await svc.savePlan(sixDayPlan('A'));
      final b = await svc.savePlan(sixDayPlan('B'));
      await svc.setActivePlan(a);
      await svc.setActivePlan(b);
      final plans = await svc.listPlans();
      expect(plans.where((p) => p.isActive).map((p) => p.id), [b]);
      await svc.setActivePlan(null);
      expect(await svc.getActivePlan(), isNull);
    });

    test('invalid data is rejected and nothing is half-saved', () async {
      expect(() => svc.savePlan(TrainingPlan(name: '  ')), throwsArgumentError);
      final bad = TrainingPlan(
        name: 'Bad',
        days: [
          TrainingPlanDay(
            weekday: 1,
            exercises: [ex(1, 'Curl', 'Biceps', sets: 0)],
          ),
          ...List.generate(
            6,
            (i) => TrainingPlanDay(weekday: i + 2, isRest: true),
          ),
        ],
      );
      expect(() => svc.savePlan(bad), throwsArgumentError);
      expect(await svc.countPlans(), 0);
      expect((await db.query('training_plan_days')), isEmpty);
    });

    test(
      'a deleted catalogue exercise in a plan still loads (name snapshot)',
      () async {
        final id = await svc.savePlan(sixDayPlan('PPL'));
        await db.delete('exercises', where: 'id = ?', whereArgs: [2]);
        final plan = (await svc.getPlan(id))!;
        expect(plan.dayFor(2).exercises.single.exerciseName, 'Row');
      },
    );
  });

  group('validation', () {
    test('decimal weights are valid, cardio needs time or distance', () {
      expect(
        TrainingPlanValidator.validateExercise(
          ex(1, 'Curl', 'Biceps', kg: 12.5),
        ),
        isNull,
      );
      expect(
        TrainingPlanValidator.validateExercise(
          ex(2, 'Treadmill Running', 'Cardio', reps: 0, kg: 0),
        ),
        'Enter a time or a distance',
      );
      expect(
        TrainingPlanValidator.validateExercise(
          ex(2, 'Treadmill Running', 'Cardio', seconds: 600),
        ),
        isNull,
      );
      expect(
        TrainingPlanValidator.validateExercise(ex(1, 'Curl', 'Biceps', kg: -1)),
        isNotNull,
      );
      expect(TrainingPlanValidator.validateName('x' * 61), isNotNull);
    });

    test('duplicate exercises in a day are detected', () {
      final day = TrainingPlanDay(
        weekday: 1,
        exercises: [
          ex(1, 'A', 'Chest'),
          ex(2, 'B', 'Chest'),
          ex(1, 'A', 'Chest'),
        ],
      );
      expect(TrainingPlanValidator.duplicateExerciseIds(day), {1});
    });
  });

  group('applying the active plan to dates', () {
    test(
      'today comes from the active plan weekday and is created once',
      () async {
        final id = await svc.savePlan(sixDayPlan('PPL'));
        await svc.setActivePlan(id);
        AppClock.setForTesting(() => DateTime(2026, 10, 20, 9)); // Tuesday
        final dbs = DatabaseService();
        final today = (await dbs.getTodayPlan())!;
        expect(today.date, '2026-10-20');
        expect(today.exercises.single.exerciseName, 'Row');
        expect(today.primaryMuscleName, 'Back');
        expect(today.isRestDay, isFalse);
        final again = (await dbs.getTodayPlan())!;
        expect(again.id, today.id);
        expect((await db.query('workout_plans')).length, 1);
      },
    );

    test('a saved dated plan is never overwritten by the template', () async {
      final id = await svc.savePlan(sixDayPlan('PPL'));
      await svc.setActivePlan(id);
      AppClock.setForTesting(() => DateTime(2026, 10, 20, 9));
      final dbs = DatabaseService();
      final first = (await dbs.getTodayPlan())!;
      await dbs.saveOrUpdatePlan(first.copyWith(exercises: const []));
      final after = (await dbs.getTodayPlan())!;
      expect(after.exercises, isEmpty);
    });

    test('sunday is a rest day; past dates are never materialised', () async {
      final id = await svc.savePlan(sixDayPlan('PPL'));
      await svc.setActivePlan(id);
      AppClock.setForTesting(() => DateTime(2026, 10, 25, 9)); // Sunday
      final today = (await DatabaseService().getTodayPlan())!;
      expect(today.isRestDay, isTrue);
      expect(await DatabaseService().getPlanForDate('2026-10-19'), isNull);
      expect(await svc.materializeDate(DateTime(2026, 10, 19)), isNull);
    });

    test('no active plan: nothing is created', () async {
      AppClock.setForTesting(() => DateTime(2026, 10, 20, 9));
      expect(await DatabaseService().getTodayPlan(), isNull);
    });

    test(
      'midnight rollover: tomorrow becomes today without duplicates',
      () async {
        final id = await svc.savePlan(sixDayPlan('PPL'));
        await svc.setActivePlan(id);
        final dbs = DatabaseService();
        AppClock.setForTesting(() => DateTime(2026, 10, 20, 23, 59)); // Tue
        final tomorrow = (await dbs.getTomorrowPlan())!;
        expect(tomorrow.date, '2026-10-21');
        AppClock.setForTesting(() => DateTime(2026, 10, 21, 0, 1)); // Wed
        final today = (await dbs.getTodayPlan())!;
        expect(today.id, tomorrow.id);
        expect(today.exercises.single.exerciseName, 'OHP');
      },
    );
  });
}
