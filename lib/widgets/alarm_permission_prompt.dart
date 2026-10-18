import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/alarm_service.dart';

/// Asks for the permissions a routine alarm needs **at the moment the user
/// creates one**, explains why, and offers a button to the matching system
/// settings page. Never blocks saving and never promises delivery.
class AlarmPermissionPrompt {
  static bool _askedNotifications = false;
  static bool _askedFullScreen = false;

  /// Visible for tests.
  static void resetSessionFlags() {
    _askedNotifications = false;
    _askedFullScreen = false;
  }

  static Future<void> ensureFor(
    BuildContext context, {
    required bool wantsAudibleAlarm,
    AlarmService? service,
  }) async {
    final alarms = service ?? AlarmService();
    final status = await alarms.checkPermissions();
    if (!context.mounted) return;

    if (!status.notificationsEnabled && !_askedNotifications) {
      _askedNotifications = true;
      final go = await _ask(
        context,
        title: 'Allow notifications?',
        body:
            'RepTrack needs notification permission to show this reminder. '
            'Without it, Android will hide the reminder.',
        action: 'Allow',
      );
      if (go == true) {
        await alarms.requestNotificationPermission();
        // If the system dialog cannot be shown (permission permanently
        // denied), the settings page is the only way left.
        final after = await alarms.checkPermissions();
        if (!after.notificationsEnabled) {
          await alarms.openNotificationSettings();
        }
      }
      if (!context.mounted) return;
    }

    if (wantsAudibleAlarm &&
        !status.canUseFullScreenIntent &&
        !_askedFullScreen) {
      _askedFullScreen = true;
      final go = await _ask(
        context,
        title: 'Show alarms over the lock screen?',
        body:
            'To wake the screen when an alarm rings, Android needs the '
            '"full-screen notifications" permission for RepTrack. '
            'Otherwise the alarm only appears as a notification.',
        action: 'Open settings',
      );
      if (go == true) await alarms.openFullScreenIntentSettings();
    }
  }

  static Future<bool?> _ask(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
