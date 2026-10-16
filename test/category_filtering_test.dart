import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/seed_data.dart';
import 'package:reptrack/screens/exercise_library_screen.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/services/exercise_terminology_service.dart';

void main() {
  group('RepTrack Category Organization and Exercise Filtering Tests', () {
    test('1. Verify all 8 required Main Categories are available and properly mapped', () {
      final mainCategories = ExerciseLibraryScreen.mainCategories;
      expect(mainCategories.length, equals(8));

      final expectedMain = [
        'Chest',
        'Triceps',
        'Back',
        'Biceps',
        'Legs',
        'Abs / Core',
        'Shoulders',
        'Cardio',
      ];

      final actualNames = mainCategories.map((m) => m.name).toList();
      for (final expected in expectedMain) {
        expect(
          actualNames,
          contains(expected),
          reason: 'Missing main category: $expected',
        );
      }

      // Verify each main category has a non-null, valid banner image
      for (final mg in mainCategories) {
        expect(mg.imagePath, isNotNull);
        final file = File(mg.imagePath!);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Main category banner image missing: ${mg.imagePath}',
        );
      }
    });

    test(
      '2. Verify all existing catalogue categories are preserved and distinct',
      () {
        final seedGroups = SeedData.muscleGroups;
        expect(seedGroups.length, equals(15));

        final preservedGroups = [
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
        ];

        final actualSeedNames = seedGroups.map((g) => g.name).toList();
        for (final name in preservedGroups) {
          expect(
            actualSeedNames,
            contains(name),
            reason: 'Preserved category missing from catalogue: $name',
          );
        }
      },
    );

    test(
      '3. Verify exact exercise count and zero partition overlap in seed data',
      () {
        final exercises = SeedData.exercises;
        expect(exercises.length, equals(201));

        // Check unique IDs and names (no duplicate records)
        final ids = <int>{};
        final names = <String>{};
        for (final ex in exercises) {
          expect(ex.id, isNotNull);
          expect(
            ids.contains(ex.id),
            isFalse,
            reason: 'Duplicate exercise ID: ${ex.id}',
          );
          ids.add(ex.id!);

          expect(
            names.contains(ex.name),
            isFalse,
            reason: 'Duplicate exercise name: ${ex.name}',
          );
          names.add(ex.name);
        }

        // Check partition counts by primary muscle group
        final countByGroup = <String, int>{};
        for (final ex in exercises) {
          countByGroup[ex.muscleGroupName] =
              (countByGroup[ex.muscleGroupName] ?? 0) + 1;
        }

        expect(countByGroup['Chest'], equals(22));
        expect(countByGroup['Triceps'], equals(19));
        expect(countByGroup['Back'], equals(10));
        expect(countByGroup['Lats'], equals(9));
        expect(countByGroup['Upper Back and Traps'], equals(10));
        expect(countByGroup['Shoulders'], equals(17));
        expect(countByGroup['Biceps'], equals(22));
        expect(countByGroup['Forearms'], equals(9));
        expect(countByGroup['Quadriceps'], equals(16));
        expect(countByGroup['Hamstrings'], equals(11));
        expect(countByGroup['Glutes'], equals(9));
        expect(countByGroup['Calves'], equals(7));
        expect(countByGroup['Abs and Core'], equals(20));
        expect(countByGroup['Full Body'], equals(9));
        expect(countByGroup['Cardio'], equals(11));

        // Sum of all primary muscle groups must equal 201
        final totalSum = countByGroup.values.fold<int>(0, (a, b) => a + b);
        expect(totalSum, equals(201));
      },
    );

    test('4. Verify primary category filtering isolation (Chest vs Triceps isolation)', () {
      final exercises = SeedData.exercises;

      // Chest primary filter must return exactly 22 exercises
      final chestExercises = exercises
          .where((e) => e.muscleGroupName == 'Chest')
          .toList();
      expect(chestExercises.length, equals(22));

      // None of the chest exercises should have primary muscle 'Triceps'
      for (final ex in chestExercises) {
        expect(ex.muscleGroupName, equals('Chest'));
      }

      // Triceps primary filter must return exactly 19 exercises
      final tricepsExercises = exercises
          .where((e) => e.muscleGroupName == 'Triceps')
          .toList();
      expect(tricepsExercises.length, equals(19));

      // Ensure Standard Barbell Bench Press (which has secondary Triceps) is NOT in primary Triceps
      final benchInTriceps = tricepsExercises
          .where((e) => e.name == 'Barbell Bench Press')
          .toList();
      expect(
        benchInTriceps,
        isEmpty,
        reason: 'Barbell Bench Press should not be in primary Triceps group',
      );

      // Close-Grip Bench Press is specifically a Triceps builder
      final closeGripInTriceps = tricepsExercises
          .where((e) => e.name == 'Close-Grip Bench Press')
          .toList();
      expect(closeGripInTriceps.length, equals(1));

      // Barbell Bench Press MUST be in primary Chest
      final benchInChest = chestExercises
          .where((e) => e.name == 'Barbell Bench Press')
          .toList();
      expect(benchInChest.length, equals(1));
      expect(benchInChest.first.secondaryMuscles, contains('Triceps'));
    });

    test(
      '5. Verify parent Legs and Back groups with distinct sub-categories',
      () {
        final exercises = SeedData.exercises;

        // Legs parent group: Quadriceps (16) + Hamstrings (11) + Glutes (9) + Calves (7) = 43
        const legGroups = ['Quadriceps', 'Hamstrings', 'Glutes', 'Calves'];
        final legExercises = exercises
            .where((e) => legGroups.contains(e.muscleGroupName))
            .toList();
        expect(legExercises.length, equals(43));

        // Sub-groups must be distinct and non-empty
        final quads = exercises
            .where((e) => e.muscleGroupName == 'Quadriceps')
            .toList();
        final hams = exercises
            .where((e) => e.muscleGroupName == 'Hamstrings')
            .toList();
        final glutes = exercises
            .where((e) => e.muscleGroupName == 'Glutes')
            .toList();
        final calves = exercises
            .where((e) => e.muscleGroupName == 'Calves')
            .toList();

        expect(quads.length, equals(16));
        expect(hams.length, equals(11));
        expect(glutes.length, equals(9));
        expect(calves.length, equals(7));

        // Back parent group: Back (10) + Lats (9) + Upper Back and Traps (10) = 29
        const backGroups = ['Back', 'Lats', 'Upper Back and Traps'];
        final backExercises = exercises
            .where((e) => backGroups.contains(e.muscleGroupName))
            .toList();
        expect(backExercises.length, equals(29));

        final lats = exercises
            .where((e) => e.muscleGroupName == 'Lats')
            .toList();
        final traps = exercises
            .where((e) => e.muscleGroupName == 'Upper Back and Traps')
            .toList();
        final midBack = exercises
            .where((e) => e.muscleGroupName == 'Back')
            .toList();

        expect(lats.length, equals(9));
        expect(traps.length, equals(10));
        expect(midBack.length, equals(10));
      },
    );

    test('6. Verify Cardio exercises are isolated under Cardio and not mixed into strength', () {
      final exercises = SeedData.exercises;

      final cardioExercises = exercises
          .where((e) => e.muscleGroupName == 'Cardio')
          .toList();
      expect(cardioExercises.length, equals(11));

      final expectedCardio = [
        'Treadmill Walking',
        'Treadmill Running',
        'Outdoor Walking',
        'Outdoor Running',
        'Stationary Cycling',
        'Elliptical Trainer',
        'Rowing Machine',
        'Stair Climber',
        'Jump Rope',
        'Jumping Jacks',
        'High Knees',
      ];

      final cardioNames = cardioExercises.map((c) => c.name).toList();
      for (final expected in expectedCardio) {
        expect(cardioNames, contains(expected));
      }

      // Verify none of the cardio exercises are listed under Chest, Back, Triceps, etc.
      for (final ex in exercises.where((e) => e.muscleGroupName != 'Cardio')) {
        expect(cardioNames.contains(ex.name), isFalse);
      }
    });

    test(
      '7. Verify secondary muscle filtering does not create duplicate entries',
      () {
        final exercises = SeedData.exercises;

        // Filter exercises where secondary muscle includes 'Triceps'
        final withSecondaryTriceps = exercises
            .where((e) => e.secondaryMuscles.toLowerCase().contains('tricep'))
            .toList();

        // Chest exercises like Bench Press, Incline Press, Dips should have secondary Triceps
        expect(withSecondaryTriceps.isNotEmpty, isTrue);

        // Verify each exercise in this filtered list has a unique ID (no duplicate records)
        final seenIds = <int>{};
        for (final ex in withSecondaryTriceps) {
          expect(seenIds.contains(ex.id), isFalse);
          seenIds.add(ex.id!);
        }
      },
    );

    test(
      '8. Verify search and category filter combinations work synergistically',
      () {
        final exercises = SeedData.exercises;
        final termService = ExerciseTerminologyService.instance;

        // Search 'press' in Chest
        final chestPress = exercises
            .where((e) => e.muscleGroupName == 'Chest')
            .where((e) => termService.matchesSearch(e, 'press'))
            .toList();
        expect(chestPress.isNotEmpty, isTrue);
        for (final ex in chestPress) {
          expect(ex.muscleGroupName, equals('Chest'));
        }

        // Search 'curl' in Biceps
        final bicepCurls = exercises
            .where((e) => e.muscleGroupName == 'Biceps')
            .where((e) => termService.matchesSearch(e, 'curl'))
            .toList();
        expect(bicepCurls.length, greaterThanOrEqualTo(10));
        for (final ex in bicepCurls) {
          expect(ex.muscleGroupName, equals('Biceps'));
        }

        // Search 'leg' slang maps to leg exercises
        final legMatches = exercises
            .where((e) => termService.matchesSearch(e, 'leg'))
            .toList();
        expect(legMatches.length, greaterThanOrEqualTo(30));
      },
    );

    test('9. Verify video demonstration mapping integrity and fallback safety', () {
      final exercises = SeedData.exercises;

      final file = File('assets/exercise_demonstrations.json');
      expect(file.existsSync(), isTrue);
      final Map<String, dynamic> demoRegistry = json.decode(
        file.readAsStringSync(),
      );

      final verifiedNames = [
        'Standing Dumbbell Curl',
        'Hammer Curl',
        'Standing EZ-Bar Curl',
        'Barbell Bench Press',
        'Barbell Back Squat',
        'Conventional Deadlift',
      ];

      for (final name in verifiedNames) {
        expect(
          demoRegistry.containsKey(name),
          isTrue,
          reason: 'Expected entry in demonstration registry for: $name',
        );
        final entry = demoRegistry[name] as Map<String, dynamic>;
        expect(entry['has_video'], isTrue);
        final localPath = entry['local_bundled_path'] as String?;
        expect(localPath, isNotNull);
        expect(localPath!.endsWith('.mp4'), isTrue);
        final videoFile = File(localPath);
        expect(
          videoFile.existsSync(),
          isTrue,
          reason: 'Demonstration video file must exist: $localPath',
        );
      }

      // For every exercise, verify image fallback is intact
      for (final ex in exercises) {
        expect(ex.imagePath, isNotNull);
        final imgFile = File(ex.imagePath!);
        expect(
          imgFile.existsSync(),
          isTrue,
          reason:
              'Every exercise must have a verified local image asset fallback: ${ex.imagePath}',
        );
      }
    });

    test('10. Verify daily workout split assignments preserve cardio and strength balance', () {
      final config = DatabaseService.sixDaySplitConfig;
      expect(config.length, equals(7)); // 6 training days + 1 rest day

      // Training days
      for (int i = 0; i < 6; i++) {
        final day = config[i];
        expect(day['isRest'], isFalse);
        final ids = day['exerciseIds'] as List<int>;
        expect(ids.length, inInclusiveRange(4, 9));
        // Verify no duplicate exercises within the same workout day
        expect(ids.toSet().length, equals(ids.length));
      }

      // Rest day has 0 exercises
      expect(config[6]['isRest'], isTrue);
      final restIds = config[6]['exerciseIds'] as List<int>;
      expect(restIds.isEmpty, isTrue);

      // Cardio is scheduled on Day 6 (192 = Treadmill Running, 199 = Jump Rope)
      final day6Ids = config[5]['exerciseIds'] as List<int>;
      expect(day6Ids.contains(192), isTrue);
      expect(day6Ids.contains(199), isTrue);
    });
  });
}
