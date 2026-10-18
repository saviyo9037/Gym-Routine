import 'package:reptrack/services/auth_service.dart';

/// MOCK-ONLY auth backend for tests: scripted failures and call log. It never
/// stores or logs passwords; `calls` only holds method names.
class ScriptedAuthService extends AuthService {
  ScriptedAuthService({
    this.configured = true,
    this.google = false,
    CloudUser? signedIn,
  }) : _user = signedIn;

  final bool configured;
  bool google;
  CloudUser? _user;
  bool _recovery = false;

  /// Thrown by the next call that can fail, then cleared.
  AuthFailure? nextFailure;

  /// signUp result when no failure is scripted.
  bool signUpNeedsConfirmation = true;

  /// Addresses that already have an account (signUp -> emailTaken).
  final Set<String> registered = {};

  /// After [refreshUser] the signed-in user's e-mail counts as confirmed.
  bool confirmOnRefresh = false;

  final List<String> calls = [];
  String lastPasswordSet = '';

  AuthFailure? _take() {
    final f = nextFailure;
    nextFailure = null;
    return f;
  }

  static String idFor(String email) => 'u-${email.trim().toLowerCase()}';

  @override
  bool get isConfigured => configured;
  @override
  bool get googleAvailable => google;
  @override
  CloudUser? get user => _user;
  @override
  bool get recoveryPending => _recovery;

  void setUser(CloudUser? u) {
    _user = u;
    notifyListeners();
  }

  void startRecovery() {
    _recovery = true;
    notifyListeners();
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    calls.add('signIn');
    final f = _take();
    if (f != null) throw f;
    _user = CloudUser(id: idFor(email), email: email.trim());
    notifyListeners();
  }

  @override
  Future<bool> signUpWithEmail(String email, String password) async {
    calls.add('signUp');
    final f = _take();
    if (f != null) throw f;
    if (registered.contains(email.trim().toLowerCase())) {
      throw const AuthFailure(
        'An account with this e-mail already exists. Try signing in.',
        kind: AuthFailureKind.emailTaken,
      );
    }
    registered.add(email.trim().toLowerCase());
    if (signUpNeedsConfirmation) return true;
    _user = CloudUser(id: idFor(email), email: email.trim());
    notifyListeners();
    return false;
  }

  @override
  Future<void> resendConfirmation(String email) async {
    calls.add('resend');
    final f = _take();
    if (f != null) throw f;
  }

  @override
  Future<void> refreshUser() async {
    calls.add('refresh');
    final f = _take();
    if (f != null) throw f;
    final u = _user;
    if (u != null && confirmOnRefresh) {
      _user = CloudUser(id: u.id, email: u.email, emailVerified: true);
    }
    notifyListeners();
  }

  @override
  Future<void> signInWithGoogle() async {
    calls.add('google');
    final f = _take();
    if (f != null) throw f;
    _user = const CloudUser(id: 'u-google', email: 'g@example.com');
    notifyListeners();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    calls.add('reset');
    final f = _take();
    if (f != null) throw f;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    final f = _take();
    if (f != null) throw f;
    lastPasswordSet = newPassword;
    _recovery = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _user = null;
    _recovery = false;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('delete');
    final f = _take();
    if (f != null) throw f;
    _user = null;
    notifyListeners();
  }
}
