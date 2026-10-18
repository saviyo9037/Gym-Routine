import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/models/training_plan.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/models/routine.dart';
import 'package:reptrack/screens/access_root.dart';
import 'package:reptrack/screens/paywall_screen.dart';
import 'package:reptrack/services/access_guard.dart';
import 'package:reptrack/services/active_workout_controller.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/cloud_config.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/routine_service.dart';
import 'package:reptrack/services/training_plan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/cloud_fakes.dart';
import 'helpers/test_db.dart';

final _now = DateTime(2026, 10, 20, 12);

PremiumSnapshot snap({
  bool active = true,
  bool trial = false,
  bool willRenew = true,
  bool billing = false,
  DateTime? expires,
  DateTime? checked,
}) => PremiumSnapshot(
  isActive: active,
  isTrial: trial,
  willRenew: willRenew,
  billingIssue: billing,
  expiresAt: expires ?? _now.add(const Duration(days: 3)),
  checkedAt: checked ?? _now,
);

EntitlementDecision decide(
  PremiumSnapshot? s, {
  bool verified = true,
  DateTime? now,
}) => deriveEntitlement(
  snapshot: s,
  now: now ?? _now,
  verifiedThisSession: verified,
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PremiumService service(
  FakeEntitlementSource src, {
  MemorySettingsStore? store,
  DateTime Function()? clock,
  Duration fetchTimeout = const Duration(seconds: 8),
  Duration retryBase = const Duration(seconds: 20),
}) => PremiumService(
  source: src,
  store: store ?? MemorySettingsStore(),
  clock: clock ?? () => _now,
  fetchTimeout: fetchTimeout,
  retryBase: retryBase,
);

void main() {
  setUp(() => AccessConfig.debugOverride = AccessModel.subscriptionRequired);
  tearDown(() {
    AccessConfig.debugOverride = null;
    CloudServices.resetForTesting();
  });

  group('ACCESS_MODEL config', () {
    test('parses both values and fails closed on garbage', () {
      expect(AccessConfig.parse('freemium'), AccessModel.freemium);
      expect(AccessConfig.parse(' Freemium '), AccessModel.freemium);
      expect(
        AccessConfig.parse('subscription_required'),
        AccessModel.subscriptionRequired,
      );
      expect(
        AccessConfig.parse('free-for-all'),
        AccessModel.subscriptionRequired,
      );
      expect(AccessConfig.parse(''), AccessModel.subscriptionRequired);
    });

    test('default (no override, no define) is subscription_required', () {
      AccessConfig.debugOverride = null;
      expect(AccessConfig.model, AccessModel.subscriptionRequired);
    });

    test('legal links: only https is accepted, empty is hidden', () {
      expect(CloudConfig.legalUri(''), isNull);
      expect(CloudConfig.legalUri('http://example.com/p'), isNull);
      expect(CloudConfig.legalUri('javascript:alert(1)'), isNull);
      expect(
        CloudConfig.legalUri('https://example.com/p')!.host,
        'example.com',
      );
      // Nothing is baked into the app.
      expect(CloudConfig.privacyUri, isNull);
      expect(CloudConfig.termsUri, isNull);
    });
  });

  group('entitlement states (pure)', () {
    test('trial grants access, ends at expiry, refund revokes', () {
      final trial = snap(trial: true);
      expect(decide(trial).state, EntitlementState.trial);
      expect(decide(trial).isPremium, isTrue);
      // trial cancelled before the end: access until expiry
      expect(decide(snap(trial: true, willRenew: false)).isPremium, isTrue);
      // trial over
      final over = decide(trial, now: _now.add(const Duration(days: 4)));
      expect(over.state, EntitlementState.expired);
      expect(over.isPremium, isFalse);
      // refunded / revoked: store answers inactive
      expect(decide(snap(active: false, trial: true)).isPremium, isFalse);
    });

    test('premium, cancelled, grace, expired, free, unknown', () {
      expect(decide(snap()).state, EntitlementState.active);
      expect(
        decide(snap(willRenew: false)).state,
        EntitlementState.cancelledActive,
      );
      expect(decide(snap(billing: true)).state, EntitlementState.gracePeriod);
      expect(decide(snap(billing: true)).isPremium, isTrue);
      expect(
        decide(snap(), now: _now.add(const Duration(days: 9))).state,
        EntitlementState.expired,
      );
      expect(decide(null).state, EntitlementState.free);
      expect(
        deriveEntitlement(
          snapshot: null,
          now: _now,
          verifiedThisSession: false,
          initialised: false,
        ).state,
        EntitlementState.unknown,
      );
    });

    test(
      'offline: a cached entitlement is trusted for 14 days, not longer',
      () {
        final cached = snap(
          expires: _now.add(const Duration(days: 60)),
          checked: _now.subtract(const Duration(days: 13)),
        );
        expect(decide(cached, verified: false).isPremium, isTrue);
        expect(decide(cached, verified: false).offline, isTrue);
        final stale = snap(
          expires: _now.add(const Duration(days: 60)),
          checked: _now.subtract(const Duration(days: 15)),
        );
        expect(
          decide(stale, verified: false).state,
          EntitlementState.staleOffline,
        );
        expect(decide(stale, verified: false).isPremium, isFalse);
        // phone clock moved back: snapshot "from the future" is not trusted
        final future = snap(
          expires: _now.add(const Duration(days: 60)),
          checked: _now.add(const Duration(days: 2)),
        );
        expect(decide(future, verified: false).isPremium, isFalse);
      },
    );

    test('snapshot json keeps the trial flag; old caches read as no trial', () {
      final back = PremiumSnapshot.fromJson(snap(trial: true).toJson())!;
      expect(back.isTrial, isTrue);
      final legacy = snap().toJson()..remove('t');
      expect(PremiumSnapshot.fromJson(legacy)!.isTrial, isFalse);
    });

    test('trial length comes from the offer data only', () {
      expect(trialFromParts('day', 1)!.label, '1 day');
      expect(trialFromParts('day', 7)!.label, '7 days');
      expect(trialFromParts('month', 1)!.label, '1 month');
      expect(trialFromParts('day', 0), isNull);
      expect(trialFromParts('fortnight', 2), isNull);
    });
  });

  group('MOCK-ONLY: AccessGate (service level)', () {
    test('locked when the store says no subscription', () async {
      final p = service(FakeEntitlementSource(active: false, now: _now));
      expect(p.accessLevel, AccessLevel.checking); // before initialize
      await p.initialize();
      expect(p.accessLevel, AccessLevel.locked);
      expect(p.isLocked, isTrue);
      expect(p.canCreatePlan(0), isFalse);
      p.dispose();
    });

    test('trial and premium are full access', () async {
      final trial = service(
        FakeEntitlementSource(active: true, now: _now)
          ..trial = true
          ..expiresAt = _now.add(const Duration(days: 1)),
      );
      await trial.initialize();
      expect(trial.accessLevel, AccessLevel.full);
      expect(trial.isTrial, isTrue);
      expect(trial.canCreatePlan(50), isTrue, reason: 'unlimited plans');

      final paid = service(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 30)),
          now: _now,
        ),
      );
      await paid.initialize();
      expect(paid.accessLevel, AccessLevel.full);
      expect(paid.isTrial, isFalse);
      trial.dispose();
      paid.dispose();
    });

    test('expired subscription is locked', () async {
      final p = service(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.subtract(const Duration(days: 1)),
          now: _now,
        ),
      );
      await p.initialize();
      expect(p.accessLevel, AccessLevel.locked);
      p.dispose();
    });

    test(
      'cold start without cache shows "checking", never the paywall first',
      () async {
        final src = FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 30)),
          now: _now,
        )..holdFetch = Completer<void>();
        final p = service(src);
        final init = p.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(p.accessLevel, AccessLevel.checking);
        src.holdFetch!.complete();
        await init;
        expect(p.accessLevel, AccessLevel.full);
        p.dispose();
      },
    );

    test(
      'offline with a valid cache keeps full access (no lock-out)',
      () async {
        final store = MemorySettingsStore();
        final online = FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 30)),
          now: _now,
        );
        final first = service(online, store: store);
        await first.initialize();
        first.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20)); // persist

        final offline = FakeEntitlementSource(now: _now)..failFetch = true;
        final p = service(
          offline,
          store: store,
          clock: () => _now.add(const Duration(days: 5)),
        );
        await p.initialize();
        expect(p.accessLevel, AccessLevel.full);
        expect(p.verificationFailed, isTrue);
        expect(p.decision.offline, isTrue);
        p.dispose();
      },
    );

    test('offline with a cache older than 14 days locks', () async {
      final store = MemorySettingsStore();
      final first = service(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 90)),
          now: _now,
        ),
        store: store,
      );
      await first.initialize();
      first.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final p = service(
        FakeEntitlementSource(now: _now)..failFetch = true,
        store: store,
        clock: () => _now.add(const Duration(days: 20)),
      );
      await p.initialize();
      expect(p.accessLevel, AccessLevel.locked);
      expect(p.entitlementState, EntitlementState.staleOffline);
      p.dispose();
    });

    test(
      'store failure: retries with backoff and recovers, never throws',
      () async {
        final src = FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 30)),
          now: _now,
        )..failFetchTimes = 2;
        final p = service(src, retryBase: const Duration(milliseconds: 15));
        await p.initialize(); // first fetch fails
        expect(p.verificationFailed, isTrue);
        expect(p.lastError, contains('retry'));
        expect(
          p.accessLevel,
          AccessLevel.locked,
          reason: 'no cache, not verified',
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(src.fetchCalls, greaterThanOrEqualTo(3));
        expect(p.verificationFailed, isFalse);
        expect(p.accessLevel, AccessLevel.full);
        p.dispose();
      },
    );

    test(
      'a store that never answers ends in the retry state, not a spinner',
      () async {
        final src = FakeEntitlementSource(now: _now)
          ..holdFetch = Completer<void>();
        final p = service(src, fetchTimeout: const Duration(milliseconds: 40));
        await p.initialize();
        expect(p.accessLevel, AccessLevel.locked);
        expect(p.verificationFailed, isTrue);
        p.dispose();
      },
    );

    test(
      'no store configured: debug builds stay open, subscriptions off',
      () async {
        final p = service(FakeEntitlementSource(now: _now)..available = false);
        await p.initialize();
        expect(p.storeAvailable, isFalse);
        // flutter test runs in debug mode: development without a key must work.
        expect(p.accessLevel, AccessLevel.full);
        p.dispose();
      },
    );

    test('flag switch: freemium is never locked, required locks', () async {
      final src = FakeEntitlementSource(active: false, now: _now);
      final p = service(src);
      await p.initialize();
      AccessConfig.debugOverride = AccessModel.freemium;
      expect(p.accessLevel, AccessLevel.full);
      expect(p.canCreatePlan(1), isTrue);
      expect(p.canCreatePlan(2), isFalse, reason: 'freemium plan limit stays');
      AccessConfig.debugOverride = AccessModel.subscriptionRequired;
      expect(p.accessLevel, AccessLevel.locked);
      p.dispose();
    });
  });

  group('MOCK-ONLY: locked state keeps data and blocks writes', () {
    late Database db;
    final calls = <String>[];

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.reptrack.app/alarm'),
            (call) async {
              calls.add(call.method);
              return call.method == 'getScheduledAlarms' ? [] : true;
            },
          );
      db = await openTestDatabase();
    });

    tearDown(() async {
      AccessGuard.isLocked = () => false;
      await closeTestDatabase(db);
    });

    Future<Map<String, int>> counts() async {
      final out = <String, int>{};
      for (final t in [
        'exercises',
        'workout_plans',
        'planned_exercises',
        'workout_sessions',
        'workout_sets',
        'routines',
        'routine_completions',
        'training_plans',
        'training_plan_days',
        'training_plan_day_exercises',
        'user_settings',
      ]) {
        out[t] = (await db.query(t)).length;
      }
      return out;
    }

    Future<PremiumService> lockedService() async {
      final p = service(FakeEntitlementSource(active: false, now: _now));
      await p.initialize();
      CloudServices.premium = p;
      CloudServices.installAccessGuard();
      return p;
    }

    test('every write entry point refuses; reads, alarms and exports work; data is untouched', () async {
      // Real user data first, while unlocked.
      final routines = RoutineService();
      final planId = await TrainingPlanService().savePlan(
        TrainingPlan(
          name: 'Mine',
          days: [
            for (var d = 1; d <= 7; d++)
              TrainingPlanDay(weekday: d, isRest: d == 7),
          ],
        ),
      );
      final sessionId = await DatabaseService().createWorkoutSession(
        WorkoutSession(
          date: '2026-10-19',
          startTime: '07:00',
          primaryMuscle: 'Chest',
          clientRef: 'x',
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
      final before = await counts();
      expect(planId, greaterThan(0));
      expect(sessionId, greaterThan(0));

      final p = await lockedService();
      expect(p.isLocked, isTrue);

      await expectLater(
        TrainingPlanService().savePlan(TrainingPlan(name: 'New')),
        throwsA(isA<AccessLockedException>()),
      );
      await expectLater(
        TrainingPlanService().duplicatePlan(planId),
        throwsA(isA<AccessLockedException>()),
      );
      await expectLater(
        TrainingPlanService().deletePlan(planId),
        throwsA(isA<AccessLockedException>()),
      );
      await expectLater(
        routines.insertRoutine(
          Routine(
            title: 'x',
            category: 'Gym',
            startTime: '07:00',
            endTime: '08:00',
            repeatDays: const [1],
          ),
        ),
        throwsA(isA<AccessLockedException>()),
      );
      await expectLater(
        DatabaseService().saveOrUpdatePlan(WorkoutPlan(date: '2026-10-25')),
        throwsA(isA<AccessLockedException>()),
      );
      await expectLater(
        DatabaseService().createWorkoutSession(
          WorkoutSession(
            date: '2026-10-20',
            startTime: '07:00',
            primaryMuscle: 'Chest',
          ),
        ),
        throwsA(isA<AccessLockedException>()),
        reason: 'manual log is a write',
      );
      await expectLater(
        ActiveWorkoutController.unplanned(SqliteActiveSessionStore()).start(),
        throwsA(isA<AccessLockedException>()),
      );
      // Reading the plan for a date must not create anything while locked.
      expect(
        await TrainingPlanService().materializeDate(DateTime(2026, 10, 25)),
        isNull,
      );

      // Reads and the read-only export keep working.
      expect((await DatabaseService().getAllSessions()).length, 1);
      expect(await DatabaseService().exportBackupJson(), contains('Mine'));

      // Alarms: locking cancels nothing and re-arming from the DB still works.
      expect(calls.contains('cancelAlarm'), isFalse);
      await routines.rescheduleAllRoutines();
      expect(calls.contains('scheduleAlarm'), isTrue);

      // All data is byte-for-byte the same row counts.
      expect(await counts(), before);

      // Unlock: writes work again.
      AccessConfig.debugOverride = AccessModel.freemium;
      expect(p.isLocked, isFalse);
      await TrainingPlanService().savePlan(TrainingPlan(name: 'After unlock'));
      expect(await TrainingPlanService().countPlans(), 2);
      p.dispose();
    });

    test(
      'finishing an already running workout is never refused (no data loss)',
      () async {
        final c = ActiveWorkoutController.fromPlan(
          WorkoutPlan(
            date: '2026-10-20',
            exercises: [
              PlannedExercise(
                planId: 0,
                exerciseId: 1,
                exerciseName: 'Barbell Bench Press',
                muscleGroupName: 'Chest',
                targetSets: 1,
                targetReps: 5,
                targetWeightKg: 50,
              ),
            ],
          ),
          SqliteActiveSessionStore(),
        );
        await c.start(); // unlocked
        c.toggleSet(0, 0);
        final p = await lockedService();
        final id = await c.finish();
        expect(id, isNotNull);
        expect((await db.query('workout_sessions')).length, 1);
        p.dispose();
      },
    );

    test('freemium mode: nothing is locked and writes work', () async {
      AccessConfig.debugOverride = AccessModel.freemium;
      final p = await lockedService();
      expect(p.isLocked, isFalse);
      await TrainingPlanService().savePlan(TrainingPlan(name: 'ok'));
      p.dispose();
    });
  });

  group('MOCK-ONLY: root gate and screens', () {
    late Database db;

    setUp(() async {
      mockPlatformPlugins();
      TestWidgetsFlutterBinding.ensureInitialized();
      db = await openTestDatabase();
    });

    tearDown(() async => closeTestDatabase(db));

    Future<void> boot(WidgetTester tester) async {
      ignoreMissingPluginErrors();
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> show(
      WidgetTester tester, {
      required FakeEntitlementSource src,
      MemorySettingsStore? flags,
      FakeAuthService? auth,
    }) async {
      final p = service(src);
      CloudServices.premium = p;
      // The subscription belongs to an account: unless a test says otherwise
      // a verified, signed-in user is present (cloud configured).
      CloudServices.attachAuth(
        auth ??
            FakeAuthService(
              signedIn: const CloudUser(
                id: 'u-test',
                email: 'test@example.com',
              ),
            ),
      );
      CloudServices.installAccessGuard();
      await tester.runAsync(p.initialize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AccessRoot(
            settings: flags ?? MemorySettingsStore(),
            child: const Scaffold(body: Text('THE REAL APP')),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets(
      'first launch: onboarding once, then the paywall; never again',
      (tester) async {
        await boot(tester);
        final flags = MemorySettingsStore();
        await show(
          tester,
          src: FakeEntitlementSource(now: _now),
          flags: flags,
        );

        expect(find.text('Plan your week'), findsOneWidget);
        expect(find.text('THE REAL APP'), findsNothing);
        await tester.tap(find.text('Next'));
        await settle(tester);
        expect(find.text('Log every set'), findsOneWidget);
        await tester.tap(find.text('Next'));
        await settle(tester);
        expect(find.text('Stay on schedule'), findsOneWidget);
        await tester.tap(find.text('See plans'));
        await settle(tester);

        expect(flags.data[AccessRoot.onboardingKey], '1');
        expect(find.text('RepTrack needs a subscription'), findsOneWidget);
        expect(find.text('Restore purchases'), findsOneWidget);
        expect(find.text('Manage subscription in Google Play'), findsOneWidget);
        expect(find.text('THE REAL APP'), findsNothing);

        // Second launch with the flag set: straight to the paywall.
        await tester.pumpWidget(const SizedBox());
        await show(
          tester,
          src: FakeEntitlementSource(now: _now),
          flags: flags,
        );
        expect(find.text('Plan your week'), findsNothing);
        expect(find.text('RepTrack needs a subscription'), findsOneWidget);
      },
    );

    testWidgets('onboarding Skip also completes it', (tester) async {
      await boot(tester);
      final flags = MemorySettingsStore();
      await show(
        tester,
        src: FakeEntitlementSource(now: _now),
        flags: flags,
      );
      await tester.tap(find.text('Skip'));
      await settle(tester);
      expect(flags.data[AccessRoot.onboardingKey], '1');
      expect(find.text('RepTrack needs a subscription'), findsOneWidget);
    });

    testWidgets(
      'locked screen: allowed actions present, no free claims, no links when unset',
      (tester) async {
        await boot(tester);
        final flags = MemorySettingsStore()
          ..data[AccessRoot.onboardingKey] = '1';
        await show(
          tester,
          src: FakeEntitlementSource(now: _now),
          flags: flags,
          auth: FakeAuthService(
            signedIn: const CloudUser(id: 'u1', email: 'a@b.c'),
          ),
        );
        expect(find.text('Export my data'), findsOneWidget);
        expect(find.text('Account and delete account'), findsOneWidget);
        expect(find.text('Restore purchases'), findsOneWidget);
        expect(find.text('Manage subscription in Google Play'), findsOneWidget);
        expect(
          find.text('Privacy policy'),
          findsNothing,
          reason: 'URL not configured',
        );
        expect(find.text('Terms of use'), findsNothing);
        expect(find.textContaining('Free forever'), findsNothing);
        expect(
          find.textContaining('free'),
          findsNothing,
          reason: 'no trial in this offer, so no word free anywhere',
        );
        expect(find.text('THE REAL APP'), findsNothing);
        // price from the offer, not hard-coded
        expect(find.textContaining(r'$39.99'), findsWidgets);
      },
    );

    testWidgets('signed-out locked user has no account button', (tester) async {
      await boot(tester);
      final flags = MemorySettingsStore()..data[AccessRoot.onboardingKey] = '1';
      await show(
        tester,
        src: FakeEntitlementSource(now: _now),
        flags: flags,
        auth: FakeAuthService(),
      );
      expect(find.text('Account and delete account'), findsNothing);
      expect(find.text('Export my data'), findsOneWidget);
    });

    testWidgets(
      'trial text comes from the offer; absent when the offer has no trial',
      (tester) async {
        await boot(tester);
        final flags = MemorySettingsStore()
          ..data[AccessRoot.onboardingKey] = '1';
        final withTrial = FakeEntitlementSource(now: _now)
          ..offers = const [
            PremiumOffer(
              id: 'm',
              title: 'Monthly',
              priceString: r'$4.99',
              period: BillingPeriod.monthly,
            ),
            PremiumOffer(
              id: 'y',
              title: 'Yearly',
              priceString: r'$39.99',
              period: BillingPeriod.yearly,
              trial: TrialInfo(1, 'day'),
            ),
          ];
        await show(tester, src: withTrial, flags: flags);
        expect(find.text('Start 1 day trial'), findsOneWidget);
        expect(find.text('1 day trial first'), findsOneWidget);
        final disclosure = tester.widget<Text>(
          find.byKey(const ValueKey('paywall_disclosure')),
        );
        expect(disclosure.data, contains('1 day trial'));
        expect(disclosure.data, contains('auto-renewing'));
        expect(disclosure.data, contains('cancel'));

        // A different trial length is shown as given (nothing hard-coded).
        await tester.pumpWidget(const SizedBox());
        final sevenDays = FakeEntitlementSource(now: _now)
          ..offers = const [
            PremiumOffer(
              id: 'y',
              title: 'Yearly',
              priceString: r'$39.99',
              period: BillingPeriod.yearly,
              trial: TrialInfo(7, 'day'),
            ),
          ];
        await show(tester, src: sevenDays, flags: flags);
        expect(find.text('Start 7 days trial'), findsOneWidget);

        // No trial in the offer: no trial wording at all.
        await tester.pumpWidget(const SizedBox());
        await show(
          tester,
          src: FakeEntitlementSource(now: _now),
          flags: flags,
        );
        expect(find.text('Subscribe'), findsOneWidget);
        expect(find.textContaining('trial'), findsNothing);
      },
    );

    testWidgets('subscriber on cold start never sees the paywall; app shows', (
      tester,
    ) async {
      await boot(tester);
      final flags = MemorySettingsStore()..data[AccessRoot.onboardingKey] = '1';
      final src = FakeEntitlementSource(
        active: true,
        expiresAt: _now.add(const Duration(days: 30)),
        now: _now,
      )..holdFetch = Completer<void>();
      final p = service(src);
      CloudServices.premium = p;
      CloudServices.installAccessGuard();
      unawaited(p.initialize());
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
      expect(find.text('Checking your subscription...'), findsOneWidget);
      expect(find.text('RepTrack needs a subscription'), findsNothing);
      src.holdFetch!.complete();
      await settle(tester);
      expect(find.text('THE REAL APP'), findsOneWidget);
      expect(find.text('RepTrack needs a subscription'), findsNothing);
    });

    testWidgets('trial and premium users get the app', (tester) async {
      await boot(tester);
      final flags = MemorySettingsStore()..data[AccessRoot.onboardingKey] = '1';
      await show(
        tester,
        src: FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 1)),
          now: _now,
        )..trial = true,
        flags: flags,
      );
      expect(find.text('THE REAL APP'), findsOneWidget);
    });

    testWidgets(
      'store unreachable: retry card, Retry recovers, never a hard failure',
      (tester) async {
        await boot(tester);
        final flags = MemorySettingsStore()
          ..data[AccessRoot.onboardingKey] = '1';
        final src = FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 30)),
          now: _now,
        )..failFetch = true;
        await show(tester, src: src, flags: flags);
        expect(
          find.text('Could not verify your subscription - retry'),
          findsOneWidget,
        );
        expect(find.text('THE REAL APP'), findsNothing);
        src.failFetch = false;
        await tester.ensureVisible(find.text('Retry').first);
        await tester.tap(find.text('Retry').first);
        await settle(tester);
        expect(find.text('THE REAL APP'), findsOneWidget);
      },
    );

    testWidgets('freemium: no onboarding, no gate', (tester) async {
      await boot(tester);
      AccessConfig.debugOverride = AccessModel.freemium;
      await show(tester, src: FakeEntitlementSource(now: _now));
      expect(find.text('THE REAL APP'), findsOneWidget);
      expect(find.text('Plan your week'), findsNothing);
    });

    testWidgets(
      'purchase from the locked screen unlocks the app (no pop of the root)',
      (tester) async {
        await boot(tester);
        final flags = MemorySettingsStore()
          ..data[AccessRoot.onboardingKey] = '1';
        await show(
          tester,
          src: FakeEntitlementSource(now: _now),
          flags: flags,
        );
        await tester.tap(find.text('Subscribe'));
        await settle(tester);
        expect(find.text('THE REAL APP'), findsOneWidget);
      },
    );

    testWidgets('paywall in freemium keeps its old wording', (tester) async {
      await boot(tester);
      AccessConfig.debugOverride = AccessModel.freemium;
      final p = service(FakeEntitlementSource(now: _now));
      CloudServices.premium = p;
      await tester.runAsync(p.initialize);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const PaywallScreen()),
      );
      await settle(tester);
      expect(find.text('REPTRACK PREMIUM'), findsOneWidget);
      expect(find.textContaining('Free forever'), findsOneWidget);
    });
  });
}
