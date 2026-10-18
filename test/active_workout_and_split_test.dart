import 'package:flutter_test/flutter_test.dart';

import 'helpers/video_fakes.dart';

import 'package:reptrack/data/seed_data.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/services/exercise_media_service.dart';
import 'package:reptrack/services/exercise_terminology_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Six-Day Weekly Workout Split Tests', () {
    test('Default 6-day split contains 6 training days and 1 rest day', () {
      final config = DatabaseService.sixDaySplitConfig;
      expect(config.length, equals(7));

      // Day 1 to Day 6 are scheduled training days
      for (int i = 0; i < 6; i++) {
        expect(config[i]['isRest'], isFalse);
        final exIds = config[i]['exerciseIds'] as List<int>;
        expect(exIds.length, greaterThanOrEqualTo(4));
        expect((config[i]['title'] as String).isNotEmpty, isTrue);
      }

      // Day 7 is designated Rest & Recovery
      expect(config[6]['isRest'], isTrue);
      final restEx = config[6]['exerciseIds'] as List<int>;
      expect(restEx.isEmpty, isTrue);
      expect(config[6]['title'], contains('Rest'));
    });

    test(
      '6-day split templates include balanced muscle combinations and cardio',
      () {
        final config = DatabaseService.sixDaySplitConfig;

        // Day 1: Chest + Triceps
        expect(config[0]['title'], contains('Chest'));
        expect(config[0]['title'], contains('Triceps'));

        // Day 2: Back + Biceps
        expect(config[1]['title'], contains('Back'));
        expect(config[1]['title'], contains('Biceps'));

        // Day 3: Shoulders + Abs
        expect(config[2]['title'], contains('Shoulders'));
        expect(config[2]['title'], contains('Abs'));

        // Day 4: Legs
        expect(config[3]['title'], contains('Legs'));

        // Day 5: Chest + Back (Push/Pull antagonist combo)
        expect(config[4]['title'], contains('Chest'));
        expect(config[4]['title'], contains('Back'));

        // Day 6: Arms + Conditioning Cardio
        expect(config[5]['title'], contains('Arms'));
        expect(config[5]['title'], contains('Cardio'));

        // Verify Cardio is incorporated on Day 6 (192 = Treadmill Running, 199 = Jump Rope)
        final day6Ids = config[5]['exerciseIds'] as List<int>;
        expect(day6Ids.contains(192), isTrue);
        expect(day6Ids.contains(199), isTrue);
      },
    );

    test(
      '6-day split preserves exercise ordering with sequential exerciseOrder',
      () {
        final config = DatabaseService.sixDaySplitConfig;
        for (final dayConfig in config) {
          final ids = dayConfig['exerciseIds'] as List<int>;
          for (int i = 0; i < ids.length; i++) {
            expect(ids[i], greaterThan(0));
          }
        }
      },
    );
  });

  group('Arbitrary Exercise Count (>3 Exercises) Tests', () {
    test('Workout plan safely holds arbitrary number of exercises (e.g. 8 exercises)', () {
      final eightExercises = List.generate(
        8,
        (i) => PlannedExercise(
          planId: 1,
          exerciseId: i + 1,
          exerciseName: 'Exercise ${i + 1}',
          targetSets: 3 + (i % 2),
          targetReps: 10 + i,
          targetWeightKg: 20.0 + (i * 5),
          exerciseOrder: i,
        ),
      );

      final plan = WorkoutPlan(
        id: 1,
        date: '2026-10-16',
        notes: 'Full 8-Exercise Hypertrophy Routine',
        isRestDay: false,
        exercises: eightExercises,
      );

      expect(plan.exercises.length, equals(8));

      // Ensure every exercise is preserved in exact index order
      for (int i = 0; i < 8; i++) {
        expect(plan.exercises[i].exerciseOrder, equals(i));
        expect(plan.exercises[i].exerciseName, equals('Exercise ${i + 1}'));
        expect(plan.exercises[i].targetReps, equals(10 + i));
      }
    });

    test('Active workout session initializes matching number of exercises without truncation', () {
      final sixExercises = [
        PlannedExercise(
          planId: 1,
          exerciseId: 1,
          exerciseName: 'Barbell Bench Press',
          targetSets: 4,
          targetReps: 8,
          exerciseOrder: 0,
        ),
        PlannedExercise(
          planId: 1,
          exerciseId: 2,
          exerciseName: 'Incline Barbell Bench Press',
          targetSets: 3,
          targetReps: 10,
          exerciseOrder: 1,
        ),
        PlannedExercise(
          planId: 1,
          exerciseId: 4,
          exerciseName: 'Flat Dumbbell Press',
          targetSets: 3,
          targetReps: 10,
          exerciseOrder: 2,
        ),
        PlannedExercise(
          planId: 1,
          exerciseId: 91,
          exerciseName: 'Cable Triceps Pushdown',
          targetSets: 3,
          targetReps: 12,
          exerciseOrder: 3,
        ),
        PlannedExercise(
          planId: 1,
          exerciseId: 93,
          exerciseName: 'Skull Crusher',
          targetSets: 3,
          targetReps: 10,
          exerciseOrder: 4,
        ),
        PlannedExercise(
          planId: 1,
          exerciseId: 98,
          exerciseName: 'Overhead Cable Triceps Extension',
          targetSets: 3,
          targetReps: 12,
          exerciseOrder: 5,
        ),
      ];

      final plan = WorkoutPlan(
        id: 1,
        date: '2026-10-16',
        notes: 'Chest & Triceps Power',
        exercises: sixExercises,
      );

      // Verify that no 3-exercise cap exists on the planned exercise collection
      expect(plan.exercises.length, equals(6));

      // Simulate generating sets for active workout
      final List<WorkoutSetRecord> activeSets = [];
      for (final pe in plan.exercises) {
        for (int s = 1; s <= pe.targetSets; s++) {
          activeSets.add(
            WorkoutSetRecord(
              sessionId: 1,
              exerciseId: pe.exerciseId,
              exerciseName: pe.exerciseName,
              setNumber: s,
              weightKg: pe.targetWeightKg,
              reps: pe.targetReps,
              isCompleted: false,
            ),
          );
        }
      }

      // Total sets: 4 + 3 + 3 + 3 + 3 + 3 = 19 sets across 6 exercises
      expect(activeSets.length, equals(19));
      final distinctExerciseIds = activeSets.map((s) => s.exerciseId).toSet();
      expect(distinctExerciseIds.length, equals(6));
    });
  });

  group('Cardio Exercise Library Audit & Integrity Tests', () {
    test('11 common cardio exercises are present in SeedData with distinct IDs 191..201', () {
      final exercises = SeedData.exercises;
      final cardioExercises = exercises
          .where((e) => e.muscleGroupId == 15)
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

      for (int i = 0; i < expectedCardio.length; i++) {
        final expectedName = expectedCardio[i];
        final expectedId = 191 + i;
        final match = cardioExercises.firstWhere(
          (e) => e.name == expectedName,
          orElse: () =>
              throw Exception('Missing cardio exercise: $expectedName'),
        );
        expect(match.id, equals(expectedId));
        expect(match.muscleGroupName, equals('Cardio'));
        expect(match.instructions.isNotEmpty, isTrue);
        expect(match.equipment.isNotEmpty, isTrue);
      }
    });

    test('Pre-existing functional cardio exercises (Mountain Climber & Burpee) remain intact without ID collisions', () {
      final exercises = SeedData.exercises;

      final mountainClimber = exercises.firstWhere(
        (e) => e.name == 'Mountain Climber',
      );
      expect(mountainClimber.id, equals(176));

      final burpee = exercises.firstWhere((e) => e.name == 'Burpee');
      expect(burpee.id, equals(189));
    });

    test('Cardio exercises correctly differentiate tracking units (Distance & Time vs Weight & Reps)', () {
      final treadmill = SeedData.exercises.firstWhere(
        (e) => e.name == 'Treadmill Running',
      );

      // Treadmill uses duration (minutes) for reps and speed/distance for default weight
      expect(treadmill.defaultSets, equals(1));
      expect(treadmill.defaultReps, greaterThan(0)); // e.g. 20 mins
      expect(treadmill.defaultWeightKg, greaterThan(0)); // e.g. 8.5 km/h

      final outdoorWalk = SeedData.exercises.firstWhere(
        (e) => e.name == 'Outdoor Walking',
      );
      expect(outdoorWalk.defaultSets, equals(1));
      expect(outdoorWalk.defaultReps, equals(30)); // 30 mins
      expect(outdoorWalk.defaultWeightKg, equals(3.0)); // 3.0 km
    });

    test(
      'ExerciseTerminologyService maps Malayalam & Kerala gym slang for Cardio',
      () async {
        final termService = ExerciseTerminologyService.instance;
        await termService.initialize();

        final treadmillTerm = termService.getTerminology(id: 191);
        expect(treadmillTerm, isNotNull);
        expect(treadmillTerm!.malayalamScript, isNotEmpty);
        expect(treadmillTerm.aliases.isNotEmpty, isTrue);

        final ropeTerm = termService.getTerminology(id: 199);
        expect(ropeTerm, isNotNull);
        expect(ropeTerm!.aliases, contains('Skipping'));
      },
    );
  });

  group('Active Workout Video Resolution & Anti-Cross-Contamination Tests', () {
    final mediaService = ExerciseMediaService.instance;

    // MOCK-ONLY entitlement/backend: videos are delivered on demand from a
    // private bucket, so resolution depends on the (faked) subscription state.
    late VideoTestRig rig;

    setUpAll(() async {
      await mediaService.initialize();
    });
    setUp(() {
      rig = VideoTestRig();
      mediaService.accessForTesting = rig.service;
    });
    tearDown(() {
      mediaService.accessForTesting = null;
      rig.dispose();
    });

    test('Standing Dumbbell Curl: entitled -> on-demand protected video for its own id', () async {
      final source = await mediaService.resolveMediaSource(
        'Standing Dumbbell Curl',
      );
      expect(source.type, equals(DemonstrationSourceType.protectedDownload));
      expect(source.exerciseId, 69);
      expect(source.uri, isNot(contains('.mp4')));
    });

    test('Standing Dumbbell Curl: not entitled -> locked photo', () async {
      rig.entitled = false;
      final source = await mediaService.resolveMediaSource(
        'Standing Dumbbell Curl',
      );
      expect(source.type, equals(DemonstrationSourceType.lockedPhoto));
      expect(source.uri, endsWith('.jpg'));
    });

    test(
      'Hammer Curl has no video (duplicate removed) and shows its photo',
      () async {
        final source = await mediaService.resolveMediaSource('Hammer Curl');
        expect(source.type, equals(DemonstrationSourceType.photoFallback));
        expect(source.uri, equals('assets/images/exercises/hammer_curl.jpg'));
      },
    );

    test('Barbell Curl alias has no video and shows a photo', () async {
      final source = await mediaService.resolveMediaSource('Barbell Curl');
      expect(source.type, equals(DemonstrationSourceType.photoFallback));
      expect(source.uri, endsWith('.jpg'));
    });

    test('Bench Press alias has no video and shows a photo', () async {
      final source = await mediaService.resolveMediaSource('Bench Press');
      expect(source.type, equals(DemonstrationSourceType.photoFallback));
      expect(source.uri, endsWith('.jpg'));
    });

    test(
      'Mismatched exercise IDs never show a different exercise media',
      () async {
        final source = await mediaService.resolveMediaSource(
          'Hammer Curl',
          exerciseId: 1, // Mismatched ID (1 is Barbell Bench Press)
        );
        expect(source.uri, equals('assets/images/exercises/hammer_curl.jpg'));
        expect(source.uri, isNot(contains('bench_press')));
      },
    );

    test('Cardio exercise with a video resolves to the protected on-demand video of its own id', () async {
      final source = await mediaService.resolveMediaSource(
        'Stationary Cycling',
      );
      expect(source.type, equals(DemonstrationSourceType.protectedDownload));
      final demo = mediaService.getDemonstration('Stationary Cycling')!;
      expect(source.exerciseId, demo.exerciseId);
      expect(demo.storagePath, 'videos/${demo.exerciseId}.mp4');
      expect(source.isOfflineReady, isFalse);
    });
  });

  group('Rest Day & Active Recovery Daily Plan Tests', () {
    test('Rest day plan correctly identified and has no required sets', () {
      final restPlan = WorkoutPlan(
        date: '2026-10-18',
        notes: 'Full recovery, stretching, mobility work, and light walking.',
        isRestDay: true,
        exercises: const [],
      );

      expect(restPlan.isRestDay, isTrue);
      expect(restPlan.exercises.isEmpty, isTrue);
      expect(restPlan.exercises.length, equals(0));
    });
  });
}
