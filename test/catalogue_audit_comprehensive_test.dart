import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/seed_data.dart';
import 'package:reptrack/models/exercise.dart';
import 'package:reptrack/services/exercise_terminology_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catalogue-Wide Audit & Anti-Contamination Verification', () {
    late List<Exercise> allExercises;
    late Map<String, dynamic> demoRegistry;

    setUpAll(() {
      allExercises = SeedData.exercises;
      final file = File('assets/exercise_demonstrations.json');
      expect(file.existsSync(), isTrue);
      demoRegistry =
          json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('1. Every exercise has a valid primary category and stable unique ID', () {
      expect(allExercises.length, equals(201));

      final validCategories = {
        'Chest',
        'Back',
        'Lats',
        'Upper Back and Traps',
        'Shoulders',
        'Biceps',
        'Triceps',
        'Forearms',
        'Quadriceps',
        'Hamstrings',
        'Glutes',
        'Calves',
        'Abs and Core',
        'Full Body',
        'Cardio',
      };

      final seenIds = <int>{};
      final seenNames = <String>{};

      for (final ex in allExercises) {
        expect(ex.id, isNotNull);
        expect(ex.id, inInclusiveRange(1, 201));
        expect(
          seenIds.contains(ex.id),
          isFalse,
          reason: 'Duplicate ID: ${ex.id}',
        );
        seenIds.add(ex.id!);

        expect(
          seenNames.contains(ex.name),
          isFalse,
          reason: 'Duplicate Name: ${ex.name}',
        );
        seenNames.add(ex.name);

        expect(
          validCategories.contains(ex.muscleGroupName),
          isTrue,
          reason:
              'Exercise "${ex.name}" has invalid muscleGroupName: "${ex.muscleGroupName}"',
        );

        expect(ex.name.trim().isNotEmpty, isTrue);
        expect(ex.target.trim().isNotEmpty, isTrue);
        expect(ex.equipment.trim().isNotEmpty, isTrue);
        expect(ex.imagePath != null && ex.imagePath!.isNotEmpty, isTrue);
      }
    });

    test('2. Strict Lower-Body / Legs Isolation: Unrelated exercises NEVER appear under Legs', () {
      const legGroups = {'Quadriceps', 'Hamstrings', 'Glutes', 'Calves'};

      // A. Seed Data Isolation
      final legExercises = allExercises
          .where((e) => legGroups.contains(e.muscleGroupName))
          .toList();
      expect(
        legExercises.length,
        equals(43),
      ); // 16 Quads + 11 Hams + 9 Glutes + 7 Calves

      for (final ex in legExercises) {
        expect(
          legGroups.contains(ex.muscleGroupName),
          isTrue,
          reason:
              'Exercise "${ex.name}" has non-leg category "${ex.muscleGroupName}" in Legs',
        );
      }

      // Explicitly assert known potential cross-muscle confusion exercises are NOT in Legs
      final nonLegExercises = [
        'Sled Push', // Full Body
        'Sled Pull', // Full Body
        'Burpee', // Full Body
        'Kettlebell Swing', // Full Body
        'Bear Crawl', // Full Body
        'Outdoor Walking', // Cardio
        'Outdoor Running', // Cardio
        'Treadmill Walking', // Cardio
        'Treadmill Running', // Cardio
        'Rowing Machine', // Cardio
        'High Knees', // Cardio
        'Jumping Jacks', // Cardio
        'Bicycle Crunch', // Abs and Core
        'Hanging Leg Raise', // Abs and Core
        'Push-Up', // Chest
        'Barbell Bench Press', // Chest
        'Pull-Up', // Lats
        'Lat Pulldown', // Lats
        'Barbell Bent-Over Row', // Back
        'Standing Dumbbell Curl', // Biceps
        'Cable Triceps Pushdown', // Triceps
        'Dumbbell Lateral Raise', // Shoulders
      ];

      for (final nonLegName in nonLegExercises) {
        final match = legExercises.where((e) => e.name == nonLegName).toList();
        expect(
          match,
          isEmpty,
          reason:
              'Critical bug: "$nonLegName" incorrectly appeared in Legs category!',
        );
      }
    });

    test('3. Search terminology for "leg" or "legs" returns only true lower-body exercises', () {
      final termService = ExerciseTerminologyService.instance;
      const legGroups = {'Quadriceps', 'Hamstrings', 'Glutes', 'Calves'};

      // Query "legs"
      final legMatches = allExercises
          .where((e) => termService.matchesSearch(e, 'legs'))
          .toList();
      expect(legMatches.isNotEmpty, isTrue);

      for (final ex in legMatches) {
        expect(
          legGroups.contains(ex.muscleGroupName),
          isTrue,
          reason:
              'Exercise "${ex.name}" (${ex.muscleGroupName}) should not match category query "legs"',
        );
      }

      // Sled Push, Outdoor Walking, Rowing Machine must NOT match "legs"
      expect(legMatches.any((e) => e.name == 'Sled Push'), isFalse);
      expect(legMatches.any((e) => e.name == 'Outdoor Walking'), isFalse);
      expect(legMatches.any((e) => e.name == 'Outdoor Running'), isFalse);
      expect(legMatches.any((e) => e.name == 'Rowing Machine'), isFalse);
      expect(legMatches.any((e) => e.name == 'Bicycle Crunch'), isFalse);
    });

    test('4. Every one of the 15 categories returns its exact expected exercise count without leaks', () {
      final expectedCounts = {
        'Chest': 22,
        'Back': 10,
        'Lats': 9,
        'Upper Back and Traps': 10,
        'Shoulders': 17,
        'Biceps': 22,
        'Triceps': 19,
        'Forearms': 9,
        'Quadriceps': 16,
        'Hamstrings': 11,
        'Glutes': 9,
        'Calves': 7,
        'Abs and Core': 20,
        'Full Body': 9,
        'Cardio': 11,
      };

      for (final entry in expectedCounts.entries) {
        final categoryName = entry.key;
        final expectedCount = entry.value;

        final matched = allExercises
            .where((e) => e.muscleGroupName == categoryName)
            .toList();
        expect(
          matched.length,
          equals(expectedCount),
          reason:
              'Category "$categoryName" expected $expectedCount exercises, got ${matched.length}',
        );

        for (final ex in matched) {
          expect(ex.muscleGroupName, equals(categoryName));
        }
      }
    });

    test('5. Every exercise has a demonstration entry; 123 have a protected video path, 78 are NO_VIDEO (video content is not checked)', () {
      expect(demoRegistry.length, equals(201));
      var withVideo = 0;
      var noVideo = 0;

      for (final ex in allExercises) {
        expect(
          demoRegistry.containsKey(ex.name),
          isTrue,
          reason:
              'Exercise "${ex.name}" is missing from exercise_demonstrations.json',
        );

        final data = demoRegistry[ex.name] as Map<String, dynamic>;
        if (data['has_video'] == true) {
          withVideo++;
          expect(data['media_type'], equals('video'));
          // Videos are delivered from a private bucket, never bundled.
          expect(data['local_bundled_path'], isNull, reason: ex.name);
          expect(data['storage_path'], 'videos/${ex.id}.mp4', reason: ex.name);
        } else {
          noVideo++;
          expect(data['status'], 'NO_VIDEO', reason: ex.name);
          expect(data['local_bundled_path'], isNull, reason: ex.name);
          expect(data['storage_path'], isNull, reason: ex.name);
        }

        final cues = data['demonstration_cues'] as List<dynamic>?;
        expect(cues, isNotNull);
        expect(cues!.length, greaterThanOrEqualTo(3));
      }
      expect(withVideo, 123);
      expect(noVideo, 78);
    });

    test(
      '6. Secondary muscle search does not pollute primary category browsing',
      () {
        final termService = ExerciseTerminologyService.instance;

        // When searching primary, Barbell Bench Press has secondary Triceps,
        // but browsing Triceps should NOT include Barbell Bench Press.
        final tricepsExercises = allExercises
            .where((e) => e.muscleGroupName == 'Triceps')
            .toList();
        expect(
          tricepsExercises.any((e) => e.name == 'Barbell Bench Press'),
          isFalse,
        );

        // Only when matchSecondary is explicitly requested does secondary match
        final matchNoSecondary = termService.matchesSearch(
          allExercises.firstWhere((e) => e.name == 'Barbell Bench Press'),
          'triceps',
          matchSecondary: false,
        );
        expect(matchNoSecondary, isFalse);

        final matchWithSecondary = termService.matchesSearch(
          allExercises.firstWhere((e) => e.name == 'Barbell Bench Press'),
          'triceps',
          matchSecondary: true,
        );
        expect(matchWithSecondary, isTrue);
      },
    );
  });
}
