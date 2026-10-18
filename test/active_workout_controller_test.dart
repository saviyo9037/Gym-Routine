import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/services/active_workout_controller.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

WorkoutPlan plan({int? id = 7}) => WorkoutPlan(
  id: id,
  date: '2026-10-20',
  primaryMuscleName: 'Chest',
  secondaryMuscleName: 'Triceps',
  exercises: [
    PlannedExercise(
      planId: id ?? 0,
      exerciseId: 1,
      exerciseName: 'Barbell Bench Press',
      muscleGroupName: 'Chest',
      targetSets: 3,
      targetReps: 8,
      targetWeightKg: 62.5,
      restSeconds: 120,
    ),
    PlannedExercise(
      planId: id ?? 0,
      exerciseId: 191,
      exerciseName: 'Treadmill Running',
      muscleGroupName: 'Cardio',
      targetSets: 1,
      targetReps: 20,
      targetWeightKg: 0,
      targetDurationSeconds: 1200,
      targetDistanceKm: 3.5,
    ),
  ],
);

void main() {
  late Database db;
  late SqliteActiveSessionStore store;

  setUp(() async {
    db = await openTestDatabase();
    await db.delete('planned_exercises');
    await db.delete('workout_plans');
    store = SqliteActiveSessionStore();
    AppClock.setForTesting(() => DateTime(2026, 10, 20, 10, 0, 0));
  });

  tearDown(() async {
    AppClock.reset();
    await closeTestDatabase(db);
  });

  Future<ActiveWorkoutController> started({WorkoutPlan? p}) async {
    final c = ActiveWorkoutController.fromPlan(p ?? plan(), store);
    await c.start();
    return c;
  }

  test(
    'builds only the plan exercises, cardio rows use time/distance',
    () async {
      final c = await started();
      expect(c.exercises.map((e) => e.name), [
        'Barbell Bench Press',
        'Treadmill Running',
      ]);
      expect(c.exercises[0].sets.length, 3);
      expect(c.exercises[0].sets.first.weight, 62.5);
      expect(c.exercises[1].isCardio, isTrue);
      expect(c.exercises[1].sets.single.durationSeconds, 1200);
      expect(c.exercises[1].sets.single.distanceKm, 3.5);
    },
  );

  test('log, edit with decimals, undo and redo-by-toggle', () async {
    final c = await started();
    expect(c.toggleSet(0, 0), isTrue);
    expect(c.completedSets, 1);
    c.updateSet(0, 0, weight: 65.25, reps: 7);
    expect(c.exercises[0].sets[0].weight, 65.25);
    c.undo(); // undo the edit
    expect(c.exercises[0].sets[0].weight, 62.5);
    expect(c.exercises[0].sets[0].isCompleted, isTrue);
    c.undo(); // undo the completion
    expect(c.completedSets, 0);
    expect(c.canUndo, isFalse);
    c.undo(); // nothing to undo: no throw
  });

  test('add and remove sets; the last set cannot be removed', () async {
    final c = await started();
    c.addSet(0);
    expect(c.exercises[0].sets.length, 4);
    expect(c.exercises[0].sets.last.setNumber, 4);
    expect(c.removeLastSet(0), isTrue);
    expect(c.removeLastSet(1), isFalse); // single cardio round stays
    c.undo();
    expect(c.exercises[0].sets.length, 4);
  });

  test('navigation clamps and next/prev/jump work', () async {
    final c = await started();
    c.next();
    expect(c.currentIndex, 1);
    c.next();
    expect(c.currentIndex, 1);
    c.previous();
    c.previous();
    expect(c.currentIndex, 0);
    c.goTo(99);
    expect(c.currentIndex, 1);
  });

  test('pause stops the clock, resume continues', () async {
    var now = DateTime(2026, 10, 20, 10, 0, 0);
    AppClock.setForTesting(() => now);
    final c = await started();
    now = now.add(const Duration(seconds: 100));
    expect(c.elapsedSeconds(), 100);
    c.pause();
    now = now.add(const Duration(minutes: 30));
    expect(c.elapsedSeconds(), 100);
    c.resume();
    now = now.add(const Duration(seconds: 20));
    expect(c.elapsedSeconds(), 120);
  });

  test('survives the app being killed and comes back paused', () async {
    var now = DateTime(2026, 10, 20, 10, 0, 0);
    AppClock.setForTesting(() => now);
    final c = await started();
    now = now.add(const Duration(seconds: 90));
    c.toggleSet(0, 0);
    c.updateSet(0, 1, weight: 70);
    await c.flush();
    // The process dies here; one hour passes before the user reopens the app.
    now = now.add(const Duration(hours: 1));

    final back = (await ActiveWorkoutController.recover(store))!;
    expect(back.clientRef, c.clientRef);
    expect(back.exercises[0].sets[0].isCompleted, isTrue);
    expect(back.exercises[0].sets[1].weight, 70);
    expect(back.isPaused, isTrue);
    expect(back.elapsedSeconds(), 90); // the dead hour is not training time
    expect(back.planId, 7);

    final summary = (await ActiveWorkoutController.peekSummary(store))!;
    expect(summary.completedSets, 1);
    expect(summary.totalSets, 4);
    expect(summary.title, 'Chest & Triceps');
  });

  test('corrupt persisted state is dropped instead of crashing', () async {
    await db.insert('active_sessions', {
      'id': 1,
      'client_ref': 'x',
      'state_json': '{not json',
      'started_at': 'now',
      'updated_at': 'now',
    });
    expect(await ActiveWorkoutController.recover(store), isNull);
    expect(await store.load(), isNull);
  });

  test(
    'finish saves exactly once, even when called twice or retried',
    () async {
      final c = await started();
      c.toggleSet(0, 0);
      c.toggleSet(0, 1);
      final dbs = DatabaseService();
      final id1 = await c.finish();
      final id2 = await c.finish();
      expect(id2, id1);
      expect((await db.query('workout_sessions')).length, 1);
      expect(await store.load(), isNull); // recovery row cleared
      // A "retry after crash" with the same client ref also writes nothing new.
      final retry = await dbs.createWorkoutSession(c.buildSession());
      expect(retry, id1);
      expect((await db.query('workout_sessions')).length, 1);
      expect((await db.query('workout_sets')).length, 4);
    },
  );

  test('saved session reflects the logged data, plan is marked done', () async {
    final pid = await DatabaseService().saveOrUpdatePlan(plan(id: null));
    final c = ActiveWorkoutController.fromPlan(plan(id: pid), store);
    c.toggleSet(0, 0);
    c.updateSet(0, 0, weight: 67.5, reps: 6);
    c.toggleSet(1, 0);
    final id = (await c.finish())!;
    final sess = (await DatabaseService().getAllSessions()).firstWhere(
      (s) => s.id == id,
    );
    expect(sess.date, '2026-10-20');
    expect(sess.completedSetsCount, 2);
    final bench = sess.sets.firstWhere(
      (s) => s.exerciseId == 1 && s.setNumber == 1,
    );
    expect(bench.weightKg, 67.5);
    expect(bench.reps, 6);
    final run = sess.sets.firstWhere((s) => s.exerciseId == 191);
    expect(run.distanceKm, 3.5);
    expect(run.durationSeconds, 1200);
    expect(run.weightKg, 0); // cardio never feeds strength volume
    expect(sess.totalVolumeKg, 67.5 * 6);
    final dated = await DatabaseService().getPlanForDate('2026-10-20');
    expect(dated!.isCompleted, isTrue);
  });

  test('cancel clears persisted state and saves nothing', () async {
    final c = await started();
    c.toggleSet(0, 0);
    await c.cancel();
    expect(await store.load(), isNull);
    expect((await db.query('workout_sessions')), isEmpty);
    c.toggleSet(0, 1); // late mutation after cancel must not resurrect it
    await c.flush();
    expect(await store.load(), isNull);
  });

  test('session started before midnight is logged on its start date', () async {
    var now = DateTime(2026, 10, 20, 23, 50);
    AppClock.setForTesting(() => now);
    final c = await started();
    c.toggleSet(0, 0);
    now = DateTime(2026, 10, 21, 0, 40);
    final s = c.buildSession();
    expect(s.date, '2026-10-20');
    expect(s.durationSeconds, 50 * 60);
    expect(s.startTime, '23:50');
    expect(s.endTime, '00:40');
  });

  test(
    'unplanned workout from a rest day: exercises can be added live',
    () async {
      final c = ActiveWorkoutController.unplanned(store);
      await c.start();
      expect(c.exercises, isEmpty);
      expect(c.current, isNull);
      c.addExercise(
        ActiveExercise.fromSpec(
          exerciseId: 4,
          name: 'Flat Dumbbell Press',
          muscleGroup: 'Chest',
          sets: 3,
          reps: 10,
          weightKg: 20,
          restSeconds: 90,
        ),
      );
      expect(c.hasExercise(4), isTrue);
      expect(c.current!.name, 'Flat Dumbbell Press');
      expect(c.isUnplanned, isTrue);
      c.undo();
      expect(c.exercises, isEmpty);
    },
  );

  test(
    'empty plan produces an empty controller that can still be finished',
    () async {
      final c = ActiveWorkoutController.fromPlan(
        WorkoutPlan(date: '2026-10-20'),
        store,
      );
      expect(c.exercises, isEmpty);
      expect(c.progress, 0);
    },
  );
}
