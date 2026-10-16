class Exercise {
  final int? id;
  final int muscleGroupId;
  final String muscleGroupName;
  final String secondaryMuscles;
  final String name;
  final String target;
  final String description;
  final String startingPosition;
  final String instructions;
  final String breathingGuidance;
  final String beginnerModification;
  final String equipment;
  final String difficulty;
  final String suggestedSetsReps;
  final String commonMistakes;
  final int defaultSets;
  final int defaultReps;
  final double defaultWeightKg;
  final int restSeconds;
  final String? imagePath;
  final String? personalPhotoPath;
  final String? personalNotes;
  final String? trainerInstructions;
  final bool isCustom;
  final bool isRecommended;
  final bool isFavourite;
  final bool isCompound;
  final String createdAt;
  final String updatedAt;

  Exercise({
    this.id,
    required this.muscleGroupId,
    this.muscleGroupName = '',
    this.secondaryMuscles = '',
    required this.name,
    required this.target,
    required this.description,
    this.startingPosition = '',
    required this.instructions,
    this.breathingGuidance = '',
    this.beginnerModification = '',
    required this.equipment,
    this.difficulty = 'Intermediate',
    this.suggestedSetsReps = '3 sets × 8-12 reps',
    this.commonMistakes = '',
    this.defaultSets = 3,
    this.defaultReps = 10,
    this.defaultWeightKg = 15.0,
    this.restSeconds = 90,
    this.imagePath,
    this.personalPhotoPath,
    this.personalNotes,
    this.trainerInstructions,
    this.isCustom = false,
    this.isRecommended = true,
    this.isFavourite = false,
    this.isCompound = false,
    String? createdAt,
    String? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String(),
       updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'muscle_group_id': muscleGroupId,
      'muscle_group_name': muscleGroupName,
      'secondary_muscles': secondaryMuscles,
      'name': name,
      'target': target,
      'description': description,
      'starting_position': startingPosition,
      'instructions': instructions,
      'breathing_guidance': breathingGuidance,
      'beginner_modification': beginnerModification,
      'equipment': equipment,
      'difficulty': difficulty,
      'suggested_sets_reps': suggestedSetsReps,
      'common_mistakes': commonMistakes,
      'default_sets': defaultSets,
      'default_reps': defaultReps,
      'default_weight_kg': defaultWeightKg,
      'rest_seconds': restSeconds,
      'image_path': imagePath,
      'personal_photo_path': personalPhotoPath,
      'personal_notes': personalNotes,
      'trainer_instructions': trainerInstructions,
      'is_custom': isCustom ? 1 : 0,
      'is_recommended': isRecommended ? 1 : 0,
      'is_favourite': isFavourite ? 1 : 0,
      'is_compound': isCompound ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Exercise.fromMap(Map<String, dynamic> map) {
    return Exercise(
      id: map['id'] as int?,
      muscleGroupId: map['muscle_group_id'] as int? ?? 0,
      muscleGroupName: map['muscle_group_name'] as String? ?? '',
      secondaryMuscles: map['secondary_muscles'] as String? ?? '',
      name: map['name'] as String,
      target: map['target'] as String? ?? '',
      description: map['description'] as String? ?? '',
      startingPosition: map['starting_position'] as String? ?? '',
      instructions: map['instructions'] as String? ?? '',
      breathingGuidance: map['breathing_guidance'] as String? ?? '',
      beginnerModification: map['beginner_modification'] as String? ?? '',
      equipment: map['equipment'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? 'Intermediate',
      suggestedSetsReps:
          map['suggested_sets_reps'] as String? ?? '3 sets × 8-12 reps',
      commonMistakes: map['common_mistakes'] as String? ?? '',
      defaultSets: map['default_sets'] as int? ?? 3,
      defaultReps: map['default_reps'] as int? ?? 10,
      defaultWeightKg: (map['default_weight_kg'] as num?)?.toDouble() ?? 15.0,
      restSeconds: map['rest_seconds'] as int? ?? 90,
      imagePath: map['image_path'] as String?,
      personalPhotoPath: map['personal_photo_path'] as String?,
      personalNotes: map['personal_notes'] as String?,
      trainerInstructions: map['trainer_instructions'] as String?,
      isCustom: (map['is_custom'] as int?) == 1,
      isRecommended: (map['is_recommended'] as int?) != 0,
      isFavourite: (map['is_favourite'] as int?) == 1,
      isCompound: (map['is_compound'] as int?) == 1,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  Exercise copyWith({
    int? id,
    int? muscleGroupId,
    String? muscleGroupName,
    String? secondaryMuscles,
    String? name,
    String? target,
    String? description,
    String? startingPosition,
    String? instructions,
    String? breathingGuidance,
    String? beginnerModification,
    String? equipment,
    String? difficulty,
    String? suggestedSetsReps,
    String? commonMistakes,
    int? defaultSets,
    int? defaultReps,
    double? defaultWeightKg,
    int? restSeconds,
    String? imagePath,
    String? personalPhotoPath,
    String? personalNotes,
    String? trainerInstructions,
    bool? isCustom,
    bool? isRecommended,
    bool? isFavourite,
    bool? isCompound,
    String? updatedAt,
  }) {
    return Exercise(
      id: id ?? this.id,
      muscleGroupId: muscleGroupId ?? this.muscleGroupId,
      muscleGroupName: muscleGroupName ?? this.muscleGroupName,
      secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
      name: name ?? this.name,
      target: target ?? this.target,
      description: description ?? this.description,
      startingPosition: startingPosition ?? this.startingPosition,
      instructions: instructions ?? this.instructions,
      breathingGuidance: breathingGuidance ?? this.breathingGuidance,
      beginnerModification: beginnerModification ?? this.beginnerModification,
      equipment: equipment ?? this.equipment,
      difficulty: difficulty ?? this.difficulty,
      suggestedSetsReps: suggestedSetsReps ?? this.suggestedSetsReps,
      commonMistakes: commonMistakes ?? this.commonMistakes,
      defaultSets: defaultSets ?? this.defaultSets,
      defaultReps: defaultReps ?? this.defaultReps,
      defaultWeightKg: defaultWeightKg ?? this.defaultWeightKg,
      restSeconds: restSeconds ?? this.restSeconds,
      imagePath: imagePath ?? this.imagePath,
      personalPhotoPath: personalPhotoPath ?? this.personalPhotoPath,
      personalNotes: personalNotes ?? this.personalNotes,
      trainerInstructions: trainerInstructions ?? this.trainerInstructions,
      isCustom: isCustom ?? this.isCustom,
      isRecommended: isRecommended ?? this.isRecommended,
      isFavourite: isFavourite ?? this.isFavourite,
      isCompound: isCompound ?? this.isCompound,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toIso8601String(),
    );
  }
}
