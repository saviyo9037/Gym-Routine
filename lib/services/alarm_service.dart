import '../core/dev_log.dart';

import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import '../core/clock.dart';
import '../core/next_occurrence.dart';
import '../models/routine.dart';

class AlarmPermissionStatus {
  final bool canScheduleExactAlarms;
  final bool notificationsEnabled;
  final bool isBatteryOptimizationIgnored;
  final bool isDndAccessGranted;
  final bool canUseFullScreenIntent;
  final String manufacturer;

  const AlarmPermissionStatus({
    required this.canScheduleExactAlarms,
    required this.notificationsEnabled,
    required this.isBatteryOptimizationIgnored,
    required this.isDndAccessGranted,
    this.canUseFullScreenIntent = true,
    this.manufacturer = '',
  });

  /// Everything an alarm needs. Battery exemption and DND access are
  /// recommended, never required.
  bool get isFullyConfigured =>
      canScheduleExactAlarms && notificationsEnabled && canUseFullScreenIntent;
}

/// One alarm the native side currently holds.
class ScheduledAlarmInfo {
  final int routineId;
  final String title;
  final DateTime? nextAlarm;
  final DateTime? nextReminder;

  const ScheduledAlarmInfo({
    required this.routineId,
    required this.title,
    this.nextAlarm,
    this.nextReminder,
  });
}

