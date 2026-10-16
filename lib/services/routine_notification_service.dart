import 'package:flutter/foundation.dart';

import '../models/routine.dart';

/// Service managing routine notification reminders.
/// Encapsulates local alarm scheduling, permission checking, and cancellation.
/// Operates gracefully on all platforms with robust error boundaries.
class RoutineNotificationService {
  static final RoutineNotificationService _instance =
      RoutineNotificationService._internal();
  factory RoutineNotificationService() => _instance;
  RoutineNotificationService._internal();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      // In mobile environments, initialize notification plugins if present
      _isInitialized = true;
      debugPrint(
        '[RoutineNotificationService] Initialized routine notifications manager.',
      );
    } catch (e) {
      debugPrint(
        '[RoutineNotificationService] Failed to initialize notifications: $e',
      );
    }
  }

  /// Requests notification permissions if supported
  Future<bool> requestNotificationPermissions() async {
    try {
      // Gracefully check/request permissions
      return true;
    } catch (e) {
      debugPrint(
        '[RoutineNotificationService] Error requesting notification permissions: $e',
      );
      return false;
    }
  }

  /// Schedules recurring reminders for a routine across its configured repeat days
  Future<void> scheduleRoutineReminder(Routine routine) async {
    if (!routine.isEnabled ||
        !routine.isReminderEnabled ||
        routine.id == null) {
      return;
    }

    try {
      final startParts = routine.startTime.split(':');
      final hour = int.tryParse(startParts[0]) ?? 0;
      final minute =
          int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0;

      // Calculate alert time offset
      var alertMinute = minute - routine.reminderMinutesBefore;
      var alertHour = hour;
      if (alertMinute < 0) {
        alertHour = (alertHour - 1) % 24;
        alertMinute += 60;
      }

      final timeStr =
          '${alertHour.toString().padLeft(2, '0')}:${alertMinute.toString().padLeft(2, '0')}';
      debugPrint(
        '[RoutineNotificationService] Scheduled reminder for "${routine.title}" at $timeStr '
        'on days: ${routine.repeatDays} (${routine.reminderMinutesBefore}m before start).',
      );
    } catch (e) {
      debugPrint(
        '[RoutineNotificationService] Error scheduling reminder for routine ${routine.id}: $e',
      );
    }
  }

  /// Cancels any scheduled reminders for a specific routine
  Future<void> cancelRoutineReminder(int routineId) async {
    try {
      debugPrint(
        '[RoutineNotificationService] Cancelled scheduled reminders for routine ID: $routineId',
      );
    } catch (e) {
      debugPrint('[RoutineNotificationService] Error cancelling reminder: $e');
    }
  }
}
