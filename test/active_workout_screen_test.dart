import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/screens/active_workout_screen.dart';
import 'package:reptrack/services/active_workout_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

WorkoutPlan plan() => WorkoutPlan(
  id: null,
  date: '2026-10-20',
  primaryMuscleName: 'Chest',
  exercises: [
    PlannedExercise(
      planId: 0,
      exerciseId: 1,
      exerciseName: 'Barbell Bench Press',
      muscleGroupName: 'Chest',
      targetSets: 2,
      targetReps: 8,
      targetWeightKg: 60,
    ),
    PlannedExercise(
      planId: 0,
      exerciseId: 4,
      exerciseName: 'Flat Dumbbell Press',
      muscleGroupName: 'Chest',
      targetSets: 3,
      targetReps: 10,
      targetWeightKg: 20,
    ),
  ],
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Database db;

  setUp(mockPlatformPlugins);

  Future<void> boot(WidgetTester tester) async {
    ignoreMissingPluginErrors();
    db = (await tester.runAsync(openTestDatabase))!;
    await tester.runAsync(() async {
      await db.delete('planned_exercises');
      await db.delete('workout_plans');
    });
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  }

  testWidgets('shows only the plan exercises and logs a set', (tester) async {
    await boot(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ActiveWorkoutScreen(plan: plan()),
      ),
    );
    await settle(tester);

    expect(find.text('EXERCISE 1 OF 2'), findsOneWidget);
    expect(find.text('0 / 5 sets done'), findsOneWidget);
    expect(find.text('Barbell Bench Press'), findsWidgets);
    expect(find.byTooltip('Pause workout'), findsOneWidget);

    await tester.tap(find.byTooltip('Mark set 1 done'));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('1 / 5 sets done'), findsOneWidget);

    // persisted for crash recovery
    final saved = await tester.runAsync(
      () => ActiveWorkoutController.recover(SqliteActiveSessionStore()),
    );
    expect(saved!.completedSets, 1);

    await teardown(tester);
  });

  testWidgets('pause, undo and exercise navigation', (tester) async {
    await boot(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ActiveWorkoutScreen(plan: plan()),
      ),
    );
    await settle(tester);

    await tester.tap(find.byTooltip('Pause workout'));
    await settle(tester);
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.byTooltip('Resume workout'), findsOneWidget);

    await tester.tap(find.byTooltip('Mark set 1 done'));
    await settle(tester);
    expect(find.text('REST TIMER'), findsOneWidget); // rest sheet after a set
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('1 / 5 sets done'), findsOneWidget);
    await tester.tap(find.byTooltip('Undo last change'));
    await settle(tester);
    expect(find.text('0 / 5 sets done'), findsOneWidget);

    await tester.ensureVisible(find.text('Next exercise'));
    await tester.tap(find.text('Next exercise'));
    await settle(tester);
    expect(find.text('EXERCISE 2 OF 2'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('back asks before leaving and keeps progress for resume', (
    tester,
  ) async {
    await boot(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => ActiveWorkoutScreen(plan: plan()),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.tap(find.byTooltip('Mark set 1 done'));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Leave workout?'), findsOneWidget);
    await tester.tap(find.text('Save & leave'));
    await settle(tester);
    expect(find.text('go'), findsOneWidget);

    final saved = await tester.runAsync(
      () => ActiveWorkoutController.recover(SqliteActiveSessionStore()),
    );
    expect(saved, isNotNull);
    expect(saved!.completedSets, 1);
    expect(saved.isPaused, isTrue);

    // Resume screen restores it.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ActiveWorkoutScreen(resume: true),
      ),
    );
    await settle(tester);
    expect(find.text('1 / 5 sets done'), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('rest-day plan shows the rest state with an unplanned option', (
    tester,
  ) async {
    await boot(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ActiveWorkoutScreen(
          plan: WorkoutPlan(date: '2026-10-25', isRestDay: true),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Today is a rest day'), findsOneWidget);
    expect(find.text('Start an unplanned workout'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('empty plan shows an empty state, not an error', (tester) async {
    await boot(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ActiveWorkoutScreen(plan: WorkoutPlan(date: '2026-10-20')),
      ),
    );
    await settle(tester);
    expect(find.text('No exercises planned for this workout'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('large text scale does not overflow the workout screen', (
    tester,
  ) async {
    await boot(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ActiveWorkoutScreen(plan: plan()),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    await teardown(tester);
  });
}
