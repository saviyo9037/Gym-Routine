import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../widgets/auth_widgets.dart';

/// "Check your inbox": shown after sign-up when the project requires e-mail
/// confirmation (not signed in yet), and for a signed-in account whose e-mail
/// is not confirmed. Resend has a cooldown so the user cannot hammer the
/// mail provider (which would trigger the rate limit).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.onSignIn,
    this.cooldown = const Duration(seconds: 60),
  });

  /// The address the confirmation mail went to.
  final String email;

  /// "I confirmed it": go to sign-in with the e-mail pre-filled.
  final void Function(String email) onSignIn;

  final Duration cooldown;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _timer;
  int _left = 0;
  bool _busy = false;
  String? _error;
  String? _info;

  AuthService get _auth => CloudServices.auth;

  @override
  void initState() {
    super.initState();
    // A mail was just sent by the sign-up call: start the cooldown at once.
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _left = widget.cooldown.inSeconds);
    if (_left <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_busy || _left > 0) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await _auth.resendConfirmation(widget.email);
      if (mounted) {
        setState(() => _info = 'A new confirmation e-mail is on its way.');
        _startCooldown();
      }
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        // After a rate limit, wait before another attempt.
        if (e.kind == AuthFailureKind.rateLimited) _startCooldown();
      }
    } catch (e) {
      if (mounted) setState(() => _error = mapAuthError(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verified() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_auth.isSignedIn) {
        await _auth.refreshUser();
        if (mounted && !(_auth.user?.emailVerified ?? false)) {
          setState(() => _error = 'Your e-mail is not confirmed yet.');
        }
      } else {
        widget.onSignIn(widget.email);
      }
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
    return AuthScaffold(
      title: 'Confirm your e-mail',
      children: [
        const Icon(
          Icons.mark_email_unread_rounded,
          color: AppColors.primary,
          size: 48,
        ),
        const SizedBox(height: 12),
        AuthHeading(
          'Check your inbox',
          'We sent a confirmation link to ${widget.email}. Open it, then '
              'come back and continue. Look in your spam folder too.',
        ),
        if (_error != null) AuthBanner(_error!),
        if (_info != null) AuthBanner(_info!, isError: false),
        AuthButton(
          label: _auth.isSignedIn
              ? "I've confirmed it"
              : "I've confirmed it - sign in",
          busy: _busy,
          onPressed: _verified,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: (_busy || _left > 0) ? null : _resend,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(
            _left > 0 ? 'Resend e-mail in ${_left}s' : 'Resend e-mail',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  if (_auth.isSignedIn) {
                    await _auth.signOut();
                  } else {
                    widget.onSignIn('');
                  }
                },
          child: Text(
            _auth.isSignedIn ? 'Use a different account' : 'Back to sign in',
          ),
        ),
      ],
    );
  }
}
