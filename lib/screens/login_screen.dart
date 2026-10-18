import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../widgets/auth_widgets.dart';
import 'not_configured_screen.dart';

/// E-mail/password and Google sign-in. Reports where to go next through
/// callbacks; the root gate reacts to the signed-in state by itself.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialEmail = '',
    required this.onRegister,
    required this.onForgot,
    required this.onNeedsVerification,
    this.onSignedIn,
    this.showBack = false,
    this.onBack,
  });

  final String initialEmail;
  final VoidCallback onRegister;
  final void Function(String email) onForgot;
  final void Function(String email) onNeedsVerification;
  final VoidCallback? onSignedIn;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  AuthService get _auth => CloudServices.auth;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && _auth.isSignedIn) widget.onSignedIn?.call();
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.kind == AuthFailureKind.emailNotConfirmed) {
        widget.onNeedsVerification(_email.text.trim());
      } else if (e.kind != AuthFailureKind.cancelled) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapAuthError(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _run(() => _auth.signInWithEmail(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isConfigured) {
      return const NotConfiguredScreen();
    }
    return AuthScaffold(
      title: 'Sign in',
      showBack: widget.showBack,
      onBack: widget.onBack,
      children: [
        const AuthHeading(
          'Welcome back',
          'Sign in to your RepTrack account. Your subscription belongs to '
              'this account.',
        ),
        if (_error != null) AuthBanner(_error!),
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                AuthEmailField(controller: _email, enabled: !_busy),
                const SizedBox(height: 12),
                AuthPasswordField(
                  fieldKey: const ValueKey('auth_password'),
                  controller: _password,
                  label: 'Password',
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AuthButton(label: 'Sign in', busy: _busy, onPressed: _submit),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : () => widget.onForgot(_email.text.trim()),
            child: const Text('Forgot password?'),
          ),
        ),
        if (_auth.googleAvailable) ...[
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(_auth.signInWithGoogle),
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Continue with Google'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _busy ? null : widget.onRegister,
            child: const Text(
              'New to RepTrack? Create an account',
              style: TextStyle(color: AppColors.primary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const LockedOptions(),
      ],
    );
  }
}
