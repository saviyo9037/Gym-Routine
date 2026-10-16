import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/models/exercise.dart';
import 'package:reptrack/data/seed_data.dart';
import 'package:reptrack/screens/exercise_library_screen.dart';

void main() {
  group('Comprehensive Gym Exercise Library Expansion Tests', () {
    test(
      'Verifies 15 target muscle groups are defined with valid asset banners',
      () {
        final groups = SeedData.muscleGroups;
        expect(groups.length, equals(15));

        final expectedNames = [
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

        final actualNames = groups.map((g) => g.name).toList();
        for (final expected in expectedNames) {
          expect(
            actualNames,
            contains(expected),
            reason: 'Missing muscle group: $expected',
          );
        }

        // Verify each muscle group has an existing bundled banner image
        for (final mg in groups) {
          expect(mg.imagePath, isNotNull);
          final file = File(mg.imagePath!);
          expect(
            file.existsSync(),
            isTrue,
            reason: 'Missing banner asset for ${mg.name}: ${mg.imagePath}',
          );
        }
      },
    );

    test('Verifies 6 movement & equipment modalities are defined with valid asset banners', () {
      final modalities = ExerciseLibraryScreen.modalityCategories;
      expect(modalities.length, equals(6));

      final expectedModalities = [
        'Compound Exercises',
        'Bodyweight Exercises',
        'Cable Exercises',
        'Machine Exercises',
        'Dumbbell Exercises',
        'Barbell Exercises',
      ];

      final actualModalities = modalities.map((m) => m.name).toList();
      for (final expected in expectedModalities) {
        expect(
          actualModalities,
          contains(expected),
          reason: 'Missing modality category: $expected',
        );
      }

      for (final mod in modalities) {
        expect(mod.imagePath, isNotNull);
        final file = File(mod.imagePath!);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Missing banner asset for ${mod.name}: ${mod.imagePath}',
        );
      }
    });

    test('Verifies all 201 catalogue exercises have non-empty details and distinct local images', () {
      final exercises = SeedData.exercises;
      expect(exercises.length, equals(201));

      final seenNames = <String>{};
      final seenImages = <String>{};

      for (final ex in exercises) {
        // Name uniqueness - No duplicate database rows
        expect(
          seenNames.contains(ex.name),
          isFalse,
          reason: 'Duplicate exercise name found: ${ex.name}',
        );
        seenNames.add(ex.name);

        // Distinct demonstration images
        expect(ex.imagePath, isNotNull);
        expect(
          seenImages.contains(ex.imagePath),
          isFalse,
          reason: 'Duplicate image asset path reused: ${ex.imagePath}',
        );
        seenImages.add(ex.imagePath!);

        // File must physically exist in assets/images/exercises/
        final file = File(ex.imagePath!);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Missing asset file for ${ex.name}: ${ex.imagePath}',
        );

        // Complete educational content
        expect(
          ex.instructions.isNotEmpty,
          isTrue,
          reason: 'Missing instructions for ${ex.name}',
        );
        expect(
          ex.startingPosition.isNotEmpty,
          isTrue,
          reason: 'Missing starting position for ${ex.name}',
        );
        expect(
          ex.breathingGuidance.isNotEmpty,
          isTrue,
          reason: 'Missing breathing guidance for ${ex.name}',
        );
        expect(
          ex.commonMistakes.isNotEmpty,
          isTrue,
          reason: 'Missing common mistakes for ${ex.name}',
        );
        expect(
          ex.beginnerModification.isNotEmpty,
          isTrue,
          reason: 'Missing beginner modification for ${ex.name}',
        );
        expect(
          ex.equipment.isNotEmpty,
          isTrue,
          reason: 'Missing equipment for ${ex.name}',
        );
        expect(
          ex.target.isNotEmpty,
          isTrue,
          reason: 'Missing target for ${ex.name}',
        );
        expect(
          ex.difficulty.isNotEmpty,
          isTrue,
          reason: 'Missing difficulty for ${ex.name}',
        );
        expect(ex.defaultSets, greaterThan(0));
        expect(ex.defaultReps, greaterThan(0));
        expect(ex.restSeconds, greaterThan(0));
      }
    });

    test('Verifies exercise_asset_manifest.json contains all 201 entries and all paths exist', () {
      final manifestFile = File('assets/exercise_asset_manifest.json');
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: 'exercise_asset_manifest.json must exist',
      );

      final content = manifestFile.readAsStringSync();
      final Map<String, dynamic> manifest = json.decode(content);
      expect(manifest.length, equals(201));

      for (final entry in manifest.entries) {
        final path = entry.value['asset_path'] as String;
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Manifest entry ${entry.key} points to non-existent file: $path',
        );
      }
    });

    test('Verifies exercise model serialization preserves all enhanced library fields', () {
      final ex = Exercise(
        id: 1,
        muscleGroupId: 1,
        muscleGroupName: 'Chest',
        secondaryMuscles: 'Triceps Brachii, Anterior Deltoids',
        name: 'Barbell Bench Press',
        target: 'Pectoralis Major',
        description: 'Standard barbell press',
        startingPosition: 'Lie supine on bench',
        instructions: 'Lower to sternum and press',
        breathingGuidance: 'Inhale down, exhale up',
        beginnerModification: 'Use dumbbell press',
        equipment: 'Barbell',
        difficulty: 'Intermediate',
        suggestedSetsReps: '4 sets × 8 reps',
        commonMistakes: 'Flaring elbows 90 deg',
        defaultSets: 4,
        defaultReps: 8,
        defaultWeightKg: 60.0,
        restSeconds: 120,
        imagePath: 'assets/images/exercises/barbell_bench_press.jpg',
        isCompound: true,
        isFavourite: true,
        isRecommended: true,
      );

      final map = ex.toMap();
      expect(map['is_favourite'], equals(1));
      expect(map['is_recommended'], equals(1));
      expect(map['is_compound'], equals(1));
      expect(
        map['secondary_muscles'],
        equals('Triceps Brachii, Anterior Deltoids'),
      );
      expect(map['starting_position'], equals('Lie supine on bench'));
      expect(map['breathing_guidance'], equals('Inhale down, exhale up'));
      expect(map['beginner_modification'], equals('Use dumbbell press'));

      final fromMap = Exercise.fromMap(map);
      expect(fromMap.id, equals(1));
      expect(fromMap.isFavourite, isTrue);
      expect(fromMap.isRecommended, isTrue);
      expect(fromMap.isCompound, isTrue);
      expect(
        fromMap.secondaryMuscles,
        equals('Triceps Brachii, Anterior Deltoids'),
      );
      expect(fromMap.startingPosition, equals('Lie supine on bench'));
      expect(fromMap.breathingGuidance, equals('Inhale down, exhale up'));
      expect(fromMap.beginnerModification, equals('Use dumbbell press'));
    });
  });
}
