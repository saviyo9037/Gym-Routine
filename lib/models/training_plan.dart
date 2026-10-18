import '../core/safe_cast.dart';
import 'workout_plan.dart';

/// Cardio detection shared by plan editor, active workout and stats.
bool isCardioExercise({
  String muscleGroup = '',
  String equipment = '',
  String name = '',
}) {
  final m = muscleGroup.toLowerCase();
  final e = equipment.toLowerCase();
  final n = name.toLowerCase();
  return m.contains('cardio') ||
      e.contains('treadmill') ||
      e.contains('bike') ||
      e.contains('elliptical') ||
      e.contains('rowing') ||
      e.contains('stair') ||
      e.contains('jump rope') ||
      n.contains('treadmill') ||
      n.contains('cycling') ||
      n.contains('elliptical') ||
      n.contains('rowing machine') ||
      n.contains('stair climber') ||
      n.contains('jump rope') ||
      n.contains('jumping jacks') ||
      n.contains('high knees') ||
      n.contains('outdoor run') ||
      n.contains('outdoor walk');
}

/// One exercise slot inside a training-plan day.
class TrainingPlanExercise {
  final int? id;
  final int? dayId;
  final int exerciseId;
  final String exerciseName;
  final String muscleGroupName;
  final int exerciseOrder;
  final int targetSets;
  final int targetReps;
  final double targetWeightKg;
  final int restSeconds;
  final int? targetDurationSeconds;
  final double? targetDistanceKm;
  final String? notes;

  const TrainingPlanExercise({
    this.id,
    this.dayId,
    required this.exerciseId,
    required this.exerciseName,
    this.muscleGroupName = '',
    this.exerciseOrder = 0,
    this.targetSets = 3,
    this.targetReps = 10,
    this.targetWeightKg = 0,
    this.restSeconds = 90,
    this.targetDurationSeconds,
    this.targetDistanceKm,
    this.notes,
  });

  bool get isCardio =>
      isCardioExercise(muscleGroup: muscleGroupName, name: exerciseName);

  Map<String, dynamic> toMap() => {
    'id': id,
    'day_id': dayId,
    'exercise_id': exerciseId,
    'exercise_name': exerciseName,
    'muscle_group_name': muscleGroupName,
    'exercise_order': exerciseOrder,
    'target_sets': targetSets,
    'target_reps': targetReps,
    'target_weight_kg': targetWeightKg,
    'rest_seconds': restSeconds,
    'target_duration_seconds': targetDurationSeconds,
    'target_distance_km': targetDistanceKm,
    'notes': notes,
  };

  factory TrainingPlanExercise.fromMap(Map<String, dynamic> m) =>
      TrainingPlanExercise(
        id: asInt(m['id']),
        dayId: asInt(m['day_id']),
        exerciseId: asInt(m['exercise_id']) ?? 0,
        exerciseName: asStr(m['exercise_name']) ?? 'Exercise',
        muscleGroupName: asStr(m['muscle_group_name']) ?? '',
        exerciseOrder: asInt(m['exercise_order']) ?? 0,
        targetSets: asInt(m['target_sets']) ?? 3,
        targetReps: asInt(m['target_reps']) ?? 10,
        targetWeightKg: asDouble(m['target_weight_kg']) ?? 0,
        restSeconds: asInt(m['rest_seconds']) ?? 90,
        targetDurationSeconds: asInt(m['target_duration_seconds']),
        targetDistanceKm: asDouble(m['target_distance_km']),
        notes: asStr(m['notes']),
      );

  TrainingPlanExercise copyWith({
    int? exerciseOrder,
    int? targetSets,
    int? targetReps,
    double? targetWeightKg,
    int? restSeconds,
    int? targetDurationSeconds,
    double? targetDistanceKm,
    String? notes,
  }) => TrainingPlanExercise(
    id: id,
    dayId: dayId,
    exerciseId: exerciseId,
    exerciseName: exerciseName,
    muscleGroupName: muscleGroupName,
    exerciseOrder: exerciseOrder ?? this.exerciseOrder,
    targetSets: targetSets ?? this.targetSets,
    targetReps: targetReps ?? this.targetReps,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    restSeconds: restSeconds ?? this.restSeconds,
    targetDurationSeconds: targetDurationSeconds ?? this.targetDurationSeconds,
    targetDistanceKm: targetDistanceKm ?? this.targetDistanceKm,
    notes: notes ?? this.notes,
  );

