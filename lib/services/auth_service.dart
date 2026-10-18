import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_config.dart';

class CloudUser {
  const CloudUser({required this.id, this.email, this.emailVerified = true});
  final String id;
  final String? email;

  /// False while the sign-up confirmation e-mail has not been clicked.
  final bool emailVerified;
}

/// What went wrong, so screens can show the right message and the right
/// follow-up action (resend e-mail, wait, check the connection...).
enum AuthFailureKind {
  wrongCredentials,
  emailTaken,
  invalidEmail,
  weakPassword,
  network,
  rateLimited,
  emailNotConfirmed,
  cancelled,
  notConfigured,
  server,
  unknown,
}

/// A user-presentable failure (never a stack trace, never contains the
/// e-mail, the password or a token).
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.kind = AuthFailureKind.unknown});
  final String message;
  final AuthFailureKind kind;
  @override
  String toString() => message;
}

/// Maps any auth/network error to a friendly [AuthFailure]. Pure and
/// testable: it only looks at the exception type and Supabase error code.
AuthFailure mapAuthError(Object e) {
  if (e is AuthFailure) return e;
  if (e is AuthRetryableFetchException ||
      e is SocketException ||
      e is TimeoutException ||
      e is HttpException) {
    return const AuthFailure(
      'Could not reach the server. Check your connection and try again.',
      kind: AuthFailureKind.network,
    );
  }
  if (e is AuthException) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    final status = e.statusCode;
    if (code == 'invalid_credentials' ||
        msg.contains('invalid login credentials')) {
      return const AuthFailure(
        'The e-mail or password is not correct.',
        kind: AuthFailureKind.wrongCredentials,
      );
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return const AuthFailure(
        'Please confirm your e-mail first. Check your inbox for the link.',
        kind: AuthFailureKind.emailNotConfirmed,
      );
    }
    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        msg.contains('already registered') ||
        msg.contains('already been registered')) {
      return const AuthFailure(
        'An account with this e-mail already exists. Try signing in.',
        kind: AuthFailureKind.emailTaken,
      );
    }
    if (code == 'weak_password' || msg.contains('password should')) {
      return const AuthFailure(
        'That password is too weak. Use a longer, less common password.',
        kind: AuthFailureKind.weakPassword,
      );
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        code == 'over_sms_send_rate_limit' ||
        status == '429' ||
        msg.contains('rate limit') ||
        msg.contains('too many')) {
      return const AuthFailure(
        'Too many attempts. Please wait a few minutes and try again.',
        kind: AuthFailureKind.rateLimited,
      );
    }
    if (code == 'validation_failed' ||
        code == 'email_address_invalid' ||
        msg.contains('invalid email') ||
        msg.contains('unable to validate email')) {
      return const AuthFailure(
        'Enter a valid e-mail address.',
        kind: AuthFailureKind.invalidEmail,
      );
    }
    if (status != null && status.startsWith('5')) {
      return const AuthFailure(
        'The server had a problem. Please try again in a moment.',
        kind: AuthFailureKind.server,
      );
    }
    return const AuthFailure(
      'Something went wrong. Please try again.',
      kind: AuthFailureKind.unknown,
    );
  }
  if (e is FunctionException) {
    return const AuthFailure(
      'The server could not complete the request. Please try again.',
      kind: AuthFailureKind.server,
    );
  }
  return const AuthFailure(
    'Could not reach the server. Check your connection and try again.',
    kind: AuthFailureKind.network,
  );
}

/// Accounts. In the subscription-required model an account is needed before
/// purchasing (the subscription is tied to the account); a build without
/// cloud configuration reports [isConfigured] == false and every method
/// throws a friendly [AuthFailure] instead of crashing.
abstract class AuthService extends ChangeNotifier {
  /// False in builds without SUPABASE_URL / SUPABASE_ANON_KEY.
  bool get isConfigured;
  bool get googleAvailable;
  CloudUser? get user;
  bool get isSignedIn => user != null;

  /// True when a password-recovery link opened the app: the user must now
  /// choose a new password ([updatePassword]).
  bool get recoveryPending => false;

  Future<void> signInWithEmail(String email, String password);

