import 'package:flutter/material.dart';

enum RoutineCategory {
  sleep('Sleep', Icons.bedtime_rounded, Color(0xFF6C5CE7)),
  study('Study', Icons.school_rounded, Color(0xFF0984E3)),
  gym('Gym', Icons.fitness_center_rounded, Color(0xFFFF8A00)),
  work('Work', Icons.work_rounded, Color(0xFF00CEC9)),
  meals('Meals', Icons.restaurant_rounded, Color(0xFFE17055)),
  walking('Walking', Icons.directions_walk_rounded, Color(0xFF00B894)),
  rest('Rest', Icons.self_improvement_rounded, Color(0xFFB388FF)),
  reading('Reading', Icons.menu_book_rounded, Color(0xFFFDCB6E)),
  personal('Personal', Icons.person_rounded, Color(0xFFE84393)),
  custom('Custom', Icons.stars_rounded, Color(0xFFFF8A00));

  final String label;
  final IconData icon;
  final Color defaultColor;

  const RoutineCategory(this.label, this.icon, this.defaultColor);

  static RoutineCategory fromString(String val) {
    return RoutineCategory.values.firstWhere(
      (c) => c.label.toLowerCase() == val.trim().toLowerCase(),
      orElse: () => RoutineCategory.custom,
    );
  }
}

class Routine {
  final int? id;
  final String title;
  final String category;
  final String startTime; // 'HH:mm' 24-hr format (e.g. '07:30')
  final String endTime;   // 'HH:mm' 24-hr format (e.g. '08:30' or '06:30' for overnight)
  final List<int> repeatDays; // 1 = Monday, 2 = Tuesday, ... 7 = Sunday
  final String? notes;
  final String? foodDetails; // Optional food details for meals: rice, lentils, eggs, banana, etc.
  final bool isReminderEnabled;
  final int reminderMinutesBefore;
  final String alarmType; // 'alarm' (audible ringing screen) | 'notification' | 'none'
  final bool isAlarmEnabled;
  final String soundName; // e.g. 'Digital Beep', 'Energetic Pulse', 'Sunrise Bell'
  final bool isVibrationEnabled;
  final int snoozeMinutes; // default 10 minutes
  final bool isEnabled;
  final String? colorHex;
  final String createdAt;
  final String updatedAt;

