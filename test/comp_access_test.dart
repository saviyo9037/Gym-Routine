import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/access_config.dart';
import 'package:reptrack/services/comp_grant_source.dart';
import 'package:reptrack/services/premium_service.dart';

import 'helpers/cloud_fakes.dart';

// MOCK-ONLY: the comp source and the store are fakes. They prove how
// PremiumService MERGES a staff-granted (comp) entitlement into the access
// decision; the server side (grants -> entitlements row, expiry, revoke) is
// covered by backend/supabase/tests/app_config.test.sql.

class FakeComp implements CompGrantSource {
  FakeComp({this.userId = 'user-a', this.grant});
  @override
  String? userId;
  CompGrant? grant;
  bool fail = false;
  Completer<void>? hold;
  int calls = 0;

  @override
  Future<CompGrant?> fetch() async {
    calls++;
    if (hold != null) await hold!.future;
    if (fail) throw Exception('offline');
    return grant;
  }
}

final _now = DateTime(2026, 10, 20, 12);

PremiumService make(
  FakeEntitlementSource src,
  FakeComp comp, {
  MemorySettingsStore? store,
  DateTime Function()? clock,
}) => PremiumService(
  source: src,
  store: store ?? MemorySettingsStore(),
  clock: clock ?? () => _now,
  compSource: comp,
);

CompGrant live({Duration? left = const Duration(days: 5)}) =>
    CompGrant(isActive: true, expiresAt: left == null ? null : _now.add(left));

