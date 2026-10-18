import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/services/active_workout_controller.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

void main() {
  late Database db;
  final svc = DatabaseService();

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.reptrack.app/alarm'),
          (call) async =>
              call.method == 'getScheduledAlarms' ? <Object?>[] : true,
        );
    db = await openTestDatabase();
    await db.delete('planned_exercises');
    await db.delete('workout_plans');
    AppClock.setForTesting(() => DateTime(2026, 10, 21, 9)); // Wednesday
  });

  tearDown(() async {
    AppClock.reset();
    await closeTestDatabase(db);
  });

  test('a week with nothing planned returns empty plans, no invented muscles or rest days', () async {
    final week = await svc.getWeeklyPlans(AppClock.now());
    expect(week.length, 7);
    expect(week.first.date, '2026-10-19'); // Monday
    expect(week.last.date, '2026-10-25'); // Sunday
    for (final p in week) {
      expect(p.id, isNull, reason: p.date);
      expect(p.primaryMuscleName, isNull, reason: p.date);
      expect(p.secondaryMuscleName, isNull);
      expect(
        p.isRestDay,
        isFalse,
        reason: 'Sunday is only a rest day when the user plans it',
      );
      expect(p.exercises, isEmpty);
    }
    // and nothing was written for browsing
    expect(await db.query('workout_plans'), isEmpty);
  });

  test('a planned rest day is still reported as a rest day', () async {
    await svc.saveOrUpdatePlan(
      WorkoutPlan(date: '2026-10-25', isRestDay: true),
    );
    final week = await svc.getWeeklyPlans(AppClock.now());
    expect(week.last.isRestDay, isTrue);
  });

  group('a workout started from another day\'s plan', () {
    WorkoutSession sessionOn(String date, int planId) => WorkoutSession(
      planId: planId,
      date: date,
      startTime: '09:00',
      primaryMuscle: 'Chest',
      clientRef: 'r-$date-$planId',
    );

    test(
      'is logged on the day it was performed and leaves the other plan open',
      () async {
        final futurePlanId = await svc.saveOrUpdatePlan(
          WorkoutPlan(date: '2026-10-23'),
        );
        await svc.createWorkoutSession(sessionOn('2026-10-21', futurePlanId));
        final future = await svc.getPlanForDate('2026-10-23');
        expect(future!.isCompleted, isFalse);
        final sessions = await svc.getSessionsForDate('2026-10-21');
        expect(sessions.length, 1);
        expect(await svc.getSessionsForDate('2026-10-23'), isEmpty);
      },
    );

    test('the plan of the same day is marked completed', () async {
      final id = await svc.saveOrUpdatePlan(WorkoutPlan(date: '2026-10-21'));
      await svc.createWorkoutSession(sessionOn('2026-10-21', id));
      expect((await svc.getPlanForDate('2026-10-21'))!.isCompleted, isTrue);
    });

    test(
      'end to end with the controller: session date is the performed date',
      () async {
        final futurePlanId = await svc.saveOrUpdatePlan(
          WorkoutPlan(
            date: '2026-10-24',
            primaryMuscleName: 'Chest',
            exercises: [
              PlannedExercise(
                planId: 0,
                exerciseId: 1,
                exerciseName: 'Barbell Bench Press',
                muscleGroupName: 'Chest',
                targetSets: 1,
              ),
            ],
          ),
        );
        final plan = (await svc.getPlanForDate('2026-10-24'))!;
        expect(plan.id, futurePlanId);
        final c = ActiveWorkoutController.fromPlan(
          plan,
          SqliteActiveSessionStore(),
        );
        c.toggleSet(0, 0);
        final id = (await c.finish())!;
        final saved = (await svc.getAllSessions()).firstWhere(
          (s) => s.id == id,
        );
        expect(saved.date, '2026-10-21');
        expect((await svc.getPlanForDate('2026-10-24'))!.isCompleted, isFalse);
      },
    );
  });

  test('no dead default settings are seeded on a fresh database', () async {
    final keys = (await db.query('user_settings')).map((r) => r['key']).toSet();
    expect(
      keys.intersection({'theme_mode', 'weight_unit', 'reminders_enabled'}),
      isEmpty,
    );
  });
}
