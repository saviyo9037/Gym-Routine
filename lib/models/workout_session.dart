import '../core/safe_cast.dart';
import 'training_plan.dart' show isCardioExercise;

class WorkoutSession {
  final int? id;
  final int? planId;
  final String date;
  final String startTime;
  final String? endTime;
  final int durationSeconds;
  final String primaryMuscle;
  final String? secondaryMuscle;
  final String? notes;
  final String createdAt;
  final List<WorkoutSetRecord> sets;

  /// Idempotency key: a session finished twice with the same key is saved once.
  final String? clientRef;

  WorkoutSession({
    this.id,
    this.planId,
    required this.date,
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    required this.primaryMuscle,
    this.secondaryMuscle,
    this.notes,
    String? createdAt,
    this.sets = const [],
    this.clientRef,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_ref': clientRef,
      'plan_id': planId,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      'duration_seconds': durationSeconds,
      'primary_muscle': primaryMuscle,
      'secondary_muscle': secondaryMuscle,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory WorkoutSession.fromMap(
    Map<String, dynamic> map, {
    List<WorkoutSetRecord> sets = const [],
  }) {
    return WorkoutSession(
      id: asInt(map['id']),
      planId: asInt(map['plan_id']),
      date: (asStr(map['date']) ?? ''),
      startTime: (asStr(map['start_time']) ?? ''),
      endTime: asStr(map['end_time']),
      durationSeconds: asInt(map['duration_seconds']) ?? 0,
      primaryMuscle: asStr(map['primary_muscle']) ?? 'General',
      secondaryMuscle: asStr(map['secondary_muscle']),
      notes: asStr(map['notes']),
      createdAt: asStr(map['created_at']),
      sets: sets,
      clientRef: asStr(map['client_ref']),
    );
  }

  WorkoutSession copyWith({
    int? id,
    int? planId,
    String? date,
    String? startTime,
    String? endTime,
    int? durationSeconds,
    String? primaryMuscle,
    String? secondaryMuscle,
    String? notes,
    List<WorkoutSetRecord>? sets,
  }) {
    return WorkoutSession(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      primaryMuscle: primaryMuscle ?? this.primaryMuscle,
      secondaryMuscle: secondaryMuscle ?? this.secondaryMuscle,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      sets: sets ?? this.sets,
    );
  }

  int get completedSetsCount => sets.where((s) => s.isCompleted).length;
  int get totalSetsCount => sets.length;

  /// A session counts as a performed workout only if at least one set was
  /// completed; an abandoned/empty session is kept in history but never
  /// counted as training.
  bool get isEffective => completedSetsCount > 0;

  /// Strength volume (kg x reps) of completed sets. Cardio is excluded.
  double get totalVolumeKg => sets
      .where((s) => s.isCompleted && !s.isCardio)
      .fold(0.0, (acc, s) => acc + (s.weightKg * s.reps));

  /// Completed cardio time in seconds (legacy rows stored minutes in reps).
  int get cardioSeconds => sets
      .where((s) => s.isCompleted && s.isCardio)
      .fold(0, (acc, s) => acc + s.cardioSeconds);

  /// Completed cardio distance in km (legacy rows stored km in weight).
  double get cardioKm => sets
      .where((s) => s.isCompleted && s.isCardio)
      .fold(0.0, (acc, s) => acc + s.cardioKm);

  List<String> get completedExerciseNames => sets
      .where((s) => s.isCompleted)
      .map((s) => s.exerciseName)
      .toSet()
      .toList();

  List<String> get allExerciseNames =>
      sets.map((s) => s.exerciseName).toSet().toList();

  String get completionStatus {
    if (sets.isEmpty) return 'Incomplete';
    if (sets.any((s) => !s.isCompleted)) return 'Partially Completed';
    return 'Completed';
  }
}

class WorkoutSetRecord {
  final int? id;
  final int sessionId;
  final int exerciseId;
  final String exerciseName;
  final int setNumber;
  final int reps;
  final double weightKg;
  final bool isCompleted;
  final String completedAt;
  final int? durationSeconds;
  final double? distanceKm;

  WorkoutSetRecord({
    this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.exerciseName,
    required this.setNumber,
    required this.reps,
    required this.weightKg,
    this.isCompleted = true,
    String? completedAt,
    this.durationSeconds,
    this.distanceKm,
  }) : completedAt = completedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'exercise_id': exerciseId,
      'exercise_name': exerciseName,
      'set_number': setNumber,
      'reps': reps,
      'weight_kg': weightKg,
      'is_completed': isCompleted ? 1 : 0,
      'completed_at': completedAt,
      'duration_seconds': durationSeconds,
      'distance_km': distanceKm,
    };
  }

  /// Cardio set: has the dedicated columns, or (legacy rows) a cardio name.
  bool get isCardio =>
      durationSeconds != null ||
      distanceKm != null ||
      isCardioExercise(name: exerciseName);

  int get cardioSeconds => durationSeconds ?? reps * 60;

  double get cardioKm => distanceKm ?? weightKg;

  factory WorkoutSetRecord.fromMap(Map<String, dynamic> map) {
    return WorkoutSetRecord(
      id: asInt(map['id']),
      sessionId: asInt(map['session_id']) ?? 0,
      exerciseId: asInt(map['exercise_id']) ?? 0,
      exerciseName: asStr(map['exercise_name']) ?? 'Exercise',
      setNumber: asInt(map['set_number']) ?? 1,
      reps: asInt(map['reps']) ?? 0,
      weightKg: asDouble(map['weight_kg']) ?? 0.0,
      isCompleted: (asInt(map['is_completed'])) == 1,
      completedAt:
          asStr(map['completed_at']) ?? DateTime.now().toIso8601String(),
      durationSeconds: asInt(map['duration_seconds']),
      distanceKm: asDouble(map['distance_km']),
    );
  }
}
