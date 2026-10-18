import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/media_config.dart';
import '../models/exercise_demonstration.dart';
import 'video_access_service.dart';

enum DemonstrationSourceType {
  /// Legacy/dev only: a video packaged in the app (release builds bundle none).
  bundledAsset,

  /// A protected video already in the private on-device cache.
  downloadedFile,

  /// Legacy remote stream (no longer produced: third-party URLs are not used).
  remoteNetwork,

  /// Photo only: NO_VIDEO exercise, or videos switched off.
  photoFallback,

  /// The exercise HAS a protected video and the user may watch it, but it is not
  /// on the device yet: the player downloads it now (on demand, per exercise).
  protectedDownload,

  /// The exercise has a video but the user has no active subscription/trial:
  /// photo plus a short explanation, never the video.
  lockedPhoto,

  /// TRIAL tier: the exercise has a video, but videos are locked during the
  /// trial. Blurred photo + "unlock with a full subscription" + Subscribe.
  /// No controller, no signed-URL request, no download.
  trialLockedPhoto,
}

class DemonstrationMediaSource {
  final DemonstrationSourceType type;
  final String uri;
  final bool isOfflineReady;
  final String? localFilePath;

  /// Set for [DemonstrationSourceType.protectedDownload] / [lockedPhoto].
  final int? exerciseId;

  /// Photo to show underneath (all types).
  final String? photoPath;

  const DemonstrationMediaSource({
    required this.type,
    required this.uri,
    required this.isOfflineReady,
    this.localFilePath,
    this.exerciseId,
    this.photoPath,
  });
}

class ExerciseMediaService {
  static final ExerciseMediaService instance = ExerciseMediaService._internal();

  ExerciseMediaService._internal();

  bool _isInitialized = false;
  bool? _videosEnabledOverride;
  VideoAccessService? _accessOverride;

  /// Delivery of protected videos (entitlement check + on-demand cache).
  VideoAccessService get access =>
      _accessOverride ?? VideoAccessService.instance;

  @visibleForTesting
  set accessForTesting(VideoAccessService? value) => _accessOverride = value;

  /// Effective value of the global video switch ([kBundledVideosEnabled]
  /// unless a test overrides it).
  bool get videosEnabled => _videosEnabledOverride ?? kBundledVideosEnabled;

  @visibleForTesting
  set videosEnabledForTesting(bool? value) => _videosEnabledOverride = value;

  ExerciseDemonstration? _effective(ExerciseDemonstration? demo) {
    if (demo == null || videosEnabled || !demo.hasVideo) return demo;
    return demo.withoutVideo();
  }

  final Map<String, ExerciseDemonstration> _registryByName = {};
  final Map<int, ExerciseDemonstration> _registryById = {};

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final jsonStr = await rootBundle.loadString(
        'assets/exercise_demonstrations.json',
      );
      final Map<String, dynamic> rawMap = json.decode(jsonStr);

      _registryByName.clear();
      _registryById.clear();

      for (final entry in rawMap.entries) {
        final demo = ExerciseDemonstration.fromMap(
          Map<String, dynamic>.from(entry.value as Map),
        );
        _registryByName[entry.key] = demo;
        _registryByName[_normalize(entry.key)] = demo;
        if (demo.exerciseId > 0) {
          _registryById[demo.exerciseId] = demo;
        }
      }

      // Also ingest aliases from exercise_terminology.json
      try {
        final termStr = await rootBundle.loadString(
          'assets/exercise_terminology.json',
        );
        final Map<String, dynamic> termMap = json.decode(termStr);
        for (final item in termMap.values) {
          if (item is Map) {
            final exId = item['exercise_id'] as int?;
            final demo = exId != null ? _registryById[exId] : null;
            if (demo != null) {
              final recName = item['recommended_display_name'] as String?;
              if (recName != null && recName.isNotEmpty) {
                _registryByName.putIfAbsent(recName, () => demo);
                _registryByName.putIfAbsent(_normalize(recName), () => demo);
              }
              final aliases = item['aliases'] as List<dynamic>?;
              if (aliases != null) {
                for (final a in aliases) {
                  final aStr = a.toString();
                  if (aStr.isNotEmpty) {
                    _registryByName.putIfAbsent(aStr, () => demo);
                    _registryByName.putIfAbsent(_normalize(aStr), () => demo);
                  }
                }
              }
            }
          }
        }
      } catch (_) {}

