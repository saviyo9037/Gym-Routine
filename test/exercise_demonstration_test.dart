import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

    test('All 201 catalogue exercises are bundled and physically exist in assets/videos/exercises', () {
      final bundledEntries = demoRegistry.values
          .where((v) => v['local_bundled_path'] != null)
          .toList();

      expect(bundledEntries.length, 201);

      for (final entry in bundledEntries) {
        final relPath = entry['local_bundled_path'] as String;
        final file = File(relPath);
        expect(
          file.existsSync(),
          true,
          reason: 'Bundled video $relPath must exist on disk',
        );
        expect(
          file.lengthSync(),
          greaterThan(10000),
          reason: 'Video $relPath must have authentic byte content',
        );
      }
    });

    test('All 201 catalogue exercises have valid video media type and demonstration cues', () {
      final verifiedEntries = demoRegistry.values
          .where((v) => v['has_video'] == true)
          .toList();

      expect(verifiedEntries.length, 201);

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
      expect(
        flatDb['local_bundled_path'],
        'assets/videos/exercises/flat_dumbbell_press.mp4',
      );

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

    test('Resolves bundledAsset source for Barbell Bench Press', () async {
      final source = await mediaService.resolveMediaSource(
        'Barbell Bench Press',
        exerciseId: 1,
      );
      expect(source.type, DemonstrationSourceType.bundledAsset);
      expect(source.isOfflineReady, true);
      expect(source.uri, 'assets/videos/exercises/barbell_bench_press.mp4');
    });

    test('Resolves bundledAsset source for Flat Dumbbell Press', () async {
      final source = await mediaService.resolveMediaSource(
        'Flat Dumbbell Press',
        exerciseId: 4,
      );
      expect(source.type, DemonstrationSourceType.bundledAsset);
      expect(source.isOfflineReady, true);
      expect(source.uri, 'assets/videos/exercises/flat_dumbbell_press.mp4');
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
      expect(source.type, DemonstrationSourceType.bundledAsset);
      expect(source.uri, 'assets/videos/exercises/standing_dumbbell_curl.mp4');

      final hammerSource = await mediaService.resolveMediaSource(
        'Hammer Curl',
        exerciseId: 1, // Intentional mismatch
      );
      expect(hammerSource.type, DemonstrationSourceType.bundledAsset);
      expect(hammerSource.uri, 'assets/videos/exercises/hammer_curl.mp4');

      final barbellCurlSource = await mediaService.resolveMediaSource(
        'Barbell Curl',
        exerciseId: 1, // Intentional mismatch
      );
      expect(barbellCurlSource.type, DemonstrationSourceType.bundledAsset);
      expect(
        barbellCurlSource.uri,
        anyOf(
          'assets/videos/exercises/barbell_curl.mp4',
          'assets/videos/exercises/straight_bar_curl.mp4',
        ),
      );

      final benchSource = await mediaService.resolveMediaSource(
        'Bench Press',
        exerciseId: 69, // Intentional mismatch
      );
      expect(benchSource.type, DemonstrationSourceType.bundledAsset);
      expect(
        benchSource.uri,
        'assets/videos/exercises/barbell_bench_press.mp4',
      );
    });

    test('Cardio exercise resolves to verified bundled video with valid asset path', () async {
      final source = await mediaService.resolveMediaSource(
        'Treadmill Walking',
        exerciseId: 191,
      );
      expect(source.type, DemonstrationSourceType.bundledAsset);
      expect(source.uri, 'assets/videos/exercises/treadmill_walking.mp4');
      expect(File(source.uri).existsSync(), true);
    });

    test('Case-insensitive and punctuation-insensitive resolution', () async {
      expect(mediaService.hasDemonstration('barbell bench press'), true);
      expect(mediaService.hasDemonstration('BARBELL BENCH PRESS'), true);
      expect(mediaService.hasDemonstration('Barbell  Bench-Press!'), true);
      expect(mediaService.hasDemonstration('flat dumbbell press'), true);
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
        expect(report['verified_demonstrations_count'], 201);
        expect(report['bundled_offline_demonstrations_count'], 201);
        expect(report['photographic_fallbacks_count'], 0);
      },
    );
  });
}
