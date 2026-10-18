import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/app_info.dart';
import 'package:reptrack/services/backup_service.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

const _t0 = '2026-09-01T07:00:00';
const _older = '2026-08-01T07:00:00';
const _newer = '2026-10-01T07:00:00';

void main() {
  late Database db;
  final service = BackupService();

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.reptrack.app/alarm'),
          (call) async =>
              call.method == 'getScheduledAlarms' ? <Object?>[] : true,
        );
    db = await openTestDatabase();
    await _wipeUserData(db);
  });

  tearDown(() => closeTestDatabase(db));

  test('app version constant matches pubspec', () {
    final pubspec = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(kAppVersion, pubspec);
  });

  group('export / parse', () {
    test(
      'envelope has format, versions, counts, checksum and all tables',
      () async {
        await _dataSetA(db);
        final json =
            jsonDecode(await service.exportJson()) as Map<String, dynamic>;
        expect(json['format'], 'reptrack-backup');
        expect(json['format_version'], 3);
        expect(json['schema_version'], 7);
        expect(json['app_version'], kAppVersion);
        expect(json['checksum'], startsWith('sha256:'));
        final tables = json['tables'] as Map;
        expect(tables.keys.toSet(), DatabaseService.backupTables.toSet());
        expect((json['counts'] as Map)['workout_sessions'], 2);
        // device-internal sync flag is not exported
        expect(
          (tables['workout_sessions'] as List).first.containsKey('sync_dirty'),
          isFalse,
        );
      },
    );

    test('parse accepts its own export and legacy v1/v2 files', () async {
      await _dataSetA(db);
      final text = await service.exportJson();
      final file = service.parse(text);
      expect(file.formatVersion, 3);
      expect(file.legacy, isFalse);
      expect(file.rowCount('workout_sessions'), 2);

      final v3 = jsonDecode(text) as Map<String, dynamic>;
      final legacy = {
        'version': 2,
        ...Map<String, dynamic>.from(v3['tables'] as Map),
      };
      final legacyFile = service.parse(jsonEncode(legacy));
      expect(legacyFile.legacy, isTrue);
      expect(legacyFile.rowCount('workout_sessions'), 2);
    });

    test('corrupt, edited, wrong-version and foreign files are refused with a reason', () async {
      await _dataSetA(db);
      final text = await service.exportJson();
      final v3 = jsonDecode(text) as Map<String, dynamic>;

      void expectCode(String input, String code) {
        try {
          service.parse(input);
          fail('expected $code');
        } on BackupException catch (e) {
          expect(e.code, code, reason: e.message);
        }
      }

      expectCode('{{ not json', 'not_json');
      expectCode('[1,2]', 'not_a_backup');
      expectCode('{"hello": 1}', 'not_a_backup');
      expectCode(
        jsonEncode({...v3, 'format_version': 99}),
        'unsupported_format',
      );
      expectCode(jsonEncode({...v3, 'schema_version': 99}), 'schema_too_new');
      expectCode(jsonEncode({...v3}..remove('checksum')), 'checksum_mismatch');
      expectCode(text.replaceFirst('Chest', 'Chesty'), 'checksum_mismatch');
      expectCode(jsonEncode({'version': 99}), 'unsupported_format');
      final noTable = Map<String, dynamic>.from(v3['tables'] as Map)
        ..remove('workout_sets');
      expectCode(jsonEncode({'version': 2, ...noTable}), 'missing_table');
      final badRows = Map<String, dynamic>.from(v3['tables'] as Map)
        ..['workout_sets'] = [
          {
            'nested': {'a': 1},
          },
        ];
      expectCode(jsonEncode({'version': 2, ...badRows}), 'bad_rows');
    });
  });

  group('replace', () {
    test('round trip restores exactly what was exported', () async {
      await _dataSetA(db);
      final before = await _userSnapshot(db);
      final text = await service.exportJson();
      await _wipeUserData(db);
      expect((await db.query('workout_sessions')), isEmpty);

      final res = await service.applyReplace(
        service.parse(text),
        confirmed: true,
      );
      expect(res.ok, isTrue, reason: res.error);
      expect(await _userSnapshot(db), before);
    });

    test('requires confirmation and changes nothing without it', () async {
      await _dataSetA(db);
      final file = service.parse(await service.exportJson());
      await _wipeUserData(db);
      await _dataSetB(db);
      final before = await _userSnapshot(db);
      final res = await service.applyReplace(file, confirmed: false);
      expect(res.ok, isFalse);
      expect(await _userSnapshot(db), before);
    });

    test('a failure half-way rolls everything back (atomic)', () async {
      await _dataSetB(db);
      final before = await _userSnapshot(db);
      final file = BackupFile(
        formatVersion: 3,
        schemaVersion: 7,
        tables: {
          for (final t in DatabaseService.backupTables)
            t: <Map<String, Object?>>[],
          'workout_sessions': [
            {
              'date': '2026-01-01',
              'start_time': '07:00',
              'primary_muscle': 'x',
              'created_at': 'x',
            },
          ],
          // NOT NULL violation late in the insert order
          'routine_completions': [
            {'routine_id': 1, 'date': null, 'status': 's', 'completed_at': 'x'},
          ],
        },
      );
      final res = await service.applyReplace(file, confirmed: true);
      expect(res.ok, isFalse);
      expect(await _userSnapshot(db), before);
    });

    test(
      'replace does not queue the restored rows as cloud deletions',
      () async {
        await _dataSetA(db);
        final text = await service.exportJson();
        await service.applyReplace(service.parse(text), confirmed: true);
        // Every row came back with its old sync id: no tombstone may remain for a live row.
        final stale = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM sync_tombstones t WHERE t.table_name = ? AND t.sync_id IN '
          '(SELECT sync_id FROM workout_sessions)',
          ['workout_sessions'],
        );
        expect(stale.first['n'], 0);
      },
    );
  });

  group('merge', () {
    test('dry run reports changes but writes nothing', () async {
      await _dataSetA(db);
      final file = service.parse(await service.exportJson());
      await _wipeUserData(db);
      await _dataSetB(db);
      final before = await _userSnapshot(db);
      final plan = await service.planMerge(file);
      expect(plan.hasChanges, isTrue);
      expect(plan.of('workout_sessions').added, 2);
      expect(plan.of('workout_plans').added, 2);
      expect(plan.of('routines').added, 2);
      expect(await _userSnapshot(db), before);
    });

    test('requires confirmation', () async {
      await _dataSetA(db);
      final file = service.parse(await service.exportJson());
      await _wipeUserData(db);
      final r = await service.applyMerge(file, confirmed: false);
      expect(r.ok, isFalse);
      expect(await db.query('workout_sessions'), isEmpty);
    });

    test('adds the other device\'s data with remapped ids and keeps local data untouched', () async {
      await _dataSetA(db);
      final file = service.parse(await service.exportJson());
      await _wipeUserData(db);
      await _dataSetB(db);
      final bSessions = await db.query('workout_sessions');
      final bPlans = await db.query('workout_plans');
      final bRoutines = await db.query('routines');

      final res = await service.applyMerge(file, confirmed: true);
      expect(res.ok, isTrue, reason: res.error);

      // B untouched
      for (final b in bSessions) {
        final now = await db.query(
          'workout_sessions',
          where: 'id = ?',
          whereArgs: [b['id']],
        );
        expect(now.single['date'], b['date']);
        expect(now.single['start_time'], b['start_time']);
      }
      expect((await db.query('workout_sessions')).length, bSessions.length + 2);
      expect((await db.query('workout_plans')).length, bPlans.length + 2);
      expect((await db.query('routines')).length, bRoutines.length + 2);

      // A's sets point at A's (new) sessions, not at B's
      final s = await db.rawQuery(
        "SELECT s.date, COUNT(w.id) AS n FROM workout_sessions s "
        "LEFT JOIN workout_sets w ON w.session_id = s.id GROUP BY s.id ORDER BY s.date",
      );
      final byDate = {for (final r in s) r['date']: r['n']};
      expect(byDate['2026-09-02'], 3); // A session 1
      expect(byDate['2026-09-05'], 1); // A session 2
      expect(byDate['2026-09-10'], 2); // B session untouched

      // planned exercises landed on the right (new) plan
      final pe = await db.rawQuery(
        "SELECT p.date, COUNT(e.id) AS n FROM workout_plans p "
        "LEFT JOIN planned_exercises e ON e.plan_id = p.id GROUP BY p.id ORDER BY p.date",
      );
      expect({for (final r in pe) r['date']: r['n']}['2026-09-02'], 2);

      // A's custom exercise exists once; sets referencing it follow its new id
      final custom = (await db.query(
        'exercises',
        where: "name = 'Zercher Squat (A)'",
      )).single;
      expect(custom['is_custom'], 1);
      final sets = await db.query(
        'workout_sets',
        where: "exercise_name = 'Zercher Squat (A)'",
      );
      expect(sets.every((r) => r['exercise_id'] == custom['id']), isTrue);

      // training plan A is added inactive with its children
      final tp = (await db.query(
        'training_plans',
        where: "name = 'PPL (A)'",
      )).single;
      expect(tp['is_active'], 0);
      expect(
        (await db.query(
          'training_plan_days',
          where: 'plan_id = ?',
          whereArgs: [tp['id']],
        )).length,
        1,
      );

      // completions follow the remapped routine ids
      final comp = await db.rawQuery(
        "SELECT r.title FROM routine_completions c JOIN routines r ON r.id = c.routine_id WHERE c.date = '2026-09-02'",
      );
      expect(comp.map((r) => r['title']), contains('Stretch (A)'));

      // user settings: local values win, missing keys added, internal flag never imported
      final settings = {
        for (final r in await db.query('user_settings')) r['key']: r['value'],
      };
      expect(settings['theme_mode'], 'light'); // B's value kept
      expect(settings['only_in_a'], '1');
      expect(settings['default_routines_seeded'], isNot('from-a'));
    });

    test(
      'importing the same file twice changes nothing the second time',
      () async {
        await _dataSetA(db);
        final file = service.parse(await service.exportJson());
        await _wipeUserData(db);
        await _dataSetB(db);

        final first = await service.applyMerge(file, confirmed: true);
        expect(first.plan.totalAdded, greaterThan(0));
        final snap = await _userSnapshot(db);
        final second = await service.applyMerge(file, confirmed: true);
        expect(second.ok, isTrue, reason: second.error);
        expect(
          second.plan.totalAdded,
          0,
          reason: second.plan.tables.toString(),
        );
        expect(
          second.plan.totalUpdated,
          0,
          reason: second.plan.tables.toString(),
        );
        expect(await _userSnapshot(db), snap);
        // and a dry run now reports nothing to do
        expect((await service.planMerge(file)).hasChanges, isFalse);
      },
    );

    test('merging a file into the database it came from is a no-op', () async {
      await _dataSetA(db);
      final file = service.parse(await service.exportJson());
      final snap = await _userSnapshot(db);
      final plan = await service.planMerge(file);
      expect(plan.hasChanges, isFalse);
      final res = await service.applyMerge(file, confirmed: true);
      expect(res.ok, isTrue);
      expect(await _userSnapshot(db), snap);
    });

    test(
      'conflicts: keep the newer copy by updated_at, never the older',
      () async {
        await _dataSetA(db);
        final fileA = service.parse(await service.exportJson());

        // Local copy of the same routine/plan/exercise edited later than the backup.
        await db.update('routines', {
          'notes': 'LOCAL NEWER',
          'updated_at': _newer,
        }, where: "title = 'Stretch (A)'");
        await db.update('workout_plans', {
          'notes': 'LOCAL NEWER',
          'updated_at': _newer,
        }, where: "date = '2026-09-02'");
        final customId = (await db.query(
          'exercises',
          where: "name = 'Zercher Squat (A)'",
        )).single['id'];
        await db.update(
          'exercises',
          {'personal_notes': 'LOCAL NEWER', 'updated_at': _newer},
          where: 'id = ?',
          whereArgs: [customId],
        );
        await service.applyMerge(fileA, confirmed: true);
        expect(
          (await db.query(
            'routines',
            where: "title = 'Stretch (A)'",
          )).single['notes'],
          'LOCAL NEWER',
        );
        expect(
          (await db.query(
            'workout_plans',
            where: "date = '2026-09-02'",
          )).single['notes'],
          'LOCAL NEWER',
        );
        expect(
          (await db.query(
            'exercises',
            where: 'id = ?',
            whereArgs: [customId],
          )).single['personal_notes'],
          'LOCAL NEWER',
        );

        // Now the local copies are OLDER than the backup: the backup wins.
        await db.update('routines', {
          'notes': 'LOCAL OLD',
          'updated_at': _older,
        }, where: "title = 'Stretch (A)'");
        await db.update('workout_plans', {
          'notes': 'LOCAL OLD',
          'updated_at': _older,
        }, where: "date = '2026-09-02'");
        await db.update(
          'exercises',
          {'personal_notes': 'LOCAL OLD', 'updated_at': _older},
          where: 'id = ?',
          whereArgs: [customId],
        );
        final plan = await service.planMerge(fileA);
        expect(plan.of('routines').updated, 1);
        expect(plan.of('workout_plans').updated, 1);
        expect(plan.of('exercises').updated, 1);
        await service.applyMerge(fileA, confirmed: true);
        expect(
          (await db.query(
            'routines',
            where: "title = 'Stretch (A)'",
          )).single['notes'],
          'A note',
        );
        expect(
          (await db.query(
            'workout_plans',
            where: "date = '2026-09-02'",
          )).single['notes'],
          'push day',
        );
        expect(
          (await db.query(
            'exercises',
            where: 'id = ?',
            whereArgs: [customId],
          )).single['personal_notes'],
          'custom A',
        );
        // the newer plan brought its planned exercises along without duplicating them
        expect(
          (await db.rawQuery(
            "SELECT COUNT(*) AS n FROM planned_exercises e JOIN workout_plans p ON p.id = e.plan_id WHERE p.date = '2026-09-02'",
          )).first['n'],
          2,
        );
      },
    );

    test(
      'favourites are unioned and a finished day is never un-finished',
      () async {
        await _dataSetA(db);
        await db.update('exercises', {'is_favourite': 1}, where: 'id = 1');
        final fileA = service.parse(await service.exportJson());
        await db.update('exercises', {'is_favourite': 0}, where: 'id = 1');
        await db.update('workout_plans', {
          'is_completed': 0,
        }, where: "date = '2026-09-02'");
        await service.applyMerge(fileA, confirmed: true);
        expect(
          (await db.query('exercises', where: 'id = 1')).single['is_favourite'],
          1,
        );
        expect(
          (await db.query(
            'workout_plans',
            where: "date = '2026-09-02'",
          )).single['is_completed'],
          1,
        );
      },
    );

    test('deleted training plans in a backup are not resurrected', () async {
      await _dataSetA(db);
      await db.update('training_plans', {'deleted_at': _t0});
      final file = service.parse(await service.exportJson());
      await db.delete('training_plan_day_exercises');
      await db.delete('training_plan_days');
      await db.delete('training_plans');
      await service.applyMerge(file, confirmed: true);
      expect(await db.query('training_plans'), isEmpty);
    });

    test('a failure during merge rolls back completely', () async {
      await _dataSetB(db);
      final before = await _userSnapshot(db);
      final file = BackupFile(
        formatVersion: 3,
        schemaVersion: 7,
        tables: {
          for (final t in DatabaseService.backupTables)
            t: <Map<String, Object?>>[],
          'workout_sessions': [
            {
              'date': '2026-12-01',
              'start_time': '07:00',
              'primary_muscle': 'x',
              'created_at': 'x1',
            },
          ],
          'routines': [
            // NOT NULL column missing: the insert throws after sessions were written
            {'id': 77, 'title': 'broken'},
          ],
        },
      );
      final res = await service.applyMerge(file, confirmed: true);
      expect(res.ok, isFalse);
      expect(await _userSnapshot(db), before);
    });
  });

  test(
    'DatabaseService export/restore delegate to the versioned format',
    () async {
      await _dataSetA(db);
      final svc = DatabaseService();
      final text = await svc.exportBackupJson();
      expect((jsonDecode(text) as Map)['format_version'], 3);
      await _wipeUserData(db);
      expect(await svc.restoreBackupJson(text), isTrue);
      expect((await db.query('workout_sessions')).length, 2);
      expect(
        await svc.restoreBackupJson(text.replaceFirst('Chest', 'Chesty')),
        isFalse,
      );
    },
  );
}

