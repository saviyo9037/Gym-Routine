import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/safe_cast.dart';
import 'package:reptrack/models/exercise.dart';
import 'package:reptrack/models/routine.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:reptrack/models/workout_session.dart';

void main() {
  test('helpers convert or return null, never throw', () {
    expect(asInt(3), 3);
    expect(asInt(3.9), 3);
    expect(asInt('7'), 7);
    expect(asInt('7.0'), 7);
    expect(asInt('x'), isNull);
    expect(asInt(double.nan), isNull);
    expect(asInt(null), isNull);
    expect(asInt(true), 1);
    expect(asDouble('12,5'), 12.5);
    expect(asDouble(4), 4.0);
    expect(asDouble('x'), isNull);
    expect(asStr(5), '5');
    expect(asStr(null), isNull);
    expect(asStr([1]), isNull);
  });

  test('models survive values of the wrong storage type', () {
    final plan = WorkoutPlan.fromMap({
      'id': '5',
      'date': 20261020, // number where text is expected
      'is_completed': '1',
      'is_rest_day': 1.0,
      'primary_muscle_id': 'x',
    });
    expect(plan.id, 5);
    expect(plan.date, '20261020');
    expect(plan.isCompleted, isTrue);
    expect(plan.isRestDay, isTrue);
    expect(plan.primaryMuscleId, isNull);

    final set = WorkoutSetRecord.fromMap({
      'session_id': '2',
      'reps': '8',
      'weight_kg': '62,5',
      'is_completed': 1,
    });
    expect(set.sessionId, 2);
    expect(set.reps, 8);
    expect(set.weightKg, 62.5);

    final session = WorkoutSession.fromMap({
      'date': '2026-10-20',
      'start_time': '07:00',
      'duration_seconds': '3600',
    });
    expect(session.durationSeconds, 3600);

    final r = Routine.fromMap({
      'title': 7,
      'repeat_days': '1,2,x',
      'reminder_minutes_before': '15',
    });
    expect(r.title, '7');
    expect(r.reminderMinutesBefore, 15);

    final ex = Exercise.fromMap({
      'id': '4',
      'name': 'Fly',
      'default_sets': 'x',
      'default_weight_kg': '12,5',
    });
    expect(ex.id, 4);
    expect(ex.defaultSets, 3);
    expect(ex.defaultWeightKg, 12.5);

    // a completely empty row must not crash the non-null readers
    expect(() => Exercise.fromMap({}), returnsNormally);
    expect(() => WorkoutSession.fromMap({}), returnsNormally);
    expect(() => WorkoutPlan.fromMap({}), returnsNormally);
  });
}
