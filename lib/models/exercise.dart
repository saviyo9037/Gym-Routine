import '../core/safe_cast.dart';

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
      id: asInt(map['id']),
      muscleGroupId: asInt(map['muscle_group_id']) ?? 0,
      muscleGroupName: asStr(map['muscle_group_name']) ?? '',
      secondaryMuscles: asStr(map['secondary_muscles']) ?? '',
      name: (asStr(map['name']) ?? ''),
      target: asStr(map['target']) ?? '',
      description: asStr(map['description']) ?? '',
      startingPosition: asStr(map['starting_position']) ?? '',
      instructions: asStr(map['instructions']) ?? '',
      breathingGuidance: asStr(map['breathing_guidance']) ?? '',
      beginnerModification: asStr(map['beginner_modification']) ?? '',
      equipment: asStr(map['equipment']) ?? '',
      difficulty: asStr(map['difficulty']) ?? 'Intermediate',
      suggestedSetsReps:
          asStr(map['suggested_sets_reps']) ?? '3 sets × 8-12 reps',
      commonMistakes: asStr(map['common_mistakes']) ?? '',
      defaultSets: asInt(map['default_sets']) ?? 3,
      defaultReps: asInt(map['default_reps']) ?? 10,
      defaultWeightKg: asDouble(map['default_weight_kg']) ?? 15.0,
      restSeconds: asInt(map['rest_seconds']) ?? 90,
      imagePath: asStr(map['image_path']),
      personalPhotoPath: asStr(map['personal_photo_path']),
      personalNotes: asStr(map['personal_notes']),
      trainerInstructions: asStr(map['trainer_instructions']),
      isCustom: (asInt(map['is_custom'])) == 1,
      isRecommended: (asInt(map['is_recommended'])) != 0,
      isFavourite: (asInt(map['is_favourite'])) == 1,
      isCompound: (asInt(map['is_compound'])) == 1,
      createdAt: asStr(map['created_at']),
      updatedAt: asStr(map['updated_at']),
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