Future<void> _wipeUserData(Database db) async {
  for (final t in [
    'workout_sets',
    'workout_sessions',
    'planned_exercises',
    'workout_plans',
    'plan_change_logs',
    'media_attachments',
    'routine_completions',
    'routines',
    'training_plan_day_exercises',
    'training_plan_days',
    'training_plans',
    'active_sessions',
    'user_settings',
  ]) {
    await db.delete(t);
  }
  await db.delete('exercises', where: 'is_custom = 1');
  await db.update('exercises', {'is_favourite': 0, 'personal_notes': null});
  await db.delete('sync_tombstones');
}

/// "Device A": the data being exported.
Future<void> _dataSetA(Database db) async {
  await db.update('exercises', {
    'personal_notes': 'catalogue note A',
    'updated_at': _t0,
  }, where: 'id = 69');
  final custom = await db.insert('exercises', {
    'muscle_group_id': 9,
    'muscle_group_name': 'Quadriceps',
    'name': 'Zercher Squat (A)',
    'target': 'Quadriceps',
    'description': 'a',
    'instructions': 'a',
    'equipment': 'Barbell',
    'is_custom': 1,
    'personal_notes': 'custom A',
    'created_at': _t0,
    'updated_at': _t0,
  });
  final p1 = await db.insert('workout_plans', {
    'date': '2026-09-02',
    'primary_muscle_name': 'Chest',
    'notes': 'push day',
    'is_completed': 1,
    'created_at': _t0,
    'updated_at': _t0,
  });
  await db.insert('workout_plans', {
    'date': '2026-09-03',
    'is_rest_day': 1,
    'created_at': _t0,
    'updated_at': _t0,
  });
  for (final (i, id, n) in [
    (0, 1, 'Barbell Bench Press'),
    (1, custom, 'Zercher Squat (A)'),
  ]) {
    await db.insert('planned_exercises', {
      'plan_id': p1,
      'exercise_id': id,
      'exercise_name': n,
      'exercise_order': i,
    });
  }
  await db.insert('plan_change_logs', {
    'plan_id': p1,
    'plan_date': '2026-09-02',
    'change_description': 'swap',
    'changed_at': _t0,
  });
  final s1 = await db.insert('workout_sessions', {
    'plan_id': p1,
    'date': '2026-09-02',
    'start_time': '18:00',
    'duration_seconds': 3000,
    'primary_muscle': 'Chest',
    'created_at': '2026-09-02T19:00:00',
    'client_ref': 'ref-a1',
  });
  for (var i = 1; i <= 3; i++) {
    await db.insert('workout_sets', {
      'session_id': s1,
      'exercise_id': i == 3 ? custom : 1,
      'exercise_name': i == 3 ? 'Zercher Squat (A)' : 'Barbell Bench Press',
      'set_number': i,
      'reps': 8,
      'weight_kg': 60.0 + i,
      'completed_at': '2026-09-02T18:1$i:00',
    });
  }
  final s2 = await db.insert('workout_sessions', {
    'date': '2026-09-05',
    'start_time': '07:00',
    'primary_muscle': 'Biceps',
    'created_at': '2026-09-05T07:30:00',
  });
  await db.insert('workout_sets', {
    'session_id': s2,
    'exercise_id': 69,
    'exercise_name': 'Standing Dumbbell Curl',
    'set_number': 1,
    'reps': 10,
    'weight_kg': 12.5,
    'completed_at': '2026-09-05T07:10:00',
  });
  await db.insert('media_attachments', {
    'entity_type': 'session',
    'entity_id': s1,
    'media_type': 'photo',
    'file_path': '/a/p1.jpg',
    'created_at': _t0,
  });
  final r1 = await db.insert(
    'routines',
    _routine('Stretch (A)', '06:30', 'A note'),
  );
  await db.insert('routines', _routine('Creatine (A)', '09:00', null));
  await db.insert('routine_completions', {
    'routine_id': r1,
    'date': '2026-09-02',
    'status': 'completed',
    'completed_at': '2026-09-02T06:50:00',
  });
  final tp = await db.insert('training_plans', {
    'name': 'PPL (A)',
    'is_active': 1,
    'created_at': _t0,
    'updated_at': _t0,
  });
  final day = await db.insert('training_plan_days', {
    'plan_id': tp,
    'weekday': 1,
    'is_rest': 0,
  });
  await db.insert('training_plan_day_exercises', {
    'day_id': day,
    'exercise_id': custom,
    'exercise_name': 'Zercher Squat (A)',
  });
  await db.insert('user_settings', {'key': 'theme_mode', 'value': 'dark'});
  await db.insert('user_settings', {'key': 'only_in_a', 'value': '1'});
  await db.insert('user_settings', {
    'key': 'default_routines_seeded',
    'value': 'from-a',
  });
}

