import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/cloud_config.dart';
import '../services/cloud_services.dart';
import '../services/password_rules.dart';
import '../widgets/auth_widgets.dart';
import 'not_configured_screen.dart';

/// Create an account: e-mail, password with live rules, confirmation and a
/// required terms checkbox.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.initialEmail = '',
    required this.onLogin,
    required this.onNeedsVerification,
    this.onSignedIn,
    this.showBack = false,
    this.onBack,
  });

  final String initialEmail;
  final void Function(String email) onLogin;
  final void Function(String email) onNeedsVerification;
  final VoidCallback? onSignedIn;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _terms = false;
  bool _termsError = false;
  bool _busy = false;
  String? _error;
  AuthFailureKind? _errorKind;

  AuthService get _auth => CloudServices.auth;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final valid = _formKey.currentState?.validate() ?? false;
    setState(() => _termsError = !_terms);
    if (!valid || !_terms) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorKind = null;
    });
    try {
      final needsConfirm = await _auth.signUpWithEmail(
        _email.text,
        _password.text,
      );
      if (!mounted) return;
      if (needsConfirm) {
        widget.onNeedsVerification(_email.text.trim());
      } else if (_auth.isSignedIn) {
        widget.onSignedIn?.call();
      }
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _errorKind = e.kind;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapAuthError(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isConfigured) return const NotConfiguredScreen();
    final hasLegal =
        CloudConfig.privacyUri != null || CloudConfig.termsUri != null;
    return AuthScaffold(
      title: 'Create account',
      showBack: widget.showBack,
      onBack: widget.onBack,
      children: [
        const AuthHeading(
          'Create your account',
          'An account is needed before you subscribe, because your '
              'subscription belongs to it. Your workouts stay on your phone.',
        ),
        if (_error != null) AuthBanner(_error!),
        if (_errorKind == AuthFailureKind.emailTaken)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => widget.onLogin(_email.text.trim()),
              child: const Text('Sign in instead'),
            ),
          ),
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                AuthEmailField(controller: _email, enabled: !_busy),
                const SizedBox(height: 12),
                AuthPasswordField(
                  fieldKey: const ValueKey('auth_new_password'),
                  controller: _password,
                  label: 'Password',
                  newPassword: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      PasswordRules.validate(v, email: _email.text),
                ),
                const SizedBox(height: 8),
                PasswordRulesView(password: _password.text, email: _email.text),
                const SizedBox(height: 12),
                AuthPasswordField(
                  fieldKey: const ValueKey('auth_confirm_password'),
                  controller: _confirm,
                  label: 'Confirm password',
                  newPassword: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Confirm your password';
                    return v == _password.text
                        ? null
                        : 'The passwords do not match';
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: const ValueKey('auth_terms'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _terms,
          activeColor: AppColors.primary,
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  _terms = v ?? false;
                  if (_terms) _termsError = false;
                }),
          title: Text(
            hasLegal
                ? 'I agree to the Terms of use and the Privacy policy (links below).'
                : 'I accept the terms of use and privacy policy.',
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: _termsError
              ? const Text(
                  'You need to accept to create an account.',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                )
              : null,
        ),
        const LegalLinks(alignment: WrapAlignment.start),
        const SizedBox(height: 8),
        AuthButton(label: 'Create account', busy: _busy, onPressed: _submit),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => widget.onLogin(_email.text.trim()),
            child: const Text(
              'I already have an account',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
}
