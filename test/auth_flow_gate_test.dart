import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/screens/access_root.dart';
import 'package:reptrack/screens/account_switch_screen.dart';
import 'package:reptrack/screens/auth_flow_screen.dart';
import 'package:reptrack/screens/locked_screen.dart';
import 'package:reptrack/screens/login_screen.dart';
import 'package:reptrack/screens/not_configured_screen.dart';
import 'package:reptrack/screens/paywall_screen.dart';
import 'package:reptrack/screens/reset_password_screen.dart';
import 'package:reptrack/screens/verify_email_screen.dart';
import 'package:reptrack/services/account_switch.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/sync_service.dart';
import 'package:reptrack/services/video_access_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/cloud_fakes.dart';
import 'helpers/scripted_auth.dart';
import 'helpers/test_db.dart';

final _now = DateTime(2026, 10, 20, 12);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PremiumService premiumFor(FakeEntitlementSource src) => PremiumService(
  source: src,
  store: MemorySettingsStore(),
  clock: () => _now,
  retryBase: const Duration(seconds: 20),
);

const _bob = CloudUser(id: 'u-bob@example.com', email: 'bob@example.com');

void main() {
  late Database db;
  late ScriptedAuthService auth;
  late FakeEntitlementSource store;
  late MemorySettingsStore flags;
  late MemorySettingsStore switchStore;

  setUp(() async {
    mockPlatformPlugins();
    ignoreMissingPluginErrors();
    TestWidgetsFlutterBinding.ensureInitialized();
    AccessConfig.debugOverride = AccessModel.subscriptionRequired;
    CloudServices.resetForTesting();
    db = await openTestDatabase();
    auth = ScriptedAuthService();
    store = FakeEntitlementSource(now: _now);
    flags = MemorySettingsStore()..data[AccessRoot.onboardingKey] = '1';
    switchStore = MemorySettingsStore();
    CloudServices.accountSwitch = AccountSwitch(store: switchStore);
  });

  tearDown(() async {
    AccessConfig.debugOverride = null;
    CloudServices.resetForTesting();
    await closeTestDatabase(db);
  });

  Future<void> boot(
    WidgetTester tester, {
    bool onboardingDone = true,
    AuthService? authService,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (!onboardingDone) flags.data.remove(AccessRoot.onboardingKey);
    final p = premiumFor(store);
    CloudServices.premium = p;
    CloudServices.installAccessGuard();
    final a = authService ?? auth;
    CloudServices.attachAuth(a);
    // The sync service reads the account from the auth service it was built with.
    CloudServices.sync = SyncService(
      auth: a,
      premium: p,
      remoteFactory: (_) => throw StateError('no cloud in this test'),
    );
    await tester.runAsync(p.initialize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AccessRoot(
          settings: flags,
          child: const Scaffold(body: Text('THE REAL APP')),
        ),
      ),
    );
    await settle(tester);
  }

  group('MOCK-ONLY: flow onboarding -> account -> paywall -> app', () {
    testWidgets('first launch: onboarding, then SIGN-IN (not the paywall)', (
      tester,
    ) async {
      await boot(tester, onboardingDone: false);
      expect(find.text('Plan your week'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await settle(tester);
      await tester.tap(find.text('Next'));
      await settle(tester);
      await tester.tap(find.text('See plans'));
      await settle(tester);
      expect(find.byType(AuthFlowScreen), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('THE REAL APP'), findsNothing);
    });

    testWidgets('signed out with cloud configured: only the auth flow', (
      tester,
    ) async {
      await boot(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('THE REAL APP'), findsNothing);
    });

    testWidgets('sign in without a subscription lands on the paywall', (
      tester,
    ) async {
      await boot(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth_email')),
        'bob@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth_password')),
        'whatever1',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
      expect(auth.isSignedIn, isTrue);
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('THE REAL APP'), findsNothing);
      // The store customer was linked to the new account.
      expect(store.loggedIn, contains('u-bob@example.com'));
    });

    testWidgets('sign in with an active subscription opens the app', (
      tester,
    ) async {
      store
        ..active = true
        ..expiresAt = _now.add(const Duration(days: 20));
      await boot(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth_email')),
        'bob@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth_password')),
        'whatever1',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
      expect(find.text('THE REAL APP'), findsOneWidget);
    });

    testWidgets(
      'restored session (already signed in) skips the sign-in screens',
      (tester) async {
        auth.setUser(_bob);
        store
          ..active = true
          ..expiresAt = _now.add(const Duration(days: 20));
        await boot(tester);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(AuthFlowScreen), findsNothing);
        expect(find.text('THE REAL APP'), findsOneWidget);
      },
    );

    testWidgets('signed in with an unconfirmed e-mail: verification screen', (
      tester,
    ) async {
      auth.setUser(
        const CloudUser(
          id: 'u-1',
          email: 'bob@example.com',
          emailVerified: false,
        ),
      );
      await boot(tester);
      expect(find.byType(VerifyEmailScreen), findsOneWidget);
      expect(find.text('THE REAL APP'), findsNothing);
    });

    testWidgets('a recovery link opens the new-password screen', (
      tester,
    ) async {
      auth.setUser(_bob);
      auth.startRecovery();
      await boot(tester);
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text('THE REAL APP'), findsNothing);
    });

    testWidgets('freemium mode shows the app without any account', (
      tester,
    ) async {
      AccessConfig.debugOverride = AccessModel.freemium;
      await boot(tester);
      expect(find.text('THE REAL APP'), findsOneWidget);
    });

    testWidgets('cloud not configured + locked: clear not-configured screen', (
      tester,
    ) async {
      await boot(tester, authService: NoCloudAuthService());
      expect(find.byType(LockedScreen), findsOneWidget);
      expect(find.byType(NotConfiguredScreen), findsOneWidget);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Export my data'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
    });

    testWidgets('cloud not configured + valid entitlement: app opens', (
      tester,
    ) async {
      store
        ..active = true
        ..expiresAt = _now.add(const Duration(days: 20));
      await boot(tester, authService: NoCloudAuthService());
      expect(find.text('THE REAL APP'), findsOneWidget);
    });

    testWidgets('locked user keeps restore, manage, export on the paywall', (
      tester,
    ) async {
      auth.setUser(_bob);
      await boot(tester);
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('Export my data'), findsOneWidget);
      expect(find.textContaining('Manage subscription'), findsWidgets);
      expect(find.text('Restore purchases'), findsWidgets);
    });
  });

  group('MOCK-ONLY: logout and account switching keep workout data', () {
    Future<Map<String, int>> counts() async {
      final out = <String, int>{};
      for (final t in [
        'workout_sessions',
        'workout_sets',
        'workout_plans',
        'planned_exercises',
        'routines',
        'exercises',
        'training_plans',
      ]) {
        out[t] =
            (await db.rawQuery('SELECT COUNT(*) c FROM $t')).first['c'] as int;
      }
      return out;
    }

    Future<void> seedUserData(WidgetTester tester) async {
      await tester.runAsync(() async {
        await DatabaseService().createWorkoutSession(
          WorkoutSession(
            date: '2026-10-19',
            startTime: '07:00',
            primaryMuscle: 'Chest',
            sets: [
              WorkoutSetRecord(
                sessionId: 0,
                exerciseId: 1,
                exerciseName: 'Barbell Bench Press',
                setNumber: 1,
                reps: 8,
                weightKg: 60,
              ),
            ],
          ),
        );
      });
    }

    testWidgets('logout clears video + entitlement caches but not workouts', (
      tester,
    ) async {
      store
        ..active = true
        ..expiresAt = _now.add(const Duration(days: 20));
      auth.setUser(_bob);

      final tmp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('reptrack_vid'),
      );
      final cache = Directory('${tmp!.path}/video_cache');
      await tester.runAsync(() async {
        await cache.create(recursive: true);
        await File('${cache.path}/1.mp4').writeAsBytes([1, 2, 3]);
      });
      VideoAccessService.overrideForTesting(
        VideoAccessService(
          canAccessVideos: () => true,
          fetchSignedUrl: (_) async => throw UnimplementedError(),
          cacheDirectory: () async => cache,
        ),
      );

      await seedUserData(tester);
      await tester.runAsync(
        () => db.insert('user_settings', {
          'key': PremiumService.cacheKey,
          'value': '{}',
        }),
      );
      final before = (await tester.runAsync(counts))!;
      expect(before['workout_sessions'], 1);

      await boot(tester);
      expect(find.text('THE REAL APP'), findsOneWidget);

      await tester.runAsync(auth.signOut);
      await settle(tester);

      final after = (await tester.runAsync(counts))!;
      expect(after, before, reason: 'no workout data touched by logout');
      final cached = (await tester.runAsync(
        () => db.query(
          'user_settings',
          where: 'key = ?',
          whereArgs: [PremiumService.cacheKey],
        ),
      ))!;
      expect(cached, isEmpty, reason: 'entitlement cache cleared');
      expect(
        await tester.runAsync(() => cache.exists()),
        isFalse,
        reason: 'protected video cache deleted',
      );
      // RevenueCat customer is logged out and the sign-in screen is back.
      expect(store.loggedIn, contains('<logout>'));
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.runAsync(() => tmp.delete(recursive: true));
    });

    testWidgets(
      'a different account on this phone asks first; cancel keeps data',
      (tester) async {
        switchStore.data[AccountSwitch.lastUserKey] = 'u-alice@example.com';
        store
          ..active = true
          ..expiresAt = _now.add(const Duration(days: 20));
        await seedUserData(tester);
        final before = (await tester.runAsync(counts))!;

        auth.setUser(_bob);
        await boot(tester);
        expect(find.byType(AccountSwitchScreen), findsOneWidget);
        expect(find.text('THE REAL APP'), findsNothing);
        expect(
          find.text('Keep this phone\'s data and link it to this account'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel and sign out'));
        await settle(tester);
        expect(auth.isSignedIn, isFalse);
        expect((await tester.runAsync(counts))!, before);
        expect(
          switchStore.data[AccountSwitch.lastUserKey],
          'u-alice@example.com',
        );
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'link: the phone data is tied to the new account, nothing deleted',
      (tester) async {
        switchStore.data[AccountSwitch.lastUserKey] = 'u-alice@example.com';
        store
          ..active = true
          ..expiresAt = _now.add(const Duration(days: 20));
        await seedUserData(tester);
        final before = (await tester.runAsync(counts))!;

        auth.setUser(_bob);
        await boot(tester);
        await tester.tap(
          find.text('Keep this phone\'s data and link it to this account'),
        );
        await settle(tester);

        expect((await tester.runAsync(counts))!, before);
        expect(switchStore.data[AccountSwitch.lastUserKey], _bob.id);
        final bound = (await tester.runAsync(
          () => db.query('sync_meta', where: "key = 'account_user_id'"),
        ))!;
        expect(bound.single['value'], _bob.id);
        expect(find.text('THE REAL APP'), findsOneWidget);
      },
    );

    testWidgets(
      'same account again: no question, and the account is remembered',
      (tester) async {
        switchStore.data[AccountSwitch.lastUserKey] = _bob.id;
        store
          ..active = true
          ..expiresAt = _now.add(const Duration(days: 20));
        auth.setUser(_bob);
        await boot(tester);
        expect(find.byType(AccountSwitchScreen), findsNothing);
        expect(find.text('THE REAL APP'), findsOneWidget);
      },
    );

    testWidgets('first sign-in on a fresh phone is remembered, no question', (
      tester,
    ) async {
      store
        ..active = true
        ..expiresAt = _now.add(const Duration(days: 20));
      auth.setUser(_bob);
      await boot(tester);
      expect(find.text('THE REAL APP'), findsOneWidget);
      expect(switchStore.data[AccountSwitch.lastUserKey], _bob.id);
    });

    testWidgets(
      'account A -> sign out -> account B never shows A\'s entitlement',
      (tester) async {
        store
          ..active = true
          ..expiresAt = _now.add(const Duration(days: 20));
        auth.setUser(const CloudUser(id: 'u-a', email: 'a@example.com'));
        await boot(tester);
        expect(find.text('THE REAL APP'), findsOneWidget);

        // A leaves; the store says the next customer (B) has nothing.
        await tester.runAsync(auth.signOut);
        store.active = false;
        await settle(tester);
        expect(find.byType(LoginScreen), findsOneWidget);

        auth.setUser(const CloudUser(id: 'u-b', email: 'b@example.com'));
        await settle(tester);
        // B has no subscription: paywall (after the switch question), never the app.
        expect(find.text('THE REAL APP'), findsNothing);
        expect(
          find.byType(PaywallScreen).evaluate().isNotEmpty ||
              find.byType(AccountSwitchScreen).evaluate().isNotEmpty,
          isTrue,
        );
      },
    );
  });

  group('MOCK-ONLY: account deletion from the account area', () {
    test(
      'deleteAccount on the scripted service signs out (contract)',
      () async {
        auth.setUser(_bob);
        await auth.deleteAccount();
        expect(auth.isSignedIn, isFalse);
        expect(auth.calls, ['delete']);
      },
    );
  });
}
