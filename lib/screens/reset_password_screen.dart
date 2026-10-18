import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../services/password_rules.dart';
import '../widgets/auth_widgets.dart';

/// Choose a new password after a recovery link opened the app
/// (`AuthService.recoveryPending`). If the build does not handle recovery
/// links, the reset happens on the project's hosted page and this screen is
/// never shown.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.onDone});

  final VoidCallback? onDone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
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
      await CloudServices.auth.updatePassword(_password.text);
      if (mounted) widget.onDone?.call();
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
    final email = CloudServices.auth.user?.email;
    return AuthScaffold(
      title: 'New password',
      children: [
        const AuthHeading(
          'Choose a new password',
          'Pick a password you have not used elsewhere.',
        ),
        if (_error != null) AuthBanner(_error!),
        AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                AuthPasswordField(
                  fieldKey: const ValueKey('auth_reset_password'),
                  controller: _password,
                  label: 'New password',
                  newPassword: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  validator: (v) => PasswordRules.validate(v, email: email),
                ),
                const SizedBox(height: 8),
                PasswordRulesView(password: _password.text, email: email),
                const SizedBox(height: 12),
                AuthPasswordField(
                  fieldKey: const ValueKey('auth_reset_confirm'),
                  controller: _confirm,
                  label: 'Confirm new password',
                  newPassword: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '').isEmpty
                      ? 'Confirm your password'
                      : (v == _password.text
                            ? null
                            : 'The passwords do not match'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        AuthButton(label: 'Save new password', busy: _busy, onPressed: _submit),
      ],
    );
  }
}
