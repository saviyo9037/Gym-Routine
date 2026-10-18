import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../core/clock.dart';
import '../data/db_helper.dart';
import '../models/weekly_summary.dart';
import '../models/workout_plan.dart';
import '../models/workout_session.dart';
import 'database_service.dart';

/// Inclusive local date range expressed as yyyy-MM-dd keys.
class DateKeyRange {
  const DateKeyRange(this.start, this.end);
  final String start;
  final String end;
}

/// Aggregate numbers for a period. All values come from stored sessions.
class PeriodStats {
  const PeriodStats({
    this.workouts = 0,
    this.setsCompleted = 0,
    this.volumeKg = 0,
    this.durationSeconds = 0,
    this.cardioSeconds = 0,
    this.cardioKm = 0,
    this.trainingDays = 0,
  });

  /// Sessions with at least one completed set.
  final int workouts;
  final int setsCompleted;

  /// Strength volume only (cardio excluded).
  final double volumeKg;
  final int durationSeconds;
  final int cardioSeconds;
  final double cardioKm;

  /// Distinct dates with a performed workout.
  final int trainingDays;

  bool get isEmpty => workouts == 0;
}

/// One session's result for a single exercise.
class ExercisePoint {
  const ExercisePoint({
    required this.date,
    required this.bestWeightKg,
    required this.repsAtBestWeight,
    required this.estimatedOneRepMaxKg,
    required this.volumeKg,
    required this.sets,
  });

  final String date;
  final double bestWeightKg;
  final int repsAtBestWeight;

  /// Epley estimate from the best qualifying set (null when no set had 1-12
  /// reps with weight).
  final double? estimatedOneRepMaxKg;
  final double volumeKg;
  final int sets;
}

class ExerciseProgress {
  const ExerciseProgress({
    required this.exerciseId,
    required this.exerciseName,
    required this.isCardio,
    required this.points,
  });

  final int exerciseId;
  final String exerciseName;
  final bool isCardio;

  /// Oldest first.
  final List<ExercisePoint> points;

  bool get hasData => points.isNotEmpty;

  double get bestWeightKg =>
      points.fold(0.0, (m, p) => p.bestWeightKg > m ? p.bestWeightKg : m);

  double? get bestOneRepMaxKg {
    double? best;
    for (final p in points) {
      final e = p.estimatedOneRepMaxKg;
      if (e != null && (best == null || e > best)) best = e;
    }
    return best;
  }

  /// Last [n] sessions, newest first.
  List<ExercisePoint> lastSessions([int n = 5]) =>
      points.reversed.take(n).toList();

  /// Volume change of the latest session vs the one before (null if < 2).
  double? get volumeTrendKg => points.length < 2
      ? null
      : points.last.volumeKg - points[points.length - 2].volumeKg;
}

class ExerciseProgressEntry {
  const ExerciseProgressEntry(
    this.exerciseId,
    this.exerciseName,
    this.sessions,
  );
  final int exerciseId;
  final String exerciseName;
  final int sessions;
}

/// Single source of truth for history and statistics.
///
/// Rules (applied everywhere):
///  * "today" and all boundaries use [AppClock] (device-local time) and
///    calendar arithmetic (`DateTime(y, m, d + n)`), never `Duration(days:)`,
///    so DST changes cannot shift a date.
///  * Week start comes from the `week_starts_on` setting (monday|sunday).
///  * A session counts as a workout only if >= 1 set was completed.
///  * Rest days are never counted as completed workouts.
///  * Volume is strength only; cardio is reported as time/distance.
class StatsService {
  StatsService({DatabaseHelper? helper, DatabaseService? db})
    : _helper = helper ?? DatabaseHelper.instance,
      _db = db ?? DatabaseService();

  final DatabaseHelper _helper;
  final DatabaseService _db;

  static const weekStartSettingKey = 'week_starts_on';

  // ----------------------------------------------------------- week setting

  Future<bool> weekStartsOnSunday() async {
    final v = await _db.getSetting(weekStartSettingKey, defaultValue: 'monday');
    return v.toLowerCase() == 'sunday';
  }

  Future<void> setWeekStartsOnSunday(bool sunday) =>
      _db.setSetting(weekStartSettingKey, sunday ? 'sunday' : 'monday');

  // ------------------------------------------------------------ date helpers

  static String key(DateTime d) => AppClock.dateKey(d);

  static DateTime dayAt(DateTime anchor, int offsetDays) =>
      DateTime(anchor.year, anchor.month, anchor.day + offsetDays);

  /// First day of the week that contains [anchor].
  static DateTime weekStart(DateTime anchor, {required bool sundayStart}) =>
      AppClock.weekStart(anchor, weekStartsOnSunday: sundayStart);

