import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/history_screen.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Database db;

  setUp(mockPlatformPlugins);

  testWidgets('manual workout log never saves invented exercises', (
    tester,
  ) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const HistoryScreen()),
    );
    await settle(tester);

    await tester.tap(find.byTooltip('Log Workout Session'));
    await settle(tester);
    expect(find.text('LOG WORKOUT SESSION'), findsOneWidget);
    // nothing pre-filled
    expect(find.textContaining('Barbell Bench Press'), findsNothing);
    expect(find.byKey(const ValueKey('manual_ex_0')), findsNothing);

    // Saving with no exercises is refused and writes nothing.
    final save = find.text('SAVE TO WORKOUT HISTORY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
    expect(find.text('Add at least one exercise first.'), findsOneWidget);
    expect(
      (await tester.runAsync(() => DatabaseService().getAllSessions()))!,
      isEmpty,
    );

    // Add a real exercise through the picker and save.
    await tester.tap(find.text('Add exercise'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'bench press');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick_1')));
    await settle(tester);
    expect(find.byKey(const ValueKey('manual_ex_0')), findsOneWidget);

    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);

    final sessions = (await tester.runAsync(
      () => DatabaseService().getAllSessions(),
    ))!;
    expect(sessions.length, 1);
    final s = sessions.single;
    expect(s.sets.every((x) => x.exerciseId == 1), isTrue);
    expect(s.sets.first.exerciseName, 'Barbell Bench Press');
    expect(s.sets.length, greaterThan(0));
    // 45 default minutes from 10:00 -> 10:45, a valid clock time
    expect(s.startTime, '10:00');
    expect(s.endTime, '10:45');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  });
}