  Routine({
    this.id,
    required this.title,
    required this.category,
    required this.startTime,
    required this.endTime,
    required this.repeatDays,
    this.notes,
    this.foodDetails,
    this.isReminderEnabled = true,
    this.reminderMinutesBefore = 10,
    this.alarmType = 'notification',
    this.isAlarmEnabled = true,
    this.soundName = 'Digital Beep',
    this.isVibrationEnabled = true,
    this.snoozeMinutes = 10,
    this.isEnabled = true,
    this.colorHex,
    String? createdAt,
    String? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  RoutineCategory get categoryEnum => RoutineCategory.fromString(category);

  IconData get icon => categoryEnum.icon;

  bool get isFoodCategory => categoryEnum == RoutineCategory.meals;
  bool get isGymCategory => categoryEnum == RoutineCategory.gym;
  bool get isSleepCategory => categoryEnum == RoutineCategory.sleep;

  bool get isAudibleAlarm => alarmType == 'alarm' && isAlarmEnabled;
  bool get isNotificationOnly => alarmType == 'notification' && isReminderEnabled;

  Color get color {
    if (colorHex != null && colorHex!.isNotEmpty) {
      try {
        final hex = colorHex!.replaceAll('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    return categoryEnum.defaultColor;
  }

  /// Whether the routine wraps around midnight (e.g. 22:30 -> 06:30)
  bool get isOvernight {
    final startMinutes = _parseMinutes(startTime);
    final endMinutes = _parseMinutes(endTime);
    return endMinutes <= startMinutes;
  }

  /// Total duration of the routine in minutes, accurately computing cross-midnight spans
  int get durationMinutes {
    final startMinutes = _parseMinutes(startTime);
    final endMinutes = _parseMinutes(endTime);
    if (endMinutes > startMinutes) {
      return endMinutes - startMinutes;
    } else {
      // Crosses midnight: minutes remaining today + minutes into next morning
      return (24 * 60 - startMinutes) + endMinutes;
    }
  }

  /// Formatted duration string, e.g. "1h 30m" or "45m"
  String get formattedDuration {
    final mins = durationMinutes;
    final hours = mins ~/ 60;
    final remainingMins = mins % 60;
    if (hours > 0 && remainingMins > 0) {
      return '${hours}h ${remainingMins}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '${remainingMins}m';
    }
  }

  /// Formatted time range e.g. "07:30 – 08:30"
  String get formattedTimeRange {
    return '$startTime – $endTime';
  }

  /// Human-readable repeat days string (e.g. "Every Day", "Mon, Wed, Fri", "Weekdays", "Weekends")
  String get formattedRepeatDays {
    if (repeatDays.isEmpty) return 'Does not repeat';
    if (repeatDays.length == 7) return 'Every Day';
    final sorted = List<int>.from(repeatDays)..sort();
    if (sorted.length == 5 &&
        sorted[0] == 1 &&
        sorted[1] == 2 &&
        sorted[2] == 3 &&
        sorted[3] == 4 &&
        sorted[4] == 5) {
      return 'Weekdays (Mon–Fri)';
    }
    if (sorted.length == 2 && sorted[0] == 6 && sorted[1] == 7) {
      return 'Weekends (Sat–Sun)';
    }
    const dayNames = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    return sorted.map((d) => dayNames[d] ?? '').where((s) => s.isNotEmpty).join(', ');
  }

  /// Checks if this routine is scheduled to run on a given DateTime
  bool appliesToDate(DateTime date) {
    if (!isEnabled) return false;
    return repeatDays.contains(date.weekday);
  }

  /// Checks if this routine overlaps with another routine on any shared day
  bool overlapsWith(Routine other) {
    if (id != null && other.id != null && id == other.id) return false;
    final commonDays = repeatDays.where((d) => other.repeatDays.contains(d));
    if (commonDays.isEmpty) return false;

    final startA = _parseMinutes(startTime);
    final endA = isOvernight ? startA + durationMinutes : _parseMinutes(endTime);
    final startB = _parseMinutes(other.startTime);
    final endB = other.isOvernight ? startB + other.durationMinutes : _parseMinutes(other.endTime);

    return (startA < endB) && (startB < endA);
  }

  /// Parses 'HH:mm' into minutes from 00:00
  static int _parseMinutes(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      final hours = int.parse(parts[0]);
      final mins = int.parse(parts[1]);
      return hours * 60 + mins;
    } catch (_) {
      return 0;
    }
  }

  Routine copyWith({
    int? id,
    String? title,
    String? category,
    String? startTime,
    String? endTime,
    List<int>? repeatDays,
    String? notes,
    String? foodDetails,
    bool? isReminderEnabled,
    int? reminderMinutesBefore,
    String? alarmType,
    bool? isAlarmEnabled,
    String? soundName,
    bool? isVibrationEnabled,
    int? snoozeMinutes,
    bool? isEnabled,
    String? colorHex,
    String? createdAt,
    String? updatedAt,
  }) {
    return Routine(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      repeatDays: repeatDays ?? List<int>.from(this.repeatDays),
      notes: notes ?? this.notes,
      foodDetails: foodDetails ?? this.foodDetails,
      isReminderEnabled: isReminderEnabled ?? this.isReminderEnabled,
      reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
      alarmType: alarmType ?? this.alarmType,
      isAlarmEnabled: isAlarmEnabled ?? this.isAlarmEnabled,
      soundName: soundName ?? this.soundName,
      isVibrationEnabled: isVibrationEnabled ?? this.isVibrationEnabled,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'category': category,
      'start_time': startTime,
      'end_time': endTime,
      'repeat_days': repeatDays.join(','),
      'notes': notes,
      'food_details': foodDetails,
      'is_reminder_enabled': isReminderEnabled ? 1 : 0,
      'reminder_minutes_before': reminderMinutesBefore,
      'alarm_type': alarmType,
      'is_alarm_enabled': isAlarmEnabled ? 1 : 0,
      'sound_name': soundName,
      'is_vibration_enabled': isVibrationEnabled ? 1 : 0,
      'snooze_minutes': snoozeMinutes,
      'is_enabled': isEnabled ? 1 : 0,
      'color_hex': colorHex,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Routine.fromMap(Map<String, dynamic> map) {
    final repeatDaysStr = (map['repeat_days'] as String? ?? '').trim();
    List<int> days = [];
    if (repeatDaysStr.isNotEmpty) {
      days = repeatDaysStr
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
    }
    if (days.isEmpty) {
      days = [1, 2, 3, 4, 5, 6, 7]; // Default to every day if empty
    }

    return Routine(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      category: map['category'] as String? ?? 'Custom',
      startTime: map['start_time'] as String? ?? '08:00',
      endTime: map['end_time'] as String? ?? '09:00',
      repeatDays: days,
      notes: map['notes'] as String?,
      foodDetails: map['food_details'] as String?,
      isReminderEnabled: (map['is_reminder_enabled'] as int? ?? 1) == 1,
      reminderMinutesBefore: map['reminder_minutes_before'] as int? ?? 10,
      alarmType: map['alarm_type'] as String? ?? 'notification',
      isAlarmEnabled: (map['is_alarm_enabled'] as int? ?? 1) == 1,
      soundName: map['sound_name'] as String? ?? 'Digital Beep',
      isVibrationEnabled: (map['is_vibration_enabled'] as int? ?? 1) == 1,
      snoozeMinutes: map['snooze_minutes'] as int? ?? 10,
      isEnabled: (map['is_enabled'] as int? ?? 1) == 1,
      colorHex: map['color_hex'] as String?,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}