  /// Returns true when the project requires e-mail confirmation before the
  /// first sign-in (no session was created).
  Future<bool> signUpWithEmail(String email, String password);

  /// Re-sends the sign-up confirmation e-mail.
  Future<void> resendConfirmation(String email);

  /// Reloads the signed-in user (to pick up a confirmed e-mail).
  Future<void> refreshUser();

  Future<void> signInWithGoogle();
  Future<void> sendPasswordReset(String email);

  /// Sets a new password for the signed-in (recovery) session.
  Future<void> updatePassword(String newPassword);

  Future<void> signOut();

  /// Deletes the cloud data and the auth user (Edge Function), then signs out.
  Future<void> deleteAccount();
}

/// Used when the build has no Supabase configuration.
class NoCloudAuthService extends AuthService {
  static const _msg = 'Cloud accounts are not set up in this build.';
  static const _failure = AuthFailure(
    _msg,
    kind: AuthFailureKind.notConfigured,
  );

  @override
  bool get isConfigured => false;
  @override
  bool get googleAvailable => false;
  @override
  CloudUser? get user => null;

  @override
  Future<void> signInWithEmail(String email, String password) async =>
      throw _failure;
  @override
  Future<bool> signUpWithEmail(String email, String password) async =>
      throw _failure;
  @override
  Future<void> resendConfirmation(String email) async => throw _failure;
  @override
  Future<void> refreshUser() async {}
  @override
  Future<void> signInWithGoogle() async => throw _failure;
  @override
  Future<void> sendPasswordReset(String email) async => throw _failure;
  @override
  Future<void> updatePassword(String newPassword) async => throw _failure;
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async => throw _failure;
}

class SupabaseAuthService extends AuthService {
  SupabaseAuthService(this._client) {
    _sub = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _recovery = true;
      } else if (state.event == AuthChangeEvent.signedOut) {
        _recovery = false;
      }
      notifyListeners();
    });
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _sub;
  bool _googleReady = false;
  bool _recovery = false;

  SupabaseClient get client => _client;

  @override
  bool get isConfigured => true;
  @override
  bool get googleAvailable => CloudConfig.googleConfigured;
  @override
  bool get recoveryPending => _recovery;

  @override
  CloudUser? get user {
    final u = _client.auth.currentUser;
    return u == null
        ? null
        : CloudUser(
            id: u.id,
            email: u.email,
            emailVerified: u.emailConfirmedAt != null,
          );
  }

  Never _fail(Object e) => throw mapAuthError(e);

  @override
  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<bool> signUpWithEmail(String email, String password) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      // With e-mail confirmation on, signing up an address that is already
      // registered returns a user without identities instead of an error.
      final identities = res.user?.identities;
      if (res.session == null && identities != null && identities.isEmpty) {
        throw const AuthFailure(
          'An account with this e-mail already exists. Try signing in.',
          kind: AuthFailureKind.emailTaken,
        );
      }
      return res.session == null;
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(type: OtpType.signup, email: email.trim());
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> refreshUser() async {
    try {
      if (_client.auth.currentSession != null) {
        await _client.auth.refreshSession();
      }
    } catch (e) {
      _fail(e);
    }
    notifyListeners();
  }

  @override
  Future<void> signInWithGoogle() async {
    if (!googleAvailable) {
      throw const AuthFailure(
        'Google sign-in is not set up in this build.',
        kind: AuthFailureKind.notConfigured,
      );
    }
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(
          serverClientId: CloudConfig.googleWebClientId,
        );
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure('Google did not return an identity token.');
      }
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure(
          'Sign-in was cancelled.',
          kind: AuthFailureKind.cancelled,
        );
      }
      throw const AuthFailure('Google sign-in failed. Please try again.');
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      _recovery = false;
      notifyListeners();
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Local sign-out must always succeed.
      await _client.auth.signOut(scope: SignOutScope.local);
    }
    _recovery = false;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount() async {
    try {
      final res = await _client.functions.invoke('delete-account');
      if (res.status >= 400) {
        throw const AuthFailure(
          'The account could not be fully deleted. Please try again; '
          'it is safe to retry.',
          kind: AuthFailureKind.server,
        );
      }
    } catch (e) {
      _fail(e);
    }
    await signOut();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
