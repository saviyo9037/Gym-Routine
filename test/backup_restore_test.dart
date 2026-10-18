import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/models/training_plan.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/services/training_plan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

void main() {
  late Database db;
  final svc = DatabaseService();

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.reptrack.app/alarm'),
          (call) async => <Object?>[],
        );
    db = await openTestDatabase();
  });

  tearDown(() => closeTestDatabase(db));

  /// Old flat backup shape (formats 1 and 2) rebuilt from a format-3 file.
  Map<String, dynamic> legacyFlat(
    Map<String, dynamic> v3, {
    required int version,
  }) => {
    'version': version,
    'exported_at': v3['exported_at'],
    ...Map<String, dynamic>.from(v3['tables'] as Map),
  };

  Future<Map<String, int>> counts() async => {
    for (final t in DatabaseService.backupTables) t: (await db.query(t)).length,
  };

  test('export includes routines, completions and training plans', () async {
    final plans = TrainingPlanService();
    await plans.savePlan(
      TrainingPlan(
        name: 'PPL',
        days: [
          TrainingPlanDay(
            weekday: 1,
            exercises: const [
              TrainingPlanExercise(
                exerciseId: 1,
                exerciseName: 'Barbell Bench Press',
                muscleGroupName: 'Chest',
              ),
            ],
          ),
          ...List.generate(
            6,
            (i) => TrainingPlanDay(weekday: i + 2, isRest: true),
          ),
        ],
      ),
    );
    final json = jsonDecode(await svc.exportBackupJson()) as Map;
    expect(json['format'], 'reptrack-backup');
    expect(json['format_version'], 3);
    expect(json['schema_version'], 7);
    expect((json['checksum'] as String), startsWith('sha256:'));
    final tables = json['tables'] as Map;
    expect((tables['routines'] as List).length, 9);
    expect((tables['training_plans'] as List).length, 1);
    expect((tables['training_plan_day_exercises'] as List).length, 1);
    expect(tables.containsKey('active_sessions'), isFalse);
    expect((json['counts'] as Map)['routines'], 9);
  });

  test('round trip restores everything after the data was wiped', () async {
    final plans = TrainingPlanService();
    await plans.savePlan(TrainingPlan(name: 'Keep me'));
    await db.insert('routine_completions', {
      'routine_id': 1,
      'date': '2026-10-20',
      'status': 'completed',
      'completed_at': '2026-10-20T08:00:00',
    });
    final before = await counts();
    final backup = await svc.exportBackupJson();

    await db.delete('routine_completions');
    await db.delete('routines');
    await db.delete('training_plan_days');
    await db.delete('training_plans');

    expect(await svc.restoreBackupJson(backup), isTrue);
    expect(await counts(), before);
    expect((await plans.listPlans()).single.name, 'Keep me');
  });

  test(
    'an old version-1 backup without routine tables still restores',
    () async {
      final map = legacyFlat(
        jsonDecode(await svc.exportBackupJson()) as Map<String, dynamic>,
        version: 1,
      );
      for (final k in [
        'routines',
        'routine_completions',
        'training_plans',
        'training_plan_days',
        'training_plan_day_exercises',
      ]) {
        map.remove(k);
      }
      expect(await svc.restoreBackupJson(jsonEncode(map)), isTrue);
      expect((await db.query('exercises')).length, 201);
    },
  );

  test('invalid files are rejected and existing data is untouched', () async {
    await TrainingPlanService().savePlan(TrainingPlan(name: 'Precious'));
    final before = await counts();
    final v3 = jsonDecode(await svc.exportBackupJson()) as Map<String, dynamic>;
    final good = legacyFlat(v3, version: 2);

    final bad = <String>[
      // format-3 file whose data was edited after export: checksum mismatch
      jsonEncode({
        ...v3,
        'tables': {
          ...(v3['tables'] as Map),
          'exercises': [
            {'id': 1, 'name': 'tampered'},
          ],
        },
      }),
      jsonEncode({...v3, 'format_version': 99}),
      jsonEncode({...v3, 'schema_version': 99}),
      jsonEncode({...v3}..remove('checksum')),
      'not json at all',
      '[]',
      jsonEncode({'version': 99}),
      jsonEncode({...good, 'version': 'x'}),
      jsonEncode({...good}..remove('exercises')),
      jsonEncode({...good, 'workout_sets': 'oops'}),
      jsonEncode({
        ...good,
        'workout_plans': [42],
      }),
      jsonEncode({
        ...good,
        'exercises': [
          {
            'name': 'x',
            'nested': {'a': 1},
          },
        ],
      }),
    ];
    for (final b in bad) {
      expect(await svc.restoreBackupJson(b), isFalse, reason: b);
      expect(await counts(), before, reason: 'untouched after: $b');
    }
  });

  test('a failure half-way through rolls the whole restore back', () async {
    final before = await counts();
    final good = legacyFlat(
      jsonDecode(await svc.exportBackupJson()) as Map<String, dynamic>,
      version: 2,
    );
    // A row with a NOT NULL violation late in the insert order.
    good['routine_completions'] = [
      {
        'routine_id': 1,
        'date': null,
        'status': 'completed',
        'completed_at': 'x',
      },
    ];
    expect(await svc.restoreBackupJson(jsonEncode(good)), isFalse);
    expect(await counts(), before);
  });
}
