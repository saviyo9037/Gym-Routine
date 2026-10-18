import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/core/next_occurrence.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:reptrack/models/routine.dart';
import 'package:reptrack/services/alarm_service.dart';
import 'package:reptrack/services/routine_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

Routine routine({
  int id = 1,
  String start = '07:00',
  String end = '08:00',
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  String type = 'alarm',
  bool alarm = true,
  bool reminder = true,
  int lead = 10,
  bool enabled = true,
}) => Routine(
  id: id,
  title: 'R$id',
  category: 'Gym',
  startTime: start,
  endTime: end,
  repeatDays: days,
  alarmType: type,
  isAlarmEnabled: alarm,
  isReminderEnabled: reminder,
  reminderMinutesBefore: lead,
  isEnabled: enabled,
);

void main() {
  group('NextOccurrence (mirrors NextOccurrence.kt)', () {
    test('today later, today passed, repeat day filtering', () {
      final now = DateTime(2026, 10, 20, 6, 0); // Tuesday
      expect(
        NextOccurrence.compute(now, '07:00', [1, 2, 3, 4, 5, 6, 7]),
        DateTime(2026, 10, 20, 7, 0),
      );
      expect(
        NextOccurrence.compute(DateTime(2026, 10, 20, 7, 0), '07:00', [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ]),
        DateTime(2026, 10, 21, 7, 0),
        reason: 'strictly after now',
      );
      // Only Mondays: from Tuesday the next one is 6 days later.
      expect(
        NextOccurrence.compute(now, '07:00', [1]),
        DateTime(2026, 10, 26, 7, 0),
      );
      // Same weekday as today but already passed -> next week.
      expect(
        NextOccurrence.compute(DateTime(2026, 10, 20, 9, 0), '07:00', [2]),
        DateTime(2026, 10, 27, 7, 0),
      );
    });

    test('empty repeat days schedules nothing', () {
      expect(
        NextOccurrence.compute(DateTime(2026, 10, 20), '07:00', []),
        isNull,
      );
    });

    test('lead time moves earlier, can fall on the previous day', () {
      final now = DateTime(2026, 10, 20, 23, 0);
      expect(
        NextOccurrence.compute(now, '00:05', [3], leadMinutes: 10),
        DateTime(2026, 10, 20, 23, 55),
        reason: 'Wednesday 00:05 minus 10 min is Tuesday 23:55',
      );
      // Reminder already passed today, alarm still ahead -> reminder is next day.
      expect(
        NextOccurrence.compute(DateTime(2026, 10, 20, 6, 55), '07:00', [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ], leadMinutes: 10),
        DateTime(2026, 10, 21, 6, 50),
      );
    });

    test('wall-clock time is stable across month, year and DST dates', () {
      for (final start in [
        DateTime(2026, 3, 28, 23, 0), // EU DST starts 29 Mar
        DateTime(2026, 3, 7, 23, 0), // US DST starts 8 Mar
        DateTime(2026, 10, 24, 23, 0), // EU DST ends 25 Oct
        DateTime(2026, 10, 31, 23, 0), // US DST ends 1 Nov
        DateTime(2026, 12, 31, 23, 0), // year rollover
      ]) {
        final next = NextOccurrence.compute(start, '07:00', [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ])!;
        expect(next.hour, 7, reason: '$start');
        expect(next.minute, 0);
        expect(next.day, start.add(const Duration(hours: 12)).day);
      }
      final ny = NextOccurrence.compute(
        DateTime(2026, 12, 31, 23, 0),
        '07:00',
        [1, 2, 3, 4, 5, 6, 7],
      )!;
      expect(ny, DateTime(2027, 1, 1, 7, 0));
    });
  });

  group('alarm scheduling contract with the native side', () {
    late Database db;
    final calls = <MethodCall>[];
    List<Map<String, Object?>> nativeScheduled = [];

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      calls.clear();
      nativeScheduled = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.reptrack.app/alarm'),
            (call) async {
              calls.add(call);
              if (call.method == 'getScheduledAlarms') return nativeScheduled;
              return true;
            },
          );
      db = await openTestDatabase();
    });

    tearDown(() async {
      AppClock.reset();
      await closeTestDatabase(db);
    });

    test('alarm routine sends days, lead time and flags', () async {
      final ok = await AlarmService().scheduleRoutineAlarm(
        routine(days: [1, 3, 5]),
      );
      expect(ok, isTrue);
      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'scheduleAlarm');
      expect(args['repeatDays'], [1, 3, 5]);
      expect(args['time'], '07:00');
      expect(args['alarmEnabled'], true);
      expect(args['isAudible'], true);
      expect(args['reminderEnabled'], true);
      expect(args['leadMinutes'], 10);
    });

    test('quiet reminder routine schedules only the heads-up', () async {
      await AlarmService().scheduleRoutineAlarm(
        routine(type: 'notification', alarm: false, lead: 15),
      );
      final args = calls.single.arguments as Map;
      expect(args['alarmEnabled'], false);
      expect(args['reminderEnabled'], true);
      expect(args['leadMinutes'], 15);
    });

    test(
      'alarm with zero lead does not duplicate itself as a reminder',
      () async {
        await AlarmService().scheduleRoutineAlarm(routine(lead: 0));
        final args = calls.single.arguments as Map;
        expect(args['alarmEnabled'], true);
        expect(args['reminderEnabled'], false);
      },
    );

    test(
      'disabled / no days / nothing wanted -> cancel, never schedule',
      () async {
        final svc = AlarmService();
        expect(
          await svc.scheduleRoutineAlarm(routine(enabled: false)),
          isFalse,
        );
        expect(await svc.scheduleRoutineAlarm(routine(days: [])), isFalse);
        expect(
          await svc.scheduleRoutineAlarm(
            routine(type: 'none', alarm: false, reminder: false),
          ),
          isFalse,
        );
        expect(calls.map((c) => c.method).toSet(), {'cancelAlarm'});
      },
    );

    test('rescheduleAllRoutines pushes the database and prunes stale native alarms', () async {
      final svc = RoutineService();
      final before = (await svc.getAllRoutines()).length;
      expect(before, greaterThan(0));
      calls.clear();
      nativeScheduled = [
        {'routineId': 424242, 'title': 'ghost'},
      ];
      await svc.rescheduleAllRoutines();
      final scheduledIds = calls
          .where((c) => c.method == 'scheduleAlarm')
          .map((c) => (c.arguments as Map)['routineId'])
          .toSet();
      expect(scheduledIds.length, greaterThan(0));
      final cancelled = calls
          .where((c) => c.method == 'cancelAlarm')
          .map((c) => (c.arguments as Map)['routineId'])
          .toList();
      expect(cancelled, contains(424242));
    });
  });

  group('routines data', () {
    late Database db;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.reptrack.app/alarm'),
            (call) async => true,
          );
      db = await openTestDatabase();
    });

    tearDown(() async {
      AppClock.reset();
      await closeTestDatabase(db);
    });

    test('default routines are seeded once and never come back', () async {
      final svc = RoutineService();
      final all = await svc.getAllRoutines();
      expect(all.length, 9);
      await svc.deleteRoutine(all.first.id!);
      await DatabaseHelper.instance.syncCatalogue(db);
      await DatabaseHelper.instance.syncCatalogue(db);
      expect((await svc.getAllRoutines()).length, 8);
    });

    test(
      'an existing install with routines keeps exactly what it has',
      () async {
        await db.delete(
          'user_settings',
          where: "key = 'default_routines_seeded'",
        );
        await db.delete('routines', where: 'id > 2');
        await DatabaseHelper.instance.syncCatalogue(db);
        expect((await db.query('routines')).length, 2);
      },
    );

    test(
      'overnight routine is "in progress" after midnight on the next day',
      () async {
        final svc = RoutineService();
        await db.delete('routines');
        await db.delete('routine_completions');
        await svc.insertRoutine(
          routine(
            id: 0,
            start: '22:30',
            end: '07:15',
            type: 'notification',
            alarm: false,
          ).copyWith(title: 'Sleep', category: 'Sleep'),
        );
        // Tuesday 02:00: Monday night's sleep is still running.
        AppClock.setForTesting(() => DateTime(2026, 10, 20, 2, 0));
        final next = (await svc.getNextUpcomingRoutine())!;
        expect(next.routine.title, 'Sleep');
        expect(next.isInProgress, isTrue);
        expect(next.date, DateTime(2026, 10, 19));
        // Tuesday 12:00: nothing running, tonight's sleep is the next one.
        AppClock.setForTesting(() => DateTime(2026, 10, 20, 12, 0));
        final later = (await svc.getNextUpcomingRoutine())!;
        expect(later.isInProgress, isFalse);
        expect(
          (later.date.year, later.date.month, later.date.day),
          (2026, 10, 20),
        );
      },
    );

    test(
      'deleting a routine cancels its native alarm and completions',
      () async {
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.reptrack.app/alarm'),
              (call) async {
                calls.add(call.method);
                return true;
              },
            );
        final svc = RoutineService();
        final id = (await svc.getAllRoutines()).first.id!;
        await svc.setRoutineCompletion(
          routineId: id,
          date: DateTime(2026, 10, 20),
          status: 'completed',
        );
        await svc.deleteRoutine(id);
        expect(calls, contains('cancelAlarm'));
        expect(await db.query('routine_completions'), isEmpty);
      },
    );

    test(
      'weekly routine stats use the Monday of the week (DST safe)',
      () async {
        final svc = RoutineService();
        for (final anchor in [
          DateTime(2026, 3, 29, 12), // EU DST Sunday
          DateTime(2026, 11, 1, 12), // US DST Sunday
          DateTime(2026, 10, 25, 0, 30),
        ]) {
          final s = await svc.getWeeklyRoutineStats(anchor);
          expect(s.totalScheduled, greaterThan(0), reason: '$anchor');
        }
      },
    );
  });
}
