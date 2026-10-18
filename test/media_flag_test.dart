import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/media_config.dart';
import 'package:reptrack/services/exercise_media_service.dart';

import 'helpers/video_fakes.dart';

// MOCK-ONLY where the entitlement and the signed-URL backend are involved
// (VideoTestRig fakes them); the flag and the registry are the real code/data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = ExerciseMediaService.instance;
  late VideoTestRig rig;

  setUpAll(() async => svc.initialize());
  setUp(() {
    rig = VideoTestRig();
    svc.accessForTesting = rig.service;
  });
  tearDown(() {
    svc.videosEnabledForTesting = null;
    svc.accessForTesting = null;
    rig.dispose();
  });

  test(
    'default build flag keeps videos on (BUNDLED_VIDEOS=false turns them off)',
    () {
      expect(kBundledVideosEnabled, isTrue);
      expect(svc.videosEnabled, isTrue);
    },
  );

  group('videos enabled', () {
    setUp(() => svc.videosEnabledForTesting = true);

    test('entitled user: an exercise with a protected video must be downloaded on demand', () async {
      final s = await svc.resolveMediaSource('Standing Dumbbell Curl');
      expect(s.type, DemonstrationSourceType.protectedDownload);
      expect(s.exerciseId, 69);
      expect(s.isOfflineReady, isFalse);
      expect(
        rig.backend.requested,
        isEmpty,
        reason: 'resolving never downloads by itself',
      );
      expect(svc.hasDemonstration('Standing Dumbbell Curl'), isTrue);
    });

    test(
      'NOT entitled: the same exercise is locked (photo only), no network',
      () async {
        rig.entitled = false;
        final s = await svc.resolveMediaSource('Standing Dumbbell Curl');
        expect(s.type, DemonstrationSourceType.lockedPhoto);
        expect(s.uri, endsWith('.jpg'));
        expect(rig.backend.requested, isEmpty);
        expect(rig.downloader.calls, 0);
      },
    );

    test(
      'after a download it resolves to the cached local file (offline capable)',
      () async {
        await rig.service.ensureDownloaded(69);
        final s = await svc.resolveMediaSource('Standing Dumbbell Curl');
        expect(s.type, DemonstrationSourceType.downloadedFile);
        expect(s.isOfflineReady, isTrue);
        expect(File(s.uri).existsSync(), isTrue);
        expect(
          s.uri.startsWith(rig.cacheDir.path),
          isTrue,
          reason: 'inside the app-private cache',
        );
      },
    );

    test('entitlement ended: cached video is no longer served', () async {
      await rig.service.ensureDownloaded(69);
      rig.entitled = false;
      final s = await svc.resolveMediaSource('Standing Dumbbell Curl');
      expect(s.type, DemonstrationSourceType.lockedPhoto);
    });

    test('NO_VIDEO exercises stay on the photo', () async {
      final s = await svc.resolveMediaSource('Barbell Bench Press');
      expect(s.type, DemonstrationSourceType.photoFallback);
      expect(rig.backend.requested, isEmpty);
    });

    test('every exercise with a video maps to videos/<id>.mp4 and none to a bundled asset or URL', () {
      var withVideo = 0;
      for (var id = 1; id <= 201; id++) {
        final d = svc.getDemonstrationById(id)!;
        expect(d.localBundledPath, isNull, reason: d.name);
        expect(d.videoUrl, isNull, reason: d.name);
        if (d.hasVideo) {
          withVideo++;
          expect(d.storagePath, 'videos/$id.mp4', reason: d.name);
          expect(d.hasProtectedVideo, isTrue);
        } else {
          expect(d.storagePath, isNull, reason: d.name);
        }
      }
      expect(withVideo, 123);
    });
  });

  group('videos disabled (kill switch)', () {
    setUp(() => svc.videosEnabledForTesting = false);

    test('every exercise resolves to photoFallback with its image and NO network call', () async {
      for (final id in List.generate(201, (i) => i + 1)) {
        final d = svc.getDemonstrationById(id)!;
        final s = await svc.resolveMediaSource(
          d.name,
          exerciseId: d.exerciseId,
          fallbackImagePath: d.imageFallbackPath,
        );
        expect(s.type, DemonstrationSourceType.photoFallback, reason: d.name);
        expect(s.uri, d.imageFallbackPath);
      }
      expect(rig.backend.requested, isEmpty);
      expect(rig.downloader.calls, 0);
    });

    test('registry reports no video, no protected path, no remote url', () {
      final d = svc.getDemonstration('Standing Dumbbell Curl')!;
      expect(d.hasVideo, isFalse);
      expect(d.mediaType, 'image');
      expect(d.localBundledPath, isNull);
      expect(d.storagePath, isNull);
      expect(d.videoUrl, isNull);
      expect(svc.hasDemonstration('Standing Dumbbell Curl'), isFalse);
      final report = svc.getMediaInventoryReport();
      expect(report['verified_demonstrations_count'], 0);
      expect(report['protected_video_demonstrations_count'], 0);
      expect(report['photographic_fallbacks_count'], 201);
    });

    test('downloads are refused (no URL to stream)', () async {
      expect(await svc.downloadDemonstration('Standing Dumbbell Curl'), isNull);
    });

    test(
      'no encoded video file is deleted by the switch (local media_src only)',
      () {
        final dir = Directory('media_src/encoded');
        if (!dir.existsSync()) {
          return; // gitignored: nothing to check on a fresh clone
        }
        expect(dir.listSync().whereType<File>().length, 123);
      },
    );
  });
}
