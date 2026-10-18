import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/diagnostics_screen.dart';
import 'package:reptrack/screens/paywall_screen.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/mock_billing.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/video_access_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

final _now = DateTime(2026, 10, 20, 12);

Future<(PremiumService, MockEntitlementSource)> boot({
  MemorySettingsStore? store,
}) async {
  final src = MockEntitlementSource(store: store, clock: () => _now);
  final p = PremiumService(
    source: src,
    store: store ?? MemorySettingsStore(),
    clock: () => _now,
  );
  await p.initialize();
  return (p, src);
}

Future<void> pushed() => Future<void>.delayed(Duration.zero);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // Default access model = subscription required (the real gate).
  setUp(() => AccessConfig.debugOverride = null);

  group('release safety', () {
    test('allowed only in a debug build that asked for it', () {
      expect(MockBilling.allowed(debugMode: true, define: true), isTrue);
      expect(MockBilling.allowed(debugMode: false, define: true), isFalse);
      expect(MockBilling.allowed(debugMode: true, define: false), isFalse);
      expect(MockBilling.allowed(debugMode: false, define: false), isFalse);
    });

    test('the source refuses to exist outside debug mode', () {
      expect(
        () => MockEntitlementSource(debugMode: false),
        throwsA(anyOf(isA<AssertionError>(), isA<StateError>())),
      );
      expect(() => MockEntitlementSource(debugMode: true), returnsNormally);
    });

    test(
      'off unless MOCK_BILLING is defined (this test run defines nothing)',
      () {
        expect(MockBilling.enabled, isFalse);
      },
    );

    test('the release script refuses a MOCK_BILLING define', () {
      final script = File('scripts/build_release.ps1').readAsStringSync();
      expect(script, contains('MOCK_BILLING'));
      expect(script, contains('throw'));
    });

    test('nothing outside the mock files references the mock source', () {
      // Only these may import it; each use is behind kDebugMode / MockBilling.
      final allowed = {
        'mock_billing.dart',
        'mock_purchase_sheet.dart',
        'premium_service.dart',
        'paywall_screen.dart',
        'diagnostics_screen.dart',
      };
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        if (allowed.contains(name)) continue;
        expect(
          f.readAsStringSync().contains('mock_billing.dart'),
          isFalse,
          reason: f.path,
        );
      }
    });
  });

  group('offers', () {
    test('monthly and yearly with real-format prices and trial text', () async {
      final (p, _) = await boot();
      final offers = await p.offerings();
      expect(offers.map((o) => o.period), [
        BillingPeriod.monthly,
        BillingPeriod.yearly,
      ]);
      expect(offers[0].priceString, r'$4.99');
      expect(offers[1].priceString, r'$29.99');
      expect(offers.every((o) => o.trial?.label == '1 day'), isTrue);
      p.dispose();
    });
  });

  group('every state (forced from Diagnostics)', () {
    final expectations = <MockBillingState, (EntitlementState, AccessLevel)>{
      MockBillingState.noAccess: (EntitlementState.free, AccessLevel.locked),
      MockBillingState.trial: (EntitlementState.trial, AccessLevel.full),
      MockBillingState.premium: (EntitlementState.active, AccessLevel.full),
      MockBillingState.expired: (EntitlementState.expired, AccessLevel.locked),
      MockBillingState.grace: (EntitlementState.gracePeriod, AccessLevel.full),
      MockBillingState.refunded: (EntitlementState.expired, AccessLevel.locked),
    };

    for (final e in expectations.entries) {
      test(
        '${e.key.label} -> ${e.value.$1.name} / ${e.value.$2.name}',
        () async {
          final (p, src) = await boot();
          await src.setState(e.key);
          await pushed();
          expect(p.entitlementState, e.value.$1);
          expect(p.accessLevel, e.value.$2);
          expect(p.isPremium, e.value.$2 == AccessLevel.full);
          p.dispose();
        },
      );
    }

    test('all six states are covered', () {
      expect(expectations.keys.toSet(), MockBillingState.values.toSet());
    });

    test(
      'state survives a restart (persisted through the settings store)',
      () async {
        final store = MemorySettingsStore();
        var (p, src) = await boot(store: store);
        await src.setState(MockBillingState.premium);
        await pushed();
        p.dispose();
        (p, src) = await boot(store: store);
        expect(src.state, MockBillingState.premium);
        expect(p.accessLevel, AccessLevel.full);
        p.dispose();
      },
    );

    test('moving from premium back to no access locks again', () async {
      final (p, src) = await boot();
      await src.setState(MockBillingState.premium);
      await pushed();
      expect(p.hasFullAccess, isTrue);
      await src.setState(MockBillingState.noAccess);
      await pushed();
      expect(p.isLocked, isTrue);
      p.dispose();
    });
  });

  group('purchase outcomes', () {
    test('success on a trial offer starts the trial', () async {
      final (p, src) = await boot();
      final offer = (await p.offerings()).last;
      expect(p.isLocked, isTrue);
      src.nextOutcome = MockOutcome.success;
      await p.purchase(offer);
      expect(p.entitlementState, EntitlementState.trial);
      expect(p.hasFullAccess, isTrue);
      p.dispose();
    });

    test('success on an offer without a trial is premium', () async {
      final (p, src) = await boot();
      src.nextOutcome = MockOutcome.success;
      await p.purchase(
        const PremiumOffer(
          id: 'x',
          title: 'x',
          priceString: r'$1.00',
          period: BillingPeriod.monthly,
        ),
      );
      expect(p.entitlementState, EntitlementState.active);
      p.dispose();
    });

    test('cancel throws a cancelled exception and changes nothing', () async {
      final (p, src) = await boot();
      src.nextOutcome = MockOutcome.cancel;
      await expectLater(
        p.purchase((await p.offerings()).first),
        throwsA(
          isA<PremiumException>().having((e) => e.cancelled, 'cancelled', true),
        ),
      );
      expect(p.isLocked, isTrue);
      p.dispose();
    });

    test('failed throws a non-cancel error and changes nothing', () async {
      final (p, src) = await boot();
      src.nextOutcome = MockOutcome.failed;
      await expectLater(
        p.purchase((await p.offerings()).first),
        throwsA(
          isA<PremiumException>().having(
            (e) => e.cancelled,
            'cancelled',
            false,
          ),
        ),
      );
      expect(p.isLocked, isTrue);
      p.dispose();
    });

    test('pending changes nothing until confirmed', () async {
      final (p, src) = await boot();
      src.nextOutcome = MockOutcome.pending;
      await p.purchase((await p.offerings()).first);
      expect(p.isLocked, isTrue);
      p.dispose();
    });

    test('a purchase without a chosen outcome is rejected', () async {
      final (p, _) = await boot();
      await expectLater(
        p.purchase((await p.offerings()).first),
        throwsA(isA<PremiumException>()),
      );
      expect(p.isLocked, isTrue);
      p.dispose();
    });

    test('the outcome is used once', () async {
      final (p, src) = await boot();
      src.nextOutcome = MockOutcome.pending;
      await p.purchase((await p.offerings()).first);
      expect(src.nextOutcome, isNull);
      p.dispose();
    });
  });

  group('videos locked state follows the mock entitlement', () {
    test('locked without access, unlocked with trial/premium/grace', () async {
      final (p, src) = await boot();
      final videos = VideoAccessService(
        canAccessVideos: () => p.isPremium,
        fetchSignedUrl: (_) async =>
            throw const VideoAccessException(VideoAccessFailure.unavailable),
        cacheDirectory: () async => Directory.systemTemp.createTemp('mockvid'),
      );
      expect(videos.isEntitled, isFalse);
      await expectLater(
        videos.ensureDownloaded(1),
        throwsA(
          isA<VideoAccessException>().having(
            (e) => e.kind,
            'kind',
            VideoAccessFailure.notEntitled,
          ),
        ),
      );
      for (final s in [
        MockBillingState.trial,
        MockBillingState.premium,
        MockBillingState.grace,
      ]) {
        await src.setState(s);
        await pushed();
        expect(videos.isEntitled, isTrue, reason: s.label);
      }
      for (final s in [MockBillingState.expired, MockBillingState.refunded]) {
        await src.setState(s);
        await pushed();
        expect(videos.isEntitled, isFalse, reason: s.label);
      }
      p.dispose();
    });
  });

  group('paywall with the fake sheet', () {
    late Database db;
    setUp(() {
      mockPlatformPlugins();
      CloudServices.resetForTesting();
    });

    Future<PremiumService> open(WidgetTester tester) async {
      ignoreMissingPluginErrors();
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      db = (await tester.runAsync(openTestDatabase))!;
      final (p, _) = (await tester.runAsync(boot))!;
      CloudServices.premium = p;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const PaywallScreen(locked: true),
        ),
      );
      await settle(tester);
      return p;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => closeTestDatabase(db));
      CloudServices.resetForTesting();
    }

    testWidgets('shows the fake offers and trial text', (tester) async {
      await open(tester);
      expect(find.textContaining(r'$29.99'), findsWidgets);
      expect(find.textContaining(r'$4.99'), findsWidgets);
      expect(find.text('Start 1 day trial'), findsOneWidget);
      await close(tester);
    });

    testWidgets('Subscribe opens the TEST MODE sheet; Success unlocks', (
      tester,
    ) async {
      final p = await open(tester);
      await tester.tap(find.text('Start 1 day trial'));
      await settle(tester);
      expect(find.text('TEST MODE, no real payment'), findsOneWidget);
      for (final k in [
        'mock_success',
        'mock_cancel',
        'mock_failed',
        'mock_pending',
      ]) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      await tester.tap(find.byKey(const ValueKey('mock_success')));
      await settle(tester);
      expect(p.entitlementState, EntitlementState.trial);
      expect(find.text('Your trial is active'), findsOneWidget);
      await close(tester);
    });

    for (final k in ['mock_cancel', 'mock_failed', 'mock_pending']) {
      testWidgets('$k leaves the user locked', (tester) async {
        final p = await open(tester);
        await tester.tap(find.text('Start 1 day trial'));
        await settle(tester);
        await tester.tap(find.byKey(ValueKey(k)));
        await settle(tester);
        expect(p.isLocked, isTrue);
        expect(find.text('Start 1 day trial'), findsOneWidget);
        await close(tester);
      });
    }

    testWidgets('dismissing the sheet counts as cancel', (tester) async {
      final p = await open(tester);
      await tester.tap(find.text('Start 1 day trial'));
      await settle(tester);
      await tester.tapAt(const Offset(10, 10)); // barrier
      await settle(tester);
      expect(p.isLocked, isTrue);
      await close(tester);
    });
  });

  group('Diagnostics buttons', () {
    late Database db;
    setUp(mockPlatformPlugins);

    testWidgets('each button sets its state', (tester) async {
      ignoreMissingPluginErrors();
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      db = (await tester.runAsync(openTestDatabase))!;
      CloudServices.resetForTesting();
      final (p, src) = (await tester.runAsync(boot))!;
      CloudServices.premium = p;

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const DiagnosticsScreen()),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('mock_billing_card')), findsOneWidget);

      for (final s in MockBillingState.values) {
        final b = find.byKey(ValueKey('mock_state_${s.name}'));
        await tester.ensureVisible(b);
        await tester.tap(b);
        await settle(tester);
        expect(src.state, s, reason: s.label);
      }
      expect(p.entitlementState, EntitlementState.expired); // refunded last

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => closeTestDatabase(db));
      CloudServices.resetForTesting();
    });

    testWidgets('no mock card without the mock source', (tester) async {
      ignoreMissingPluginErrors();
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      db = (await tester.runAsync(openTestDatabase))!;
      CloudServices.resetForTesting();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const DiagnosticsScreen()),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('mock_billing_card')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => closeTestDatabase(db));
    });
  });
}
