import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/workout_session.dart';
import 'database_service.dart';

/// Premium: export of the workout history as CSV or JSON.
/// (The full local backup in Settings stays free.)
class ExportService {
  ExportService({DatabaseService? db}) : _db = db ?? DatabaseService();
  final DatabaseService _db;

  static const csvHeader =
      'session_id,date,start,end,duration_seconds,primary_muscle,'
      'secondary_muscle,exercise,set,reps,weight_kg,completed,'
      'cardio_seconds,cardio_km';

  /// Spreadsheet apps run text that starts with = + - @ (or a tab/CR) as a
  /// formula. User-typed text (exercise names, notes) is neutralised with a
  /// leading apostrophe; numbers are written untouched.
  static const _formulaStarts = ['=', '+', '-', '@', '\t', '\r'];

  static String _csv(Object? v) {
    var s = v?.toString() ?? '';
    if (v is String && s.isNotEmpty && _formulaStarts.contains(s[0])) {
      s = "'$s";
    }
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// One row per set; sessions without sets still produce one row.
  static String buildCsv(List<WorkoutSession> sessions) {
    final b = StringBuffer()..writeln(csvHeader);
    for (final s in sessions) {
      List<List<Object?>> rows;
      if (s.sets.isEmpty) {
        rows = [
          [null, null, null, null, null, null, null],
        ];
      } else {
        rows = [
          for (final x in s.sets)
            [
              x.exerciseName,
              x.setNumber,
              x.reps,
              x.weightKg,
              x.isCompleted ? 1 : 0,
              x.durationSeconds,
              x.distanceKm,
            ],
        ];
      }
      for (final r in rows) {
        b.writeln(
          [
            s.id,
            s.date,
            s.startTime,
            s.endTime,
            s.durationSeconds,
            s.primaryMuscle,
            s.secondaryMuscle,
            ...r,
          ].map(_csv).join(','),
        );
      }
    }
    return b.toString();
  }

  static String buildJson(List<WorkoutSession> sessions) =>
      const JsonEncoder.withIndent('  ').convert({
        'exported_at': DateTime.now().toIso8601String(),
        'sessions': [
          for (final s in sessions)
            {
              ...s.toMap(),
              'sets': [for (final x in s.sets) x.toMap()],
            },
        ],
      });

  /// Writes the export to a temporary file and returns its path.
  Future<String> exportToFile({required bool csv}) async {
    final sessions = await _db.getAllSessions();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${dir.path}/reptrack_history_$stamp.${csv ? 'csv' : 'json'}',
    );
    await file.writeAsString(csv ? buildCsv(sessions) : buildJson(sessions));
    return file.path;
  }
}