  static DateKeyRange weekRange(DateTime anchor, {required bool sundayStart}) {
    final start = weekStart(anchor, sundayStart: sundayStart);
    return DateKeyRange(key(start), key(dayAt(start, 6)));
  }

  static DateKeyRange monthRange(DateTime anchor) => DateKeyRange(
    key(DateTime(anchor.year, anchor.month, 1)),
    // day 0 of next month = last day of this month (handles Dec -> Jan).
    key(DateTime(anchor.year, anchor.month + 1, 0)),
  );

  /// Last [days] calendar days **including today** (7 -> today-6 .. today).
  static DateKeyRange lastDays(DateTime today, int days) =>
      DateKeyRange(key(dayAt(today, -(days - 1))), key(dayAt(today, 0)));

  /// Maps a UI filter label to a range; null = no restriction.
  static DateKeyRange? rangeForFilter(
    String label,
    DateTime now, {
    required bool sundayStart,
  }) {
    switch (label) {
      case 'This Week':
        return weekRange(now, sundayStart: sundayStart);
      case 'Last 7 Days':
        return lastDays(now, 7);
      case 'This Month':
        final m = monthRange(now);
        return DateKeyRange(m.start, key(now));
      case 'Last 30 Days':
        return lastDays(now, 30);
      default:
        return null;
    }
  }

  /// Epley estimate: weight x (1 + reps / 30). Null for unreliable inputs.
  static double? epleyOneRepMax(double weightKg, int reps) {
    if (weightKg <= 0 || reps < 1 || reps > 12) return null;
    return reps == 1 ? weightKg : weightKg * (1 + reps / 30);
  }

  // ---------------------------------------------------------------- queries

  Future<List<WorkoutSession>> sessionsInRange(DateKeyRange? range) =>
      range == null
      ? _db.getAllSessions()
      : _db.getSessionsForDateRange(range.start, range.end);

  PeriodStats summarize(Iterable<WorkoutSession> sessions) {
    var workouts = 0;
    var sets = 0;
    var volume = 0.0;
    var duration = 0;
    var cardioSec = 0;
    var cardioKm = 0.0;
    final days = <String>{};
    for (final s in sessions) {
      if (!s.isEffective) continue;
      workouts++;
      sets += s.completedSetsCount;
      volume += s.totalVolumeKg;
      duration += s.durationSeconds;
      cardioSec += s.cardioSeconds;
      cardioKm += s.cardioKm;
      days.add(s.date);
    }
    return PeriodStats(
      workouts: workouts,
      setsCompleted: sets,
      volumeKg: volume,
      durationSeconds: duration,
      cardioSeconds: cardioSec,
      cardioKm: cardioKm,
      trainingDays: days.length,
    );
  }

  Future<PeriodStats> periodStats(DateKeyRange? range) async =>
      summarize(await sessionsInRange(range));

