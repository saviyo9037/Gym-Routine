import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/cloud_config.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/sync_service.dart';

import 'helpers/cloud_fakes.dart';
import 'helpers/fake_sync_remote.dart';

import 'package:reptrack/core/access_config.dart';

final _now = DateTime(2026, 10, 20, 12);

PremiumService make(
  FakeEntitlementSource src, {
  MemorySettingsStore? store,
  DateTime Function()? clock,
}) => PremiumService(
  source: src,
  store: store ?? MemorySettingsStore(),
  clock: clock ?? () => _now,
);

void main() {
  // These tests describe the FREEMIUM behaviour (free core, premium extras).
  // The subscription-required model is covered by access_gate_test.dart.
  setUp(() => AccessConfig.debugOverride = AccessModel.freemium);
  tearDown(() => AccessConfig.debugOverride = null);

  group('MOCK-ONLY: PremiumService gating', () {
    test('free by default: every premium feature is locked', () async {
      final p = make(FakeEntitlementSource(active: false));
      await p.initialize();
      expect(p.status, PremiumStatus.free);
      for (final f in PremiumFeature.values) {
        expect(p.canUse(f), isFalse, reason: '$f');
      }
    });

    test('active entitlement unlocks every premium feature', () async {
      final p = make(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 20)),
        ),
      );
      await p.initialize();
      expect(p.isPremium, isTrue);
      for (final f in PremiumFeature.values) {
        expect(p.canUse(f), isTrue, reason: '$f');
      }
    });

    test('alarms, logging, library, history and routines are not gateable', () {
      final names = PremiumFeature.values
          .map((e) => e.name.toLowerCase())
          .join(' ');
      for (final forbidden in [
        'alarm',
        'routine',
        'log',
        'library',
        'history',
      ]) {
        expect(names.contains(forbidden), isFalse, reason: forbidden);
      }
      expect(PremiumFeature.values.toSet(), {
        PremiumFeature.cloudSync,
        PremiumFeature.advancedStats,
        PremiumFeature.unlimitedPlans,
        PremiumFeature.exportData,
      });
    });

    test('expired entitlement is free even if the store says active', () async {
      final p = make(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.subtract(const Duration(minutes: 1)),
        ),
      );
      await p.initialize();
      expect(p.isPremium, isFalse);
    });

    test(
      'refresh picks up a new purchase / cancellation pushed by the store',
      () async {
        final src = FakeEntitlementSource(active: false);
        final p = make(src);
        await p.initialize();
        expect(p.isPremium, isFalse);
        src
          ..active = true
          ..expiresAt = _now.add(const Duration(days: 30))
          ..push();
        await Future<void>.delayed(Duration.zero);
        expect(p.isPremium, isTrue);
        src
          ..active = false
          ..push();
        await Future<void>.delayed(Duration.zero);
        expect(p.isPremium, isFalse);
      },
    );

    test(
      'purchase unlocks, cancelled purchase changes nothing and reports it',
      () async {
        final src = FakeEntitlementSource();
        final p = make(src);
        await p.initialize();
        final offer = (await p.offerings()).first;
        src.cancelPurchase = true;
        await expectLater(
          p.purchase(offer),
          throwsA(
            isA<PremiumException>().having(
              (e) => e.cancelled,
              'cancelled',
              true,
            ),
          ),
        );
        expect(p.isPremium, isFalse);
        src.cancelPurchase = false;
        await p.purchase(offer);
        expect(p.isPremium, isTrue);
      },
    );
  });

  group('MOCK-ONLY: offline / cached state', () {
    test(
      'last known premium is trusted offline within the grace period',
      () async {
        final store = MemorySettingsStore();
        final online = FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 60)),
          now: _now,
        );
        await make(online, store: store).initialize();
        expect(store.data[PremiumService.cacheKey], isNotNull);

        // App restarts with no network 5 days later.
        final offline = FakeEntitlementSource()..failFetch = true;
        final later = _now.add(const Duration(days: 5));
        final p = make(offline, store: store, clock: () => later);
        await p.initialize();
        expect(p.isPremium, isTrue);
        expect(p.lastError, isNotNull);
      },
    );

    test(
      'cached premium stops being trusted after the offline grace',
      () async {
        final store = MemorySettingsStore();
        await make(
          FakeEntitlementSource(
            active: true,
            expiresAt: _now.add(const Duration(days: 365)),
            now: _now,
          ),
          store: store,
        ).initialize();
        final offline = FakeEntitlementSource()..failFetch = true;
        final later = _now.add(
          PremiumService.offlineGrace + const Duration(days: 1),
        );
        final p = make(offline, store: store, clock: () => later);
        await p.initialize();
        expect(p.isPremium, isFalse);
      },
    );

    test('cached entitlement past its expiry date is free', () async {
      final store = MemorySettingsStore();
      await make(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 2)),
          now: _now,
        ),
        store: store,
      ).initialize();
      final offline = FakeEntitlementSource()..failFetch = true;
      final p = make(
        offline,
        store: store,
        clock: () => _now.add(const Duration(days: 3)),
      );
      await p.initialize();
      expect(p.isPremium, isFalse);
    });

    test('a corrupt cache never crashes and means free', () async {
      final store = MemorySettingsStore()
        ..data[PremiumService.cacheKey] = '{not json';
      final src = FakeEntitlementSource()..failFetch = true;
      final p = make(src, store: store);
      await p.initialize();
      expect(p.isPremium, isFalse);
    });

    test('verified status is cached for the next start', () async {
      final store = MemorySettingsStore();
      await make(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 9)),
        ),
        store: store,
      ).initialize();
      final j = jsonDecode(store.data[PremiumService.cacheKey]!) as Map;
      expect(j['a'], true);
    });
  });

  group('MOCK-ONLY: plan limit', () {
    test('free users can keep 2 plans; the 3rd is blocked, existing ones untouched', () async {
      final p = make(FakeEntitlementSource());
      await p.initialize();
      expect(PremiumService.freePlanLimit, 2);
      expect(p.canCreatePlan(0), isTrue);
      expect(p.canCreatePlan(1), isTrue);
      expect(p.canCreatePlan(2), isFalse);
      expect(
        p.canCreatePlan(7),
        isFalse,
      ); // already over the limit: no new ones
    });

    test('premium has no limit', () async {
      final p = make(
        FakeEntitlementSource(
          active: true,
          expiresAt: _now.add(const Duration(days: 9)),
        ),
      );
      await p.initialize();
      expect(p.canCreatePlan(500), isTrue);
    });
  });

  group('MOCK-ONLY: account linking', () {
    test('signing in links the store customer to the account id', () async {
      final src = FakeEntitlementSource();
      final p = make(src);
      await p.initialize();
      await p.bindUser('user-42');
      await p.bindUser(null);
      expect(src.loggedIn, ['user-42', '<logout>']);
    });
  });

  group(
    'MOCK-ONLY: cloud not configured (default test build has no dart-defines)',
    () {
      setUp(CloudServices.resetForTesting);

      test(
        'config is empty, accounts and store are off, nothing throws',
        () async {
          expect(CloudConfig.supabaseConfigured, isFalse);
          expect(CloudConfig.revenueCatConfigured, isFalse);
          expect(CloudConfig.googleConfigured, isFalse);
          final auth = CloudServices.auth;
          expect(auth.isConfigured, isFalse);
          expect(auth.isSignedIn, isFalse);
          await auth.signOut(); // no-op
          await expectLater(
            auth.signInWithEmail('a@b.c', 'secret1'),
            throwsA(isA<AuthFailure>()),
          );
          final p = CloudServices.premium;
          await p.initialize();
          expect(p.isPremium, isFalse);
          expect(p.storeAvailable, isFalse);
          expect(await p.offerings(), isEmpty);
          expect(CloudServices.sync.state, SyncState.notConfigured);
          await CloudServices.sync.syncNow(); // must not throw or do anything
          expect(CloudServices.sync.lastReport, isNull);
        },
      );
    },
  );

  group('MOCK-ONLY: SyncService eligibility', () {
    test('runs only when configured + signed in + premium', () async {
      final remote = FakeSyncRemote();
      var built = 0;
      final src = FakeEntitlementSource();
      final premium = make(src);
      await premium.initialize();
      final auth = FakeAuthService();
      final sync = SyncService(
        auth: auth,
        premium: premium,
        remoteFactory: (_) {
          built++;
          return remote;
        },
      );
      expect(sync.state, SyncState.signedOut);
      await sync.syncNow();
      expect(built, 0);

      await auth.signInWithEmail('a@b.c', 'secret1');
      expect(sync.state, SyncState.needsPremium);
      await sync.syncNow();
      expect(built, 0, reason: 'free users never sync');

      src
        ..active = true
        ..expiresAt = _now.add(const Duration(days: 9));
      await premium.refresh();
      expect(sync.state, SyncState.idle);
      expect(sync.canSync, isTrue);
      expect(built, 0);

      await auth.signOut();
      expect(sync.state, SyncState.signedOut);
      expect(sync.canSync, isFalse);
    });
  });
}
