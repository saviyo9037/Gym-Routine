import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/video_fakes.dart';

import 'package:reptrack/models/exercise_demonstration.dart';
import 'package:reptrack/services/exercise_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExerciseDemonstration Model Tests', () {
    test(
      'Correctly serializes and deserializes ExerciseDemonstration with video',
      () {
        final demo = ExerciseDemonstration(
          exerciseId: 1,
          name: 'Barbell Bench Press',
          slug: 'barbell_bench_press',
          muscleGroup: 'Chest',
          equipment: 'Barbell',
          hasVideo: true,
          mediaType: 'video',
          videoUrl: 'https://cdn.example.com/videos/bench_press.mp4',
          thumbnailUrl: 'https://cdn.example.com/thumbs/bench_press.jpg',
          imageFallbackPath: 'assets/images/exercises/barbell_bench_press.jpg',
          localBundledPath: 'assets/videos/exercises/barbell_bench_press.mp4',
          durationSeconds: 10,
          license: 'MIT License',
          attribution: 'Free Exercise DB (MIT License)',
          demonstrationCues: const [
            'Plant feet firmly and retract scapulae',
            'Lower bar to lower sternum under control',
            'Drive vertically to full lockout',
          ],
        );

        final map = demo.toMap();
        expect(map['exercise_id'], 1);
        expect(map['name'], 'Barbell Bench Press');
        expect(map['has_video'], true);
        expect(
          map['local_bundled_path'],
          'assets/videos/exercises/barbell_bench_press.mp4',
        );
        expect(map['demonstration_cues'].length, 3);
        expect(demo.isBundled, true);

        final reconstituted = ExerciseDemonstration.fromMap(map);
        expect(reconstituted.exerciseId, 1);
        expect(reconstituted.name, 'Barbell Bench Press');
        expect(reconstituted.hasVideo, true);
        expect(reconstituted.isBundled, true);
        expect(reconstituted.durationSeconds, 10);
        expect(
          reconstituted.demonstrationCues.first,
          'Plant feet firmly and retract scapulae',
        );
      },
    );

    test(
      'Correctly serializes and deserializes photo fallback demonstration',
      () {
        final demo = ExerciseDemonstration(
          exerciseId: 99,
          name: 'Plate Pinch Hold',
          slug: 'plate_pinch_hold',
          muscleGroup: 'Forearms',
          equipment: 'Weight Plates',
          hasVideo: false,
          mediaType: 'image',
          imageFallbackPath: 'assets/images/exercises/plate_pinch_hold.jpg',
          durationSeconds: 0,
          license: 'RepTrack Core Assets',
          attribution: 'RepTrack Visual Guide',
          demonstrationCues: const [
            'Pinch smooth plates together between fingers and thumb',
            'Maintain upright posture and shoulder pack',
          ],
        );

        expect(demo.isBundled, false);
        expect(demo.hasVideo, false);
        expect(demo.videoUrl, isNull);

        final map = demo.toMap();
        final reconstituted = ExerciseDemonstration.fromMap(map);
        expect(reconstituted.hasVideo, false);
        expect(reconstituted.isBundled, false);
        expect(reconstituted.mediaType, 'image');
      },
    );
  });

  group('Demonstration Catalogue Integrity Tests', () {
    late Map<String, dynamic> demoRegistry;

    setUpAll(() {
      final file = File('assets/exercise_demonstrations.json');
      expect(
        file.existsSync(),
        true,
        reason: 'assets/exercise_demonstrations.json must exist',
      );
      final content = file.readAsStringSync();
      demoRegistry = json.decode(content) as Map<String, dynamic>;
    });

    test('Registry contains all 201 catalogue exercises', () {
      expect(demoRegistry.length, 201);
    });

    test(
      'All 15 muscle groups are represented in the demonstration registry',
      () {
        final muscleGroups = <String>{};
        for (final entry in demoRegistry.values) {
          muscleGroups.add(entry['muscle_group'] as String);
        }

        expect(muscleGroups.contains('Chest'), true);
        expect(muscleGroups.contains('Back'), true);
        expect(muscleGroups.contains('Lats'), true);
        expect(muscleGroups.contains('Upper Back and Traps'), true);
        expect(muscleGroups.contains('Shoulders'), true);
        expect(muscleGroups.contains('Biceps'), true);
        expect(muscleGroups.contains('Triceps'), true);
        expect(muscleGroups.contains('Forearms'), true);
        expect(muscleGroups.contains('Quadriceps'), true);
        expect(muscleGroups.contains('Hamstrings'), true);
        expect(muscleGroups.contains('Glutes'), true);
        expect(muscleGroups.contains('Calves'), true);
        expect(muscleGroups.contains('Abs and Core'), true);
        expect(muscleGroups.contains('Full Body'), true);
        expect(muscleGroups.contains('Cardio'), true);
        expect(muscleGroups.length, 15);
      },
    );

    test('123 exercises have a protected (non-bundled) video; the other 78 have none (NO_VIDEO)', () {
      final protectedEntries = demoRegistry.values
          .where((v) => v['storage_path'] != null)
          .toList();

      expect(protectedEntries.length, 123);
      expect(demoRegistry.length - protectedEntries.length, 78);
      for (final v in demoRegistry.values.where(
        (v) => v['storage_path'] == null,
      )) {
        expect(v['has_video'], false);
        expect(v['status'], 'NO_VIDEO');
      }
      for (final entry in demoRegistry.values) {
        expect(
          entry['local_bundled_path'],
          isNull,
          reason: 'nothing is bundled in the app: ${entry['name']}',
        );
        expect(
          entry['video_url'],
          isNull,
          reason: 'no third-party stream: ${entry['name']}',
        );
      }
    });

    test('Every exercise has demonstration cues; the 123 with video have a valid media type', () {
      final verifiedEntries = demoRegistry.values
          .where((v) => v['has_video'] == true)
          .toList();

      expect(verifiedEntries.length, 123);

      for (final entry in demoRegistry.values) {
        final cues = entry['demonstration_cues'] as List<dynamic>?;
        expect(cues!.length, greaterThanOrEqualTo(3));
      }
      for (final entry in verifiedEntries) {
        expect(entry['media_type'], 'video');
        expect(entry['duration_seconds'], greaterThan(0));
        final cues = entry['demonstration_cues'] as List<dynamic>?;
        expect(cues, isNotNull);
        expect(cues!.length, greaterThanOrEqualTo(3));
      }
    });
  });

  group('Strict Video-Matching and Anti-Cross-Contamination Tests', () {
    late Map<String, dynamic> demoRegistry;

    setUpAll(() {
      final file = File('assets/exercise_demonstrations.json');
      demoRegistry =
          json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('Flat Dumbbell Press resolves to Dumbbell Lying Hammer Press (Chest bench press), NOT Seated Shoulder Press', () {
      final flatDb = demoRegistry['Flat Dumbbell Press'];
      expect(flatDb, isNotNull);
      expect(flatDb['muscle_group'], 'Chest');
      expect(flatDb['mapped_model_source'], 'Dumbbell Lying Hammer Press');
      // Its video was byte-identical to Dumbbell Pullover's, so it was removed.
      expect(flatDb['local_bundled_path'], isNull);
      expect(flatDb['has_video'], false);

      final shoulderPress = demoRegistry['Seated Dumbbell Shoulder Press'];
      expect(shoulderPress, isNotNull);
      expect(shoulderPress['muscle_group'], 'Shoulders');
      expect(
        shoulderPress['mapped_model_source'],
        'Seated Dumbbell Shoulder Press',
      );

      // Crucial: They must not share the same mapped video source
      expect(
        flatDb['mapped_model_source'],
        isNot(equals(shoulderPress['mapped_model_source'])),
      );
    });

    test('Triceps exercises never resolve to Biceps demonstrations', () {
      for (final entry in demoRegistry.values) {
        if (entry['muscle_group'] == 'Triceps') {
          final src = (entry['mapped_model_source'] as String).toLowerCase();
          expect(
            src.contains('biceps'),
            false,
            reason: '${entry['name']} must not resolve to a biceps video',
          );
          expect(
            src.contains('inner curl'),
            false,
            reason: '${entry['name']} must not resolve to a curl video',
          );
        }
      }
    });

    test('Chest exercises never resolve to Back or Biceps demonstrations', () {
      for (final entry in demoRegistry.values) {
        if (entry['muscle_group'] == 'Chest') {
          final src = (entry['mapped_model_source'] as String).toLowerCase();
          expect(
            src.contains('row'),
            false,
            reason: '${entry['name']} must not resolve to a row',
          );
          expect(
            src.contains('pulldown'),
            false,
            reason: '${entry['name']} must not resolve to a pulldown',
          );
          expect(
            src.contains('curl'),
            false,
            reason: '${entry['name']} must not resolve to a curl',
          );
        }
      }
    });

    test(
      'Biceps exercises resolve to their own elbow-flexion demonstrations',
      () {
        final standingCurl = demoRegistry['Standing Dumbbell Curl'];
        expect(standingCurl, isNotNull);
        expect(standingCurl['muscle_group'], 'Biceps');

        final preacherCurl = demoRegistry['Preacher Curl'];
        expect(preacherCurl, isNotNull);
        expect(preacherCurl['muscle_group'], 'Biceps');

        final hammerCurl = demoRegistry['Hammer Curl'];
        expect(hammerCurl, isNotNull);
        expect(hammerCurl['muscle_group'], 'Biceps');
      },
    );

    test('Back exercises resolve to posterior pulling demonstrations', () {
      final tBar = demoRegistry['T-Bar Row'];
      expect(tBar, isNotNull);
      expect(tBar['muscle_group'], 'Back');

      final landmine = demoRegistry['Landmine Row'];
      expect(landmine, isNotNull);
      expect(landmine['muscle_group'], 'Back');
      expect(landmine['mapped_model_source'], 'Lever Reverse T-Bar Row');
      expect(tBar['mapped_model_source'], 'Lever T-Bar Row');
      // Crucial: Distinct mappings
      expect(
        landmine['mapped_model_source'],
        isNot(equals(tBar['mapped_model_source'])),
      );
    });

    test('Cable Biceps Curl and Low Cable Curl have distinct mappings', () {
      final cableCurl = demoRegistry['Cable Biceps Curl'];
      final lowCableCurl = demoRegistry['Low Cable Curl'];
      expect(
        cableCurl['mapped_model_source'],
        isNot(equals(lowCableCurl['mapped_model_source'])),
      );
    });

    test(
      'Cable Triceps Pushdown and Straight-Bar Pushdown have distinct mappings',
      () {
        final pushdown = demoRegistry['Cable Triceps Pushdown'];
        final straightBar = demoRegistry['Straight-Bar Pushdown'];
        expect(
          pushdown['mapped_model_source'],
          isNot(equals(straightBar['mapped_model_source'])),
        );
      },
    );
  });

  group('ExerciseMediaService Source Resolution and Fallback Tests', () {
    final mediaService = ExerciseMediaService.instance;
    // MOCK-ONLY entitlement/backend (videos come from a private bucket).
    late VideoTestRig rig;
    setUp(() {
      rig = VideoTestRig();
      mediaService.accessForTesting = rig.service;
    });
    tearDown(() {
      mediaService.accessForTesting = null;
      rig.dispose();
    });

    test('Barbell Bench Press has no video (duplicate removed) and resolves to its photo', () async {
      final source = await mediaService.resolveMediaSource(
        'Barbell Bench Press',
        exerciseId: 1,
      );
      expect(source.type, DemonstrationSourceType.photoFallback);
      expect(source.isOfflineReady, true);
      expect(source.uri, 'assets/images/exercises/barbell_bench_press.jpg');
    });

    test('Flat Dumbbell Press has no video (duplicate removed) and resolves to its photo', () async {
      final source = await mediaService.resolveMediaSource(
        'Flat Dumbbell Press',
        exerciseId: 4,
      );
      expect(source.type, DemonstrationSourceType.photoFallback);
      expect(source.isOfflineReady, true);
      expect(source.uri, 'assets/images/exercises/flat_dumbbell_press.jpg');
    });

    test('Resolves by exerciseId directly', () async {
      await mediaService.initialize();
      final demo1 = mediaService.getDemonstrationById(1);
      expect(demo1, isNotNull);
      expect(demo1!.name, 'Barbell Bench Press');

      final demo4 = mediaService.getDemonstrationById(4);
      expect(demo4, isNotNull);
      expect(demo4!.name, 'Flat Dumbbell Press');
    });

    test('Prioritizes exercise name over mismatched ID to prevent wrong video playback', () async {
      await mediaService.initialize();
      // Even if mismatched id: 1 is provided, "Standing Dumbbell Curl" must resolve to curl video, NOT bench press
      final source = await mediaService.resolveMediaSource(
        'Standing Dumbbell Curl',
        exerciseId: 1, // Intentional mismatch
      );
      // MOCK-ONLY entitlement: an entitled user's video is requested by the
      // exercise the NAME resolves to (69), never by the mismatched id.
      expect(source.type, DemonstrationSourceType.protectedDownload);
      expect(source.exerciseId, 69);

      final hammerSource = await mediaService.resolveMediaSource(
        'Hammer Curl',
        exerciseId: 1, // Intentional mismatch
      );
      expect(hammerSource.type, DemonstrationSourceType.photoFallback);
      expect(hammerSource.uri, 'assets/images/exercises/hammer_curl.jpg');

      final benchSource = await mediaService.resolveMediaSource(
        'Bench Press',
        exerciseId: 69, // Intentional mismatch
      );
      expect(benchSource.type, DemonstrationSourceType.photoFallback);
      expect(benchSource.uri, endsWith('.jpg'));
    });

    test('Cardio exercise with a video resolves to its own protected on-demand video', () async {
      final source = await mediaService.resolveMediaSource(
        'Treadmill Walking',
        exerciseId: 191,
      );
      expect(source.type, DemonstrationSourceType.protectedDownload);
      expect(source.exerciseId, 191);
    });

    test('Case-insensitive and punctuation-insensitive resolution', () async {
      expect(mediaService.hasDemonstration('standing dumbbell curl'), true);
      expect(mediaService.hasDemonstration('STANDING DUMBBELL CURL'), true);
      expect(mediaService.hasDemonstration('Standing  Dumbbell-Curl!'), true);
      // NO_VIDEO exercises report no demonstration video.
      expect(mediaService.hasDemonstration('flat dumbbell press'), false);
    });

    test(
      'Gracefully returns photoFallback for unknown exercise without crashing',
      () async {
        final source = await mediaService.resolveMediaSource(
          'NonExistent Exercise Name 999',
          fallbackImagePath: 'assets/images/placeholder.jpg',
        );
        expect(source.type, DemonstrationSourceType.photoFallback);
        expect(source.uri, 'assets/images/placeholder.jpg');
        expect(source.isOfflineReady, true);
      },
    );

    test(
      'Generates media inventory coverage statistics for complete catalogue',
      () {
        final report = mediaService.getMediaInventoryReport();
        expect(report['total_catalogue_exercises'], 201);
        expect(report['verified_demonstrations_count'], 123);
        expect(report['bundled_offline_demonstrations_count'], 0);
        expect(report['protected_video_demonstrations_count'], 123);
        expect(report['photographic_fallbacks_count'], 78);
      },
    );
  });
}
