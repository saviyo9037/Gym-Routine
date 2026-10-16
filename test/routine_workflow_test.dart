import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/models/routine.dart';
import 'package:reptrack/models/routine_completion.dart';
import 'package:reptrack/models/routine_today_item.dart';

void main() {
  group('Routine Model & Overnight Calculation Tests', () {
    test(
      'Standard daytime routine calculates duration and overnight correctly',
      () {
        final gym = Routine(
          id: 1,
          title: 'Morning Strength Workout',
          category: 'Gym',
          startTime: '07:00',
          endTime: '08:30',
          repeatDays: [1, 2, 3, 4, 5, 6], // Mon - Sat
        );

        expect(gym.isOvernight, isFalse);
        expect(gym.durationMinutes, equals(90));
        expect(gym.formattedDuration, equals('1h 30m'));
        expect(gym.formattedTimeRange, equals('07:00 – 08:30'));
        expect(gym.categoryEnum, equals(RoutineCategory.gym));
      },
    );

    test(
      'Overnight sleep routine crossing midnight calculates 480 minutes (8h)',
      () {
        final sleep = Routine(
          id: 2,
          title: 'Deep Recovery Sleep',
          category: 'Sleep',
          startTime: '22:30',
          endTime: '06:30',
          repeatDays: [1, 2, 3, 4, 5, 6, 7],
        );

        expect(sleep.isOvernight, isTrue);
        // From 22:30 to 24:00 is 90 mins, 00:00 to 06:30 is 390 mins -> 480 mins = 8 hours
        expect(sleep.durationMinutes, equals(480));
        expect(sleep.formattedDuration, equals('8h'));
        expect(sleep.formattedTimeRange, equals('22:30 – 06:30'));
        expect(sleep.categoryEnum, equals(RoutineCategory.sleep));
      },
    );

    test(
      'Short overnight shift (e.g. 23:45 to 00:30) calculates 45 minutes',
      () {
        final shift = Routine(
          id: 3,
          title: 'Midnight Check',
          category: 'Work',
          startTime: '23:45',
          endTime: '00:30',
          repeatDays: [1, 2, 3, 4, 5],
        );

        expect(shift.isOvernight, isTrue);
        expect(shift.durationMinutes, equals(45));
        expect(shift.formattedDuration, equals('45m'));
      },
    );

    test('Repeat days formatting handles standard patterns', () {
      final everyday = Routine(
        title: 'Everyday Activity',
        category: 'Meals',
        startTime: '12:00',
        endTime: '13:00',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );
      expect(everyday.formattedRepeatDays, equals('Every Day'));

      final weekdays = Routine(
        title: 'Work Sprint',
        category: 'Work',
        startTime: '09:00',
        endTime: '17:00',
        repeatDays: [1, 2, 3, 4, 5],
      );
      expect(weekdays.formattedRepeatDays, equals('Weekdays (Mon–Fri)'));

      final weekends = Routine(
        title: 'Weekend Trail Walk',
        category: 'Walking',
        startTime: '08:00',
        endTime: '10:00',
        repeatDays: [6, 7],
      );
      expect(weekends.formattedRepeatDays, equals('Weekends (Sat–Sun)'));

      final customDays = Routine(
        title: 'Specific Days',
        category: 'Reading',
        startTime: '20:00',
        endTime: '21:00',
        repeatDays: [1, 3, 5],
      );
      expect(customDays.formattedRepeatDays, equals('Mon, Wed, Fri'));
    });

    test(
      'appliesToDate accurately checks weekday match and enabled status',
      () {
        // October 16, 2026 is a Friday (weekday = 5)
        final fridayDate = DateTime(2026, 10, 16);
        // October 17, 2026 is a Saturday (weekday = 6)
        final saturdayDate = DateTime(2026, 10, 17);

        final weekdayRoutine = Routine(
          title: 'Weekday Study',
          category: 'Study',
          startTime: '18:00',
          endTime: '19:30',
          repeatDays: [1, 2, 3, 4, 5],
          isEnabled: true,
        );

        expect(weekdayRoutine.appliesToDate(fridayDate), isTrue);
        expect(weekdayRoutine.appliesToDate(saturdayDate), isFalse);

        final disabledRoutine = weekdayRoutine.copyWith(isEnabled: false);
        expect(disabledRoutine.appliesToDate(fridayDate), isFalse);
      },
    );

    test('Routine serialization toMap and fromMap preserves all fields', () {
      final original = Routine(
        id: 99,
        title: 'Evening Reflection & Stretches',
        category: 'Rest',
        startTime: '21:00',
        endTime: '21:45',
        repeatDays: [2, 4, 6],
        notes: 'Follow hip mobility sequence',
        isReminderEnabled: true,
        reminderMinutesBefore: 15,
        isEnabled: true,
        colorHex: '#B388FF',
      );

      final map = original.toMap();
      expect(map['title'], equals('Evening Reflection & Stretches'));
      expect(map['repeat_days'], equals('2,4,6'));
      expect(map['is_reminder_enabled'], equals(1));
      expect(map['reminder_minutes_before'], equals(15));
      expect(map['color_hex'], equals('#B388FF'));

      final reconstructed = Routine.fromMap(map);
      expect(reconstructed.id, equals(original.id));
      expect(reconstructed.title, equals(original.title));
      expect(reconstructed.category, equals(original.category));
      expect(reconstructed.startTime, equals(original.startTime));
      expect(reconstructed.endTime, equals(original.endTime));
      expect(reconstructed.repeatDays, equals([2, 4, 6]));
      expect(reconstructed.notes, equals('Follow hip mobility sequence'));
      expect(reconstructed.isReminderEnabled, isTrue);
      expect(reconstructed.reminderMinutesBefore, equals(15));
      expect(reconstructed.isEnabled, isTrue);
      expect(reconstructed.colorHex, equals('#B388FF'));
    });
  });

  group('RoutineCompletion & RoutineTodayItem Tests', () {
    test('RoutineCompletion correctly identifies completed vs skipped', () {
      final comp1 = RoutineCompletion(
        routineId: 10,
        date: '2026-10-16',
        status: 'completed',
        notes: 'Felt energetic',
      );
      expect(comp1.isCompleted, isTrue);
      expect(comp1.isSkipped, isFalse);

      final comp2 = RoutineCompletion(
        routineId: 10,
        date: '2026-10-17',
        status: 'skipped',
        notes: 'Traveling',
      );
      expect(comp2.isCompleted, isFalse);
      expect(comp2.isSkipped, isTrue);
    });

    test('Overnight RoutineTodayItem correctly calculates startDateTime and endDateTime across midnight', () {
      final testDate = DateTime(2026, 10, 16); // Friday
      final sleepRoutine = Routine(
        id: 5,
        title: 'Sleep Routine',
        category: 'Sleep',
        startTime: '22:30',
        endTime: '06:30',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );

      final item = RoutineTodayItem(routine: sleepRoutine, date: testDate);

      expect(item.startDateTime, equals(DateTime(2026, 10, 16, 22, 30)));
      // End time is 06:30 on NEXT day (October 17)
      expect(item.endDateTime, equals(DateTime(2026, 10, 17, 6, 30)));
      expect(item.endDateTime.isAfter(item.startDateTime), isTrue);
    });

    test('RoutineTodayItem reflects explicit completed status even after scheduled window', () {
      final testDate = DateTime.now();
      final routine = Routine(
        id: 7,
        title: 'Morning Water',
        category: 'Walking',
        startTime: '06:00',
        endTime: '06:15',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );

      final completedItem = RoutineTodayItem(
        routine: routine,
        date: testDate,
        completion: RoutineCompletion(
          routineId: 7,
          date: '2026-10-16',
          status: 'completed',
        ),
      );

      expect(completedItem.status, equals(RoutineCompletionStatus.completed));
      expect(completedItem.isCompleted, isTrue);
    });

    test(
      'Past completion history is decoupled from routine schedule changes',
      () {
        // Simulating a routine that gets rescheduled from 07:00 to 09:00
        final routineOriginal = Routine(
          id: 8,
          title: 'Morning Run',
          category: 'Walking',
          startTime: '07:00',
          endTime: '08:00',
          repeatDays: [1, 3, 5],
        );

        final pastLog = RoutineCompletion(
          id: 101,
          routineId: 8,
          date: '2026-10-14',
          status: 'completed',
          notes: 'Logged at original 7am slot',
        );

        // User changes routine schedule to 09:00
        final routineRescheduled = routineOriginal.copyWith(
          startTime: '09:00',
          endTime: '10:00',
          repeatDays: [2, 4, 6],
        );

        // The historical log remains unaltered and valid
        expect(pastLog.routineId, equals(routineRescheduled.id));
        expect(pastLog.status, equals('completed'));
        expect(pastLog.notes, equals('Logged at original 7am slot'));
      },
    );
  });

  group('Routine Overlap & Conflict Detection Tests', () {
    test('Detects daytime overlap between two scheduled routines sharing repeat days', () {
      final routineA = Routine(
        id: 1,
        title: 'Morning Yoga',
        category: 'Rest',
        startTime: '07:00',
        endTime: '08:00',
        repeatDays: [1, 2, 3, 4, 5],
      );

      final routineB = Routine(
        id: 2,
        title: 'Morning Run',
        category: 'Walking',
        startTime: '07:30',
        endTime: '08:30',
        repeatDays: [2, 3], // Overlaps on Tue, Wed
      );

      expect(routineA.overlapsWith(routineB), isTrue);
      expect(routineB.overlapsWith(routineA), isTrue);
    });

    test('Identifies distinct, back-to-back routines as non-overlapping', () {
      final wakeUp = Routine(
        id: 1,
        title: 'Wake Up',
        category: 'Wakeup',
        startTime: '07:15',
        endTime: '07:30',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );

      final breakfast = Routine(
        id: 2,
        title: 'Breakfast',
        category: 'Meals',
        startTime: '07:30',
        endTime: '08:00',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );

      // Touching boundary 07:30 is not a conflict
      expect(wakeUp.overlapsWith(breakfast), isFalse);
    });

    test('No overlap when repeat days do not intersect', () {
      final weekdayOnly = Routine(
        id: 1,
        title: 'Office Work',
        category: 'Work',
        startTime: '09:00',
        endTime: '17:00',
        repeatDays: [1, 2, 3, 4, 5],
      );

      final weekendStudy = Routine(
        id: 2,
        title: 'Weekend Study',
        category: 'Study',
        startTime: '10:00',
        endTime: '14:00',
        repeatDays: [6, 7],
      );

      expect(weekdayOnly.overlapsWith(weekendStudy), isFalse);
    });

    test('Detects overlap with overnight schedule crossing midnight', () {
      final sleep = Routine(
        id: 1,
        title: 'Sleep',
        category: 'Sleep',
        startTime: '22:30',
        endTime: '07:00',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
      );

      final lateWork = Routine(
        id: 2,
        title: 'Late Coding',
        category: 'Work',
        startTime: '23:00',
        endTime: '01:00',
        repeatDays: [1, 2, 3, 4, 5],
      );

      expect(sleep.overlapsWith(lateWork), isTrue);
      expect(lateWork.overlapsWith(sleep), isTrue);
    });
  });

  group('Food, Gym, and Reliable Alarm Attributes Tests', () {
    test('Routine model supports alarmType, soundName, vibration, snooze, and foodDetails', () {
      final breakfast = Routine(
        id: 10,
        title: 'Healthy Breakfast',
        category: 'Meals',
        startTime: '07:30',
        endTime: '08:00',
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
        alarmType: 'alarm',
        isAlarmEnabled: true,
        soundName: 'Gentle Chime',
        isVibrationEnabled: true,
        snoozeMinutes: 5,
        foodDetails: 'Oatmeal, 3 whole eggs, banana, black coffee',
      );

      expect(breakfast.isFoodCategory, isTrue);
      expect(breakfast.isGymCategory, isFalse);
      expect(breakfast.alarmType, equals('alarm'));
      expect(breakfast.isAudibleAlarm, isTrue);
      expect(breakfast.soundName, equals('Gentle Chime'));
      expect(breakfast.isVibrationEnabled, isTrue);
      expect(breakfast.snoozeMinutes, equals(5));
      expect(breakfast.foodDetails, contains('Oatmeal'));

      // Test map serialization & roundtrip
      final map = breakfast.toMap();
      expect(map['alarm_type'], equals('alarm'));
      expect(map['is_alarm_enabled'], equals(1));
      expect(map['sound_name'], equals('Gentle Chime'));
      expect(map['is_vibration_enabled'], equals(1));
      expect(map['snooze_minutes'], equals(5));
      expect(
        map['food_details'],
        equals('Oatmeal, 3 whole eggs, banana, black coffee'),
      );

      final restored = Routine.fromMap(map);
      expect(restored.alarmType, equals('alarm'));
      expect(restored.isAlarmEnabled, isTrue);
      expect(restored.soundName, equals('Gentle Chime'));
      expect(restored.isVibrationEnabled, isTrue);
      expect(restored.snoozeMinutes, equals(5));
      expect(restored.foodDetails, equals(breakfast.foodDetails));
    });

    test('Gym category identifies correctly and supports non-audible notification alarmType', () {
      final gym = Routine(
        id: 20,
        title: 'Evening Gym Workout',
        category: 'Gym',
        startTime: '19:00',
        endTime: '20:30',
        repeatDays: [1, 2, 3, 4, 5, 6],
        alarmType: 'notification',
        isAlarmEnabled: true,
      );

      expect(gym.isGymCategory, isTrue);
      expect(gym.isFoodCategory, isFalse);
      expect(gym.alarmType, equals('notification'));
      expect(gym.isAudibleAlarm, isFalse);
    });

    test('Dynamic suggested dinner calculation accurately computes 15m post-gym end time', () {
      // Configured gym ending at 20:30 (8:30 PM) -> Dinner is 20:45 (8:45 PM)
      const gymEndTime = '20:30';
      final parts = gymEndTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      var dinnerMin = minute + 15;
      var dinnerHour = hour;
      if (dinnerMin >= 60) {
        dinnerHour = (dinnerHour + (dinnerMin ~/ 60)) % 24;
        dinnerMin %= 60;
      }
      final calculated =
          '${dinnerHour.toString().padLeft(2, '0')}:${dinnerMin.toString().padLeft(2, '0')}';
      expect(calculated, equals('20:45'));

      // Edge case: Gym ending at 23:50 -> Dinner at 00:05
      const lateGym = '23:50';
      final parts2 = lateGym.split(':');
      final hour2 = int.parse(parts2[0]);
      final minute2 = int.parse(parts2[1]);
      var dinnerMin2 = minute2 + 15;
      var dinnerHour2 = hour2;
      if (dinnerMin2 >= 60) {
        dinnerHour2 = (dinnerHour2 + (dinnerMin2 ~/ 60)) % 24;
        dinnerMin2 %= 60;
      }
      final calculated2 =
          '${dinnerHour2.toString().padLeft(2, '0')}:${dinnerMin2.toString().padLeft(2, '0')}';
      expect(calculated2, equals('00:05'));
    });
  });
}
