import '../core/safe_cast.dart';

class MediaAttachment {
  final int? id;
  final String entityType; // 'muscle', 'exercise', 'plan', 'session'
  final int entityId;
  final String mediaType; // 'photo', 'video', 'audio'
  final String filePath;
  final String title;
  final String? description;
  final int? durationSeconds;
  final String createdAt;

  MediaAttachment({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.mediaType,
    required this.filePath,
    required this.title,
    this.description,
    this.durationSeconds,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'media_type': mediaType,
      'file_path': filePath,
      'title': title,
      'description': description,
      'duration_seconds': durationSeconds,
      'created_at': createdAt,
    };
  }

  factory MediaAttachment.fromMap(Map<String, dynamic> map) {
    return MediaAttachment(
      id: asInt(map['id']),
      entityType: (asStr(map['entity_type']) ?? ''),
      entityId: (asInt(map['entity_id']) ?? 0),
      mediaType: (asStr(map['media_type']) ?? ''),
      filePath: (asStr(map['file_path']) ?? ''),
      title: asStr(map['title']) ?? 'Attachment',
      description: asStr(map['description']),
      durationSeconds: asInt(map['duration_seconds']),
      createdAt: asStr(map['created_at']),
    );
  }

  MediaAttachment copyWith({
    int? id,
    String? entityType,
    int? entityId,
    String? mediaType,
    String? filePath,
    String? title,
    String? description,
    int? durationSeconds,
    String? createdAt,
  }) {
    return MediaAttachment(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      mediaType: mediaType ?? this.mediaType,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      description: description ?? this.description,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
