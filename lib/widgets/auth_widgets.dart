import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/cloud_config.dart';
import '../services/cloud_services.dart';
import '../services/password_rules.dart';
import '../services/premium_service.dart';

/// Page frame for every auth screen: dark background, centred column, scrolls
/// (so it survives 2.0x text and small screens), keyboard friendly.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.children,
    this.showBack = false,
    this.onBack,
  });

  final String title;
  final List<Widget> children;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: onBack ?? () => Navigator.maybePop(context),
              )
            : null,
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class AuthHeading extends StatelessWidget {
  const AuthHeading(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class AuthEmailField extends StatelessWidget {
  const AuthEmailField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const ValueKey('auth_email'),
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      enableSuggestions: false,
      onFieldSubmitted: onSubmitted,
      decoration: const InputDecoration(
        labelText: 'E-mail',
        prefixIcon: Icon(Icons.mail_outline_rounded),
      ),
      validator: (v) => (v ?? '').trim().isEmpty
          ? 'Enter your e-mail'
          : (PasswordRules.validEmail(v) ? null : 'Enter a valid e-mail'),
    );
  }
}

/// Password input with an accessible show/hide toggle and the right
/// autofill hint (`password` for sign-in, `newPassword` for sign-up).
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.fieldKey,
    this.newPassword = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final bool newPassword;
  final bool enabled;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.fieldKey,
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onFieldSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(
            _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator:
          widget.validator ??
          (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
    );
  }
}

/// Live rule checklist + strength meter for a new password.
class PasswordRulesView extends StatelessWidget {
  const PasswordRulesView({super.key, required this.password, this.email});

  final String password;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final strength = PasswordRules.strength(password, email: email);
    final label = PasswordRules.strengthLabel(strength);
    final color = switch (strength) {
      0 || 1 => AppColors.error,
      2 => AppColors.warning,
      _ => AppColors.success,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Password strength: $label',
          child: ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: i < strength ? color : AppColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          password.isEmpty ? 'Choose a strong password' : 'Strength: $label',
          style: TextStyle(color: color, fontSize: 12),
        ),
        const SizedBox(height: 6),
        for (final r in PasswordRules.checklist(password))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Semantics(
              label: '${r.label}: ${r.ok ? 'met' : 'not met'}',
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      r.ok
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: r.ok ? AppColors.success : AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: r.ok
                              ? AppColors.textMain
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Error / info banner. A live region so screen readers announce changes.
class AuthBanner extends StatelessWidget {
  const AuthBanner(this.text, {super.key, this.isError = true});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.error : AppColors.success;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: AppColors.textMain, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(label, textAlign: TextAlign.center),
    );
  }
}

Future<void> _openLink(BuildContext context, Uri uri) async {
  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
  }
}

/// Privacy / terms links. A link whose URL was not set at build time is
/// hidden (no URL is ever invented).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.alignment = WrapAlignment.center});
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final privacy = CloudConfig.privacyUri;
    final terms = CloudConfig.termsUri;
    if (privacy == null && terms == null) return const SizedBox.shrink();
    return Wrap(
      alignment: alignment,
      spacing: 8,
      children: [
        if (privacy != null)
          TextButton(
            onPressed: () => _openLink(context, privacy),
            child: const Text('Privacy policy'),
          ),
        if (terms != null)
          TextButton(
            onPressed: () => _openLink(context, terms),
            child: const Text('Terms of use'),
          ),
      ],
    );
  }
}

/// What must stay reachable for someone who is not (yet) able to use the app:
/// restore purchases, manage the subscription, legal links and an export of
/// the data already on this phone. None of it changes any data.
class LockedOptions extends StatefulWidget {
  const LockedOptions({super.key, this.showRestore = true});

  final bool showRestore;

  @override
  State<LockedOptions> createState() => _LockedOptionsState();
}

class _LockedOptionsState extends State<LockedOptions> {
  String? _busy;

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _restore() async {
    if (_busy != null) return;
    setState(() => _busy = 'restore');
    try {
      final premium = CloudServices.premium;
      await premium.restore();
      _toast(
        premium.isPremium
            ? 'Subscription restored.'
            : 'No active subscription was found for this Google account.',
      );
    } on PremiumException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not restore purchases. Try again later.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _export() async {
    if (_busy != null) return;
    setState(() => _busy = 'export');
    try {
      final json = await BackupService().exportJson();
      final file = File(
        '${Directory.systemTemp.path}/reptrack_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'RepTrack backup',
          text: 'RepTrack data export (JSON)',
        ),
      );
    } catch (_) {
      _toast('Export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(color: AppColors.border, height: 28),
        const Text(
          'MORE OPTIONS',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (widget.showRestore)
              OutlinedButton.icon(
                onPressed: _busy == null ? _restore : null,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('Restore purchases'),
              ),
            OutlinedButton.icon(
              onPressed: () => _openLink(
                context,
                Uri.parse(CloudConfig.playSubscriptionsUrl),
              ),
              icon: const Icon(Icons.manage_accounts_rounded, size: 18),
              label: const Text('Manage subscription'),
            ),
            OutlinedButton.icon(
              onPressed: _busy == null ? _export : null,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Export my data'),
            ),
          ],
        ),
        const LegalLinks(alignment: WrapAlignment.start),
      ],
    );
  }
}

/// Maps an [AuthFailure] to the text the user sees.
String authErrorText(Object e) {
  if (e is AuthFailure) return e.message;
  return mapAuthError(e).message;
}
