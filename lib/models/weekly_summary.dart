import 'workout_plan.dart';
import 'workout_session.dart';

enum DayStatus {
  completed, // Session recorded and all planned sets/exercises completed
  partiallyCompleted, // Session recorded, but some sets/exercises were skipped
  planned, // Future or today's scheduled workout, not yet completed
  missed, // Past scheduled workout that was never performed
  restDay, // Scheduled or designated rest day
}

class DayWorkoutSummary {
  final DateTime date;
  final String dateStr; // YYYY-MM-DD
  final String dayName; // Mon, Tue, etc.
  final DayStatus status;
  final String? primaryMuscle;
  final String? secondaryMuscle;
  final int plannedExerciseCount;
  final int completedExerciseCount;
  final WorkoutPlan? plan;
  final List<WorkoutSession> sessions;
  final bool isToday;

  DayWorkoutSummary({
    required this.date,
    required this.dateStr,
    required this.dayName,
    required this.status,
    this.primaryMuscle,
    this.secondaryMuscle,
    this.plannedExerciseCount = 0,
    this.completedExerciseCount = 0,
    this.plan,
    this.sessions = const [],
    this.isToday = false,
  });

  String get statusLabel {
    switch (status) {
      case DayStatus.completed:
        return 'Completed';
      case DayStatus.partiallyCompleted:
        return 'Partially Completed';
      case DayStatus.planned:
        return 'Planned';
      case DayStatus.missed:
        return 'Missed';
      case DayStatus.restDay:
        return 'Rest Day';
    }
  }
}

class WeeklySummary {
  final DateTime startOfWeek; // Monday
  final DateTime endOfWeek; // Sunday
  final List<DayWorkoutSummary> days; // 7 days (Mon to Sun)
  final int workoutsCompleted;
  final int exercisesCompleted;
  final int plannedWorkouts;
  final int restDays;
  final double totalVolumeKg;
  final int totalDurationSeconds;

  WeeklySummary({
    required this.startOfWeek,
    required this.endOfWeek,
    required this.days,
    required this.workoutsCompleted,
    required this.exercisesCompleted,
    required this.plannedWorkouts,
    required this.restDays,
    required this.totalVolumeKg,
    required this.totalDurationSeconds,
  });
}
