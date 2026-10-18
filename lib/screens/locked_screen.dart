import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/cloud_services.dart';
import 'not_configured_screen.dart';
import 'paywall_screen.dart';

/// The only screen a user without an active subscription/trial can reach
/// (subscription-required model). It is the paywall plus the things that must
/// stay available: restore, manage subscription, legal links, export of the
/// existing local data and account deletion. Nothing is deleted or changed.
///
/// The subscription belongs to the account, so the paywall (and with it any
/// purchase) is only offered when accounts exist in this build; otherwise the
/// "not configured" explanation is shown (with the same always-available
/// options).
class LockedScreen extends StatelessWidget {
  const LockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!CloudServices.auth.isConfigured) return const NotConfiguredScreen();
    return const PaywallScreen(locked: true);
  }
}

/// Shown on a cold start while the entitlement is being determined, so a
/// subscriber never sees a flash of the paywall.
class AccessCheckingScreen extends StatelessWidget {
  const AccessCheckingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Checking your subscription...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
