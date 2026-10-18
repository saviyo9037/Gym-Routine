import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/exercise_library_screen.dart';
import 'package:reptrack/screens/history_screen.dart';
import 'package:reptrack/screens/home_screen.dart';
import 'package:reptrack/screens/routine_management_screen.dart';
import 'package:reptrack/screens/settings_screen.dart';
import 'package:reptrack/screens/workout_plan_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

/// Every screen reachable from the bottom navigation, at a small phone
/// (360x640) and a large screen (800x1280), text scale 1.0 and 2.0, with real
/// data in the database, plus each segment/tab of the multi-view screens.
/// Any RenderFlex overflow or thrown exception fails the test.

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Case {
  const _Case(this.name, this.build, [this.taps = const []]);
  final String name;
  final Widget Function() build;
  final List<String> taps;
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

  Future<void> boot(WidgetTester tester, Size size) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;
    await tester.runAsync(() async {
      // A few realistic sessions with sets so cards/summaries are populated.
      final today = DateTime.now();
      for (var i = 0; i < 6; i++) {
        final d = DateTime(today.year, today.month, today.day - i);
        final date =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final id = await db.insert('workout_sessions', {
          'date': date,
          'start_time': '07:00',
          'end_time': '08:00',
          'duration_seconds': 3600,
          'primary_muscle': i.isEven ? 'Chest' : 'Upper Back and Traps',
          'secondary_muscle': i.isEven ? 'Triceps' : 'Biceps',
          'created_at': d.toIso8601String(),
        });
        for (var s = 1; s <= 3; s++) {
          await db.insert('workout_sets', {
            'session_id': id,
            'exercise_id': 1,
            'exercise_name': 'Barbell Bench Press',
            'set_number': s,
            'reps': 8,
            'weight_kg': 62.5,
            'is_completed': s < 3 ? 1 : 0,
            'completed_at': d.toIso8601String(),
          });
        }
      }
    });
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

  final cases = <_Case>[
    _Case('home', () => const HomeScreen()),
    _Case('workout plan', () => const WorkoutPlanScreen()),
    _Case('exercise library', () => const ExerciseLibraryScreen()),
    _Case('history', () => const HistoryScreen(), [
      'All Sessions',
      'Muscle History',
      'This Week',
    ]),
    _Case('routines', () => const RoutineManagementScreen(), [
      'Weekly Schedule',
      'All Routines',
      "Today's Schedule",
    ]),
    _Case('settings', () => const SettingsScreen()),
  ];

  for (final size in const [Size(360, 640), Size(800, 1280)]) {
    for (final scale in const [1.0, 2.0]) {
      for (final c in cases) {
        testWidgets('${c.name}: ${size.width.toInt()}x${size.height.toInt()}, '
            'text x$scale, no overflow', (tester) async {
          await boot(tester, size);
          await show(tester, c.build(), scale);
          expect(
            tester.takeException(),
            isNull,
            reason: '${c.name} first view',
          );
          for (final label in c.taps) {
            final f = find.text(label);
            if (f.evaluate().isEmpty) continue;
            await tester.ensureVisible(f.first);
            await tester.tap(f.first, warnIfMissed: false);
            await settle(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '${c.name} / $label',
            );
          }
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() => closeTestDatabase(db));
        });
      }
    }
  }
}
