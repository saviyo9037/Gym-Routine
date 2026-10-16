import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/models/exercise_demonstration.dart';
import 'package:reptrack/services/exercise_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExerciseDemonstration Model Tests', () {
    test('Correctly serializes and deserializes ExerciseDemonstration with video', () {
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
      expect(map['local_bundled_path'], 'assets/videos/exercises/barbell_bench_press.mp4');
      expect(map['demonstration_cues'].length, 3);
      expect(demo.isBundled, true);

      final reconstituted = ExerciseDemonstration.fromMap(map);
      expect(reconstituted.exerciseId, 1);
      expect(reconstituted.name, 'Barbell Bench Press');
      expect(reconstituted.hasVideo, true);
      expect(reconstituted.isBundled, true);
      expect(reconstituted.durationSeconds, 10);
      expect(reconstituted.demonstrationCues.first, 'Plant feet firmly and retract scapulae');
    });

    test('Correctly serializes and deserializes photo fallback demonstration', () {
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
    });
  });

  group('Demonstration Catalogue Integrity Tests', () {
    late Map<String, dynamic> demoRegistry;

    setUpAll(() {
      final file = File('assets/exercise_demonstrations.json');
      expect(file.existsSync(), true, reason: 'assets/exercise_demonstrations.json must exist');
      final content = file.readAsStringSync();
      demoRegistry = json.decode(content) as Map<String, dynamic>;
    });

    test('Registry contains all 190 catalogue exercises', () {
      expect(demoRegistry.length, 190);
    });

    test('All 14 muscle groups are represented in the demonstration registry', () {
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
      expect(muscleGroups.length, 14);
    });

    test('All 190 catalogue exercises are bundled and physically exist in assets/videos/exercises', () {
      final bundledEntries = demoRegistry.values
          .where((v) => v['local_bundled_path'] != null)
          .toList();

      expect(bundledEntries.length, 190);

      for (final entry in bundledEntries) {
        final relPath = entry['local_bundled_path'] as String;
        final file = File(relPath);
        expect(file.existsSync(), true, reason: 'Bundled video $relPath must exist on disk');
        expect(file.lengthSync(), greaterThan(50000), reason: 'Video $relPath must have authentic byte content');
      }
    });

    test('All 190 catalogue exercises have valid video media type and demonstration cues', () {
      final verifiedEntries = demoRegistry.values
          .where((v) => v['has_video'] == true)
          .toList();

      expect(verifiedEntries.length, 190);

      for (final entry in verifiedEntries) {
        expect(entry['media_type'], 'video');
        expect(entry['duration_seconds'], 10);
        final cues = entry['demonstration_cues'] as List<dynamic>?;
        expect(cues, isNotNull);
        expect(cues!.length, greaterThanOrEqualTo(3));
      }
    });
  });

  group('ExerciseMediaService Source Resolution Tests', () {
    final mediaService = ExerciseMediaService.instance;

    test('Resolves bundledAsset source for Barbell Bench Press', () async {
      final source = await mediaService.resolveMediaSource('Barbell Bench Press');
      expect(source.type, DemonstrationSourceType.bundledAsset);
      expect(source.isOfflineReady, true);
      expect(source.uri, 'assets/videos/exercises/barbell_bench_press.mp4');
    });

    test('Resolves bundledAsset source for Plate Pinch Hold', () async {
      final source = await mediaService.resolveMediaSource('Plate Pinch Hold');
      expect(source.type, DemonstrationSourceType.bundledAsset);
      expect(source.isOfflineReady, true);
      expect(source.uri, 'assets/videos/exercises/plate_pinch_hold.mp4');
    });

    test('Case-insensitive and punctuation-insensitive resolution', () async {
      expect(mediaService.hasDemonstration('barbell bench press'), true);
      expect(mediaService.hasDemonstration('BARBELL BENCH PRESS'), true);
      expect(mediaService.hasDemonstration('Barbell  Bench-Press!'), true);
      expect(mediaService.hasDemonstration('plate pinch hold'), true);
    });

    test('Generates media inventory coverage statistics for complete catalogue', () {
      final report = mediaService.getMediaInventoryReport();
      expect(report['total_catalogue_exercises'], 190);
      expect(report['verified_demonstrations_count'], 190);
      expect(report['bundled_offline_demonstrations_count'], 190);
      expect(report['photographic_fallbacks_count'], 0);
    });
  });
}
