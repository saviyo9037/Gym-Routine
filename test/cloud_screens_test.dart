import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/models/training_plan.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/screens/account_screen.dart';
import 'package:reptrack/screens/paywall_screen.dart';
import 'package:reptrack/screens/progress_screen.dart';
import 'package:reptrack/screens/training_plans_screen.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/export_service.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/sync_service.dart';
import 'package:reptrack/services/training_plan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/cloud_fakes.dart';
import 'helpers/fake_sync_remote.dart';
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

final _now = DateTime(2026, 10, 20, 12);

Future<PremiumService> premiumService({required bool active}) async {
  final src = FakeEntitlementSource(
    active: active,
    expiresAt: active ? _now.add(const Duration(days: 30)) : null,
    now: _now,
  );
  final p = PremiumService(
    source: src,
    store: MemorySettingsStore(),
    clock: () => _now,
  );
  await p.initialize();
  return p;
}

TrainingPlan plan(String name) => TrainingPlan(
  name: name,
  days: [
    for (var d = 1; d <= 7; d++) TrainingPlanDay(weekday: d, isRest: d == 7),
  ],
);

Widget app(Widget home) => MaterialApp(theme: AppTheme.darkTheme, home: home);

void main() {
  // These tests describe the FREEMIUM behaviour (free core, premium extras).
  // The subscription-required model is covered by access_gate_test.dart.
  setUp(() => AccessConfig.debugOverride = AccessModel.freemium);
  tearDown(() => AccessConfig.debugOverride = null);

  late Database db;

  setUp(() {
    mockPlatformPlugins();
    CloudServices.resetForTesting();
  });

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
    CloudServices.resetForTesting();
  }

  group('MOCK-ONLY: plan limit in the UI', () {
    testWidgets('free: 2 plans stay editable; a 3rd shows the paywall', (
      tester,
    ) async {
      await boot(tester);
      CloudServices.premium = await tester.runAsync(
        () => premiumService(active: false),
      ) as PremiumService;
      final svc = TrainingPlanService();
      await tester.runAsync(() async {
        await svc.savePlan(plan('Plan A'));
        await svc.savePlan(plan('Plan B'));
      });
      await tester.pumpWidget(app(const TrainingPlansScreen()));
      await settle(tester);
      expect(find.text('Plan A'), findsOneWidget);

      await tester.tap(find.text('New plan'));
      await settle(tester);
      expect(find.text('REPTRACK PREMIUM'), findsOneWidget);
      expect(find.textContaining('keep 2 training plans'), findsOneWidget);
      expect(await tester.runAsync(svc.countPlans), 2);

      await tester.pageBack();
      await settle(tester);
      // duplicating would create a 3rd plan: also blocked
      await tester.tap(find.byTooltip('Plan actions').first);
      await settle(tester);
      await tester.tap(find.text('Duplicate'));
      await settle(tester);
      expect(find.text('REPTRACK PREMIUM'), findsOneWidget);
      expect(await tester.runAsync(svc.countPlans), 2);
      await tester.pageBack();
      await settle(tester);

      // editing an existing plan is never gated
      await tester.tap(find.text('Plan A'));
      await settle(tester);
      expect(find.text('EDIT PLAN'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('free user already over the limit keeps every plan', (
      tester,
    ) async {
      await boot(tester);
      CloudServices.premium = await tester.runAsync(
        () => premiumService(active: false),
      ) as PremiumService;
      final svc = TrainingPlanService();
      await tester.runAsync(() async {
        for (var i = 0; i < 4; i++) {
          await svc.savePlan(plan('Old $i'));
        }
      });
      await tester.pumpWidget(app(const TrainingPlansScreen()));
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        expect(find.text('Old $i'), findsOneWidget);
      }
      await teardown(tester);
    });

    testWidgets('premium: no limit, the editor opens', (tester) async {
      await boot(tester);
      CloudServices.premium = await tester.runAsync(
        () => premiumService(active: true),
      ) as PremiumService;
      final svc = TrainingPlanService();
      await tester.runAsync(() async {
        await svc.savePlan(plan('Plan A'));
        await svc.savePlan(plan('Plan B'));
      });
      await tester.pumpWidget(app(const TrainingPlansScreen()));
      await settle(tester);
      await tester.tap(find.text('New plan'));
      await settle(tester);
      expect(find.text('NEW PLAN'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('MOCK-ONLY: account screen', () {
    testWidgets(
      'cloud not configured: explains, no sign-in form, nothing crashes',
      (tester) async {
        await boot(tester);
        await tester.pumpWidget(app(const AccountScreen()));
        await settle(tester);
        expect(find.textContaining('not set up in this build'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
        await teardown(tester);
      },
    );

    testWidgets(
      'sign in (via the auth flow) validates, shows errors, then the signed-in state',
      (tester) async {
        await boot(tester);
        final auth = FakeAuthService();
        CloudServices.auth = auth;
        CloudServices.premium = await tester.runAsync(
          () => premiumService(active: false),
        ) as PremiumService;
        CloudServices.sync = SyncService(
          auth: auth,
          premium: CloudServices.premium,
          remoteFactory: (_) => FakeSyncRemote(),
        );
        await tester.pumpWidget(app(const AccountScreen()));
        await settle(tester);

        // Signed out: the account screen opens the sign-in flow.
        await tester.tap(find.text('Sign in or create an account'));
        await settle(tester);
        final signInButton = find.widgetWithText(ElevatedButton, 'Sign in');
        await tester.tap(signInButton);
        await settle(tester);
        expect(find.text('Enter your e-mail'), findsOneWidget);

        auth.failSignIn = true;
        await tester.enterText(
          find.byType(TextFormField).first,
          'me@example.com',
        );
        await tester.enterText(find.byType(TextFormField).last, 'secret1');
        await tester.tap(signInButton);
        await settle(tester);
        expect(find.text('Invalid login credentials'), findsOneWidget);

        auth.failSignIn = false;
        await tester.tap(signInButton);
        await settle(tester);
        // The flow closes itself and the account screen shows the signed-in state.
        expect(find.text('me@example.com'), findsOneWidget);
        expect(find.text('Unlock with Premium'), findsOneWidget);
        expect(find.text('Sync now'), findsNothing);
        await teardown(tester);
      },
    );

    testWidgets('delete account keeps local data unless the user opts in', (
      tester,
    ) async {
      await boot(tester);
      final auth = FakeAuthService(
        signedIn: const CloudUser(id: 'u-1', email: 'me@example.com'),
      );
      CloudServices.auth = auth;
      CloudServices.premium = await tester.runAsync(
        () => premiumService(active: true),
      ) as PremiumService;
      CloudServices.sync = SyncService(
        auth: auth,
        premium: CloudServices.premium,
        remoteFactory: (_) => FakeSyncRemote(),
      );
      final svc = TrainingPlanService();
      await tester.runAsync(() => svc.savePlan(plan('Keep me')));

      await tester.pumpWidget(app(const AccountScreen()));
      await settle(tester);
      expect(find.text('Sync now'), findsOneWidget);

      await tester.ensureVisible(find.text('Delete my account'));
      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      expect(find.text('Delete your account?'), findsOneWidget);
      // cancel does nothing
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(auth.deleteCalls, 0);

      await tester.tap(find.text('Delete my account'));
      await settle(tester);
      // Destructive: the button stays disabled until DELETE is typed.
      final disabled = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Delete account'),
      );
      expect(disabled.onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'delete');
      await settle(tester);
      await tester.tap(find.text('Delete account'));
      await settle(tester);
      expect(auth.deleteCalls, 1);
      expect(auth.isSignedIn, isFalse);
      expect(
        await tester.runAsync(svc.countPlans),
        1,
        reason: 'local data survives account deletion by default',
      );
      await teardown(tester);
    });
  });

  group('MOCK-ONLY: paywall', () {
    testWidgets(
      'no store configured: friendly message, free features untouched',
      (tester) async {
        await boot(tester);
        await tester.pumpWidget(app(const PaywallScreen()));
        await settle(tester);
        expect(
          find.textContaining('not available in this build'),
          findsOneWidget,
        );
        expect(find.text('Subscribe'), findsNothing);
        expect(find.textContaining('Premium never locks them'), findsOneWidget);
        await teardown(tester);
      },
    );

    testWidgets('shows monthly + yearly, discloses renewal, subscribes', (
      tester,
    ) async {
      await boot(tester);
      final src = FakeEntitlementSource(now: _now);
      final p = PremiumService(
        source: src,
        store: MemorySettingsStore(),
        clock: () => _now,
      );
      await tester.runAsync(p.initialize);
      CloudServices.premium = p;
      var opened = false;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                opened = true;
                await Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => const PaywallScreen()),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(opened, isTrue);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.textContaining('auto-renewing subscription'), findsOneWidget);
      expect(find.textContaining('Restore purchases'), findsOneWidget);
      expect(
        find.textContaining('Manage subscription in Google Play'),
        findsOneWidget,
      );

      await tester.tap(find.text('Subscribe'));
      await settle(tester);
      expect(p.isPremium, isTrue);
      expect(find.text('open'), findsOneWidget); // paywall closed itself
      await teardown(tester);
    });

    testWidgets('cancelled purchase shows nothing alarming and stays free', (
      tester,
    ) async {
      await boot(tester);
      final src = FakeEntitlementSource(now: _now)..cancelPurchase = true;
      final p = PremiumService(
        source: src,
        store: MemorySettingsStore(),
        clock: () => _now,
      );
      await tester.runAsync(p.initialize);
      CloudServices.premium = p;
      await tester.pumpWidget(app(const PaywallScreen()));
      await settle(tester);
      await tester.tap(find.text('Subscribe'));
      await settle(tester);
      expect(p.isPremium, isFalse);
      expect(find.text('Subscribe'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('MOCK-ONLY: premium-only screens', () {
    testWidgets(
      'progress charts: free users see the upsell, premium users the empty state',
      (tester) async {
        await boot(tester);
        await tester.pumpWidget(app(const ProgressScreen()));
        await settle(tester);
        expect(
          find.text('Progress charts are a Premium feature'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());

        CloudServices.premium = await tester.runAsync(
          () => premiumService(active: true),
        ) as PremiumService;
        await tester.pumpWidget(app(const ProgressScreen()));
        await settle(tester);
        expect(find.textContaining('Finish a workout'), findsOneWidget);
        await teardown(tester);
      },
    );
  });

  group('MOCK-ONLY: sync service end to end', () {
    testWidgets(
      'premium + signed in pushes local data; failures keep data and show an error',
      (tester) async {
        await boot(tester);
        final auth = FakeAuthService(
          signedIn: const CloudUser(id: 'u-1', email: 'me@example.com'),
        );
        final premium = await tester.runAsync(
          () => premiumService(active: true),
        ) as PremiumService;
        final remote = FakeSyncRemote();
        var applied = 0;
        final sync = SyncService(
          auth: auth,
          premium: premium,
          remoteFactory: (_) => remote,
          onApplied: () async => applied++,
        );
        await tester.runAsync(() async {
          await TrainingPlanService().savePlan(plan('Cloud me'));
          await sync.syncNow();
        });
        expect(sync.state, SyncState.idle);
        expect(remote.t('training_plans').values.single['name'], 'Cloud me');
        expect(sync.lastSyncedAt, isNotNull);

        remote.failUpsert = true;
        await tester.runAsync(() async {
          await TrainingPlanService().savePlan(plan('Edited offline'));
          await sync.syncNow();
        });
        expect(sync.state, SyncState.partial);
        expect(sync.lastError, contains('Nothing was lost'));
        expect(
          (await tester.runAsync(TrainingPlanService().listPlans))!.length,
          2,
        );
        expect(applied, 0);
        await teardown(tester);
      },
    );
  });

  group('MOCK-ONLY: export', () {
    test('CSV escapes commas/quotes and writes one row per set', () {
      final csv = ExportService.buildCsv([
        WorkoutSession(
          id: 1,
          date: '2026-10-20',
          startTime: '07:00',
          endTime: '08:00',
          durationSeconds: 3600,
          primaryMuscle: 'Chest',
          sets: [
            WorkoutSetRecord(
              sessionId: 1,
              exerciseId: 1,
              exerciseName: 'Press, "flat"',
              setNumber: 1,
              reps: 8,
              weightKg: 62.5,
            ),
            WorkoutSetRecord(
              sessionId: 1,
              exerciseId: 191,
              exerciseName: 'Treadmill Running',
              setNumber: 1,
              reps: 20,
              weightKg: 0,
              durationSeconds: 1200,
              distanceKm: 3.5,
            ),
          ],
        ),
        WorkoutSession(
          id: 2,
          date: '2026-10-21',
          startTime: '07:00',
          primaryMuscle: 'Back',
        ),
      ]);
      final lines = csv.trim().split('\n');
      expect(lines.first, ExportService.csvHeader);
      expect(lines.length, 4);
      expect(lines[1], contains('"Press, ""flat"""'));
      expect(lines[1], contains(',62.5,1,'));
      expect(lines[2], endsWith(',1200,3.5'));
      expect(lines[3], startsWith('2,2026-10-21,07:00,'));
    });
  });
}
