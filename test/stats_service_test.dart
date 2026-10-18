import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:reptrack/models/weekly_summary.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/services/stats_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

/// Set spec: [exerciseId, name, setNumber, reps, kg, completed, cardio?]
typedef S = ({
  int id,
  String name,
  int n,
  int reps,
  double kg,
  bool done,
  int? sec,
  double? km,
});

S st(
  int id,
  String name,
  int n,
  int reps,
  double kg, {
  bool done = true,
  int? sec,
  double? km,
}) => (
  id: id,
  name: name,
  n: n,
  reps: reps,
  kg: kg,
  done: done,
  sec: sec,
  km: km,
);

Future<int> addSession(
  Database db,
  String date,
  List<S> sets, {
  String muscle = 'Chest',
  String? secondary = 'Triceps',
  int duration = 3000,
}) async {
  final id = await db.insert('workout_sessions', {
    'date': date,
    'start_time': '10:00',
    'end_time': '10:50',
    'duration_seconds': duration,
    'primary_muscle': muscle,
    'secondary_muscle': secondary,
    'created_at': '${date}T10:00:00',
  });
  for (final s in sets) {
    await db.insert('workout_sets', {
      'session_id': id,
      'exercise_id': s.id,
      'exercise_name': s.name,
      'set_number': s.n,
      'reps': s.reps,
      'weight_kg': s.kg,
      'is_completed': s.done ? 1 : 0,
      'completed_at': '${date}T10:10:00',
      'duration_seconds': s.sec,
      'distance_km': s.km,
    });
  }
  return id;
}

Future<void> addPlan(
  Database db,
  String date, {
  bool rest = false,
  List<String> exercises = const [],
}) async {
  final id = await db.insert('workout_plans', {
    'date': date,
    'is_rest_day': rest ? 1 : 0,
    'primary_muscle_name': rest ? null : 'Chest',
    'created_at': '${date}T00:00:00',
    'updated_at': '${date}T00:00:00',
  });
  for (var i = 0; i < exercises.length; i++) {
    await db.insert('planned_exercises', {
      'plan_id': id,
      'exercise_id': 1 + i,
      'exercise_name': exercises[i],
      'muscle_group_name': 'Chest',
      'exercise_order': i,
    });
  }
}

final bench = [
  st(1, 'Barbell Bench Press', 1, 8, 60),
  st(1, 'Barbell Bench Press', 2, 8, 60),
];

