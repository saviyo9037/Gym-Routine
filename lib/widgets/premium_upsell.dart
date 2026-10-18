import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../screens/paywall_screen.dart';
import '../services/cloud_services.dart';
import '../services/premium_service.dart';

/// Entry points that decide, through [PremiumService] only, whether a
/// premium action may proceed or the paywall is shown instead.
class PremiumGate {
  static Future<bool> ensure(
    BuildContext context,
    PremiumFeature feature, {
    String? reason,
  }) async {
    if (CloudServices.premium.canUse(feature)) return true;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PaywallScreen(reason: reason)),
    );
    return CloudServices.premium.canUse(feature);
  }

  /// Free users may keep [PremiumService.freePlanLimit] plans. Existing plans
  /// are never removed; only creating/duplicating beyond the limit is gated.
  static Future<bool> ensureCanCreatePlan(
    BuildContext context,
    int existingPlans,
  ) async {
    if (CloudServices.premium.canCreatePlan(existingPlans)) return true;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaywallScreen(
          reason:
              'Free accounts can keep ${PremiumService.freePlanLimit} training '
              'plans. Your existing plans stay exactly as they are. Premium '
              'lets you create as many as you like.',
        ),
      ),
    );
    return CloudServices.premium.canCreatePlan(existingPlans);
  }
}

/// Inline card shown in place of a premium-only screen section.
class PremiumUpsellCard extends StatelessWidget {
  const PremiumUpsellCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              color: AppColors.primary,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
              child: const Text('See Premium'),
            ),
          ],
        ),
      ),
    );
  }
}
