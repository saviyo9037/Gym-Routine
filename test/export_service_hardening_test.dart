import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/services/export_service.dart';

WorkoutSession sessionWith(String exercise, {String muscle = 'Chest'}) =>
    WorkoutSession(
      date: '2026-10-20',
      startTime: '07:00',
      primaryMuscle: muscle,
      sets: [
        WorkoutSetRecord(
          sessionId: 1,
          exerciseId: 1,
          exerciseName: exercise,
          setNumber: 1,
          reps: 5,
          weightKg: 60,
        ),
      ],
    );

void main() {
  test('CSV: formula-looking text is neutralised, numbers are untouched', () {
    final csv = ExportService.buildCsv([
      sessionWith('=HYPERLINK("http://evil","x")'),
      sessionWith('+SUM(A1)'),
      sessionWith('@cmd', muscle: '-2+3'),
      sessionWith('Normal, with comma'),
    ]);
    final lines = csv.trim().split('\n');
    expect(
      lines[1],
      contains("\"'=HYPERLINK(\"\"http://evil\"\",\"\"x\"\")\""),
    );
    expect(lines[2], contains("'+SUM(A1)"));
    expect(lines[3], contains("'@cmd"));
    expect(lines[3], contains("'-2+3"));
    expect(lines[4], contains('"Normal, with comma"'));
    // weight stays a bare number
    expect(lines[1].split(',').contains('60.0'), isTrue);
  });

  test('CSV: quotes and newlines are escaped', () {
    final csv = ExportService.buildCsv([sessionWith('He said "hi"\nbye')]);
    expect(csv, contains('"He said ""hi""\nbye"'));
  });
}
