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
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
      id: map['id'] as int?,
      planId: map['plan_id'] as int?,
      date: map['date'] as String,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String?,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      primaryMuscle: map['primary_muscle'] as String? ?? 'General',
      secondaryMuscle: map['secondary_muscle'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String?,
      sets: sets,
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
  double get totalVolumeKg => sets
      .where((s) => s.isCompleted)
      .fold(0.0, (acc, s) => acc + (s.weightKg * s.reps));

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
    };
  }

  factory WorkoutSetRecord.fromMap(Map<String, dynamic> map) {
    return WorkoutSetRecord(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int? ?? 0,
      exerciseId: map['exercise_id'] as int? ?? 0,
      exerciseName: map['exercise_name'] as String? ?? 'Exercise',
      setNumber: map['set_number'] as int? ?? 1,
      reps: map['reps'] as int? ?? 0,
      weightKg: (map['weight_kg'] as num?)?.toDouble() ?? 0.0,
      isCompleted: (map['is_completed'] as int?) == 1,
      completedAt:
          map['completed_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}
