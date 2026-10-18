class ExerciseDemonstration {
  final int exerciseId;
  final String name;
  final String slug;
  final String muscleGroup;
  final String equipment;
  final bool hasVideo;
  final String mediaType; // 'video' | 'image'
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? imageFallbackPath;
  final String? localBundledPath;

  /// Object key of the video in the PRIVATE Supabase bucket `exercise-videos` (informational: the app asks the
  /// `video-url` function by exercise id; the server decides the real object). Null = no protected video.
  final String? storagePath;
  final int durationSeconds;
  final String license;
  final String attribution;
  final List<String> demonstrationCues;

  const ExerciseDemonstration({
    required this.exerciseId,
    required this.name,
    required this.slug,
    required this.muscleGroup,
    required this.equipment,
    required this.hasVideo,
    required this.mediaType,
    this.videoUrl,
    this.thumbnailUrl,
    this.imageFallbackPath,
    this.localBundledPath,
    this.storagePath,
    this.durationSeconds = 10,
    required this.license,
    required this.attribution,
    this.demonstrationCues = const [],
  });

  bool get isBundled =>
      localBundledPath != null && localBundledPath!.isNotEmpty;

  /// Has a video that is delivered on demand from the private bucket.
  bool get hasProtectedVideo =>
      hasVideo && storagePath != null && storagePath!.isNotEmpty;

  /// Same entry presented as NO_VIDEO (photo only). Used by the global
  /// kBundledVideosEnabled switch; nothing is deleted.
  ExerciseDemonstration withoutVideo() => ExerciseDemonstration(
    exerciseId: exerciseId,
    name: name,
    slug: slug,
    muscleGroup: muscleGroup,
    equipment: equipment,
    hasVideo: false,
    mediaType: 'image',
    videoUrl: null,
    thumbnailUrl: thumbnailUrl,
    imageFallbackPath: imageFallbackPath,
    localBundledPath: null,
    storagePath: null,
    durationSeconds: durationSeconds,
    license: license,
    attribution: attribution,
    demonstrationCues: demonstrationCues,
  );

  Map<String, dynamic> toMap() {
    return {
      'exercise_id': exerciseId,
      'name': name,
      'slug': slug,
      'muscle_group': muscleGroup,
      'equipment': equipment,
      'has_video': hasVideo,
      'media_type': mediaType,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'image_fallback_path': imageFallbackPath,
      'local_bundled_path': localBundledPath,
      'storage_path': storagePath,
      'duration_seconds': durationSeconds,
      'license': license,
      'attribution': attribution,
      'demonstration_cues': demonstrationCues,
    };
  }

  factory ExerciseDemonstration.fromMap(Map<String, dynamic> map) {
    return ExerciseDemonstration(
      exerciseId: map['exercise_id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      muscleGroup: map['muscle_group'] as String? ?? '',
      equipment: map['equipment'] as String? ?? '',
      hasVideo: map['has_video'] as bool? ?? false,
      mediaType: map['media_type'] as String? ?? 'image',
      videoUrl: map['video_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      imageFallbackPath: map['image_fallback_path'] as String?,
      localBundledPath: map['local_bundled_path'] as String?,
      storagePath: map['storage_path'] as String?,
      durationSeconds: map['duration_seconds'] as int? ?? 10,
      license: map['license'] as String? ?? 'UNVERIFIED',
      attribution: map['attribution'] as String? ?? '',
      demonstrationCues:
          (map['demonstration_cues'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
