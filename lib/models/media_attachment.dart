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
      id: map['id'] as int?,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as int,
      mediaType: map['media_type'] as String,
      filePath: map['file_path'] as String,
      title: map['title'] as String? ?? 'Attachment',
      description: map['description'] as String?,
      durationSeconds: map['duration_seconds'] as int?,
      createdAt: map['created_at'] as String?,
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