  PlannedExercise toPlanned(int planId, int order) => PlannedExercise(
    planId: planId,
    exerciseId: exerciseId,
    exerciseName: exerciseName,
    muscleGroupName: muscleGroupName,
    exerciseOrder: order,
    targetSets: targetSets,
    targetReps: targetReps,
    targetWeightKg: targetWeightKg,
    restSeconds: restSeconds,
    notes: notes,
    targetDurationSeconds: targetDurationSeconds,
    targetDistanceKm: targetDistanceKm,
  );
}

/// One weekday of a training plan. [weekday] follows DateTime (1=Mon..7=Sun).
class TrainingPlanDay {
  final int? id;
  final int weekday;
  final bool isRest;
  final String? title;
  final String? notes;
  final List<TrainingPlanExercise> exercises;

  const TrainingPlanDay({
    this.id,
    required this.weekday,
    this.isRest = false,
    this.title,
    this.notes,
    this.exercises = const [],
  });

  TrainingPlanDay copyWith({
    bool? isRest,
    String? title,
    String? notes,
    List<TrainingPlanExercise>? exercises,
  }) => TrainingPlanDay(
    id: id,
    weekday: weekday,
    isRest: isRest ?? this.isRest,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    exercises: exercises ?? this.exercises,
  );
}

class TrainingPlan {
  final int? id;
  final String name;
  final String? notes;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  /// Always 7 entries, Monday..Sunday, once loaded through the service.
  final List<TrainingPlanDay> days;

  TrainingPlan({
    this.id,
    required this.name,
    this.notes,
    this.isActive = false,
    String? createdAt,
    String? updatedAt,
    List<TrainingPlanDay>? days,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String(),
       updatedAt = updatedAt ?? DateTime.now().toIso8601String(),
       days = days ?? defaultDays();

  static List<TrainingPlanDay> defaultDays() => [
    for (var d = 1; d <= 7; d++) TrainingPlanDay(weekday: d, isRest: d == 7),
  ];

  int get trainingDayCount => days.where((d) => !d.isRest).length;
  int get exerciseCount =>
      days.where((d) => !d.isRest).fold(0, (n, d) => n + d.exercises.length);

  TrainingPlanDay dayFor(int weekday) => days.firstWhere(
    (d) => d.weekday == weekday,
    orElse: () => TrainingPlanDay(weekday: weekday, isRest: true),
  );

  TrainingPlan copyWith({
    String? name,
    String? notes,
    bool? isActive,
    List<TrainingPlanDay>? days,
  }) => TrainingPlan(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: DateTime.now().toIso8601String(),
    days: days ?? this.days,
  );
}

/// Pure validation, shared by the editor UI and the service.
class TrainingPlanValidator {
  static const maxNameLength = 60;

  static String? validateName(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'Enter a plan name';
    if (n.length > maxNameLength) {
      return 'Keep the name under $maxNameLength characters';
    }
    return null;
  }

  static String? validateExercise(TrainingPlanExercise e) {
    if (e.targetSets < 1 || e.targetSets > 20) return 'Sets must be 1-20';
    if (e.isCardio) {
      final d = e.targetDurationSeconds;
      final km = e.targetDistanceKm;
      if ((d == null || d <= 0) && (km == null || km <= 0)) {
        return 'Enter a time or a distance';
      }
      if (d != null && (d < 0 || d > 6 * 3600)) {
        return 'Time must be under 6 hours';
      }
      if (km != null && (km < 0 || km > 500)) {
        return 'Distance must be 0-500 km';
      }
    } else {
      if (e.targetReps < 1 || e.targetReps > 200) return 'Reps must be 1-200';
      if (e.targetWeightKg < 0 || e.targetWeightKg > 1000) {
        return 'Weight must be 0-1000 kg';
      }
    }
    if (e.restSeconds < 0 || e.restSeconds > 1800) {
      return 'Rest must be 0-1800 s';
    }
    return null;
  }

  /// Exercise ids that appear more than once in [day].
  static Set<int> duplicateExerciseIds(TrainingPlanDay day) {
    final seen = <int>{};
    final dup = <int>{};
    for (final e in day.exercises) {
      if (!seen.add(e.exerciseId)) dup.add(e.exerciseId);
    }
    return dup;
  }
}
