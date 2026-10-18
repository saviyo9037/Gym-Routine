import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dev_log.dart';
import 'cloud_config.dart';
import 'cloud_services.dart';

/// Why a protected video could not be provided.
enum VideoAccessFailure {
  /// The subscription (or trial) is not active: no video, photo + short text.
  notEntitled,

  /// The server has no publishable video for this exercise.
  noVideo,

  /// No connection and nothing cached: "connect once to download this video".
  offline,

  /// Cloud not configured / not signed in in this build.
  unavailable,

  /// Anything else (server error, interrupted download...). Retry is possible.
  failed,
}

class VideoAccessException implements Exception {
  const VideoAccessException(this.kind, [this.message = '']);
  final VideoAccessFailure kind;
  final String message;

  @override
  String toString() => 'VideoAccessException($kind)'; // never carries URLs or tokens
}

class SignedVideoUrl {
  const SignedVideoUrl(this.url, this.expiresAt);
  final Uri url;
  final DateTime expiresAt;
}

/// Asks the server (video-url Edge Function) for a short-lived signed URL.
/// Throws [VideoAccessException].
typedef SignedUrlFetcher = Future<SignedVideoUrl> Function(int exerciseId);

/// Streams [url] into [target]; returns the number of bytes written.
/// Throws [VideoAccessException] (offline / failed).
abstract class VideoDownloader {
  Future<int> download(
    Uri url,
    File target, {
    void Function(double progress)? onProgress,
  });
}

class HttpVideoDownloader implements VideoDownloader {
  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    if (url.scheme != 'https' && url.scheme != 'http') {
      throw const VideoAccessException(VideoAccessFailure.failed);
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw VideoAccessException(
          response.statusCode == HttpStatus.forbidden ||
                  response.statusCode == HttpStatus.unauthorized
              ? VideoAccessFailure.notEntitled
              : VideoAccessFailure.failed,
        );
      }
      final total = response.contentLength;
      var received = 0;
      sink = target.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0) {
        throw const VideoAccessException(VideoAccessFailure.failed);
      }
      return received;
    } on VideoAccessException {
      rethrow;
    } on SocketException {
      throw const VideoAccessException(VideoAccessFailure.offline);
    } on TimeoutException {
      throw const VideoAccessException(VideoAccessFailure.offline);
    } on HttpException {
      throw const VideoAccessException(VideoAccessFailure.failed);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }
}

/// On-demand, per-exercise delivery of protected videos.
///
///  * [canAccessVideos] decides whether this user may see videos at all (the
///    subscription / trial gate; the server re-checks everything).
///  * Videos are downloaded **one exercise at a time, when it is opened**, into
///    the app's private storage (never external storage) and played from there.
///  * Cached videos are served only while entitled; when the entitlement ends
///    the whole cache is deleted ([onEntitlementChanged] / [purgeIfNotEntitled]).
class VideoAccessService {
  VideoAccessService({
    required this.canAccessVideos,
    required this.fetchSignedUrl,
    this.isTrialLocked,
    VideoDownloader? downloader,
    Future<Directory> Function()? cacheDirectory,
  }) : _downloader = downloader ?? HttpVideoDownloader(),
       _cacheDirectory = cacheDirectory ?? _defaultCacheDirectory;

  final bool Function() canAccessVideos;

  /// True when the user is in a trial and videos are locked for trials. Such a
  /// user is never entitled here ([canAccessVideos] is false), so no signed URL
  /// is ever requested; this only lets the UI show the trial lock instead of
  /// the generic locked card.
  final bool Function()? isTrialLocked;
  final SignedUrlFetcher fetchSignedUrl;
  final VideoDownloader _downloader;
  final Future<Directory> Function() _cacheDirectory;

  static const String _indexName = 'index.json';
  static const int _indexVersion = 1;

  final Map<int, Future<File>> _inFlight = {};
  Future<void> _indexQueue = Future.value();

  /// Process-wide instance wired to the real entitlement and Supabase.
  /// Tests replace it with [overrideForTesting].
  static VideoAccessService instance = VideoAccessService(
    // Read-only use of the subscription state. If the access gate API changes,
    // adapt only this line.
    canAccessVideos: () => CloudServices.premium.videosAllowed,
    isTrialLocked: () => CloudServices.premium.videosLockedForTrial,
    fetchSignedUrl: _fetchViaSupabase,
  );

  static void overrideForTesting(VideoAccessService service) =>
      instance = service;

  static Future<Directory> _defaultCacheDirectory() async {
    final base = await getApplicationSupportDirectory(); // app-private
    return Directory(p.join(base.path, 'video_cache'));
  }

  // ------------------------------------------------------------------ remote

  static Future<SignedVideoUrl> _fetchViaSupabase(int exerciseId) async {
    if (!CloudConfig.supabaseConfigured || !CloudServices.auth.isSignedIn) {
      throw const VideoAccessException(VideoAccessFailure.unavailable);
    }
    try {
      final res = await Supabase.instance.client.functions
          .invoke('video-url', body: {'exercise_id': exerciseId})
          .timeout(const Duration(seconds: 20));
      final data = res.data;
      final url = data is Map ? data['url'] : null;
      final ttl = data is Map ? (data['expires_in'] as num?)?.toInt() : null;
      if (url is! String || url.isEmpty) {
        throw const VideoAccessException(VideoAccessFailure.failed);
      }
      return SignedVideoUrl(
        Uri.parse(url),
        DateTime.now().add(Duration(seconds: ttl ?? 300)),
      );
    } on VideoAccessException {
      rethrow;
    } on FunctionException catch (e) {
      switch (e.status) {
        case 401:
        case 403:
          throw const VideoAccessException(VideoAccessFailure.notEntitled);
        case 404:
          throw const VideoAccessException(VideoAccessFailure.noVideo);
        default:
          throw const VideoAccessException(VideoAccessFailure.failed);
      }
    } on SocketException {
      throw const VideoAccessException(VideoAccessFailure.offline);
    } on TimeoutException {
      throw const VideoAccessException(VideoAccessFailure.offline);
    } catch (e) {
      // http ClientException etc. Never log the exception text (may hold URLs).
      devLog('video-url call failed (${e.runtimeType})');
      final t = e.runtimeType.toString();
      throw VideoAccessException(
        t.contains('Client') || t.contains('Socket')
            ? VideoAccessFailure.offline
            : VideoAccessFailure.failed,
      );
    }
  }

