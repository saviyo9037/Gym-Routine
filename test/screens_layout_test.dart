import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/models/exercise.dart';
import 'package:reptrack/screens/add_edit_exercise_screen.dart';
import 'package:reptrack/screens/add_edit_routine_screen.dart';
import 'package:reptrack/screens/exercise_detail_screen.dart';
import 'package:reptrack/screens/exercise_library_screen.dart';
import 'package:reptrack/screens/history_screen.dart';
import 'package:reptrack/screens/home_screen.dart';
import 'package:reptrack/screens/routine_management_screen.dart';
import 'package:reptrack/screens/workout_plan_screen.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Database db;

  setUp(() {
    mockPlatformPlugins();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.reptrack.app/alarm'),
          (call) async =>
              call.method == 'getScheduledAlarms' ? <Object?>[] : true,
        );
  });

  Future<void> boot(WidgetTester tester, double scale) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;
  }

  Future<void> show(WidgetTester tester, Widget screen, double scale) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await settle(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  }

  final screens = <String, Widget Function()>{
    'home': () => const HomeScreen(),
    'workout plan': () => const WorkoutPlanScreen(),
    'exercise library': () => const ExerciseLibraryScreen(),
    'history': () => const HistoryScreen(),
    'routines': () => const RoutineManagementScreen(),
    'add routine': () => const AddEditRoutineScreen(),
    'add exercise': () => const AddEditExerciseScreen(),
  };

  for (final scale in [1.0, 2.0]) {
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key} renders at 360x640, text x$scale, no overflow',
        (tester) async {
          await boot(tester, scale);
          await show(tester, entry.value(), scale);
          expect(tester.takeException(), isNull);
          expect(find.byType(Scaffold), findsWidgets);
          await teardown(tester);
        },
      );
    }

    testWidgets('exercise detail renders at 360x640, text x$scale', (
      tester,
    ) async {
      await boot(tester, scale);
      final Exercise ex = (await tester.runAsync<Exercise?>(
        () => DatabaseService().getExerciseById(1),
      ))!;
      await show(tester, ExerciseDetailScreen(exercise: ex), scale);
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });
  }

  testWidgets('a failing database shows an error with Retry, not a spinner', (
    tester,
  ) async {
    await boot(tester, 1.0);
    await tester.runAsync(() => db.close());
    await show(tester, const HistoryScreen(), 1.0);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    resetTestDatabaseReference();
    await tester.pumpWidget(const SizedBox());
  });
}
