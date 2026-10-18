import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../widgets/auth_widgets.dart';
import 'not_configured_screen.dart';

/// Request a password-reset e-mail. The link in that e-mail opens the
/// project's hosted reset page (or, if the build handles the recovery link,
/// the in-app [ResetPasswordScreen]); the user then signs in with the new
/// password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    this.initialEmail = '',
    required this.onBack,
  });

  final String initialEmail;
  final VoidCallback onBack;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudServices.auth.sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = mapAuthError(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CloudServices.auth.isConfigured) return const NotConfiguredScreen();
    return AuthScaffold(
      title: 'Reset password',
      showBack: true,
      onBack: widget.onBack,
      children: [
        const AuthHeading(
          'Forgot your password?',
          'Enter your account e-mail and we will send you a reset link.',
        ),
        if (_error != null) AuthBanner(_error!),
        if (_sent) ...[
          const AuthBanner(
            'If an account exists for this e-mail, a reset link is on its '
            'way. Open it on this phone, choose a new password, then come '
            'back here and sign in.',
            isError: false,
          ),
          OutlinedButton(
            onPressed: widget.onBack,
            child: const Text('Back to sign in'),
          ),
        ] else ...[
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: AuthEmailField(
                controller: _email,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AuthButton(label: 'Send reset link', busy: _busy, onPressed: _submit),
        ],
      ],
    );
  }
}
