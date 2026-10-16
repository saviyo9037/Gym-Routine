import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/models/weekly_summary.dart';

void main() {
  group('Workout History and Weekly Summary Tests', () {
    test('Week calculation bounds Monday as start and Sunday as end', () {
      // Pick a Wednesday: 2026-10-14
      final wednesday = DateTime(2026, 10, 14);
      final monday = wednesday.subtract(
        Duration(days: wednesday.weekday - DateTime.monday),
      );
      final sunday = monday.add(const Duration(days: 6));

      expect(monday.weekday, equals(DateTime.monday));
      expect(sunday.weekday, equals(DateTime.sunday));
      expect(DateFormat('yyyy-MM-dd').format(monday), equals('2026-10-12'));
      expect(DateFormat('yyyy-MM-dd').format(sunday), equals('2026-10-18'));

      // Pick a Sunday: 2026-10-18
      final testSunday = DateTime(2026, 10, 18);
      final sunMonday = testSunday.subtract(
        Duration(days: testSunday.weekday - DateTime.monday),
      );
      expect(DateFormat('yyyy-MM-dd').format(sunMonday), equals('2026-10-12'));
    });

    test('WorkoutSession correctly calculates completed sets, volume, and completion status', () {
      final fullyCompletedSession = WorkoutSession(
        date: '2026-10-14',
        startTime: '10:00',
        endTime: '10:45',
        durationSeconds: 2700,
        primaryMuscle: 'Chest',
        secondaryMuscle: 'Triceps',
        sets: [
          WorkoutSetRecord(
            sessionId: 1,
            exerciseId: 1,
            exerciseName: 'Barbell Bench Press',
            setNumber: 1,
            reps: 10,
            weightKg: 60.0,
            isCompleted: true,
          ),
          WorkoutSetRecord(
            sessionId: 1,
            exerciseId: 1,
            exerciseName: 'Barbell Bench Press',
            setNumber: 2,
            reps: 10,
            weightKg: 60.0,
            isCompleted: true,
          ),
        ],
      );

      expect(fullyCompletedSession.completedSetsCount, equals(2));
      expect(fullyCompletedSession.totalSetsCount, equals(2));
      expect(
        fullyCompletedSession.totalVolumeKg,
        equals(1200.0),
      ); // 60*10 + 60*10
      expect(fullyCompletedSession.completionStatus, equals('Completed'));
      expect(
        fullyCompletedSession.completedExerciseNames,
        contains('Barbell Bench Press'),
      );

      // Partially completed session with a skipped/unperformed set
      final partiallyCompletedSession = WorkoutSession(
        date: '2026-10-15',
        startTime: '11:00',
        endTime: '11:30',
        durationSeconds: 1800,
        primaryMuscle: 'Back',
        sets: [
          WorkoutSetRecord(
            sessionId: 2,
            exerciseId: 2,
            exerciseName: 'Pull-Up',
            setNumber: 1,
            reps: 8,
            weightKg: 0.0,
            isCompleted: true,
          ),
          WorkoutSetRecord(
            sessionId: 2,
            exerciseId: 2,
            exerciseName: 'Pull-Up',
            setNumber: 2,
            reps: 0,
            weightKg: 0.0,
            isCompleted: false, // Skipped
          ),
        ],
      );

      expect(partiallyCompletedSession.completedSetsCount, equals(1));
      expect(partiallyCompletedSession.totalSetsCount, equals(2));
      expect(
        partiallyCompletedSession.completionStatus,
        equals('Partially Completed'),
      );
    });

    test('Rest days are never counted as completed workouts', () {
      final monday = DateTime(2026, 10, 12);
      final sunday = DateTime(2026, 10, 18);

      final List<DayWorkoutSummary> days = [
        DayWorkoutSummary(
          date: monday,
          dateStr: '2026-10-12',
          dayName: 'Mon',
          status: DayStatus.completed,
          primaryMuscle: 'Chest',
          plannedExerciseCount: 3,
          completedExerciseCount: 3,
          sessions: [
            WorkoutSession(
              date: '2026-10-12',
              startTime: '09:00',
              primaryMuscle: 'Chest',
              durationSeconds: 3000,
            ),
          ],
        ),
        DayWorkoutSummary(
          date: monday.add(const Duration(days: 1)),
          dateStr: '2026-10-13',
          dayName: 'Tue',
          status: DayStatus.restDay,
          primaryMuscle: null,
          plannedExerciseCount: 0,
          completedExerciseCount: 0,
          sessions: [],
        ),
        DayWorkoutSummary(
          date: sunday,
          dateStr: '2026-10-18',
          dayName: 'Sun',
          status: DayStatus.restDay,
          primaryMuscle: null,
          plannedExerciseCount: 0,
          completedExerciseCount: 0,
          sessions: [],
        ),
      ];

      final completedCount = days.where((d) => d.sessions.isNotEmpty).length;
      final restCount = days.where((d) => d.status == DayStatus.restDay).length;

      expect(completedCount, equals(1));
      expect(restCount, equals(2));

      final summary = WeeklySummary(
        startOfWeek: monday,
        endOfWeek: sunday,
        days: days,
        workoutsCompleted: completedCount,
        exercisesCompleted: 3,
        plannedWorkouts: 1,
        restDays: restCount,
        totalVolumeKg: 1500.0,
        totalDurationSeconds: 3000,
      );

      expect(summary.workoutsCompleted, equals(1));
      expect(summary.restDays, equals(2));
    });

    test('Planned vs Completed separation: editing a future plan does not alter past workout history', () {
      // Historical session on Monday
      final pastSession = WorkoutSession(
        id: 101,
        date: '2026-10-12',
        startTime: '10:00',
        endTime: '10:50',
        durationSeconds: 3000,
        primaryMuscle: 'Chest',
        secondaryMuscle: 'Triceps',
        notes: 'Great heavy bench day',
        sets: [
          WorkoutSetRecord(
            sessionId: 101,
            exerciseId: 1,
            exerciseName: 'Barbell Bench Press',
            setNumber: 1,
            reps: 10,
            weightKg: 80.0,
          ),
        ],
      );

      // Future plan on Friday
      final futurePlan = WorkoutPlan(
        id: 55,
        date: '2026-10-16',
        primaryMuscleName: 'Legs',
        secondaryMuscleName: 'Calves',
        exercises: [
          PlannedExercise(
            planId: 55,
            exerciseId: 10,
            exerciseName: 'Barbell Back Squat',
            targetSets: 4,
            targetReps: 8,
            targetWeightKg: 100.0,
          ),
        ],
      );

      // User edits future plan: changes to Shoulders & Abs
      final updatedFuturePlan = futurePlan.copyWith(
        primaryMuscleName: 'Shoulders',
        secondaryMuscleName: 'Abs and Core',
        exercises: [
          PlannedExercise(
            planId: 55,
            exerciseId: 25,
            exerciseName: 'Overhead Press',
            targetSets: 3,
            targetReps: 10,
          ),
        ],
      );

      // Past session remains completely intact
      expect(pastSession.primaryMuscle, equals('Chest'));
      expect(pastSession.secondaryMuscle, equals('Triceps'));
      expect(pastSession.sets.length, equals(1));
      expect(pastSession.sets.first.weightKg, equals(80.0));

      // Updated plan is reflected separately
      expect(updatedFuturePlan.primaryMuscleName, equals('Shoulders'));
      expect(
        updatedFuturePlan.exercises.first.exerciseName,
        equals('Overhead Press'),
      );
    });

    test('Muscle training frequency aggregates primary, secondary, and categories properly', () {
      final sessions = [
        WorkoutSession(
          date: '2026-10-12',
          startTime: '08:00',
          primaryMuscle: 'Chest',
          secondaryMuscle: 'Triceps',
        ),
        WorkoutSession(
          date: '2026-10-13',
          startTime: '08:00',
          primaryMuscle: 'Back',
          secondaryMuscle: 'Biceps',
        ),
        WorkoutSession(
          date: '2026-10-14',
          startTime: '08:00',
          primaryMuscle: 'Quadriceps',
          secondaryMuscle: 'Calves',
        ),
        WorkoutSession(
          date: '2026-10-15',
          startTime: '08:00',
          primaryMuscle: 'Chest',
          secondaryMuscle: 'Shoulders',
        ),
      ];

      final Map<String, int> counts = {
        'Chest': 0,
        'Back': 0,
        'Shoulders': 0,
        'Biceps': 0,
        'Triceps': 0,
        'Legs': 0,
        'Abs': 0,
        'Full Body': 0,
      };

      for (final s in sessions) {
        final muscles = [
          s.primaryMuscle,
          if (s.secondaryMuscle != null) s.secondaryMuscle!,
        ];
        for (final m in muscles) {
          final lower = m.toLowerCase();
          if (lower.contains('chest')) {
            counts['Chest'] = (counts['Chest'] ?? 0) + 1;
          }
          if (lower.contains('back')) {
            counts['Back'] = (counts['Back'] ?? 0) + 1;
          }
          if (lower.contains('shoulder')) {
            counts['Shoulders'] = (counts['Shoulders'] ?? 0) + 1;
          }
          if (lower.contains('bicep')) {
            counts['Biceps'] = (counts['Biceps'] ?? 0) + 1;
          }
          if (lower.contains('tricep')) {
            counts['Triceps'] = (counts['Triceps'] ?? 0) + 1;
          }
          if (lower.contains('quad') ||
              lower.contains('calv') ||
              lower.contains('calf') ||
              lower.contains('leg')) {
            counts['Legs'] = (counts['Legs'] ?? 0) + 1;
          }
        }
      }

      expect(counts['Chest'], equals(2));
      expect(counts['Back'], equals(1));
      expect(counts['Triceps'], equals(1));
      expect(counts['Biceps'], equals(1));
      expect(counts['Shoulders'], equals(1));
      expect(counts['Legs'], equals(2)); // Quads + Calves
    });
  });
}
