import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/exercise_demonstration.dart';

enum DemonstrationSourceType {
  bundledAsset,
  downloadedFile,
  remoteNetwork,
  photoFallback,
}

class DemonstrationMediaSource {
  final DemonstrationSourceType type;
  final String uri;
  final bool isOfflineReady;
  final String? localFilePath;

  const DemonstrationMediaSource({
    required this.type,
    required this.uri,
    required this.isOfflineReady,
    this.localFilePath,
  });
}

class ExerciseMediaService {
  static final ExerciseMediaService instance = ExerciseMediaService._internal();

  ExerciseMediaService._internal();

  bool _isInitialized = false;
  final Map<String, ExerciseDemonstration> _registryByName = {};
  final Map<int, ExerciseDemonstration> _registryById = {};

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final jsonStr = await rootBundle.loadString('assets/exercise_demonstrations.json');
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
      return _registryByName[name];
    }
    return _registryByName[_normalize(name)];
  }

  ExerciseDemonstration? getDemonstrationById(int id) {
    return _registryById[id];
  }

  bool hasDemonstration(String name, {int? exerciseId}) {
    ExerciseDemonstration? demo;
    if (exerciseId != null && exerciseId > 0) {
      demo = getDemonstrationById(exerciseId);
    }
    demo ??= getDemonstration(name);
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
    final prefix = exerciseId != null && exerciseId > 0 ? 'ex_${exerciseId}_' : '';
    final slug = _normalize(exerciseName);
    return File(p.join(dir.path, '$prefix$slug.mp4'));
  }

  Future<bool> isDownloaded(
    String exerciseName, {
    int? exerciseId,
  }) async {
    try {
      final file = await _getCachedFileForExercise(exerciseName, exerciseId: exerciseId);
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
      final file = await _getCachedFileForExercise(exerciseName, exerciseId: exerciseId);
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
    ExerciseDemonstration? demo;
    if (exerciseId != null && exerciseId > 0) {
      demo = getDemonstrationById(exerciseId);
    }
    demo ??= getDemonstration(exerciseName);

    if (demo == null || !demo.hasVideo) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.photoFallback,
        uri: fallbackImagePath ?? demo?.imageFallbackPath ?? '',
        isOfflineReady: true,
      );
    }

    // 1. Check if bundled in assets
    if (demo.isBundled && demo.localBundledPath != null) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.bundledAsset,
        uri: demo.localBundledPath!,
        isOfflineReady: true,
      );
    }

    // 2. Check if downloaded in app-private storage
    final localPath = await getLocalCachedVideoPath(exerciseName, exerciseId: exerciseId);
    if (localPath != null) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.downloadedFile,
        uri: localPath,
        isOfflineReady: true,
        localFilePath: localPath,
      );
    }

    // 3. Fallback to remote network stream
    if (demo.videoUrl != null && demo.videoUrl!.isNotEmpty) {
      return DemonstrationMediaSource(
        type: DemonstrationSourceType.remoteNetwork,
        uri: demo.videoUrl!,
        isOfflineReady: false,
      );
    }

    // 4. Default to photo fallback
    return DemonstrationMediaSource(
      type: DemonstrationSourceType.photoFallback,
      uri: fallbackImagePath ?? demo.imageFallbackPath ?? '',
      isOfflineReady: true,
    );
  }

  Future<File?> downloadDemonstration(
    String exerciseName, {
    int? exerciseId,
    void Function(double progress)? onProgress,
  }) async {
    await initialize();
    ExerciseDemonstration? demo;
    if (exerciseId != null && exerciseId > 0) {
      demo = getDemonstrationById(exerciseId);
    }
    demo ??= getDemonstration(exerciseName);
    if (demo == null || demo.videoUrl == null || demo.videoUrl!.isEmpty) {
      return null;
    }

    final targetFile = await _getCachedFileForExercise(exerciseName, exerciseId: exerciseId);
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
      final file = await _getCachedFileForExercise(exerciseName, exerciseId: exerciseId);
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
    final verified = _registryByName.values.where((d) => d.hasVideo).toSet();
    final bundled = _registryByName.values.where((d) => d.isBundled).toSet();
    final fallbacks = _registryByName.values.where((d) => !d.hasVideo).toSet();

    return {
      'total_catalogue_exercises': verified.length + fallbacks.length,
      'verified_demonstrations_count': verified.length,
      'bundled_offline_demonstrations_count': bundled.length,
      'photographic_fallbacks_count': fallbacks.length,
      'verified_exercises': verified.map((e) => e.name).toList(),
      'bundled_exercises': bundled.map((e) => e.name).toList(),
      'fallback_exercises': fallbacks.map((e) => e.name).toList(),
    };
  }
}
