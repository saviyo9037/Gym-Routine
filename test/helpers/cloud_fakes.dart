import 'dart:async';

import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/premium_service.dart';

class FakeEntitlementSource implements EntitlementSource {
  FakeEntitlementSource({this.active = false, this.expiresAt, DateTime? now})
    : _now = now ?? DateTime(2026, 10, 20, 12);

  bool active;
  DateTime? expiresAt;
  bool failFetch = false;
  bool trial = false;
  int failFetchTimes = 0; // fail this many fetches, then succeed
  Completer<void>? holdFetch; // fetch waits for this completer
  int fetchCalls = 0;
  bool failPurchase = false;
  bool cancelPurchase = false;
  bool available = true;
  List<PremiumOffer> offers = const [
    PremiumOffer(
      id: r'$rc_monthly',
      title: 'Monthly',
      priceString: r'$4.99',
      period: BillingPeriod.monthly,
    ),
    PremiumOffer(
      id: r'$rc_annual',
      title: 'Yearly',
      priceString: r'$39.99',
      period: BillingPeriod.yearly,
    ),
  ];
  final List<String> loggedIn = [];
  final _updates = StreamController<PremiumSnapshot>.broadcast();
  DateTime _now;

  void setNow(DateTime d) => _now = d;

  PremiumSnapshot snapshot() => PremiumSnapshot(
    isActive: active,
    expiresAt: expiresAt,
    willRenew: active,
    isTrial: active && trial,
    productId: active ? 'premium_monthly' : null,
    checkedAt: _now,
  );

  void push() => _updates.add(snapshot());

  @override
  bool get isAvailable => available;
  @override
  Future<PremiumSnapshot> fetch() async {
    fetchCalls++;
    if (holdFetch != null) await holdFetch!.future;
    if (failFetch) throw Exception('offline');
    if (failFetchTimes > 0) {
      failFetchTimes--;
      throw Exception('offline');
    }
    return snapshot();
  }

  @override
  Stream<PremiumSnapshot> get updates => _updates.stream;
  @override
  Future<List<PremiumOffer>> offerings() async => offers;
  @override
  Future<PremiumSnapshot> purchase(PremiumOffer offer) async {
    if (cancelPurchase) {
      throw const PremiumException('Purchase cancelled.', cancelled: true);
    }
    if (failPurchase) throw const PremiumException('declined');
    active = true;
    expiresAt = _now.add(const Duration(days: 30));
    return snapshot();
  }

  @override
  Future<PremiumSnapshot> restore() async => snapshot();
  @override
  Future<void> logIn(String appUserId) async => loggedIn.add(appUserId);
  @override
  Future<void> logOut() async => loggedIn.add('<logout>');
}

class FakeAuthService extends AuthService {
  FakeAuthService({CloudUser? signedIn, this.configured = true})
    : _user = signedIn;

  CloudUser? _user;
  final bool configured;
  int deleteCalls = 0;
  bool failSignIn = false;

  void _setUserForTest(CloudUser? u) {
    _user = u;
    notifyListeners();
  }

  @override
  bool get isConfigured => configured;
  @override
  bool get googleAvailable => false;
  @override
  CloudUser? get user => _user;

  @override
  Future<void> signInWithEmail(String email, String password) async {
    if (failSignIn) throw const AuthFailure('Invalid login credentials');
    _user = CloudUser(id: 'u-1', email: email);
    notifyListeners();
  }

  @override
  Future<bool> signUpWithEmail(String email, String password) async => true;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> resendConfirmation(String email) async {}
  @override
  Future<void> refreshUser() async {}
  @override
  Future<void> updatePassword(String newPassword) async {}
  @override
  Future<void> signOut() async {
    _user = null;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    _user = null;
    notifyListeners();
  }
}

/// Test helper: swap the signed-in user without going through sign-in.
extension FakeAuthUser on FakeAuthService {
  void setUser(CloudUser? u) {
    // ignore: invalid_use_of_protected_member
    _setUserForTest(u);
  }
}