  /// True when no workout was ever recorded (first-time state).
  Future<bool> hasNoHistory() async {
    final db = await _helper.database;
    final n = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM workout_sessions s WHERE EXISTS '
        '(SELECT 1 FROM workout_sets w WHERE w.session_id = s.id AND w.is_completed = 1)',
      ),
    );
    return (n ?? 0) == 0;
  }

  // --------------------------------------------------------------- weekly

  Future<WeeklySummary> weeklySummary(DateTime anchor) async {
    final sundayStart = await weekStartsOnSunday();
    final start = weekStart(anchor, sundayStart: sundayStart);
    final end = dayAt(start, 6);
    final range = DateKeyRange(key(start), key(end));
    final todayKey = AppClock.todayKey();

    final sessions = await _db.getSessionsForDateRange(range.start, range.end);

    final days = <DayWorkoutSummary>[];
    var completedWorkouts = 0;
    var plannedWorkouts = 0;
    var restDays = 0;
    var volume = 0.0;
    var duration = 0;
    var sets = 0;
    var cardioSec = 0;
    var cardioKm = 0.0;
    final distinctExercises = <String>{};

    for (var i = 0; i < 7; i++) {
      final date = dayAt(start, i);
      final dayKey = key(date);
      final isToday = dayKey == todayKey;
      final plan = await _db.getEffectivePlanForDate(date);
      final daySessions = sessions.where((s) => s.date == dayKey).toList();
      final effective = daySessions.where((s) => s.isEffective).toList();

      DayStatus status;
      String? primary = plan?.primaryMuscleName;
      String? secondary = plan?.secondaryMuscleName;
      var plannedCount = plan?.exercises.length ?? 0;
      var completedCount = 0;

      if (effective.isNotEmpty) {
        completedWorkouts += effective.length;
        for (final s in effective) {
          duration += s.durationSeconds;
          volume += s.totalVolumeKg;
          sets += s.completedSetsCount;
          cardioSec += s.cardioSeconds;
          cardioKm += s.cardioKm;
          final names = s.completedExerciseNames;
          distinctExercises.addAll(names);
          completedCount += names.length;
        }
        primary = effective.first.primaryMuscle;
        secondary =
            effective.first.secondaryMuscle ?? plan?.secondaryMuscleName;
        final anyUnfinished = effective.any(
          (s) => s.completionStatus == 'Partially Completed',
        );
        final skippedPlanned =
            plannedCount > 0 && completedCount < plannedCount;
        status = (anyUnfinished || skippedPlanned)
            ? DayStatus.partiallyCompleted
            : DayStatus.completed;
      } else if (plan != null && plan.isRestDay) {
        status = DayStatus.restDay;
        restDays++;
      } else if (plan != null && plan.exercises.isNotEmpty) {
        plannedWorkouts++;
        status = dayKey.compareTo(todayKey) < 0
            ? DayStatus.missed
            : DayStatus.planned;
      } else {
        status = DayStatus.noPlan;
      }

      days.add(
        DayWorkoutSummary(
          date: date,
          dateStr: dayKey,
          dayName: DateFormat('E').format(date),
          status: status,
          primaryMuscle: primary,
          secondaryMuscle: secondary,
          plannedExerciseCount: plannedCount,
          completedExerciseCount: completedCount,
          plan: plan ?? WorkoutPlan(date: dayKey),
          sessions: daySessions,
          isToday: isToday,
        ),
      );
    }

    return WeeklySummary(
      startOfWeek: start,
      endOfWeek: end,
      days: days,
      workoutsCompleted: completedWorkouts,
      exercisesCompleted: distinctExercises.length,
      plannedWorkouts: plannedWorkouts,
      restDays: restDays,
      totalVolumeKg: volume,
      totalDurationSeconds: duration,
      setsCompleted: sets,
      cardioSeconds: cardioSec,
      cardioKm: cardioKm,
    );
  }

  /// `done / planned` for the home week strip: workouts actually performed vs
  /// workout days that were scheduled (performed or not). Rest days are not
  /// part of the denominator.
  ({int done, int scheduled}) weekProgress(WeeklySummary w) {
    var done = 0;
    var scheduled = 0;
    for (final d in w.days) {
      switch (d.status) {
        case DayStatus.completed:
        case DayStatus.partiallyCompleted:
          done++;
          scheduled++;
        case DayStatus.planned:
        case DayStatus.missed:
          scheduled++;
        case DayStatus.restDay:
        case DayStatus.noPlan:
          break;
      }
    }
    return (done: done, scheduled: scheduled);
  }

  // --------------------------------------------------------------- streak

  /// Consecutive days with a performed workout, counted back from today.
  /// Today without a workout yet does not break the streak; days explicitly
  /// planned as rest days neither add to nor break it.
  Future<int> currentStreak() async {
    final db = await _helper.database;
    final sessionRows = await db.rawQuery(
      'SELECT DISTINCT s.date AS d FROM workout_sessions s WHERE EXISTS '
      '(SELECT 1 FROM workout_sets w WHERE w.session_id = s.id AND w.is_completed = 1)',
    );
    final trained = {for (final r in sessionRows) r['d'] as String};
    if (trained.isEmpty) return 0;
    final restRows = await db.query(
      'workout_plans',
      columns: ['date'],
      where: 'is_rest_day = 1',
    );
    final rest = {for (final r in restRows) r['date'] as String};

    final today = AppClock.now();
    var streak = 0;
    for (var i = 0; i < 3660; i++) {
      final k = key(dayAt(today, -i));
      if (trained.contains(k)) {
        streak++;
      } else if (i == 0) {
        continue; // today not trained yet
      } else if (rest.contains(k)) {
        continue;
      } else {
        break;
      }
    }
    return streak;
  }

  // --------------------------------------------------------- exercise stats

  Future<List<ExerciseProgressEntry>> exercisesWithHistory() async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      'SELECT w.exercise_id AS id, MAX(w.exercise_name) AS name, '
      'COUNT(DISTINCT w.session_id) AS n FROM workout_sets w '
      'WHERE w.is_completed = 1 GROUP BY w.exercise_id ORDER BY name ASC',
    );
    return [
      for (final r in rows)
        ExerciseProgressEntry(
          r['id'] as int,
          r['name'] as String? ?? 'Exercise',
          r['n'] as int? ?? 0,
        ),
    ];
  }

  Future<ExerciseProgress> exerciseProgress(int exerciseId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      'SELECT w.*, s.date AS session_date, s.id AS sid FROM workout_sets w '
      'JOIN workout_sessions s ON s.id = w.session_id '
      'WHERE w.exercise_id = ? AND w.is_completed = 1 '
      'ORDER BY s.date ASC, s.id ASC, w.set_number ASC',
      [exerciseId],
    );
    var name = 'Exercise';
    var cardio = false;
    final byKey = <String, List<WorkoutSetRecord>>{};
    final order = <String>[];
    final dateOf = <String, String>{};
    for (final r in rows) {
      final set = WorkoutSetRecord.fromMap(r);
      name = set.exerciseName;
      cardio = set.isCardio;
      final k = '${r['sid']}';
      if (!byKey.containsKey(k)) {
        order.add(k);
        dateOf[k] = r['session_date'] as String;
      }
      byKey.putIfAbsent(k, () => []).add(set);
    }

    final points = <ExercisePoint>[];
    for (final k in order) {
      final sets = byKey[k]!;
      var bestW = 0.0;
      var repsAtBest = 0;
      double? best1rm;
      var volume = 0.0;
      for (final s in sets) {
        if (s.isCardio) continue;
        volume += s.weightKg * s.reps;
        if (s.weightKg > bestW ||
            (s.weightKg == bestW && s.reps > repsAtBest)) {
          bestW = s.weightKg;
          repsAtBest = s.reps;
        }
        final e = epleyOneRepMax(s.weightKg, s.reps);
        if (e != null && (best1rm == null || e > best1rm)) best1rm = e;
      }
      points.add(
        ExercisePoint(
          date: dateOf[k]!,
          bestWeightKg: bestW,
          repsAtBestWeight: repsAtBest,
          estimatedOneRepMaxKg: best1rm,
          volumeKg: volume,
          sets: sets.length,
        ),
      );
    }
    return ExerciseProgress(
      exerciseId: exerciseId,
      exerciseName: name,
      isCardio: cardio,
      points: points,
    );
  }

  // ---------------------------------------------------------------- muscles

  static const muscleCategories = [
    'Chest',
    'Back',
    'Shoulders',
    'Biceps',
    'Triceps',
    'Legs',
    'Abs',
    'Full Body',
  ];

  static Set<String> _categoriesFor(String muscle) {
    final lower = muscle.toLowerCase();
    final out = <String>{};
    if (lower.contains('chest')) out.add('Chest');
    if (lower.contains('back') ||
        lower.contains('lat') ||
        lower.contains('trap')) {
      out.add('Back');
    }
    if (lower.contains('shoulder') || lower.contains('delt')) {
      out.add('Shoulders');
    }
    if (lower.contains('bicep')) out.add('Biceps');
    if (lower.contains('tricep')) out.add('Triceps');
    if (lower.contains('leg') ||
        lower.contains('quad') ||
        lower.contains('hamstring') ||
        lower.contains('glute') ||
        lower.contains('calv') ||
        lower.contains('calf')) {
      out.add('Legs');
    }
    if (lower.contains('abs') ||
        lower.contains('core') ||
        lower.contains('abdom')) {
      out.add('Abs');
    }
    if (lower.contains('full body') || lower.contains('compound')) {
      out.add('Full Body');
    }
    return out;
  }

  /// Workout count per muscle category over [range] (null = all time).
  Future<Map<String, int>> muscleFrequency(DateKeyRange? range) async {
    final sessions = (await sessionsInRange(range)).where((s) => s.isEffective);
    final counts = {for (final c in muscleCategories) c: 0};
    for (final s in sessions) {
      final cats = <String>{
        ..._categoriesFor(s.primaryMuscle),
        if (s.secondaryMuscle != null) ..._categoriesFor(s.secondaryMuscle!),
      };
      if (cats.isEmpty) {
        counts[s.primaryMuscle] = (counts[s.primaryMuscle] ?? 0) + 1;
      } else {
        for (final c in cats) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  /// Performed sessions that trained [category] ('All' = every session).
  Future<List<WorkoutSession>> sessionsForMuscle(
    String category,
    DateKeyRange? range,
  ) async {
    final all = (await sessionsInRange(range)).where((s) => s.isEffective);
    if (category.toLowerCase() == 'all') return all.toList();
    final target = category.toLowerCase();
    return all.where((s) {
      final cats = <String>{
        ..._categoriesFor(s.primaryMuscle),
        if (s.secondaryMuscle != null) ..._categoriesFor(s.secondaryMuscle!),
      };
      if (cats.any((c) => c.toLowerCase() == target)) return true;
      return s.primaryMuscle.toLowerCase().contains(target) ||
          (s.secondaryMuscle ?? '').toLowerCase().contains(target);
    }).toList();
  }
}