/// "Device B": different data already in the target database (same autoincrement ids).
Future<void> _dataSetB(Database db) async {
  final p = await db.insert('workout_plans', {
    'date': '2026-09-10',
    'primary_muscle_name': 'Back',
    'created_at': _t0,
    'updated_at': _t0,
  });
  final s = await db.insert('workout_sessions', {
    'plan_id': p,
    'date': '2026-09-10',
    'start_time': '17:00',
    'primary_muscle': 'Back',
    'created_at': '2026-09-10T18:00:00',
  });
  for (var i = 1; i <= 2; i++) {
    await db.insert('workout_sets', {
      'session_id': s,
      'exercise_id': 26,
      'exercise_name': 'Lat Pulldown',
      'set_number': i,
      'reps': 10,
      'weight_kg': 50.0,
      'completed_at': '2026-09-10T17:1$i:00',
    });
  }
  await db.insert('routines', _routine('Walk (B)', '18:00', null));
  await db.insert('routines', _routine('Water (B)', '12:00', null));
  await db.insert('user_settings', {'key': 'theme_mode', 'value': 'light'});
}

Map<String, Object?> _routine(String title, String start, String? notes) => {
  'title': title,
  'category': 'Personal',
  'start_time': start,
  'end_time': '23:00',
  'repeat_days': '1,2,3,4,5,6,7',
  'notes': notes,
  'created_at': _t0,
  'updated_at': _t0,
};

Future<Map<String, Object?>> _userSnapshot(Database db) async {
  final out = <String, Object?>{};
  for (final t in DatabaseService.backupTables) {
    if (t == 'muscle_groups') continue;
    final rows = await db.query(
      t,
      where: t == 'exercises'
          ? 'is_custom = 1 OR is_favourite = 1 OR personal_notes IS NOT NULL'
          : null,
      orderBy: t == 'user_settings' ? 'key' : 'id',
    );
    out[t] = [
      for (final r in rows)
        {
          for (final e in r.entries)
            if (!e.key.startsWith('sync_')) e.key: e.value,
        },
    ];
  }
  return out;
}
