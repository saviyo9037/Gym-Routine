// Pure logic: deriveEntitlement has no I/O, so these tests are NOT mock-based.
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/services/premium_service.dart';

final now = DateTime.utc(2026, 10, 17, 12);

PremiumSnapshot snap({
  bool active = true,
  DateTime? expires,
  bool renew = true,
  bool billing = false,
  Duration checkedAgo = Duration.zero,
}) => PremiumSnapshot(
  isActive: active,
  expiresAt: expires,
  willRenew: renew,
  billingIssue: billing,
  checkedAt: now.subtract(checkedAgo),
);

EntitlementDecision d(
  PremiumSnapshot? s, {
  bool verified = true,
  bool initialised = true,
  DateTime? at,
}) => deriveEntitlement(
  snapshot: s,
  now: at ?? now,
  verifiedThisSession: verified,
  initialised: initialised,
);

void main() {
  group('entitlement states', () {
    test('unknown until loaded', () {
      final r = d(null, initialised: false);
      expect(r.state, EntitlementState.unknown);
      expect(r.isPremium, isFalse);
    });

    test('no snapshot: free', () {
      final r = d(null);
      expect(r.state, EntitlementState.free);
      expect(r.isPremium, isFalse);
    });

    test('active and renewing: premium', () {
      final r = d(snap(expires: now.add(const Duration(days: 20))));
      expect(r.state, EntitlementState.active);
      expect(r.isPremium, isTrue);
      expect(r.offline, isFalse);
    });

    test('lifetime-style entitlement without expiry date stays active', () {
      expect(d(snap()).isPremium, isTrue);
    });

    test(
      'cancelled (will not renew) keeps premium until the paid period ends',
      () {
        final r = d(
          snap(renew: false, expires: now.add(const Duration(days: 3))),
        );
        expect(r.state, EntitlementState.cancelledActive);
        expect(r.isPremium, isTrue);
        // ...and loses it the moment the period ends.
        final later = d(
          snap(renew: false, expires: now.add(const Duration(days: 3))),
          at: now.add(const Duration(days: 3, seconds: 1)),
        );
        expect(later.state, EntitlementState.expired);
        expect(later.isPremium, isFalse);
      },
    );

    test(
      'billing problem inside the paid period: grace period, still premium',
      () {
        final r = d(
          snap(billing: true, expires: now.add(const Duration(days: 1))),
        );
        expect(r.state, EntitlementState.gracePeriod);
        expect(r.isPremium, isTrue);
      },
    );

    test(
      'billing problem after expiry: grace is honoured for at most 16 days',
      () {
        final exp = now.subtract(const Duration(days: 5));
        final inGrace = d(snap(billing: true, expires: exp));
        expect(inGrace.state, EntitlementState.gracePeriod);
        expect(inGrace.isPremium, isTrue);
        final tooLong = d(
          snap(billing: true, expires: now.subtract(const Duration(days: 17))),
        );
        expect(tooLong.state, EntitlementState.expired);
        expect(tooLong.isPremium, isFalse);
      },
    );

    test('expired (active flag still set but date passed): not premium', () {
      final r = d(snap(expires: now.subtract(const Duration(minutes: 1))));
      expect(r.state, EntitlementState.expired);
      expect(r.isPremium, isFalse);
    });

    test(
      'inactive entitlement that had an end date is expired, otherwise free',
      () {
        expect(
          d(snap(active: false, expires: now.subtract(const Duration(days: 1))))
              .state,
          EntitlementState.expired,
        );
        expect(d(snap(active: false)).state, EntitlementState.free);
      },
    );

    test(
      'refunded / revoked arrives as inactive: premium ends immediately',
      () {
        // RevenueCat flips the entitlement to inactive even though the period
        // had not ended; the app cannot tell a refund from an expiry.
        final r = d(
          snap(active: false, expires: now.add(const Duration(days: 10))),
        );
        expect(r.isPremium, isFalse);
        expect(r.state, EntitlementState.free);
      },
    );

    test(
      'restored purchase: a fresh verified active snapshot is premium again',
      () {
        final before = d(snap(active: false));
        final restored = d(snap(expires: now.add(const Duration(days: 30))));
        expect(before.isPremium, isFalse);
        expect(restored.isPremium, isTrue);
      },
    );
  });

  group('offline cache rules', () {
    final active = now.add(const Duration(days: 40));

    test('cached premium checked 10 days ago is trusted while offline', () {
      final r = d(
        snap(expires: active, checkedAgo: const Duration(days: 10)),
        verified: false,
      );
      expect(r.isPremium, isTrue);
      expect(r.offline, isTrue);
      expect(r.state, EntitlementState.active);
    });

    test('cached premium older than 14 days is NOT trusted', () {
      final r = d(
        snap(expires: active, checkedAgo: const Duration(days: 15)),
        verified: false,
      );
      expect(r.state, EntitlementState.staleOffline);
      expect(r.isPremium, isFalse);
    });

    test('exactly 14 days is still trusted, 14 days + 1 s is not', () {
      expect(
        d(
          snap(expires: active, checkedAgo: const Duration(days: 14)),
          verified: false,
        ).isPremium,
        isTrue,
      );
      expect(
        d(
          snap(
            expires: active,
            checkedAgo: const Duration(days: 14, seconds: 1),
          ),
          verified: false,
        ).isPremium,
        isFalse,
      );
    });

    test('a verified session ignores the cache age', () {
      final r = d(
        snap(expires: active, checkedAgo: const Duration(days: 30)),
        verified: true,
      );
      expect(r.isPremium, isTrue);
    });

    test('moving the phone clock BACK does not extend offline premium', () {
      // Snapshot was verified "tomorrow" relative to the (rolled back) clock.
      final s = PremiumSnapshot(
        isActive: true,
        expiresAt: active,
        willRenew: true,
        checkedAt: now.add(const Duration(days: 20)),
      );
      final r = d(s, verified: false);
      expect(r.state, EntitlementState.staleOffline);
      expect(r.isPremium, isFalse);
    });

    test('the cached expiry date is still enforced offline', () {
      final r = d(
        snap(
          expires: now.subtract(const Duration(days: 1)),
          checkedAgo: const Duration(days: 2),
        ),
        verified: false,
      );
      expect(r.state, EntitlementState.expired);
      expect(r.isPremium, isFalse);
    });

    test('cached grace period is bounded by the offline limit too', () {
      final r = d(
        snap(
          billing: true,
          expires: now.add(const Duration(days: 2)),
          checkedAgo: const Duration(days: 20),
        ),
        verified: false,
      );
      expect(r.isPremium, isFalse);
    });
  });

  group('snapshot persistence', () {
    test('billingIssue survives the cache round trip', () {
      final s = snap(billing: true, expires: now.add(const Duration(days: 1)));
      final back = PremiumSnapshot.fromJson(s.toJson())!;
      expect(back.billingIssue, isTrue);
      expect(back.willRenew, isTrue);
    });

    test('an old cache entry without the billing flag still loads', () {
      final back = PremiumSnapshot.fromJson({
        'a': true,
        'e': now.add(const Duration(days: 1)).toIso8601String(),
        'r': true,
        'p': 'monthly',
        'c': now.toIso8601String(),
      })!;
      expect(back.billingIssue, isFalse);
    });
  });
}