void main() {
  setUp(() => AccessConfig.debugOverride = AccessModel.subscriptionRequired);
  tearDown(() {
    AccessConfig.debugOverride = null;
    AccessConfig.setRemote(null);
  });

  test(
    'no comp source: behaviour is unchanged (free store user is locked)',
    () async {
      final p = PremiumService(
        source: FakeEntitlementSource(now: _now),
        store: MemorySettingsStore(),
        clock: () => _now,
      );
      await p.initialize();
      expect(p.isPremium, isFalse);
      expect(p.hasCompAccess, isFalse);
      expect(p.isLocked, isTrue);
    },
  );

  test(
    'a live comp grant opens the app for a user with no subscription',
    () async {
      final p = make(FakeEntitlementSource(now: _now), FakeComp(grant: live()));
      await p.initialize();
      expect(p.isPremium, isTrue);
      expect(p.entitlementState, EntitlementState.comp);
      expect(p.hasFullAccess, isTrue);
      expect(p.canUse(PremiumFeature.cloudSync), isTrue);
    },
  );

  test('comp without an expiry (owner-granted) stays open', () async {
    final p = make(
      FakeEntitlementSource(now: _now),
      FakeComp(grant: live(left: null)),
    );
    await p.initialize();
    expect(p.hasFullAccess, isTrue);
  });

  test(
    'expired, revoked (inactive) and missing grants do not open the app',
    () async {
      for (final g in <CompGrant?>[
        CompGrant(
          isActive: true,
          expiresAt: _now.subtract(const Duration(minutes: 1)),
        ),
        CompGrant(
          isActive: false,
          expiresAt: _now.add(const Duration(days: 5)),
        ),
        const CompGrant(isActive: false),
        null,
      ]) {
        final p = make(FakeEntitlementSource(now: _now), FakeComp(grant: g));
        await p.initialize();
        expect(p.isPremium, isFalse, reason: '$g');
        expect(p.isLocked, isTrue, reason: '$g');
        expect(p.entitlementState, isNot(EntitlementState.comp));
      }
    },
  );

  test(
    'a paid subscription keeps its own state; comp is the fallback',
    () async {
      final src = FakeEntitlementSource(
        active: true,
        expiresAt: _now.add(const Duration(days: 20)),
        now: _now,
      );
      final p = make(src, FakeComp(grant: live()));
      await p.initialize();
      expect(p.entitlementState, EntitlementState.active);
      // Subscription ends, comp is still valid -> comp.
      src
        ..active = false
        ..expiresAt = _now.subtract(const Duration(days: 1));
      await p.refresh();
      expect(p.entitlementState, EntitlementState.comp);
      expect(p.hasFullAccess, isTrue);
    },
  );

  test('revoking on the server locks the user at the next refresh', () async {
    final comp = FakeComp(grant: live());
    final p = make(FakeEntitlementSource(now: _now), comp);
    await p.initialize();
    expect(p.hasFullAccess, isTrue);
    comp.grant = const CompGrant(isActive: false);
    await p.refresh();
    expect(p.isLocked, isTrue);
  });

  test('"no row" from the server clears a cached grant', () async {
    final store = MemorySettingsStore();
    final comp = FakeComp(grant: live());
    final p = make(FakeEntitlementSource(now: _now), comp, store: store);
    await p.initialize();
    expect(store.data[PremiumService.compCacheKey], isNotEmpty);
    comp.grant = null;
    await p.refresh();
    expect(p.isLocked, isTrue);
    expect(store.data[PremiumService.compCacheKey], isEmpty);
  });

  group('offline rules (same as subscriptions)', () {
    test('a cached grant works offline within 14 days', () async {
      final store = MemorySettingsStore();
      final first = make(
        FakeEntitlementSource(now: _now),
        FakeComp(grant: live(left: const Duration(days: 60))),
        store: store,
      );
      await first.initialize();

      final later = _now.add(const Duration(days: 10));
      final offline = FakeComp(grant: null)..fail = true;
      final p = make(
        FakeEntitlementSource(now: later)..failFetch = true,
        offline,
        store: store,
        clock: () => later,
      );
      await p.initialize();
      expect(p.hasCompAccess, isTrue);
      expect(p.hasFullAccess, isTrue);
    });

    test('...but not after 14 days without a successful check', () async {
      final store = MemorySettingsStore();
      final first = make(
        FakeEntitlementSource(now: _now),
        FakeComp(grant: live(left: const Duration(days: 60))),
        store: store,
      );
      await first.initialize();

      final later = _now.add(const Duration(days: 15));
      final p = make(
        FakeEntitlementSource(now: later)..failFetch = true,
        FakeComp()..fail = true,
        store: store,
        clock: () => later,
      );
      await p.initialize();
      expect(p.hasCompAccess, isFalse);
      expect(p.isLocked, isTrue);
    });

    test('an offline grant also ends at its own expiry', () async {
      final store = MemorySettingsStore();
      final first = make(
        FakeEntitlementSource(now: _now),
        FakeComp(grant: live(left: const Duration(days: 2))),
        store: store,
      );
      await first.initialize();
      final later = _now.add(const Duration(days: 3));
      final p = make(
        FakeEntitlementSource(now: later)..failFetch = true,
        FakeComp()..fail = true,
        store: store,
        clock: () => later,
      );
      await p.initialize();
      expect(p.isLocked, isTrue);
    });

    test('a phone clock moved back does not extend a cached grant', () async {
      final store = MemorySettingsStore();
      final first = make(
        FakeEntitlementSource(now: _now),
        FakeComp(grant: live(left: const Duration(days: 60))),
        store: store,
      );
      await first.initialize();
      final earlier = _now.subtract(const Duration(days: 2));
      final p = make(
        FakeEntitlementSource(now: earlier)..failFetch = true,
        FakeComp()..fail = true,
        store: store,
        clock: () => earlier,
      );
      await p.initialize();
      expect(p.hasCompAccess, isFalse);
    });
  });

  group('account safety', () {
    test('a cached grant of another account is ignored at start-up', () async {
      final store = MemorySettingsStore();
      final first = make(
        FakeEntitlementSource(now: _now),
        FakeComp(userId: 'user-a', grant: live()),
        store: store,
      );
      await first.initialize();
      final p = make(
        FakeEntitlementSource(now: _now),
        FakeComp(userId: 'user-b')..fail = true,
        store: store,
      );
      await p.initialize();
      expect(p.hasCompAccess, isFalse);
      expect(p.isLocked, isTrue);
    });

    test('signing out clears the grant and its cache', () async {
      final store = MemorySettingsStore();
      final comp = FakeComp(grant: live());
      final p = make(FakeEntitlementSource(now: _now), comp, store: store);
      await p.initialize();
      expect(p.hasFullAccess, isTrue);
      comp.userId = null;
      await p.bindUser(null);
      expect(p.hasCompAccess, isFalse);
      expect(store.data[PremiumService.compCacheKey], isEmpty);
    });

    test(
      'switching accounts drops the previous account grant before refreshing',
      () async {
        final comp = FakeComp(userId: 'user-a', grant: live());
        final p = make(FakeEntitlementSource(now: _now), comp);
        await p.initialize();
        expect(p.hasCompAccess, isTrue);
        comp
          ..userId = 'user-b'
          ..grant = null;
        await p.bindUser('user-b');
        expect(p.hasCompAccess, isFalse);
        expect(p.isLocked, isTrue);
      },
    );

    test('an answer for a previous account that arrives after a switch is discarded', () async {
      final comp = FakeComp(userId: 'user-a', grant: live())
        ..hold = Completer<void>();
      final p = make(FakeEntitlementSource(now: _now), comp);
      final init = p.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      comp.userId =
          'user-b'; // switched while the request for user-a was in flight
      comp.hold!.complete();
      await init;
      expect(p.hasCompAccess, isFalse);
    });
  });

  test(
    'no flash of the paywall while a first comp answer is still pending',
    () async {
      final src = FakeEntitlementSource(now: _now);
      final comp = FakeComp(grant: live())..hold = Completer<void>();
      final p = make(src, comp);
      final init = p.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // The store has answered "free", the comp answer is outstanding.
      expect(p.accessLevel, AccessLevel.checking);
      comp.hold!.complete();
      await init;
      expect(p.accessLevel, AccessLevel.full);
    },
  );

  test(
    'a comp server error never marks the subscription check as failed',
    () async {
      final p = make(FakeEntitlementSource(now: _now), FakeComp()..fail = true);
      await p.initialize();
      expect(p.verificationFailed, isFalse);
      expect(p.isLocked, isTrue);
    },
  );

  test(
    'a remote access-model change re-evaluates the gate and notifies listeners',
    () async {
      AccessConfig.debugOverride =
          null; // the test override would outrank the remote layer
      final p = make(FakeEntitlementSource(now: _now), FakeComp());
      await p.initialize();
      expect(p.isLocked, isTrue);
      var notified = 0;
      p.addListener(() => notified++);
      AccessConfig.setRemote(AccessModel.freemium);
      expect(notified, 1);
      expect(p.accessLevel, AccessLevel.full);
      AccessConfig.setRemote(null);
      expect(p.isLocked, isTrue);
      p.dispose();
      // After dispose the listener is gone: no notifications, no exception.
      AccessConfig.setRemote(AccessModel.freemium);
    },
  );
}
