import '../core/safe_cast.dart';
import 'exercise.dart';

class WorkoutPlan {
  final int? id;
  final String date; // YYYY-MM-DD
  final int? primaryMuscleId;
  final String? primaryMuscleName;
  final int? secondaryMuscleId;
  final String? secondaryMuscleName;
  final String? notes;
  final String? trainerInstructions;
  final bool isCompleted;
  final bool isRestDay;
  final String createdAt;
  final String updatedAt;
  final List<PlannedExercise> exercises;

  WorkoutPlan({
    this.id,
    required this.date,
    this.primaryMuscleId,
    this.primaryMuscleName,
    this.secondaryMuscleId,
    this.secondaryMuscleName,
    this.notes,
    this.trainerInstructions,
    this.isCompleted = false,
    this.isRestDay = false,
    String? createdAt,
    String? updatedAt,
    this.exercises = const [],
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String(),
       updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'primary_muscle_id': primaryMuscleId,
      'primary_muscle_name': primaryMuscleName,
      'secondary_muscle_id': secondaryMuscleId,
      'secondary_muscle_name': secondaryMuscleName,
      'notes': notes,
      'trainer_instructions': trainerInstructions,
      'is_completed': isCompleted ? 1 : 0,
      'is_rest_day': isRestDay ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory WorkoutPlan.fromMap(
    Map<String, dynamic> map, {
    List<PlannedExercise> exercises = const [],
  }) {
    return WorkoutPlan(
      id: asInt(map['id']),
      date: (asStr(map['date']) ?? ''),
      primaryMuscleId: asInt(map['primary_muscle_id']),
      primaryMuscleName: asStr(map['primary_muscle_name']),
      secondaryMuscleId: asInt(map['secondary_muscle_id']),
      secondaryMuscleName: asStr(map['secondary_muscle_name']),
      notes: asStr(map['notes']),
      trainerInstructions: asStr(map['trainer_instructions']),
      isCompleted: (asInt(map['is_completed'])) == 1,
      isRestDay: (asInt(map['is_rest_day'])) == 1,
      createdAt: asStr(map['created_at']),
      updatedAt: asStr(map['updated_at']),
      exercises: exercises,
    );
  }

  WorkoutPlan copyWith({
    int? id,
    String? date,
    int? primaryMuscleId,
    String? primaryMuscleName,
    int? secondaryMuscleId,
    String? secondaryMuscleName,
    String? notes,
    String? trainerInstructions,
    bool? isCompleted,
    bool? isRestDay,
    String? updatedAt,
    List<PlannedExercise>? exercises,
  }) {
    return WorkoutPlan(
      id: id ?? this.id,
      date: date ?? this.date,
      primaryMuscleId: primaryMuscleId ?? this.primaryMuscleId,
      primaryMuscleName: primaryMuscleName ?? this.primaryMuscleName,
      secondaryMuscleId: secondaryMuscleId ?? this.secondaryMuscleId,
      secondaryMuscleName: secondaryMuscleName ?? this.secondaryMuscleName,
      notes: notes ?? this.notes,
      trainerInstructions: trainerInstructions ?? this.trainerInstructions,
      isCompleted: isCompleted ?? this.isCompleted,
      isRestDay: isRestDay ?? this.isRestDay,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toIso8601String(),
      exercises: exercises ?? this.exercises,
    );
  }
}

class PlannedExercise {
  final int? id;
  final int planId;
  final int exerciseId;
  final String exerciseName;
  final String muscleGroupName;
  final int exerciseOrder;
  final int targetSets;
  final int targetReps;
  final double targetWeightKg;
  final int restSeconds;
  final String? notes;
  final String? imagePath;
  final Exercise? exercise;

  /// Cardio targets (null for strength work).
  final int? targetDurationSeconds;
  final double? targetDistanceKm;

  PlannedExercise({
    this.id,
    required this.planId,
    required this.exerciseId,
    required this.exerciseName,
    this.muscleGroupName = '',
    this.exerciseOrder = 0,
    this.targetSets = 3,
    this.targetReps = 10,
    this.targetWeightKg = 15.0,
    this.restSeconds = 90,
    this.notes,
    this.imagePath,
    this.exercise,
    this.targetDurationSeconds,
    this.targetDistanceKm,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'plan_id': planId,
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'muscle_group_name': muscleGroupName,
      'exercise_order': exerciseOrder,
      'target_sets': targetSets,
      'target_reps': targetReps,
      'target_weight_kg': targetWeightKg,
      'rest_seconds': restSeconds,
      'notes': notes,
      'image_path': imagePath,
      'target_duration_seconds': targetDurationSeconds,
      'target_distance_km': targetDistanceKm,
    };
  }

  factory PlannedExercise.fromMap(
    Map<String, dynamic> map, {
    Exercise? exercise,
  }) {
    return PlannedExercise(
      id: asInt(map['id']),
      planId: asInt(map['plan_id']) ?? 0,
      exerciseId: asInt(map['exercise_id']) ?? 0,
      exerciseName:
          asStr(map['exercise_name']) ?? (exercise?.name ?? 'Exercise'),
      muscleGroupName:
          asStr(map['muscle_group_name']) ?? (exercise?.muscleGroupName ?? ''),
      exerciseOrder: asInt(map['exercise_order']) ?? 0,
      targetSets: asInt(map['target_sets']) ?? (exercise?.defaultSets ?? 3),
      targetReps: asInt(map['target_reps']) ?? (exercise?.defaultReps ?? 10),
      targetWeightKg:
          asDouble(map['target_weight_kg']) ??
          (exercise?.defaultWeightKg ?? 15.0),
      restSeconds: asInt(map['rest_seconds']) ?? (exercise?.restSeconds ?? 90),
      notes: asStr(map['notes']),
      imagePath: asStr(map['image_path']) ?? exercise?.imagePath,
      exercise: exercise,
      targetDurationSeconds: asInt(map['target_duration_seconds']),
      targetDistanceKm: asDouble(map['target_distance_km']),
    );
  }

  PlannedExercise copyWith({
    int? id,
    int? planId,
    int? exerciseId,
    String? exerciseName,
    String? muscleGroupName,
    int? exerciseOrder,
    int? targetSets,
    int? targetReps,
    double? targetWeightKg,
    int? restSeconds,
    String? notes,
    String? imagePath,
    Exercise? exercise,
    int? targetDurationSeconds,
    double? targetDistanceKm,
  }) {
    return PlannedExercise(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      muscleGroupName: muscleGroupName ?? this.muscleGroupName,
      exerciseOrder: exerciseOrder ?? this.exerciseOrder,
      targetSets: targetSets ?? this.targetSets,
      targetReps: targetReps ?? this.targetReps,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      restSeconds: restSeconds ?? this.restSeconds,
      notes: notes ?? this.notes,
      imagePath: imagePath ?? this.imagePath,
      exercise: exercise ?? this.exercise,
      targetDurationSeconds:
          targetDurationSeconds ?? this.targetDurationSeconds,
      targetDistanceKm: targetDistanceKm ?? this.targetDistanceKm,
    );
  }
}
