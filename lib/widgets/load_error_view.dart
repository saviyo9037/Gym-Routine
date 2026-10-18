import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Shown when a screen could not load its data: plain message + Retry, never
/// an endless spinner and never a raw exception text.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({
    super.key,
    required this.onRetry,
    this.message = 'Something went wrong while loading. Your data is safe.',
  });

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.warning,
              size: 44,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: Colors.black),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
