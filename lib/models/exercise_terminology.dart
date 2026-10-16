class ExerciseTerminology {
  final int exerciseId;
  final String currentName;
  final String recommendedDisplayName;
  final String formalName;
  final List<String> aliases;
  final String keralaGymNotes;
  final String malayalamScript;
  final String status;
  final String reason;
  final String muscleGroup;
  final String equipment;

  const ExerciseTerminology({
    required this.exerciseId,
    required this.currentName,
    required this.recommendedDisplayName,
    required this.formalName,
    required this.aliases,
    required this.keralaGymNotes,
    required this.malayalamScript,
    required this.status,
    required this.reason,
    required this.muscleGroup,
    required this.equipment,
  });

  String get originalName => currentName;

  factory ExerciseTerminology.fromMap(Map<String, dynamic> map) {
    return ExerciseTerminology(
      exerciseId: map['exercise_id'] as int? ?? 0,
      currentName: map['current_name'] as String? ?? '',
      recommendedDisplayName: map['recommended_display_name'] as String? ?? '',
      formalName: map['formal_name'] as String? ?? '',
      aliases:
          (map['aliases'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      keralaGymNotes: map['kerala_gym_notes'] as String? ?? '',
      malayalamScript: map['malayalam_script'] as String? ?? '',
      status: map['status'] as String? ?? 'KEEP',
      reason: map['reason'] as String? ?? '',
      muscleGroup: map['muscle_group'] as String? ?? '',
      equipment: map['equipment'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'exercise_id': exerciseId,
      'current_name': currentName,
      'recommended_display_name': recommendedDisplayName,
      'formal_name': formalName,
      'aliases': aliases,
      'kerala_gym_notes': keralaGymNotes,
      'malayalam_script': malayalamScript,
      'status': status,
      'reason': reason,
      'muscle_group': muscleGroup,
      'equipment': equipment,
    };
  }
}
