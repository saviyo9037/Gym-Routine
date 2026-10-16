import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/seed_data.dart';
import 'package:reptrack/models/exercise_terminology.dart';
import 'package:reptrack/services/exercise_media_service.dart';
import 'package:reptrack/services/exercise_terminology_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> terminologyJson;
  final allExercises = SeedData.exercises;

  setUpAll(() async {
    final file = File('assets/exercise_terminology.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'assets/exercise_terminology.json must exist',
    );
    final content = await file.readAsString();
    terminologyJson = json.decode(content);

    // Initialize services
    await ExerciseMediaService.instance.initialize();
    await ExerciseTerminologyService.instance.initialize(jsonContent: content);
  });

  group('RepTrack Kerala Gym Terminology & Catalogue Integrity Tests', () {
    test('1. Catalogue Integrity: Exactly 201 exercises with stable consecutive IDs (1..201)', () {
      expect(allExercises.length, equals(201));

      final ids = allExercises.map((e) => e.id!).toList();
      expect(
        ids.toSet().length,
        equals(201),
        reason: 'Exercise IDs must be strictly unique',
      );

      for (int i = 1; i <= 201; i++) {
        expect(
          ids.contains(i),
          isTrue,
          reason: 'Exercise with stable ID $i must exist',
        );
      }
    });

    test('2. Terminology Coverage: All 201 exercises are mapped in exercise_terminology.json', () {
      expect(terminologyJson.length, equals(201));

      for (final ex in allExercises) {
        expect(
          terminologyJson.containsKey(ex.name),
          isTrue,
          reason: 'Missing terminology mapping for exercise: ${ex.name}',
        );

        final termMap = Map<String, dynamic>.from(terminologyJson[ex.name]);
        final term = ExerciseTerminology.fromMap(termMap);

        expect(term.exerciseId, equals(ex.id));
        expect(term.originalName, equals(ex.name));
        expect(term.recommendedDisplayName.isNotEmpty, isTrue);
        expect(term.formalName.isNotEmpty, isTrue);
        expect(term.aliases.isNotEmpty, isTrue);
        expect(term.keralaGymNotes.isNotEmpty, isTrue);
        expect(term.malayalamScript.isNotEmpty, isTrue);
        expect([
          'KEEP',
          'RENAME',
          'ADD ALIAS',
          'REVIEW',
        ], contains(term.status));
      }
    });

    test('3. Search Aliases: Common Kerala gym terms and acronyms match correct exercises without duplicates', () {
      final service = ExerciseTerminologyService.instance;

      // Test "RDL" matches Romanian Deadlift
      final rdlMatches = allExercises
          .where((e) => service.matchesSearch(e, 'rdl'))
          .toList();
      expect(rdlMatches.isNotEmpty, isTrue);
      expect(
        rdlMatches.map((e) => e.id).toSet().length,
        equals(rdlMatches.length),
        reason: 'Search must not produce duplicate records',
      );
      expect(
        rdlMatches.any(
          (e) => e.name.toLowerCase().contains('romanian deadlift'),
        ),
        isTrue,
        reason: '"rdl" must match Romanian Deadlift',
      );

      // Test "lat pull" matches Lat Pulldown
      final latPullMatches = allExercises
          .where((e) => service.matchesSearch(e, 'lat pull'))
          .toList();
      expect(latPullMatches.isNotEmpty, isTrue);
      expect(
        latPullMatches.any((e) => e.name.toLowerCase().contains('pulldown')),
        isTrue,
      );

      // Test "pec deck" and "butterfly" match Pec Deck Fly
      final butterflyMatches = allExercises
          .where((e) => service.matchesSearch(e, 'butterfly'))
          .toList();
      expect(butterflyMatches.isNotEmpty, isTrue);
      expect(
        butterflyMatches.any(
          (e) => e.name.toLowerCase().contains('pec deck fly'),
        ),
        isTrue,
      );

      final pecDeckMatches = allExercises
          .where((e) => service.matchesSearch(e, 'pec deck'))
          .toList();
      expect(pecDeckMatches.isNotEmpty, isTrue);
      expect(
        pecDeckMatches.any(
          (e) => e.name.toLowerCase().contains('pec deck fly'),
        ),
        isTrue,
      );

      // Test "skull crusher" matches Lying Triceps Extension
      final skullMatches = allExercises
          .where((e) => service.matchesSearch(e, 'skull crusher'))
          .toList();
      expect(skullMatches.isNotEmpty, isTrue);
      expect(
        skullMatches.any((e) => e.name.toLowerCase().contains('skull crusher')),
        isTrue,
      );

      // Test "ohp" matches Overhead Press
      final ohpMatches = allExercises
          .where((e) => service.matchesSearch(e, 'ohp'))
          .toList();
      expect(ohpMatches.isNotEmpty, isTrue);
      expect(
        ohpMatches.any((e) => e.name.toLowerCase().contains('overhead press')),
        isTrue,
      );
    });

    test('4. Muscle Slang Search: "wings", "quads", "thighs", "hams", "delts" discover correct muscle groups', () {
      final service = ExerciseTerminologyService.instance;

      // "wings" -> Lats
      final wingMatches = allExercises
          .where((e) => service.matchesSearch(e, 'wings'))
          .toList();
      expect(wingMatches.isNotEmpty, isTrue);
      expect(
        wingMatches.every(
          (e) => e.muscleGroupName.toLowerCase().contains('lats'),
        ),
        isTrue,
        reason: 'Wings must map to Lats exercises',
      );

      // "quads" -> Quadriceps
      final quadMatches = allExercises
          .where((e) => service.matchesSearch(e, 'quads'))
          .toList();
      expect(quadMatches.isNotEmpty, isTrue);
      expect(
        quadMatches.every(
          (e) => e.muscleGroupName.toLowerCase().contains('quadriceps'),
        ),
        isTrue,
        reason: 'Quads must map to Quadriceps exercises',
      );

      // "thighs" -> Quadriceps
      final thighMatches = allExercises
          .where((e) => service.matchesSearch(e, 'thighs'))
          .toList();
      expect(thighMatches.isNotEmpty, isTrue);
      expect(
        thighMatches.any(
          (e) => e.muscleGroupName.toLowerCase().contains('quadriceps'),
        ),
        isTrue,
      );

      // "delts" -> Shoulders
      final deltMatches = allExercises
          .where((e) => service.matchesSearch(e, 'delts'))
          .toList();
      expect(deltMatches.isNotEmpty, isTrue);
      expect(
        deltMatches.every(
          (e) => e.muscleGroupName.toLowerCase().contains('shoulders'),
        ),
        isTrue,
      );
    });

    test('5. Equipment Terminology Search: "db", "bb", "ez" match correct equipment categories', () {
      final service = ExerciseTerminologyService.instance;

      final dbMatches = allExercises
          .where((e) => service.matchesSearch(e, 'db'))
          .toList();
      expect(dbMatches.isNotEmpty, isTrue);
      expect(
        dbMatches.every((e) => e.equipment.toLowerCase().contains('dumbbell')),
        isTrue,
      );

      final bbMatches = allExercises
          .where((e) => service.matchesSearch(e, 'bb'))
          .toList();
      expect(bbMatches.isNotEmpty, isTrue);
      expect(
        bbMatches.every((e) => e.equipment.toLowerCase().contains('barbell')),
        isTrue,
      );

      final ezMatches = allExercises
          .where((e) => service.matchesSearch(e, 'ez'))
          .toList();
      expect(ezMatches.isNotEmpty, isTrue);
      expect(
        ezMatches.every(
          (e) =>
              e.equipment.toLowerCase().contains('ez') ||
              e.name.toLowerCase().contains('ez'),
        ),
        isTrue,
      );
    });

    test('6. Distinct Variations: Different variations remain distinctly distinguishable', () {
      final deadlifts = allExercises
          .where((e) => e.name.toLowerCase().contains('deadlift'))
          .toList();
      expect(deadlifts.length, greaterThanOrEqualTo(4));

      final deadliftNames = deadlifts.map((e) => e.name).toList();
      expect(deadliftNames, contains('Conventional Deadlift'));
      expect(deadliftNames, contains('Romanian Deadlift'));
      expect(deadliftNames, contains('Stiff-Leg Deadlift'));
      expect(deadliftNames, contains('Single-Leg Romanian Deadlift'));

      // Variations must have different IDs
      final deadliftIds = deadlifts.map((e) => e.id).toSet();
      expect(deadliftIds.length, equals(deadlifts.length));

      // Biceps variations distinct
      final biceps = allExercises.where((e) => e.muscleGroupId == 6).toList();
      final bicepsNames = biceps.map((e) => e.name).toList();
      expect(bicepsNames, contains('Standing Dumbbell Curl'));
      expect(bicepsNames, contains('Alternating Dumbbell Curl'));
      expect(bicepsNames, contains('Hammer Curl'));
      expect(bicepsNames, contains('Preacher Curl'));
      expect(bicepsNames, contains('Concentration Curl'));
    });

    test('7. Media Mapping Integrity: All 201 exercises correspond to verified offline demonstration videos', () {
      final mediaService = ExerciseMediaService.instance;

      for (final ex in allExercises) {
        final demo =
            mediaService.getDemonstrationById(ex.id!) ??
            mediaService.getDemonstration(ex.name);

        expect(
          demo,
          isNotNull,
          reason:
              'Exercise ${ex.id} (${ex.name}) must have a valid demonstration',
        );
        expect(
          demo!.hasVideo,
          isTrue,
          reason:
              'Exercise ${ex.id} (${ex.name}) must have a demonstration video',
        );
        expect(demo.localBundledPath, isNotNull);

        final videoFile = File(demo.localBundledPath!);
        expect(
          videoFile.existsSync(),
          isTrue,
          reason:
              'Video file must physically exist on disk: ${demo.localBundledPath}',
        );
      }
    });

    test('8. Terminology Service API: getDisplayName and friendly muscle labels return valid values', () {
      final service = ExerciseTerminologyService.instance;

      final dbCurlName = service.getDisplayName(
        'Standing Dumbbell Curl',
        id: 69,
      );
      expect(dbCurlName, equals('Dumbbell Curl'));

      final hammerName = service.getDisplayName('Hammer Curl', id: 73);
      expect(hammerName, equals('Hammer Curl'));

      expect(
        service.getFriendlyMuscleName('Quadriceps'),
        equals('Quads (Front Thighs)'),
      );
      expect(
        service.getFriendlyMuscleName('Hamstrings'),
        equals('Hamstrings (Back of Thighs)'),
      );
      expect(service.getFriendlyMuscleName('Lats'), equals('Back (Lats)'));
      expect(service.getFriendlyMuscleName('Chest'), equals('Chest'));
    });
  });
}
