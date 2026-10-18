import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/backup_service.dart';

/// Import flow for a parsed backup: shows a dry-run summary, then lets the
/// user choose MERGE (default: nothing is deleted, only newer data wins) or
/// REPLACE (destroys current data, needs a second explicit confirmation).
/// Nothing is written until the user confirms.
class BackupImportFlow {
  /// Returns true when data was imported.
  static Future<bool> run(
    BuildContext context,
    BackupFile file, {
    BackupService? service,
  }) async {
    final backup = service ?? BackupService();
    final plan = await backup.planMerge(file);
    if (!context.mounted) return false;

    final choice = await showDialog<_Choice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Import backup'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backup from ${file.exportedAt ?? 'an unknown date'}'
                '${file.appVersion != null ? ' (app ${file.appVersion})' : ''}.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              const Text(
                'Merge (recommended)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                plan.hasChanges
                    ? 'Adds ${plan.totalAdded} item(s) and updates '
                          '${plan.totalUpdated} older item(s). Nothing is '
                          'deleted; your newer data stays.'
                    : 'Nothing new to add: your data already contains this backup.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (plan.warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final w in plan.warnings.take(3))
                  Text(
                    '• $w',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Replace everything',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'Deletes the data on this phone and installs the backup.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _Choice.replace),
            child: const Text(
              'Replace…',
              style: TextStyle(color: AppColors.error),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _Choice.merge),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return false;

    if (choice == _Choice.replace) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: const Text('Replace all data?'),
          content: const Text(
            'Your current plans, workouts and routines on this phone will be '
            'deleted and replaced by the backup. This cannot be undone. '
            'Export a backup first if you are unsure.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Replace everything',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      );
      if (sure != true) return false;
      final r = await backup.applyReplace(file, confirmed: true);
      return r.ok;
    }

    final r = await backup.applyMerge(file, confirmed: true);
    return r.ok;
  }
}

enum _Choice { merge, replace }
