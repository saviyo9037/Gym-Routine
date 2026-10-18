import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/services/exercise_media_service.dart';
import 'package:reptrack/services/video_access_service.dart';
import 'package:reptrack/widgets/exercise_demonstration_player.dart';

import 'helpers/test_db.dart';
import 'helpers/video_fakes.dart';

// MOCK-ONLY: entitlement, signed URLs and downloads are fakes; the widget, the media
// service and the cache are the real code. The native video plugin is not available
// under flutter_test, so these tests stop at the states shown BEFORE playback starts.

/// Waits on a completer so a test can look at the "downloading" state.
class _BlockingDownloader implements VideoDownloader {
  final gate = Completer<void>();
  void Function(double)? progress;

  @override
  Future<int> download(
    Uri url,
    File target, {
    void Function(double progress)? onProgress,
  }) async {
    progress = onProgress;
    onProgress?.call(0.5);
    await gate.future;
    await target.writeAsBytes(List<int>.filled(100, 1));
    return 100;
  }
}

Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final svc = ExerciseMediaService.instance;
  late VideoTestRig rig;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await svc.initialize();
  });
  setUp(() {
    mockPlatformPlugins();
    rig = VideoTestRig();
    svc.accessForTesting = rig.service;
    svc.videosEnabledForTesting = true;
  });
  tearDown(() {
    svc.accessForTesting = null;
    svc.videosEnabledForTesting = null;
    rig.dispose();
  });

  // 69 = Standing Dumbbell Curl (has a protected video), 1 = Barbell Bench Press (NO_VIDEO)
  Widget player(int id, String name, {double scale = 1.0}) => MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: ExerciseDemonstrationPlayer(
        key: ValueKey('p_$id'),
        exerciseId: id,
        exerciseName: name,
        fallbackImagePath: 'assets/images/exercises/standing_dumbbell_curl.jpg',
        height: 210,
      ),
    ),
  );

  void useSmallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ignoreMissingPluginErrors();
  }

  testWidgets(
    'not entitled: locked photo with a short explanation, no network',
    (tester) async {
      useSmallScreen(tester);
      rig.entitled = false;
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester);
      expect(find.text('Video demonstration'), findsOneWidget);
      expect(find.textContaining('active subscription'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsNothing);
      expect(rig.backend.requested, isEmpty);
    },
  );

  testWidgets('entitled and not cached: shows downloading with progress', (
    tester,
  ) async {
    useSmallScreen(tester);
    final blocking = _BlockingDownloader();
    svc.accessForTesting = VideoAccessService(
      canAccessVideos: () => true,
      fetchSignedUrl: rig.backend.fetch,
      downloader: blocking,
      cacheDirectory: () async => rig.cacheDir,
    );
    await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
    await settle(tester);
    expect(find.text('Downloading video... 50%'), findsOneWidget);
    expect(rig.backend.requested, [
      69,
    ], reason: 'only the opened exercise is requested');
    blocking.gate.complete();
    await settle(tester); // playback itself needs the native plugin: ends in an error state, not a crash
    expect(find.textContaining('Downloading'), findsNothing);
  });

  testWidgets('offline: "connect once" message with a working Retry', (
    tester,
  ) async {
    useSmallScreen(tester);
    rig.backend.fetchFailure = VideoAccessFailure.offline;
    await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
    await settle(tester);
    expect(find.text('Connect once to download this video'), findsOneWidget);

    // connection is back: Retry downloads (the cached file then fails only at the native player)
    rig.backend.fetchFailure = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Connect once to download this video'), findsNothing);
    expect(rig.downloader.calls, 1);
  });

  testWidgets('server/transport failure: error with Retry, never a crash', (
    tester,
  ) async {
    useSmallScreen(tester);
    rig.backend.fetchFailure = VideoAccessFailure.failed;
    await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
    await settle(tester);
    expect(find.text('Could not load demonstration video'), findsOneWidget);
    expect(find.text('Retry Playback'), findsOneWidget);
  });

  testWidgets(
    'subscription ended while opening: locked photo (server said no)',
    (tester) async {
      useSmallScreen(tester);
      rig.backend.fetchFailure = VideoAccessFailure.notEntitled;
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester);
      expect(find.textContaining('active subscription'), findsOneWidget);
    },
  );

  testWidgets(
    'NO_VIDEO exercise: photo and "No demonstration video yet", no request',
    (tester) async {
      useSmallScreen(tester);
      await tester.pumpWidget(player(1, 'Barbell Bench Press'));
      await settle(tester);
      expect(find.text('No demonstration video yet'), findsOneWidget);
      expect(rig.backend.requested, isEmpty);
    },
  );

  testWidgets(
    'BUNDLED_VIDEOS=false: even a video exercise shows only the photo',
    (tester) async {
      useSmallScreen(tester);
      svc.videosEnabledForTesting = false;
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester);
      expect(find.text('No demonstration video yet'), findsOneWidget);
      expect(rig.backend.requested, isEmpty);
      expect(rig.downloader.calls, 0);
    },
  );

  testWidgets(
    'switching exercise never shows the previous exercise video (late download is ignored)',
    (tester) async {
      useSmallScreen(tester);
      final blocking = _BlockingDownloader();
      svc.accessForTesting = VideoAccessService(
        canAccessVideos: () => true,
        fetchSignedUrl: rig.backend.fetch,
        downloader: blocking,
        cacheDirectory: () async => rig.cacheDir,
      );
      await tester.pumpWidget(player(69, 'Standing Dumbbell Curl'));
      await settle(tester);
      expect(find.text('Downloading video... 50%'), findsOneWidget);

      // user moves on to an exercise without video while the first one is still downloading
      await tester.pumpWidget(player(1, 'Barbell Bench Press'));
      await settle(tester);
      expect(find.text('No demonstration video yet'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsNothing);

      blocking.gate.complete(); // the old download finishes late
      await settle(tester);
      expect(find.text('No demonstration video yet'), findsOneWidget);
      expect(find.textContaining('Downloading'), findsNothing);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '360x640 text x$scale: locked / offline / downloading do not overflow',
      (tester) async {
        useSmallScreen(tester);
        // locked
        rig.entitled = false;
        await tester.pumpWidget(
          player(69, 'Standing Dumbbell Curl', scale: scale),
        );
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'locked');

        // offline
        rig.entitled = true;
        rig.backend.fetchFailure = VideoAccessFailure.offline;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          player(69, 'Standing Dumbbell Curl', scale: scale),
        );
        await settle(tester);
        expect(
          find.text('Connect once to download this video'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'offline');

        // downloading
        final blocking = _BlockingDownloader();
        rig.backend.fetchFailure = null;
        svc.accessForTesting = VideoAccessService(
          canAccessVideos: () => true,
          fetchSignedUrl: rig.backend.fetch,
          downloader: blocking,
          cacheDirectory: () async => rig.cacheDir,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          player(69, 'Standing Dumbbell Curl', scale: scale),
        );
        await settle(tester);
        expect(find.text('Downloading video... 50%'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'downloading');
        blocking.gate.complete();
        await settle(tester);
      },
    );
  }
}
