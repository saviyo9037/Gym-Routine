import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/plan_change_log.dart';

class ChangeLogDialog extends StatelessWidget {
  final List<PlanChangeLog> logs;

  const ChangeLogDialog({super.key, required this.logs});

  static Future<void> show(BuildContext context, List<PlanChangeLog> logs) {
    return showDialog(
      context: context,
      builder: (_) => ChangeLogDialog(logs: logs),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'TRAINER REVISION HISTORY',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No trainer modifications recorded yet for this plan.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppColors.border, height: 16),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    DateTime? dt;
                    try {
                      dt = DateTime.parse(log.changedAt);
                    } catch (_) {}
                    final timeStr = dt != null
                        ? DateFormat('MMM d, hh:mm a').format(dt)
                        : log.changedAt;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                log.reason,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          log.changeDescription,
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
