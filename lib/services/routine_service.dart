import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/db_helper.dart';
import '../models/routine.dart';
import '../models/routine_completion.dart';
import '../models/routine_today_item.dart';
import 'routine_notification_service.dart';
import 'alarm_service.dart';

class RoutineWeeklyStats {
  final int totalScheduled;
  final int completedCount;
  final int skippedCount;
  final double completionRate; // 0.0 to 1.0

  const RoutineWeeklyStats({
    required this.totalScheduled,
    required this.completedCount,
    required this.skippedCount,
    required this.completionRate,
  });
}

class RoutineService {
  static final RoutineService _instance = RoutineService._internal();
  factory RoutineService() => _instance;
  RoutineService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final RoutineNotificationService _notificationService = RoutineNotificationService();
  final AlarmService _alarmService = AlarmService();

  /// Retrieves all routines from the database sorted by start time
  Future<List<Routine>> getAllRoutines() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'routines',
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => Routine.fromMap(m)).toList();
  }

  /// Retrieves only enabled routines
  Future<List<Routine>> getEnabledRoutines() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'routines',
      where: 'is_enabled = 1',
      orderBy: 'start_time ASC',
    );
    return maps.map((m) => Routine.fromMap(m)).toList();
  }

  /// Retrieves a specific routine by ID
  Future<Routine?> getRoutineById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'routines',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Routine.fromMap(maps.first);
  }

  /// Inserts a new routine and schedules notifications and alarms if enabled
  Future<int> insertRoutine(Routine routine) async {
    final db = await _dbHelper.database;
    final id = await db.insert('routines', routine.toMap());
    final createdRoutine = routine.copyWith(id: id);

    // Schedule notifications and native AlarmManager alarms
    if (createdRoutine.isEnabled) {
      if (createdRoutine.isReminderEnabled) {
        await _notificationService.scheduleRoutineReminder(createdRoutine);
      }
      if (createdRoutine.isAlarmEnabled) {
        await _alarmService.scheduleRoutineAlarm(createdRoutine);
      }
    }
    return id;
  }

  /// Updates an existing routine, synchronizing notification and alarm schedules
  Future<int> updateRoutine(Routine routine) async {
    final db = await _dbHelper.database;
    final count = await db.update(
      'routines',
      routine.toMap(),
      where: 'id = ?',
      whereArgs: [routine.id],
    );

    if (routine.isEnabled) {
      if (routine.isReminderEnabled) {
        await _notificationService.scheduleRoutineReminder(routine);
      } else if (routine.id != null) {
        await _notificationService.cancelRoutineReminder(routine.id!);
      }

      if (routine.isAlarmEnabled) {
        await _alarmService.scheduleRoutineAlarm(routine);
      } else if (routine.id != null) {
        await _alarmService.cancelRoutineAlarm(routine.id!);
      }
    } else {
      if (routine.id != null) {
        await _notificationService.cancelRoutineReminder(routine.id!);
        await _alarmService.cancelRoutineAlarm(routine.id!);
      }
    }
    return count;
  }

  /// Updates time only for quick action
  Future<void> updateRoutineTime(int id, String startTime, String endTime) async {
    final existing = await getRoutineById(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      startTime: startTime,
      endTime: endTime,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await updateRoutine(updated);
  }

  /// Updates repeat days only for quick action
  Future<void> updateRoutineRepeatDays(int id, List<int> repeatDays) async {
    final existing = await getRoutineById(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      repeatDays: repeatDays,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await updateRoutine(updated);
  }

  /// Toggles enabled/disabled status
  Future<void> toggleRoutineEnabled(int id, bool isEnabled) async {
    final existing = await getRoutineById(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      isEnabled: isEnabled,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await updateRoutine(updated);
  }

  /// Deletes a routine permanently and removes related completions, alarms & notifications
  Future<int> deleteRoutine(int id) async {
    final db = await _dbHelper.database;
    await _notificationService.cancelRoutineReminder(id);
    await _alarmService.cancelRoutineAlarm(id);
    await db.delete(
      'routine_completions',
      where: 'routine_id = ?',
      whereArgs: [id],
    );
    return await db.delete(
      'routines',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Gets routine items scheduled for a specific date, paired with any recorded completion
  Future<List<RoutineTodayItem>> getRoutineItemsForDate(DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    // Fetch all enabled routines
    final allRoutines = await getEnabledRoutines();
    final dayRoutines = allRoutines.where((r) => r.appliesToDate(date)).toList();

    // Fetch completions recorded for this date
    final List<Map<String, dynamic>> completionMaps = await db.query(
      'routine_completions',
      where: 'date = ?',
      whereArgs: [dateStr],
    );

    final Map<int, RoutineCompletion> completionMap = {};
    for (final m in completionMaps) {
      final comp = RoutineCompletion.fromMap(m);
      completionMap[comp.routineId] = comp;
    }

    final items = dayRoutines.map((routine) {
      return RoutineTodayItem(
        routine: routine,
        completion: routine.id != null ? completionMap[routine.id!] : null,
        date: date,
      );
    }).toList();

    // Sort chronologically by start time
    items.sort((a, b) => a.routine.startTime.compareTo(b.routine.startTime));
    return items;
  }

  /// Convenient helper for today's routine items
  Future<List<RoutineTodayItem>> getTodayRoutineItems() async {
    return await getRoutineItemsForDate(DateTime.now());
  }

  /// Returns the currently active item, or the next upcoming item today
  Future<RoutineTodayItem?> getNextUpcomingRoutine([DateTime? referenceTime]) async {
    final now = referenceTime ?? DateTime.now();
    final todayItems = await getTodayRoutineItems();

    if (todayItems.isEmpty) return null;

    // 1. Look for currently In Progress item
    for (final item in todayItems) {
      if (item.isInProgress) return item;
    }

    // 2. Look for upcoming item whose start time is in the future and not completed/skipped
    for (final item in todayItems) {
      if (item.isUpcoming && item.startDateTime.isAfter(now)) {
        return item;
      }
    }

    // 3. Fallback: look for any item not completed/skipped
    for (final item in todayItems) {
      if (!item.isCompleted && !item.isSkipped) {
        return item;
      }
    }

    // All completed or skipped for today
    return null;
  }

  /// Returns the next upcoming meal / snack routine
  Future<RoutineTodayItem?> getNextUpcomingMeal([DateTime? referenceTime]) async {
    final todayItems = await getTodayRoutineItems();
    final mealItems = todayItems.where((i) => i.routine.isFoodCategory).toList();
    if (mealItems.isEmpty) return null;

    final now = referenceTime ?? DateTime.now();
    for (final item in mealItems) {
      if (item.isInProgress) return item;
    }
    for (final item in mealItems) {
      if (item.isUpcoming && item.startDateTime.isAfter(now)) {
        return item;
      }
    }
    for (final item in mealItems) {
      if (!item.isCompleted && !item.isSkipped) {
        return item;
      }
    }
    return mealItems.first;
  }

  /// Calculates suggested dinner reminder time based on configured gym workout end time
  Future<String> getSuggestedDinnerTime() async {
    final all = await getAllRoutines();
    final gym = all.firstWhere(
      (r) => r.isGymCategory,
      orElse: () => Routine(
        title: 'Gym',
        category: 'Gym',
        startTime: '19:00',
        endTime: '20:30',
        repeatDays: [1, 2, 3, 4, 5, 6],
      ),
    );

    // Add 15 minutes to gym end time
    final parts = gym.endTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 20;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 30;

    var dinnerMinute = minute + 15;
    var dinnerHour = hour;
    if (dinnerMinute >= 60) {
      dinnerHour = (dinnerHour + (dinnerMinute ~/ 60)) % 24;
      dinnerMinute %= 60;
    }

    return '${dinnerHour.toString().padLeft(2, '0')}:${dinnerMinute.toString().padLeft(2, '0')}';
  }

  /// Reschedules all enabled alarms across the system
  Future<void> rescheduleAllRoutines() async {
    final routines = await getEnabledRoutines();
    for (final r in routines) {
      if (r.isAlarmEnabled) {
        await _alarmService.scheduleRoutineAlarm(r);
      }
      if (r.isReminderEnabled) {
        await _notificationService.scheduleRoutineReminder(r);
      }
    }
  }

  /// Marks a routine as completed or skipped on a given date (upsert)
  Future<void> setRoutineCompletion({
    required int routineId,
    required DateTime date,
    required String status, // 'completed' | 'skipped'
    String? notes,
  }) async {
    final db = await _dbHelper.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final nowIso = DateTime.now().toIso8601String();

    await db.insert(
      'routine_completions',
      {
        'routine_id': routineId,
        'date': dateStr,
        'status': status.toLowerCase(),
        'notes': notes,
        'completed_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears/unsets completion status for an activity on a given date
  Future<void> removeRoutineCompletion({
    required int routineId,
    required DateTime date,
  }) async {
    final db = await _dbHelper.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    await db.delete(
      'routine_completions',
      where: 'routine_id = ? AND date = ?',
      whereArgs: [routineId, dateStr],
    );
  }

  /// Retrieves completion history for a specific routine (reverse chronological)
  Future<List<RoutineCompletion>> getRoutineCompletionHistory(int routineId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'routine_completions',
      where: 'routine_id = ?',
      whereArgs: [routineId],
      orderBy: 'date DESC, completed_at DESC',
      limit: 30,
    );
    return maps.map((m) => RoutineCompletion.fromMap(m)).toList();
  }

  /// Calculates weekly routine performance across Monday through Sunday
  Future<RoutineWeeklyStats> getWeeklyRoutineStats(DateTime anchorDate) async {
    final db = await _dbHelper.database;

    // Calculate Monday of the anchor week
    final monday = anchorDate.subtract(Duration(days: anchorDate.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final startStr = DateFormat('yyyy-MM-dd').format(monday);
    final endStr = DateFormat('yyyy-MM-dd').format(sunday);

    final allRoutines = await getEnabledRoutines();
    int totalScheduled = 0;

    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      totalScheduled += allRoutines.where((r) => r.appliesToDate(day)).length;
    }

    final List<Map<String, dynamic>> completions = await db.rawQuery('''
      SELECT status, COUNT(*) as count 
      FROM routine_completions
      WHERE date >= ? AND date <= ?
      GROUP BY status
    ''', [startStr, endStr]);

    int completed = 0;
    int skipped = 0;

    for (final row in completions) {
      final status = (row['status'] as String? ?? '').toLowerCase();
      final count = row['count'] as int? ?? 0;
      if (status == 'completed') {
        completed += count;
      } else if (status == 'skipped') {
        skipped += count;
      }
    }

    final rate = totalScheduled > 0 ? (completed / totalScheduled).clamp(0.0, 1.0) : 0.0;

    return RoutineWeeklyStats(
      totalScheduled: totalScheduled,
      completedCount: completed,
      skippedCount: skipped,
      completionRate: rate,
    );
  }
}
