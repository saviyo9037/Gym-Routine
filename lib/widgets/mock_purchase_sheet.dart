import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/mock_billing.dart';
import '../services/premium_service.dart';

/// Fake "Google Play" purchase sheet. Only ever shown when
/// [MockBilling.enabled] (debug build + MOCK_BILLING=true).
/// Returns null when dismissed (treated as a cancel).
Future<MockOutcome?> showMockPurchaseSheet(
  BuildContext context,
  PremiumOffer offer,
) {
  return showModalBottomSheet<MockOutcome>(
    context: context,
    backgroundColor: AppColors.cardSurface,
    isScrollControlled: true,
    builder: (_) => _MockPurchaseSheet(offer: offer),
  );
}

class _MockPurchaseSheet extends StatelessWidget {
  const _MockPurchaseSheet({required this.offer});
  final PremiumOffer offer;

  @override
  Widget build(BuildContext context) {
    final yearly = offer.period == BillingPeriod.yearly;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const ValueKey('mock_banner'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning),
              ),
              child: const Text(
                'TEST MODE, no real payment',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${yearly ? 'Yearly' : 'Monthly'} plan, ${offer.priceString}'
              '${offer.trial == null ? '' : ' after a ${offer.trial!.label} trial'}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMain, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick the result the store should return.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              key: const ValueKey('mock_success'),
              onPressed: () => Navigator.pop(context, MockOutcome.success),
              child: const Text('Success'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('mock_cancel'),
              onPressed: () => Navigator.pop(context, MockOutcome.cancel),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('mock_failed'),
              onPressed: () => Navigator.pop(context, MockOutcome.failed),
              child: const Text('Failed'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('mock_pending'),
              onPressed: () => Navigator.pop(context, MockOutcome.pending),
              child: const Text('Pending'),
            ),
          ],
        ),
      ),
    );
  }
}
