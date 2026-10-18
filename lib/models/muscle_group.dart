import '../core/safe_cast.dart';

class MuscleGroup {
  final int? id;
  final String name;
  final String description;
  final String? imagePath;
  final bool isCustom;
  final String createdAt;

  MuscleGroup({
    this.id,
    required this.name,
    required this.description,
    this.imagePath,
    this.isCustom = false,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'image_path': imagePath,
      'is_custom': isCustom ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory MuscleGroup.fromMap(Map<String, dynamic> map) {
    return MuscleGroup(
      id: asInt(map['id']),
      name: (asStr(map['name']) ?? ''),
      description: asStr(map['description']) ?? '',
      imagePath: asStr(map['image_path']),
      isCustom: (asInt(map['is_custom'])) == 1,
      createdAt: asStr(map['created_at']),
    );
  }

  MuscleGroup copyWith({
    int? id,
    String? name,
    String? description,
    String? imagePath,
    bool? isCustom,
  }) {
    return MuscleGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imagePath: imagePath ?? this.imagePath,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt,
    );
  }
}
