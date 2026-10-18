import 'dart:io';

import 'package:reptrack/services/video_access_service.dart';

/// MOCK-ONLY fakes for the protected-video pipeline (no network, no Supabase).
class FakeVideoDownloader implements VideoDownloader {
  FakeVideoDownloader({this.bytes = 2048, this.failWith});

  final int bytes;
  VideoAccessFailure? failWith;
  int calls = 0;
  final List<Uri> urls = [];

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    urls.add(url);
    final f = failWith;
    if (f != null) throw VideoAccessException(f);
    onProgress?.call(0.5);
    await target.writeAsBytes(List<int>.filled(bytes, 7));
    onProgress?.call(1.0);
    return bytes;
  }
}

class FakeVideoBackend {
  FakeVideoBackend({this.fetchFailure});

  /// When set, the signed-URL request fails like the server/network would.
  VideoAccessFailure? fetchFailure;
  final List<int> requested = [];

  Future<SignedVideoUrl> fetch(int id) async {
    requested.add(id);
    final f = fetchFailure;
    if (f != null) throw VideoAccessException(f);
    return SignedVideoUrl(
      Uri.parse('https://signed.invalid/videos/$id.mp4?token=T'),
      DateTime.now().add(const Duration(minutes: 5)),
    );
  }
}

class VideoTestRig {
  VideoTestRig({this.entitled = true, int bytes = 2048})
    : downloader = FakeVideoDownloader(bytes: bytes),
      backend = FakeVideoBackend() {
    cacheDir = Directory.systemTemp.createTempSync('reptrack_video_cache_');
    service = VideoAccessService(
      canAccessVideos: () => entitled,
      fetchSignedUrl: backend.fetch,
      downloader: downloader,
      cacheDirectory: () async => cacheDir,
    );
  }

  bool entitled;
  final FakeVideoDownloader downloader;
  final FakeVideoBackend backend;
  late final Directory cacheDir;
  late final VideoAccessService service;

  void dispose() {
    try {
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
