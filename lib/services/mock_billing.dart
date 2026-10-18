import 'dart:async';

import 'package:flutter/foundation.dart';

import 'premium_service.dart';

/// DEBUG-ONLY mock billing. Enabled with `--dart-define=MOCK_BILLING=true` in a
/// debug build; in profile/release builds it can never be on:
///  * [enabled] is `kDebugMode && define` - `kDebugMode` is a compile-time
///    constant, so every branch guarded by it is dead code in release;
///  * [MockEntitlementSource]'s constructor throws outside debug mode (and
///    asserts), so even a stray call cannot hand out access;
///  * `scripts/build_release.ps1` refuses to build when MOCK_BILLING is set.
class MockBilling {
  static const bool _define = bool.fromEnvironment('MOCK_BILLING');

  /// The only switch the app reads.
  static bool get enabled => kDebugMode && _define;

  /// Pure rule (injectable for tests): mock billing is allowed only in a debug
  /// build that asked for it.
  static bool allowed({required bool debugMode, required bool define}) =>
      debugMode && define;

  /// Throws outside debug mode.
  static void requireDebug([bool? debugMode]) {
    final debug = debugMode ?? kDebugMode;
    assert(debug, 'Mock billing is debug-only');
    if (!debug) {
      throw StateError('Mock billing is debug-only and cannot run here.');
    }
  }
}

/// What the user picked in the fake purchase sheet.
enum MockOutcome { success, cancel, failed, pending }

/// The entitlement states the Diagnostics screen can force.
enum MockBillingState {
  noAccess('No access'),
  trial('Trial'),
  premium('Premium'),
  expired('Expired'),
  grace('Grace period'),
  refunded('Refunded');

  const MockBillingState(this.label);
  final String label;
}

/// Fake [EntitlementSource]: fake offers, fake purchases, forced states.
/// Nothing here talks to RevenueCat or Google Play.
class MockEntitlementSource implements EntitlementSource {
  MockEntitlementSource({
    this._store,
    DateTime Function()? clock,
    bool? debugMode,
  }) : _clock = clock ?? DateTime.now {
    MockBilling.requireDebug(debugMode);
  }

  static const String storeKey = 'mock_billing_state';

  /// Fake trial text source: the real app reads this from the Play offer.
  static const TrialInfo mockTrial = TrialInfo(1, 'day');

  final SettingsStore? _store;
  final DateTime Function() _clock;
  final _controller = StreamController<PremiumSnapshot>.broadcast();

  MockBillingState _state = MockBillingState.noAccess;
  bool _loaded = false;

  /// Set by the fake sheet just before [PremiumService.purchase].
  MockOutcome? nextOutcome;

  MockBillingState get state => _state;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _store?.read(storeKey);
      for (final s in MockBillingState.values) {
        if (s.name == raw) _state = s;
      }
    } catch (_) {}
  }

  PremiumSnapshot snapshotFor(MockBillingState s) {
    final now = _clock();
    const day = Duration(days: 1);
    switch (s) {
      case MockBillingState.noAccess:
        return PremiumSnapshot(isActive: false, checkedAt: now);
      case MockBillingState.trial:
        return PremiumSnapshot(
          isActive: true,
          isTrial: true,
          willRenew: true,
          expiresAt: now.add(day),
          productId: 'mock_yearly',
          checkedAt: now,
        );
      case MockBillingState.premium:
        return PremiumSnapshot(
          isActive: true,
          willRenew: true,
          expiresAt: now.add(day * 30),
          productId: 'mock_monthly',
          checkedAt: now,
        );
      case MockBillingState.expired:
        return PremiumSnapshot(
          isActive: false,
          expiresAt: now.subtract(day),
          productId: 'mock_monthly',
          checkedAt: now,
        );
      case MockBillingState.grace:
        return PremiumSnapshot(
          isActive: true,
          billingIssue: true,
          willRenew: true,
          expiresAt: now.add(day * 3),
          productId: 'mock_monthly',
          checkedAt: now,
        );
      case MockBillingState.refunded:
        // The store reports a refund as an ended entitlement.
        return PremiumSnapshot(
          isActive: false,
          expiresAt: now.subtract(day * 2),
          productId: 'mock_monthly',
          checkedAt: now,
        );
    }
  }

  /// Forces [s] (Diagnostics buttons). The service picks it up through the
  /// updates stream exactly like a push from the store.
  Future<void> setState(MockBillingState s) async {
    await _load();
    _state = s;
    try {
      await _store?.write(storeKey, s.name);
    } catch (_) {}
    if (!_controller.isClosed) _controller.add(snapshotFor(s));
  }

  @override
  bool get isAvailable => true;

  @override
  Future<PremiumSnapshot> fetch() async {
    await _load();
    return snapshotFor(_state);
  }

  @override
  Stream<PremiumSnapshot> get updates => _controller.stream;

  @override
  Future<List<PremiumOffer>> offerings() async => const [
    PremiumOffer(
      id: 'mock_monthly',
      title: 'RepTrack Monthly (TEST)',
      priceString: '\$4.99',
      period: BillingPeriod.monthly,
      trial: mockTrial,
    ),
    PremiumOffer(
      id: 'mock_yearly',
      title: 'RepTrack Yearly (TEST)',
      priceString: '\$29.99',
      period: BillingPeriod.yearly,
      trial: mockTrial,
    ),
  ];

  @override
  Future<PremiumSnapshot> purchase(PremiumOffer offer) async {
    final outcome = nextOutcome;
    nextOutcome = null;
    if (outcome == null) {
      throw const PremiumException('Mock purchase: no outcome was chosen.');
    }
    switch (outcome) {
      case MockOutcome.success:
        await setState(
          offer.trial != null
              ? MockBillingState.trial
              : MockBillingState.premium,
        );
        return snapshotFor(_state);
      case MockOutcome.cancel:
        throw const PremiumException('Purchase cancelled.', cancelled: true);
      case MockOutcome.failed:
        throw const PremiumException(
          'The purchase could not be completed. You were not charged.',
        );
      case MockOutcome.pending:
        // Nothing changes until the (fake) payment is confirmed.
        await _load();
        return snapshotFor(_state);
    }
  }

  @override
  Future<PremiumSnapshot> restore() async {
    await _load();
    return snapshotFor(_state);
  }

  @override
  Future<void> logIn(String appUserId) async {}

  @override
  Future<void> logOut() async {}
}