void main() {
  late Database db;
  late StatsService stats;

  setUp(() async {
    db = await openTestDatabase();
    await db.delete('planned_exercises');
    await db.delete('workout_plans');
    stats = StatsService();
    // Wednesday 2026-10-21 12:00 local.
    AppClock.setForTesting(() => DateTime(2026, 10, 21, 12));
  });

  tearDown(() async {
    AppClock.reset();
    await closeTestDatabase(db);
  });

  group('date helpers (pure, timezone independent)', () {
    test('week ranges for both week starts, incl. Sunday/Monday edges', () {
      // Sunday 2026-10-25
      var r = StatsService.weekRange(
        DateTime(2026, 10, 25),
        sundayStart: false,
      );
      expect([r.start, r.end], ['2026-10-19', '2026-10-25']);
      r = StatsService.weekRange(DateTime(2026, 10, 25), sundayStart: true);
      expect([r.start, r.end], ['2026-10-25', '2026-10-31']);
      // Monday 2026-10-26 starts a new Monday-week
      r = StatsService.weekRange(DateTime(2026, 10, 26), sundayStart: false);
      expect([r.start, r.end], ['2026-10-26', '2026-11-01']);
      r = StatsService.weekRange(DateTime(2026, 10, 26), sundayStart: true);
      expect([r.start, r.end], ['2026-10-25', '2026-10-31']);
      // Saturday 2026-10-24
      r = StatsService.weekRange(DateTime(2026, 10, 24), sundayStart: true);
      expect([r.start, r.end], ['2026-10-18', '2026-10-24']);
      r = StatsService.weekRange(DateTime(2026, 10, 24), sundayStart: false);
      expect([r.start, r.end], ['2026-10-19', '2026-10-25']);
    });

    test('month and year rollover', () {
      var m = StatsService.monthRange(DateTime(2026, 2, 15));
      expect([m.start, m.end], ['2026-02-01', '2026-02-28']);
      m = StatsService.monthRange(DateTime(2028, 2, 10));
      expect(m.end, '2028-02-29'); // leap year
      m = StatsService.monthRange(DateTime(2026, 12, 31));
      expect([m.start, m.end], ['2026-12-01', '2026-12-31']);
      // A week that spans the new year
      final w = StatsService.weekRange(
        DateTime(2026, 12, 31),
        sundayStart: false,
      );
      expect([w.start, w.end], ['2026-12-28', '2027-01-03']);
      final l = StatsService.lastDays(DateTime(2026, 1, 3), 7);
      expect([l.start, l.end], ['2025-12-28', '2026-01-03']);
    });

    test('last N days includes today and is exactly N days', () {
      final r = StatsService.lastDays(DateTime(2026, 10, 21), 7);
      expect([r.start, r.end], ['2026-10-15', '2026-10-21']);
      final r30 = StatsService.lastDays(DateTime(2026, 10, 21), 30);
      expect(r30.start, '2026-09-22');
    });

    test('calendar arithmetic is correct for every day of 2026 (DST safe)', () {
      final fmt = DateFormat('yyyy-MM-dd');
      for (var i = 0; i < 366; i++) {
        final d = DateTime(2026, 1, 1 + i);
        final next = StatsService.dayAt(d, 1);
        final expected = fmt.format(DateTime.utc(2026, 1, 2 + i));
        expect(StatsService.key(next), expected, reason: 'day ${d.toString()}');
        final ws = StatsService.weekStart(d, sundayStart: false);
        expect(ws.weekday, DateTime.monday);
        expect(ws.hour, 0);
        final ss = StatsService.weekStart(d, sundayStart: true);
        expect(ss.weekday, DateTime.sunday);
        expect(ss.hour, 0);
      }
    });

    test('DST-change weeks keep seven distinct dates', () {
      for (final anchor in [
        DateTime(2026, 3, 29),
        DateTime(2026, 11, 1),
        DateTime(2026, 3, 8),
        DateTime(2026, 10, 25),
      ]) {
        for (final sunday in [false, true]) {
          final start = StatsService.weekStart(anchor, sundayStart: sunday);
          final keys = {
            for (var i = 0; i < 7; i++)
              StatsService.key(StatsService.dayAt(start, i)),
          };
          expect(keys.length, 7);
          expect(keys.contains(StatsService.key(anchor)), isTrue);
        }
      }
    });

    test('filter labels map to ranges', () {
      final now = DateTime(2026, 10, 21);
      expect(
        StatsService.rangeForFilter('All Time', now, sundayStart: false),
        isNull,
      );
      final tm = StatsService.rangeForFilter(
        'This Month',
        now,
        sundayStart: false,
      )!;
      expect([tm.start, tm.end], ['2026-10-01', '2026-10-21']);
      final tw = StatsService.rangeForFilter(
        'This Week',
        now,
        sundayStart: true,
      )!;
      expect([tw.start, tw.end], ['2026-10-18', '2026-10-24']);
    });

    test('Epley estimate', () {
      expect(StatsService.epleyOneRepMax(100, 1), 100);
      expect(StatsService.epleyOneRepMax(100, 10), closeTo(133.33, 0.01));
      expect(StatsService.epleyOneRepMax(100, 30), isNull); // unreliable
      expect(StatsService.epleyOneRepMax(0, 5), isNull);
    });
  });

  group('empty and first-time state', () {
    test('no data: zeros, no history, streak 0, no crash', () async {
      expect(await stats.hasNoHistory(), isTrue);
      expect((await stats.periodStats(null)).isEmpty, isTrue);
      expect(await stats.currentStreak(), 0);
      expect(await stats.exercisesWithHistory(), isEmpty);
      final w = await stats.weeklySummary(AppClock.now());
      expect(w.workoutsCompleted, 0);
      expect(w.totalVolumeKg, 0);
      expect(w.days.length, 7);
      expect(w.days.every((d) => d.status == DayStatus.noPlan), isTrue);
      expect(w.restDays, 0); // nothing scheduled is not a rest day
      expect(await stats.muscleFrequency(null), {
        for (final c in StatsService.muscleCategories) c: 0,
      });
    });

    test('a session with no completed sets is not a workout', () async {
      await addSession(db, '2026-10-21', [
        st(1, 'Barbell Bench Press', 1, 8, 60, done: false),
      ]);
      expect(await stats.hasNoHistory(), isTrue);
      final w = await stats.weeklySummary(AppClock.now());
      expect(w.workoutsCompleted, 0);
      final today = w.days.firstWhere((d) => d.isToday);
      expect(today.sessions.length, 1);
      expect(today.status, isNot(DayStatus.completed));
      expect(await stats.currentStreak(), 0);
    });
  });

  group('weekly summary', () {
    test(
      'Monday-start week boundaries (Sunday belongs to the week it ends)',
      () async {
        await addSession(db, '2026-10-18', bench); // Sun, previous week
        await addSession(db, '2026-10-19', bench); // Mon
        await addSession(db, '2026-10-25', bench); // Sun, same week
        await addSession(db, '2026-10-26', bench); // Mon, next week
        final w = await stats.weeklySummary(DateTime(2026, 10, 21));
        expect(StatsService.key(w.startOfWeek), '2026-10-19');
        expect(StatsService.key(w.endOfWeek), '2026-10-25');
        expect(w.workoutsCompleted, 2);
        expect(w.days.first.dayName, 'Mon');
        expect(w.days.last.dateStr, '2026-10-25');
      },
    );

    test('Sunday-start week boundaries via the setting', () async {
      expect(await stats.weekStartsOnSunday(), isFalse); // default
      await stats.setWeekStartsOnSunday(true);
      expect(await stats.weekStartsOnSunday(), isTrue);
      await addSession(db, '2026-10-17', bench); // Sat, previous week
      await addSession(db, '2026-10-18', bench); // Sun, first day
      await addSession(db, '2026-10-24', bench); // Sat, last day
      await addSession(db, '2026-10-25', bench); // Sun, next week
      final w = await stats.weeklySummary(DateTime(2026, 10, 21));
      expect(StatsService.key(w.startOfWeek), '2026-10-18');
      expect(StatsService.key(w.endOfWeek), '2026-10-24');
      expect(w.workoutsCompleted, 2);
      expect(w.days.first.dayName, 'Sun');
    });

    test('week spanning a year boundary', () async {
      AppClock.setForTesting(() => DateTime(2027, 1, 1, 9));
      await addSession(db, '2026-12-31', bench);
      await addSession(db, '2027-01-01', bench);
      final w = await stats.weeklySummary(DateTime(2027, 1, 1));
      expect(
        [StatsService.key(w.startOfWeek), StatsService.key(w.endOfWeek)],
        ['2026-12-28', '2027-01-03'],
      );
      expect(w.workoutsCompleted, 2);
    });

    test('planned vs completed vs missed vs rest', () async {
      await addPlan(
        db,
        '2026-10-19',
        exercises: ['Barbell Bench Press', 'Incline Barbell Bench Press'],
      ); // Mon done
      await addSession(db, '2026-10-19', bench);
      await addPlan(
        db,
        '2026-10-20',
        exercises: ['Lat Pulldown'],
      ); // Tue missed
      await addPlan(
        db,
        '2026-10-21',
        exercises: ['Hammer Curl'],
      ); // Wed today, planned
      await addPlan(db, '2026-10-22', rest: true); // Thu rest
      await addPlan(db, '2026-10-23', exercises: ['Squat']); // Fri future
      final w = await stats.weeklySummary(AppClock.now());
      final byDate = {for (final d in w.days) d.dateStr: d};
      expect(
        byDate['2026-10-19']!.status,
        DayStatus.partiallyCompleted,
      ); // 1 of 2 planned exercises
      expect(byDate['2026-10-20']!.status, DayStatus.missed);
      expect(byDate['2026-10-21']!.status, DayStatus.planned);
      expect(byDate['2026-10-22']!.status, DayStatus.restDay);
      expect(byDate['2026-10-23']!.status, DayStatus.planned);
      expect(byDate['2026-10-24']!.status, DayStatus.noPlan);
      expect(w.workoutsCompleted, 1);
      expect(w.plannedWorkouts, 3); // missed + two planned
      expect(w.restDays, 1);
      final p = stats.weekProgress(w);
      expect((p.done, p.scheduled), (1, 4)); // rest day not in the denominator
    });

    test(
      'a session on a rest day counts as a workout, not as a rest day',
      () async {
        await addPlan(db, '2026-10-20', rest: true);
        await addSession(db, '2026-10-20', bench);
        final w = await stats.weeklySummary(AppClock.now());
        expect(w.workoutsCompleted, 1);
        expect(w.restDays, 0);
      },
    );

    test('strength volume excludes cardio; cardio reported as time/distance', () async {
      await addSession(db, '2026-10-20', [
        st(1, 'Barbell Bench Press', 1, 10, 50), // 500
        st(191, 'Treadmill Running', 1, 20, 0, sec: 1200, km: 3.5),
      ], duration: 2400);
      // Legacy (pre-v6) cardio row: minutes in reps, km in weight, no columns.
      await addSession(
        db,
        '2026-10-21',
        [st(192, 'Stationary Cycling', 1, 30, 12.0)],
        muscle: 'Cardio',
        secondary: null,
        duration: 1800,
      );
      final w = await stats.weeklySummary(AppClock.now());
      expect(w.totalVolumeKg, 500);
      expect(w.cardioSeconds, 1200 + 30 * 60);
      expect(w.cardioKm, closeTo(15.5, 1e-9));
      expect(w.totalDurationSeconds, 4200);
      expect(w.setsCompleted, 3);
    });

    test(
      'midnight boundary: session date is its start date, not split',
      () async {
        // Saved by the app on the start day even if finished after midnight.
        await addSession(db, '2026-10-25', bench, duration: 3600);
        AppClock.setForTesting(() => DateTime(2026, 10, 26, 0, 5));
        final lastWeek = await stats.weeklySummary(DateTime(2026, 10, 25));
        final thisWeek = await stats.weeklySummary(AppClock.now());
        expect(lastWeek.workoutsCompleted, 1);
        expect(thisWeek.workoutsCompleted, 0);
        expect(thisWeek.days.first.isToday, isTrue); // Monday 26th
      },
    );
  });

  group('period stats, streak, exercises, muscles', () {
    test('period stats over a range', () async {
      await addSession(db, '2026-10-01', bench, duration: 1000);
      await addSession(db, '2026-10-10', bench, duration: 2000);
      await addSession(db, '2026-09-30', bench, duration: 4000);
      final oct = await stats.periodStats(
        StatsService.monthRange(DateTime(2026, 10, 15)),
      );
      expect(oct.workouts, 2);
      expect(oct.durationSeconds, 3000);
      expect(oct.volumeKg, 2 * 960);
      expect(oct.trainingDays, 2);
      final all = await stats.periodStats(null);
      expect(all.workouts, 3);
    });

    test('streak: rest days neither count nor break; today not yet trained is fine', () async {
      await addSession(db, '2026-10-21', bench); // today
      await addSession(db, '2026-10-20', bench);
      await addSession(db, '2026-10-19', bench);
      await addPlan(db, '2026-10-18', rest: true);
      await addSession(db, '2026-10-17', bench);
      expect(await stats.currentStreak(), 4);

      // Yesterday trained, today not yet.
      AppClock.setForTesting(() => DateTime(2026, 10, 22, 8));
      expect(await stats.currentStreak(), 4);
      // A gap of an unplanned day breaks it.
      AppClock.setForTesting(() => DateTime(2026, 10, 23, 8));
      expect(await stats.currentStreak(), 0);
    });

    test(
      'exercise progress: best weight, 1RM, volume trend, last sessions',
      () async {
        await addSession(db, '2026-10-05', [
          st(1, 'Barbell Bench Press', 1, 10, 60),
          st(1, 'Barbell Bench Press', 2, 8, 70),
        ]);
        await addSession(db, '2026-10-12', [
          st(1, 'Barbell Bench Press', 1, 5, 80),
          st(1, 'Barbell Bench Press', 2, 5, 80, done: false), // ignored
        ]);
        await addSession(db, '2026-10-19', [
          st(1, 'Barbell Bench Press', 1, 1, 100),
        ]);
        await addSession(db, '2026-10-19', [st(2, 'Other', 1, 10, 10)]);
        final p = await stats.exerciseProgress(1);
        expect(p.points.map((e) => e.date), [
          '2026-10-05',
          '2026-10-12',
          '2026-10-19',
        ]);
        expect(p.bestWeightKg, 100);
        expect(p.points.first.bestWeightKg, 70);
        expect(p.points.first.repsAtBestWeight, 8);
        expect(p.points.first.volumeKg, 600 + 560);
        expect(p.points[1].sets, 1);
        expect(p.bestOneRepMaxKg, closeTo(100, 1e-9));
        expect(
          p.points[1].estimatedOneRepMaxKg,
          closeTo(80 * (1 + 5 / 30), 1e-9),
        );
        expect(p.volumeTrendKg, 100 - 400);
        expect(p.lastSessions(2).map((e) => e.date), [
          '2026-10-19',
          '2026-10-12',
        ]);
        final list = await stats.exercisesWithHistory();
        expect(list.map((e) => e.exerciseId), [1, 2]);
        expect((await stats.exerciseProgress(999)).hasData, isFalse);
      },
    );

    test(
      'muscle frequency and sessions for muscle ignore empty sessions',
      () async {
        await addSession(db, '2026-10-19', bench); // Chest + Triceps
        await addSession(
          db,
          '2026-10-20',
          bench,
          muscle: 'Back',
          secondary: 'Biceps',
        );
        await addSession(
          db,
          '2026-10-21',
          [st(1, 'x', 1, 5, 5, done: false)],
          muscle: 'Legs',
          secondary: null,
        );
        final f = await stats.muscleFrequency(null);
        expect(f['Chest'], 1);
        expect(f['Triceps'], 1);
        expect(f['Back'], 1);
        expect(f['Biceps'], 1);
        expect(f['Legs'], 0);
        final chest = await stats.sessionsForMuscle('Chest', null);
        expect(chest.length, 1);
        expect((await stats.sessionsForMuscle('All', null)).length, 2);
      },
    );
  });

  group('restart persistence', () {
    test('stats and the week-start setting survive closing and reopening a file database', () async {
      final dir = Directory.systemTemp.createTempSync('reptrack_stats_');
      final path = '${dir.path}/restart.db';
      try {
        sqfliteFfiInit();
        var file = await DatabaseHelper.instance.openForTesting(
          databaseFactoryFfi,
          path,
        );
        DatabaseHelper.instance.useDatabaseForTesting(file);
        await file.delete('workout_plans');
        await addSession(file, '2026-10-20', bench);
        await StatsService().setWeekStartsOnSunday(true);
        await file.close();

        file = await DatabaseHelper.instance.openForTesting(
          databaseFactoryFfi,
          path,
        );
        DatabaseHelper.instance.useDatabaseForTesting(file);
        final again = StatsService();
        expect(await again.weekStartsOnSunday(), isTrue);
        final w = await again.weeklySummary(AppClock.now());
        expect(w.workoutsCompleted, 1);
        expect(w.totalVolumeKg, 960);
        expect(await DatabaseService().getAllSessions(), hasLength(1));
        await file.close();
      } finally {
        DatabaseHelper.instance.useDatabaseForTesting(null);
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
