import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/training_plans_screen.dart';
import 'package:reptrack/services/training_plan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

import 'package:reptrack/core/access_config.dart';

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

  setUp(() {
    mockPlatformPlugins();
    // This test is about the plan editor, not access: run it under the
    // freemium model (a service that was never initialised has no entitlement
    // yet, which the subscription-required gate rightly treats as "checking").
    AccessConfig.debugOverride = AccessModel.freemium;
  });
  tearDown(() => AccessConfig.debugOverride = null);

  Future<void> boot(WidgetTester tester) async {
    ignoreMissingPluginErrors();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    db = (await tester.runAsync(openTestDatabase))!;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => closeTestDatabase(db));
  }

  Widget app() =>
      MaterialApp(theme: AppTheme.darkTheme, home: const TrainingPlansScreen());

  testWidgets('empty state, create a plan with exercises, duplicate, delete', (
    tester,
  ) async {
    await boot(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('Build your weekly plan'), findsOneWidget);

    await tester.tap(find.text('Create a plan'));
    await settle(tester);
    expect(find.text('NEW PLAN'), findsOneWidget);

    // Saving without a name is blocked with feedback.
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    expect(find.text('Enter a plan name'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Push Pull Legs');

    // Add an exercise to Monday through the picker (alias search works).
    await tester.tap(find.text('Add exercise'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'bench press');
    await settle(tester);
    expect(find.text('Barbell Bench Press'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('pick_1')));
    await settle(tester);
    // The edit sheet opens with defaults; confirm with Add.
    expect(find.text('Sets'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.textContaining(RegExp(r'\d+ × \d+')), findsWidgets);

    // Adding the same exercise again warns.
    await tester.tap(find.text('Add exercise'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'bench press');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick_1')));
    await settle(tester);
    expect(find.text('Already in this day'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    // Make Tuesday a rest day.
    await tester.tap(find.bySemanticsLabel(RegExp('^Tuesday')));
    await settle(tester);
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(find.textContaining('Rest & recovery'), findsOneWidget);

    await tester.tap(find.text('SAVE'));
    await settle(tester);

    // Back on the list.
    expect(find.text('Push Pull Legs'), findsOneWidget);
    final svc = TrainingPlanService();
    final saved = (await tester.runAsync(svc.listPlans))!.single;
    expect(saved.dayFor(1).exercises.single.exerciseId, 1);
    expect(saved.dayFor(2).isRest, isTrue);
    expect(saved.trainingDayCount, 5); // Mon + Wed..Sat; Tue and Sun rest

    // Duplicate through the menu.
    await tester.tap(find.byTooltip('Plan actions'));
    await settle(tester);
    await tester.tap(find.text('Duplicate'));
    await settle(tester);
    expect(find.text('Copy of Push Pull Legs'), findsOneWidget);

    // Delete asks for confirmation; cancelling keeps it.
    await tester.tap(find.byTooltip('Plan actions').first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete this plan?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Copy of Push Pull Legs'), findsOneWidget);

    await tester.tap(find.byTooltip('Plan actions').first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    expect(find.text('Copy of Push Pull Legs'), findsNothing);
    expect(find.text('Push Pull Legs'), findsOneWidget);

    await teardown(tester);
  });
}