  // ------------------------------------------------------------------- cache

  bool get isEntitled => canAccessVideos();

  bool get trialLocked => !isEntitled && (isTrialLocked?.call() ?? false);

  Future<Directory> _dir() async {
    final d = await _cacheDirectory();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  File _fileIn(Directory d, int id) => File(p.join(d.path, '$id.mp4'));

  Future<Map<String, dynamic>> _readIndex(Directory d) async {
    try {
      final f = File(p.join(d.path, _indexName));
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString());
      if (j is Map && j['version'] == _indexVersion && j['entries'] is Map) {
        return Map<String, dynamic>.from(j['entries'] as Map);
      }
    } catch (_) {}
    return {};
  }

  Future<void> _writeIndex(Directory d, Map<String, dynamic> entries) async {
    final tmp = File(p.join(d.path, '$_indexName.tmp'));
    await tmp.writeAsString(
      jsonEncode({'version': _indexVersion, 'entries': entries}),
      flush: true,
    );
    await tmp.rename(p.join(d.path, _indexName));
  }

  /// Serialises index read-modify-write cycles.
  Future<T> _withIndex<T>(
    Future<T> Function(Directory d, Map<String, dynamic> entries) body,
  ) {
    final run = _indexQueue.then((_) async {
      final d = await _dir();
      final entries = await _readIndex(d);
      return body(d, entries);
    });
    _indexQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// The cached file for [exerciseId], or null. Only returned while entitled
  /// and only if the file still matches the size recorded when it was saved.
  Future<File?> cachedFile(int exerciseId) async {
    if (!isEntitled) return null;
    return _withIndex((d, entries) async {
      final entry = entries['$exerciseId'];
      final f = _fileIn(d, exerciseId);
      if (entry is Map && await f.exists()) {
        if (await f.length() == entry['bytes']) return f;
      }
      if (entry != null) {
        // Stale index entry (file missing/changed): forget it, keep nothing half-valid.
        entries.remove('$exerciseId');
        await _writeIndex(d, entries);
        if (await f.exists()) await f.delete();
      }
      return null;
    });
  }

  /// Returns the local file, downloading it first if needed. Concurrent calls
  /// for the same exercise share one download.
  Future<File> ensureDownloaded(
    int exerciseId, {
    void Function(double progress)? onProgress,
  }) {
    if (!isEntitled) {
      return Future.error(
        const VideoAccessException(VideoAccessFailure.notEntitled),
      );
    }
    final running = _inFlight[exerciseId];
    if (running != null) return running;
    final job = _download(exerciseId, onProgress).whenComplete(() {
      // NB: must not RETURN the removed future, or whenComplete would wait for
      // the very job it belongs to (deadlock).
      _inFlight.remove(exerciseId);
    });
    _inFlight[exerciseId] = job;
    return job;
  }

  Future<File> _download(
    int exerciseId,
    void Function(double progress)? onProgress,
  ) async {
    final cached = await cachedFile(exerciseId);
    if (cached != null) return cached;

    final signed = await fetchSignedUrl(
      exerciseId,
    ); // may throw VideoAccessException
    final dir = await _dir();
    final part = File(p.join(dir.path, '$exerciseId.mp4.part'));
    try {
      if (await part.exists()) await part.delete();
      final bytes = await _downloader.download(
        signed.url,
        part,
        onProgress: onProgress,
      );
      // Entitlement may have ended while downloading: never keep the file then.
      if (!isEntitled) {
        throw const VideoAccessException(VideoAccessFailure.notEntitled);
      }
      final target = _fileIn(dir, exerciseId);
      await _withIndex((d, entries) async {
        if (await target.exists()) await target.delete();
        await part.rename(target.path);
        entries['$exerciseId'] = {
          'bytes': bytes,
          'at': DateTime.now().toUtc().toIso8601String(),
        };
        await _writeIndex(d, entries);
      });
      return target;
    } catch (_) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Deletes every cached video (entitlement ended, sign-out, account deletion).
  Future<void> clearCache() async {
    await _withIndex((d, entries) async {
      if (await d.exists()) await d.delete(recursive: true);
    });
  }

  /// Hook for the access gate. When [entitled] becomes false the cache is
  /// deleted. [known] = false means the entitlement state is not determined
  /// yet (app start before the first check): nothing is touched.
  Future<void> onEntitlementChanged(bool entitled, {bool known = true}) async {
    if (!known || entitled) return;
    await clearCache();
  }

  /// Run once at app start, AFTER the entitlement state was loaded.
  Future<void> purgeIfNotEntitled() => onEntitlementChanged(isEntitled);

  Future<int> cachedCount() => _withIndex((d, entries) async => entries.length);

  Future<int> cachedBytes() => _withIndex((d, entries) async {
    var total = 0;
    for (final v in entries.values) {
      if (v is Map && v['bytes'] is int) total += v['bytes'] as int;
    }
    return total;
  });
}
