import 'package:flutter/material.dart';

import 'forgot_password_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';

enum AuthPage { login, register, forgot, verify }

/// The signed-out part of the flow: sign in / create account / forgot
/// password / confirm e-mail. Used by the root gate (no route, no way around
/// it) and from Settings (as a route with [popOnSignedIn]).
class AuthFlowScreen extends StatefulWidget {
  const AuthFlowScreen({
    super.key,
    this.initialPage = AuthPage.login,
    this.popOnSignedIn = false,
    this.verifyCooldown = const Duration(seconds: 60),
  });

  final AuthPage initialPage;

  /// When opened as a route: close it once the user is signed in.
  final bool popOnSignedIn;
  final Duration verifyCooldown;

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  late AuthPage _page = widget.initialPage;
  String _email = '';

  void _go(AuthPage p, [String? email]) {
    setState(() {
      _page = p;
      if (email != null) _email = email;
    });
  }

  void _signedIn() {
    if (widget.popOnSignedIn && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = widget.popOnSignedIn;
    final Widget body = switch (_page) {
      AuthPage.login => LoginScreen(
        key: ValueKey('login-$_email'),
        initialEmail: _email,
        showBack: canGoBack,
        onRegister: () => _go(AuthPage.register),
        onForgot: (e) => _go(AuthPage.forgot, e),
        onNeedsVerification: (e) => _go(AuthPage.verify, e),
        onSignedIn: _signedIn,
      ),
      AuthPage.register => RegisterScreen(
        key: ValueKey('register-$_email'),
        initialEmail: _email,
        showBack: true,
        onBack: () => _go(AuthPage.login),
        onLogin: (e) => _go(AuthPage.login, e),
        onNeedsVerification: (e) => _go(AuthPage.verify, e),
        onSignedIn: _signedIn,
      ),
      AuthPage.forgot => ForgotPasswordScreen(
        key: ValueKey('forgot-$_email'),
        initialEmail: _email,
        onBack: () => _go(AuthPage.login),
      ),
      AuthPage.verify => VerifyEmailScreen(
        key: ValueKey('verify-$_email'),
        email: _email,
        cooldown: widget.verifyCooldown,
        onSignIn: (e) => _go(AuthPage.login, e),
      ),
    };
    // Back button: sub-pages return to sign-in first; on the sign-in page the
    // system default applies (leave the route / exit the app).
    return PopScope(
      canPop: _page == AuthPage.login,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(AuthPage.login);
      },
      child: body,
    );
  }
}
