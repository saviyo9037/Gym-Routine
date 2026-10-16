import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/routine.dart';

class AlarmPermissionStatus {
  final bool canScheduleExactAlarms;
  final bool notificationsEnabled;
  final bool isBatteryOptimizationIgnored;
  final bool isDndAccessGranted;

  const AlarmPermissionStatus({
    required this.canScheduleExactAlarms,
    required this.notificationsEnabled,
    required this.isBatteryOptimizationIgnored,
    required this.isDndAccessGranted,
  });

  bool get isFullyConfigured =>
      canScheduleExactAlarms &&
      notificationsEnabled &&
      isBatteryOptimizationIgnored;
}

class AlarmService {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;
  AlarmService._internal();

  static const MethodChannel _channel = MethodChannel('com.reptrack.app/alarm');
  AudioPlayer? _fallbackPlayer;

  /// Schedules a real reliable Android Alarm using AlarmManager.setAlarmClock
  Future<bool> scheduleRoutineAlarm(Routine routine) async {
    if (!routine.isEnabled || !routine.isAlarmEnabled || routine.id == null) {
      if (routine.id != null) {
        await cancelRoutineAlarm(routine.id!);
      }
      return false;
    }

    try {
      final now = DateTime.now();
      final startParts = routine.startTime.split(':');
      final hour = int.tryParse(startParts[0]) ?? 0;
      final minute =
          int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0;

      // Find next occurrence matching routine's repeat days
      DateTime targetDate = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // If time has already passed today, check tomorrow onwards
      if (targetDate.isBefore(now)) {
        targetDate = targetDate.add(const Duration(days: 1));
      }

      // Loop up to 7 days to find the next active repeat day
      int attempts = 0;
      while (!routine.repeatDays.contains(targetDate.weekday) && attempts < 8) {
        targetDate = targetDate.add(const Duration(days: 1));
        attempts++;
      }

      final triggerEpochMs = targetDate.millisecondsSinceEpoch;

      final success = await _channel.invokeMethod<bool>('scheduleAlarm', {
        'routineId': routine.id,
        'title': routine.title,
        'category': routine.category,
        'time': routine.startTime,
        'triggerEpochMs': triggerEpochMs,
        'isAudible': routine.alarmType == 'alarm',
        'vibration': routine.isVibrationEnabled,
        'soundName': routine.soundName,
      });

      debugPrint(
        '[AlarmService] Scheduled ${routine.alarmType} for "${routine.title}" at $targetDate (epoch $triggerEpochMs). Result: $success',
      );
      return success ?? true;
    } catch (e) {
      debugPrint(
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
      debugPrint('[AlarmService] Cancelled alarm for routine $routineId');
      return res ?? true;
    } catch (e) {
      debugPrint('[AlarmService] Error cancelling alarm $routineId: $e');
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
      debugPrint(
        '[AlarmService] Test alarm launched with delay $delaySeconds s',
      );
      return res ?? true;
    } catch (e) {
      debugPrint('[AlarmService] Error triggering test alarm: $e');
      return false;
    }
  }

  /// Stops ongoing alarm audio and vibration
  Future<void> stopAlarm() async {
    try {
      await _channel.invokeMethod('stopAlarm');
      await _stopFallbackAudio();
      debugPrint('[AlarmService] Alarm audio stopped');
    } catch (e) {
      debugPrint('[AlarmService] Error stopping alarm: $e');
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
      debugPrint(
        '[AlarmService] Snoozed routine $routineId for $snoozeMinutes minutes',
      );
    } catch (e) {
      debugPrint('[AlarmService] Error snoozing alarm: $e');
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
        );
      }
    } catch (e) {
      debugPrint('[AlarmService] Error checking permissions: $e');
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
      debugPrint('[AlarmService] Error requesting exact alarm permission: $e');
    }
  }

  /// Requests battery optimization exemption
  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (e) {
      debugPrint('[AlarmService] Error requesting battery exemption: $e');
    }
  }

  /// Opens Android Do Not Disturb / Notification Policy settings
  Future<void> openDndSettings() async {
    try {
      await _channel.invokeMethod('openDndSettings');
    } catch (e) {
      debugPrint('[AlarmService] Error opening DND settings: $e');
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
      debugPrint('[AlarmService] Error checking triggered alarm data: $e');
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
      debugPrint('[AlarmService] Fallback audio player error: $e');
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