class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  static const MethodChannel _channel = MethodChannel('com.reptrack.app/alarm');
  AudioPlayer? _fallbackPlayer;

  /// Hands the routine to the native scheduler, which stores it, arms the next
  /// occurrence with AlarmManager.setAlarmClock and re-arms it after every
  /// firing, reboot, app update, clock or timezone change (so Flutter does not
  /// need to be running). Returns false when nothing was scheduled.
  Future<bool> scheduleRoutineAlarm(Routine routine) async {
    final wantsAlarm = routine.isAlarmEnabled && routine.alarmType != 'none';
    // A heads-up at exactly the start time would duplicate the alarm itself.
    final wantsReminder =
        routine.isReminderEnabled &&
        routine.alarmType != 'none' &&
        !(wantsAlarm && routine.reminderMinutesBefore <= 0);
    if (!routine.isEnabled ||
        routine.id == null ||
        routine.repeatDays.isEmpty ||
        (!wantsAlarm && !wantsReminder)) {
      if (routine.id != null) {
        await cancelRoutineAlarm(routine.id!);
      }
      return false;
    }

    try {
      final success = await _channel.invokeMethod<bool>('scheduleAlarm', {
        'routineId': routine.id,
        'title': routine.title,
        'category': routine.category,
        'time': routine.startTime,
        'repeatDays': routine.repeatDays,
        'alarmEnabled': wantsAlarm,
        'isAudible': routine.alarmType == 'alarm',
        'vibration': routine.isVibrationEnabled,
        'soundName': routine.soundName,
        'leadMinutes': routine.reminderMinutesBefore < 0
            ? 0
            : routine.reminderMinutesBefore,
        'reminderEnabled': wantsReminder,
      });

      final next = NextOccurrence.compute(
        AppClock.now(),
        routine.startTime,
        routine.repeatDays,
      );
      devLog(
        '[AlarmService] Scheduled "${routine.title}" (next $next). Result: $success',
      );
      return success ?? true;
    } catch (e) {
      devLog(
        '[AlarmService] Error scheduling alarm for routine ${routine.id}: $e',
      );
      return false;
    }
  }

  /// Cancels scheduled alarm for a given routine ID
  Future<bool> cancelRoutineAlarm(int routineId) async {
    try {
      final res = await _channel.invokeMethod<bool>('cancelAlarm', {
        'routineId': routineId,
      });
      devLog('[AlarmService] Cancelled alarm for routine $routineId');
      return res ?? true;
    } catch (e) {
      devLog('[AlarmService] Error cancelling alarm $routineId: $e');
      return false;
    }
  }

  /// Triggers a live test alarm with a short delay (e.g. 2-3 seconds)
  Future<bool> testAlarm({
    required String title,
    required String category,
    int delaySeconds = 2,
    bool isAudible = true,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('testAlarm', {
        'title': title,
        'category': category,
        'delaySeconds': delaySeconds,
        'isAudible': isAudible,
      });
      devLog('[AlarmService] Test alarm launched with delay $delaySeconds s');
      return res ?? true;
    } catch (e) {
      devLog('[AlarmService] Error triggering test alarm: $e');
      return false;
    }
  }

  /// Stops ongoing alarm audio and vibration
  Future<void> stopAlarm() async {
    try {
      await _channel.invokeMethod('stopAlarm');
      await _stopFallbackAudio();
      devLog('[AlarmService] Alarm audio stopped');
    } catch (e) {
      devLog('[AlarmService] Error stopping alarm: $e');
    }
  }

  /// Snoozes alarm for X minutes
  Future<void> snoozeAlarm(
    int routineId, {
    int snoozeMinutes = 10,
    String? title,
  }) async {
    try {
      await _channel.invokeMethod('snoozeAlarm', {
        'routineId': routineId,
        'snoozeMinutes': snoozeMinutes,
        'title': title ?? 'Routine Alarm',
      });
      await _stopFallbackAudio();
      devLog(
        '[AlarmService] Snoozed routine $routineId for $snoozeMinutes minutes',
      );
    } catch (e) {
      devLog('[AlarmService] Error snoozing alarm: $e');
    }
  }

  /// Checks current Android permissions (Exact Alarm, Notification, Battery Optimization, DND)
  Future<AlarmPermissionStatus> checkPermissions() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'checkPermissions',
      );
      if (map != null) {
        return AlarmPermissionStatus(
          canScheduleExactAlarms:
              map['canScheduleExactAlarms'] as bool? ?? true,
          notificationsEnabled: map['notificationsEnabled'] as bool? ?? true,
          isBatteryOptimizationIgnored:
              map['isBatteryOptimizationIgnored'] as bool? ?? false,
          isDndAccessGranted: map['isDndAccessGranted'] as bool? ?? false,
          canUseFullScreenIntent:
              map['canUseFullScreenIntent'] as bool? ?? true,
          manufacturer: map['manufacturer'] as String? ?? '',
        );
      }
    } catch (e) {
      devLog('[AlarmService] Error checking permissions: $e');
    }

    return const AlarmPermissionStatus(
      canScheduleExactAlarms: true,
      notificationsEnabled: true,
      isBatteryOptimizationIgnored: false,
      isDndAccessGranted: false,
    );
  }

  /// Requests exact alarm permission from Android settings
  Future<void> requestExactAlarmPermission() async {
    try {
      await _channel.invokeMethod('requestExactAlarmPermission');
    } catch (e) {
      devLog('[AlarmService] Error requesting exact alarm permission: $e');
    }
  }

  /// Requests battery optimization exemption
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      devLog('[AlarmService] Error requesting battery exemption: $e');
    }
  }

  /// Shows the Android 13+ notification permission prompt (no-op below 13).
  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (e) {
      devLog('[AlarmService] Error requesting notification permission: $e');
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      devLog('[AlarmService] Error opening notification settings: $e');
    }
  }

  Future<void> openFullScreenIntentSettings() async {
    try {
      await _channel.invokeMethod('openFullScreenIntentSettings');
    } catch (e) {
      devLog('[AlarmService] Error opening full-screen settings: $e');
    }
  }

  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      devLog('[AlarmService] Error opening app settings: $e');
    }
  }

  /// Alarms the native scheduler currently holds, with their next fire times.
  Future<List<ScheduledAlarmInfo>> getScheduledAlarms() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'getScheduledAlarms',
      );
      return [
        for (final e in raw ?? const [])
          ScheduledAlarmInfo(
            routineId: (e as Map)['routineId'] as int,
            title: e['title'] as String? ?? '',
            nextAlarm: e['nextAlarmEpochMs'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    e['nextAlarmEpochMs'] as int,
                  ),
            nextReminder: e['nextReminderEpochMs'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    e['nextReminderEpochMs'] as int,
                  ),
          ),
      ];
    } catch (e) {
      devLog('[AlarmService] Error reading scheduled alarms: $e');
      return const [];
    }
  }

  /// Asks the native side to re-arm everything it has stored.
  Future<void> rescheduleAllNative() async {
    try {
      await _channel.invokeMethod('rescheduleAll');
    } catch (e) {
      devLog('[AlarmService] Error rescheduling: $e');
    }
  }

  /// Opens Android Do Not Disturb / Notification Policy settings
  Future<void> openDndSettings() async {
    try {
      await _channel.invokeMethod('openDndSettings');
    } catch (e) {
      devLog('[AlarmService] Error opening DND settings: $e');
    }
  }

  /// Retrieves intent extras if the app was launched by a ringing alarm
  Future<Map<String, dynamic>?> getTriggeredAlarmData() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'getTriggeredAlarmData',
      );
      return map;
    } catch (e) {
      devLog('[AlarmService] Error checking triggered alarm data: $e');
      return null;
    }
  }

  /// Clears triggered alarm data once handled
  Future<void> clearTriggeredAlarmData() async {
    try {
      await _channel.invokeMethod('clearTriggeredAlarmData');
    } catch (_) {}
  }

  /// Plays alarm stream audio inside Flutter if needed
  Future<void> playAlarmAudioStream() async {
    try {
      _fallbackPlayer?.dispose();
      _fallbackPlayer = AudioPlayer();

      await _fallbackPlayer!.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
        ),
      );

      await _fallbackPlayer!.setReleaseMode(ReleaseMode.loop);
      // Play system alert sound or local synthesized beep
    } catch (e) {
      devLog('[AlarmService] Fallback audio player error: $e');
    }
  }

  Future<void> _stopFallbackAudio() async {
    try {
      await _fallbackPlayer?.stop();
      await _fallbackPlayer?.dispose();
      _fallbackPlayer = null;
    } catch (_) {}
  }
}
