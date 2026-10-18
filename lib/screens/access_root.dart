import 'package:flutter/material.dart';

import '../core/access_config.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/cloud_services.dart';
import '../services/premium_service.dart';
import 'account_switch_screen.dart';
import 'auth_flow_screen.dart';
import 'locked_screen.dart';
import 'onboarding_screen.dart';
import 'reset_password_screen.dart';
import 'verify_email_screen.dart';

/// The root gate. With `ACCESS_MODEL=subscription_required` the order is:
///
///   onboarding -> sign in / register -> (account checks) -> paywall -> app
///
/// The subscription belongs to the account, so an account is required before
/// the paywall whenever the build has cloud accounts configured. Without
/// cloud configuration there is nothing to sign in to: the premium gate (and
/// the "not configured" locked screen) decide. In `freemium` mode the app is
/// shown directly.
class AccessRoot extends StatefulWidget {
  const AccessRoot({super.key, required this.child, this.settings});

  final Widget child;

  /// Where the "onboarding done" flag lives (defaults to user_settings).
  final SettingsStore? settings;

  static const onboardingKey = 'onboarding_done';

  @override
  State<AccessRoot> createState() => _AccessRootState();
}

class _AccessRootState extends State<AccessRoot> {
  late final SettingsStore _settings = widget.settings ?? DbSettingsStore();
  PremiumService? _premium;
  AuthService? _auth;
  bool? _onboardingDone;

  // Account-switch decision for the currently signed-in user.
  String? _switchCheckedFor;
  bool _switchNeeded = false;
  bool _switchChecking = false;

  @override
  void initState() {
    super.initState();
    _bind();
    _loadFlag();
  }

  void _bind() {
    final p = CloudServices.premium;
    if (!identical(p, _premium)) {
      _premium?.removeListener(_changed);
      _premium = p..addListener(_changed);
    }
    final a = CloudServices.auth;
    if (!identical(a, _auth)) {
      _auth?.removeListener(_authChanged);
      _auth = a..addListener(_authChanged);
      CloudServices.binding
        ..removeListener(_changed)
        ..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _premium?.removeListener(_changed);
    _auth?.removeListener(_authChanged);
    CloudServices.binding.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _authChanged() {
    if (!mounted) return;
    final id = CloudServices.auth.user?.id;
    if (id == null) {
      // Signed out: forget the decision so the next sign-in is checked again.
      _switchCheckedFor = null;
      _switchNeeded = false;
    }
    setState(() {});
  }

  Future<void> _loadFlag() async {
    var done = false;
    try {
      done = (await _settings.read(AccessRoot.onboardingKey)) == '1';
    } catch (_) {
      done = false;
    }
    if (mounted) setState(() => _onboardingDone = done);
  }

  Future<void> _finishOnboarding() async {
    setState(() => _onboardingDone = true);
    try {
      await _settings.write(AccessRoot.onboardingKey, '1');
    } catch (_) {
      // Worst case the onboarding shows once more; nothing else depends on it.
    }
  }

  /// Decide (once per signed-in user) whether this phone belongs to another
  /// account. Remembers the account when there is nothing to decide.
  Future<void> _checkSwitch(String userId) async {
    if (_switchChecking || _switchCheckedFor == userId) return;
    _switchChecking = true;
    var needed = false;
    try {
      needed = await CloudServices.accountSwitch.needsDecision(userId);
      if (!needed) await CloudServices.accountSwitch.remember(userId);
    } catch (_) {
      needed = false; // never block the app on a bookkeeping failure
    }
    _switchChecking = false;
    if (!mounted) return;
    setState(() {
      _switchCheckedFor = userId;
      _switchNeeded = needed;
    });
  }

  Widget _checking() => const AccessCheckingScreen();

  @override
  Widget build(BuildContext context) {
    _bind();
    if (!AccessConfig.subscriptionRequired) return widget.child;
    if (_onboardingDone == null) {
      return const Scaffold(backgroundColor: AppColors.background);
    }
    if (_onboardingDone == false) {
      return OnboardingScreen(onDone: _finishOnboarding);
    }

    final auth = CloudServices.auth;
    if (auth.isConfigured) {
      final user = auth.user;
      if (user == null) return const AuthFlowScreen();
      if (auth.recoveryPending) return const ResetPasswordScreen();
      if (!user.emailVerified) {
        return VerifyEmailScreen(
          email: user.email ?? '',
          onSignIn: (_) => auth.signOut(),
        );
      }
      if (_switchCheckedFor != user.id) {
        _checkSwitch(user.id);
        return _checking();
      }
      if (_switchNeeded) {
        return AccountSwitchScreen(
          onResolved: () => setState(() => _switchNeeded = false),
        );
      }
      // The store customer must be linked to THIS account before any
      // entitlement is trusted (never show the previous account's access).
      if (!CloudServices.binding.isReady(auth)) return _checking();
    }

    switch (CloudServices.premium.accessLevel) {
      case AccessLevel.checking:
        return _checking();
      case AccessLevel.full:
        return widget.child;
      case AccessLevel.locked:
        return const LockedScreen();
    }
  }
}