      // Common universal shortcuts
      final benchDemo = _registryById[1];
      if (benchDemo != null) {
        _registryByName.putIfAbsent('Bench Press', () => benchDemo);
        _registryByName.putIfAbsent('benchpress', () => benchDemo);
      }

      _isInitialized = true;
    } catch (e) {
      // Graceful fallback if asset cannot be parsed during early tests
      _isInitialized = true;
    }
  }

  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  ExerciseDemonstration? getDemonstration(String name) {
    if (_registryByName.containsKey(name)) {
      return _effective(_registryByName[name]);
    }
    return _effective(_registryByName[_normalize(name)]);
  }

  ExerciseDemonstration? getDemonstrationById(int id) {
    return _effective(_registryById[id]);
  }

  bool hasDemonstration(String name, {int? exerciseId}) {
    ExerciseDemonstration? demo;
    if (name.isNotEmpty) {
      demo = getDemonstration(name);
    }
    if (demo == null && exerciseId != null && exerciseId > 0) {
      demo = getDemonstrationById(exerciseId);
    }
    return demo != null && demo.hasVideo;
  }

  Future<Directory> _getDemonstrationsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final demoDir = Directory(p.join(appDir.path, 'demonstrations'));
    if (!await demoDir.exists()) {
      await demoDir.create(recursive: true);
    }
    return demoDir;
  }

  Future<File> _getCachedFileForExercise(
    String exerciseName, {
    int? exerciseId,
  }) async {
    final dir = await _getDemonstrationsDirectory();
    final prefix = exerciseId != null && exerciseId > 0
        ? 'ex_${exerciseId}_'
        : '';
    final slug = _normalize(exerciseName);
    return File(p.join(dir.path, '$prefix$slug.mp4'));
  }

  Future<bool> isDownloaded(String exerciseName, {int? exerciseId}) async {
    try {
      final file = await _getCachedFileForExercise(
        exerciseName,
        exerciseId: exerciseId,
      );
      return await file.exists() && (await file.length()) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getLocalCachedVideoPath(
    String exerciseName, {
    int? exerciseId,
  }) async {
    try {
      final file = await _getCachedFileForExercise(
        exerciseName,
        exerciseId: exerciseId,
      );
      if (await file.exists() && (await file.length()) > 0) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  Future<DemonstrationMediaSource> resolveMediaSource(
    String exerciseName, {
    int? exerciseId,
    String? fallbackImagePath,
  }) async {
    await initialize();
    if (!videosEnabled) {
      // Global kill switch: photo only, no controller, no remote stream.
      final demo =
          (exerciseName.isNotEmpty ? getDemonstration(exerciseName) : null) ??
          (exerciseId != null && exerciseId > 0
              ? getDemonstrationById(exerciseId)
              : null);
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.photoFallback,
        uri: fallbackImagePath ?? demo?.imageFallbackPath ?? '',
        isOfflineReady: true,
      );
    }
    ExerciseDemonstration? demo;
    if (exerciseName.isNotEmpty) {
      demo = getDemonstration(exerciseName);
    }
    if (demo == null && exerciseId != null && exerciseId > 0) {
      demo = getDemonstrationById(exerciseId);
    }

    if (demo == null || !demo.hasVideo) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.photoFallback,
        uri: fallbackImagePath ?? demo?.imageFallbackPath ?? '',
        isOfflineReady: true,
      );
    }

    final photo = fallbackImagePath ?? demo.imageFallbackPath ?? '';

    // Trial tier: a deliverable video exists but trials may not watch it. Decided
    // before ANY source (bundled, cached, protected) so nothing is requested.
    final deliverable =
        (demo.isBundled && demo.localBundledPath != null) ||
        demo.hasProtectedVideo;
    if (deliverable && access.trialLocked) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.trialLockedPhoto,
        uri: photo,
        isOfflineReady: true,
        exerciseId: demo.exerciseId,
        photoPath: photo,
      );
    }

    // 1. Legacy / dev: a video packaged inside the app (release builds bundle none).
    if (demo.isBundled && demo.localBundledPath != null) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.bundledAsset,
        uri: demo.localBundledPath!,
        isOfflineReady: true,
        photoPath: photo,
      );
    }

    // 2. Protected video (private bucket, on demand, entitlement required).
    if (demo.hasProtectedVideo) {
      final id = demo.exerciseId;
      if (!access.isEntitled) {
        return DemonstrationMediaSource(
          type: DemonstrationSourceType.lockedPhoto,
          uri: photo,
          isOfflineReady: true,
          exerciseId: id,
          photoPath: photo,
        );
      }
      final cached = await access.cachedFile(id);
      if (cached != null) {
        return DemonstrationMediaSource(
          type: DemonstrationSourceType.downloadedFile,
          uri: cached.path,
          isOfflineReady: true,
          localFilePath: cached.path,
          exerciseId: id,
          photoPath: photo,
        );
      }
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.protectedDownload,
        uri: photo,
        isOfflineReady: false,
        exerciseId: id,
        photoPath: photo,
      );
    }

    // 3. Anything else has no deliverable video: photo.
    return DemonstrationMediaSource(
      type: DemonstrationSourceType.photoFallback,
      uri: photo,
      isOfflineReady: true,
      photoPath: photo,
    );
  }

  Future<File?> downloadDemonstration(
    String exerciseName, {
    int? exerciseId,
    void Function(double progress)? onProgress,
  }) async {
    await initialize();
    ExerciseDemonstration? demo;
    if (exerciseName.isNotEmpty) {
      demo = getDemonstration(exerciseName);
    }
    if (demo == null && exerciseId != null && exerciseId > 0) {
      demo = getDemonstrationById(exerciseId);
    }
    if (demo == null || demo.videoUrl == null || demo.videoUrl!.isEmpty) {
      return null;
    }

    final targetFile = await _getCachedFileForExercise(
      exerciseName,
      exerciseId: exerciseId,
    );
    final tempFile = File('${targetFile.path}.tmp');

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(demo.videoUrl!));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        client.close();
        return null;
      }

      final contentLength = response.contentLength;
      var received = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(received / contentLength);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      // Atomic rename
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      return targetFile;
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<bool> deleteDownloadedDemonstration(
    String exerciseName, {
    int? exerciseId,
  }) async {
    try {
      final file = await _getCachedFileForExercise(
        exerciseName,
        exerciseId: exerciseId,
      );
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<int> getTotalCachedBytes() async {
    try {
      final dir = await _getDemonstrationsDirectory();
      int total = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<int> getCachedVideosCount() async {
    try {
      final dir = await _getDemonstrationsDirectory();
      int count = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.mp4')) {
          count++;
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearAllCachedVideos() async {
    try {
      final dir = await _getDemonstrationsDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  Map<String, dynamic> getMediaInventoryReport() {
    final all = _registryById.values.map((d) => _effective(d)!).toSet();
    final verified = all.where((d) => d.hasVideo).toSet();
    final bundled = all.where((d) => d.isBundled).toSet();
    final protectedVideos = all.where((d) => d.hasProtectedVideo).toSet();
    final fallbacks = all.where((d) => !d.hasVideo).toSet();

    return {
      'total_catalogue_exercises': verified.length + fallbacks.length,
      'verified_demonstrations_count': verified.length,
      'bundled_offline_demonstrations_count': bundled.length,
      'protected_video_demonstrations_count': protectedVideos.length,
      'photographic_fallbacks_count': fallbacks.length,
      'verified_exercises': verified.map((e) => e.name).toList(),
      'bundled_exercises': bundled.map((e) => e.name).toList(),
      'fallback_exercises': fallbacks.map((e) => e.name).toList(),
    };
  }
}
