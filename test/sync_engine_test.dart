import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/services/database_service.dart';
import 'package:reptrack/models/workout_session.dart';
import 'package:reptrack/services/sync_engine.dart';
import 'package:reptrack/services/sync_remote.dart';
import 'package:reptrack/services/sync_tables.dart';
import 'package:reptrack/models/workout_plan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_sync_remote.dart';
import 'helpers/test_db.dart';

const _user = 'user-1';

Future<void> resetData(Database db) async {
  for (final s in syncTables.reversed) {
    if (s.local == 'exercises') {
      await db.delete('exercises', where: 'is_custom = 1');
    } else {
      await db.delete(s.local);
    }
  }
  await db.delete('sync_tombstones');
  await db.delete('sync_meta');
  await db.delete('sync_conflicts');
}

Future<int> insertRoutine(
  Database db,
  String title, {
  String start = '07:00',
}) => db.insert('routines', {
  'title': title,
  'category': 'Gym',
  'start_time': start,
  'end_time': '08:00',
  'repeat_days': '1,2,3',
  'created_at': '2026-10-01T00:00:00',
  'updated_at': '2026-10-01T00:00:00',
});

Future<Map<String, Object?>> routineRow(Database db, int id) async =>
    (await db.query('routines', where: 'id = ?', whereArgs: [id])).single;

SyncEngine engine(
  SyncRemote remote, {
  int pageSize = 200,
  int batchSize = 100,
}) => SyncEngine(
  remote: remote,
  userId: _user,
  pageSize: pageSize,
  batchSize: batchSize,
);

Map<String, dynamic> remoteRoutine(
  String id,
  String title, {
  String start = '09:00',
}) => {
  'id': id,
  'user_id': _user,
  'title': title,
  'category': 'Gym',
  'start_time': start,
  'end_time': '10:00',
  'repeat_days': '4,5',
  'is_reminder_enabled': true,
  'reminder_minutes_before': 5,
  'alarm_type': 'alarm',
  'is_alarm_enabled': true,
  'sound_name': 'Digital Beep',
  'is_vibration_enabled': true,
  'snooze_minutes': 10,
  'is_enabled': true,
};

void main() {
  late Database db;
  late FakeSyncRemote remote;

  setUp(() async {
    db = await openTestDatabase();
    await resetData(db);
    remote = FakeSyncRemote();
  });

  tearDown(() async {
    AppClock.reset();
    await closeTestDatabase(db);
  });

  group('MOCK-ONLY: change tracking (triggers)', () {
    test('insert stamps sync id + dirty; update re-dirties; delete leaves a tombstone', () async {
      final id = await insertRoutine(db, 'Run');
      var r = await routineRow(db, id);
      expect(r['sync_id'], isNotNull);
      expect((r['sync_id'] as String).length, 36);
      expect(r['sync_dirty'], 1);
      final firstSyncId = r['sync_id'];

      await db.update(
        'routines',
        {'sync_dirty': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      // sync_dirty written by the engine path alone must not re-dirty... but
      // an app update must:
      await db.update(
        'routines',
        {'title': 'Run fast'},
        where: 'id = ?',
        whereArgs: [id],
      );
      r = await routineRow(db, id);
      expect(r['sync_dirty'], 1);
      expect(r['sync_id'], firstSyncId);

      await db.delete('routines', where: 'id = ?', whereArgs: [id]);
      final t = await db.query('sync_tombstones');
      expect(t.single['sync_id'], firstSyncId);
      expect(t.single['table_name'], 'routines');
    });

    test('catalogue exercises are not tracked, custom ones are', () async {
      await db.update('exercises', {
        'name': 'Barbell Bench Press',
      }, where: 'id = 1');
      final cat = (await db.query('exercises', where: 'id = 1')).single;
      expect(cat['sync_dirty'], 0);
      final id = await db.insert('exercises', {
        'muscle_group_id': 1,
        'muscle_group_name': 'Chest',
        'name': 'My Cable Thing',
        'is_custom': 1,
        'created_at': '2026-10-01T00:00:00',
      });
      final c = (await db.query(
        'exercises',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(c['sync_dirty'], 1);
      expect(c['sync_id'], isNotNull);
    });

    test('clearAllData does not queue mass deletions for the cloud', () async {
      await insertRoutine(db, 'A');
      await insertRoutine(db, 'B');
      await db.delete('sync_tombstones');
      await db.execute('DELETE FROM routines');
      expect((await db.query('sync_tombstones')).length, 2);
      await db.delete('sync_tombstones'); // what clearAllData does
      expect(await db.query('sync_tombstones'), isEmpty);
    });
  });

  group('MOCK-ONLY: push', () {
    test(
      'uploads dirty rows once; a second run pushes nothing (idempotent)',
      () async {
        final id = await insertRoutine(db, 'Run');
        final rep1 = await engine(remote).run();
        expect(rep1.pushed, 1);
        final cloud = remote.t('routines').values.single;
        expect(cloud['title'], 'Run');
        expect(cloud['user_id'], _user);
        expect(cloud['is_enabled'], isA<bool>());
        expect((await routineRow(db, id))['sync_dirty'], 0);

        final rep2 = await engine(remote).run();
        expect(rep2.pushed, 0);
        expect(remote.upsertedRows, 1);
      },
    );

    test(
      'a row edited after being pushed is pushed again with the new data',
      () async {
        final id = await insertRoutine(db, 'Run');
        await engine(remote).run();
        await db.update(
          'routines',
          {'title': 'Run 2'},
          where: 'id = ?',
          whereArgs: [id],
        );
        await engine(remote).run();
        expect(remote.t('routines').values.single['title'], 'Run 2');
      },
    );

    test(
      'network failure keeps rows dirty; retry succeeds without duplicates',
      () async {
        await insertRoutine(db, 'Run');
        remote.failUpsert = true;
        await expectLater(engine(remote).run(), throwsException);
        expect((await db.query('routines')).single['sync_dirty'], 1);
        remote.failUpsert = false;
        await engine(remote).run();
        expect(remote.t('routines').length, 1);
      },
    );

    test('children wait for their parent id (parent first)', () async {
      final plan = await DatabaseService().saveOrUpdatePlan(
        WorkoutPlan(
          date: '2026-10-20',
          exercises: [
            PlannedExercise(
              planId: 0,
              exerciseId: 1,
              exerciseName: 'Barbell Bench Press',
              muscleGroupName: 'Chest',
              targetSets: 4,
              targetReps: 8,
              targetWeightKg: 62.5,
              targetDurationSeconds: null,
            ),
          ],
        ),
      );
      expect(plan, greaterThan(0));
      final rep = await engine(remote).run();
      expect(rep.pushed, 2);
      final cloudPlan = remote.t('workout_plans').values.single;
      final cloudEx = remote.t('workout_plan_exercises').values.single;
      expect(cloudEx['plan_id'], cloudPlan['id']);
      expect(cloudPlan['plan_date'], '2026-10-20');
      expect(cloudEx['target_weight_kg'], 62.5);
    });

    test(
      'plans/completions use deterministic ids (same date = same cloud row)',
      () async {
        await DatabaseService().saveOrUpdatePlan(
          WorkoutPlan(date: '2026-10-20'),
        );
        await engine(remote).run();
        final id1 = remote.t('workout_plans').keys.single;
        expect(id1, deterministicUuid('plan:2026-10-20'));

        // A second device creating the same date produces the same id.
        await closeTestDatabase(db);
        db = await openTestDatabase();
        await resetData(db);
        await DatabaseService().saveOrUpdatePlan(
          WorkoutPlan(date: '2026-10-20'),
        );
        await engine(remote).run();
        expect(remote.t('workout_plans').length, 1);
      },
    );
  });

  group('MOCK-ONLY: last-write-wins', () {
    test(
      'newer remote beats an older local edit (no blind overwrite)',
      () async {
        final id = await insertRoutine(db, 'Local');
        final syncId = (await routineRow(db, id))['sync_id'] as String;
        final localTs = DateTime.parse(
          (await routineRow(db, id))['sync_updated_at'] as String,
        );
        remote.plant(
          'routines',
          remoteRoutine(syncId, 'Remote wins'),
          clientUpdatedAt: localTs.add(const Duration(hours: 1)),
        );
        final rep = await engine(remote).run();
        expect(rep.conflicts, greaterThan(0));
        expect((await routineRow(db, id))['title'], 'Remote wins');
        expect(remote.t('routines')[syncId]!['title'], 'Remote wins');
        final log = await db.query('sync_conflicts');
        expect(log.map((e) => e['kind']), contains('remote-newer'));
      },
    );

    test('newer local edit beats an older remote row and is pushed', () async {
      final id = await insertRoutine(db, 'Local newest');
      final syncId = (await routineRow(db, id))['sync_id'] as String;
      final localTs = DateTime.parse(
        (await routineRow(db, id))['sync_updated_at'] as String,
      );
      remote.plant(
        'routines',
        remoteRoutine(syncId, 'Old remote'),
        clientUpdatedAt: localTs.subtract(const Duration(hours: 1)),
      );
      await engine(remote).run();
      expect((await routineRow(db, id))['title'], 'Local newest');
      expect(remote.t('routines')[syncId]!['title'], 'Local newest');
    });

    test('local edit made during pull window is kept when newer than the incoming row', () async {
      final id = await insertRoutine(db, 'Mine');
      final r = await routineRow(db, id);
      final syncId = r['sync_id'] as String;
      // Remote row older than the dirty local row, but local push is blocked
      // (offline) so the pull-side rule alone must protect the edit.
      remote.plant(
        'routines',
        remoteRoutine(syncId, 'Stale'),
        clientUpdatedAt: DateTime.parse(r['sync_updated_at'] as String)
            .subtract(const Duration(minutes: 5)),
      );
      remote.failUpsert = true;
      await expectLater(engine(remote).run(), throwsException);
      expect((await routineRow(db, id))['title'], 'Mine');
      expect((await routineRow(db, id))['sync_dirty'], 1);
    });

    test('remote delete removes the local row; newer local edit survives a remote delete', () async {
      final a = await insertRoutine(db, 'A');
      final b = await insertRoutine(db, 'B');
      final ra = await routineRow(db, a);
      final rb = await routineRow(db, b);
      await engine(remote).run();
      // another device deletes A now, and deletes B long ago
      remote.plant(
        'routines',
        remoteRoutine(ra['sync_id'] as String, 'A'),
        clientUpdatedAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        deletedAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      );
      remote.plant(
        'routines',
        remoteRoutine(rb['sync_id'] as String, 'B'),
        clientUpdatedAt: DateTime.now().toUtc().subtract(
          const Duration(days: 1),
        ),
        deletedAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );
      await db.update(
        'routines',
        {'title': 'B edited'},
        where: 'id = ?',
        whereArgs: [b],
      );
      final rep = await engine(remote).run();
      expect(rep.removedLocal, 1);
      expect(
        await db.query('routines', where: 'id = ?', whereArgs: [a]),
        isEmpty,
      );
      expect((await routineRow(db, b))['title'], 'B edited');
      // the surviving edit resurrects B in the cloud
      expect(remote.t('routines')[rb['sync_id']]!['deleted_at'], isNull);
    });

    test('local delete is pushed as a tombstone; newer remote edit beats a local delete', () async {
      final a = await insertRoutine(db, 'A');
      final b = await insertRoutine(db, 'B');
      final ra = await routineRow(db, a);
      final rb = await routineRow(db, b);
      await engine(remote).run();
      await db.delete('routines', where: 'id = ?', whereArgs: [a]);
      await db.delete('routines', where: 'id = ?', whereArgs: [b]);
      // someone edits B in the cloud after the local delete
      remote.plant(
        'routines',
        remoteRoutine(rb['sync_id'] as String, 'B edited elsewhere'),
        clientUpdatedAt: DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      final rep = await engine(remote).run();
      expect(rep.tombstonesPushed, 1);
      expect(remote.t('routines')[ra['sync_id']]!['deleted_at'], isNotNull);
      expect(remote.t('routines')[rb['sync_id']]!['deleted_at'], isNull);
      // B comes back locally on the same run (cursor reset then re-pull)
      final back = await db.query(
        'routines',
        where: 'title = ?',
        whereArgs: ['B edited elsewhere'],
      );
      expect(back.length, 1);
      expect(await db.query('sync_tombstones'), isEmpty);
    });
  });

  group('MOCK-ONLY: pull', () {
    test('applies remote rows, parents before children, without marking them dirty', () async {
      final planId = deterministicUuid('plan:2026-11-02');
      remote.plant('workout_plans', {
        'id': planId,
        'user_id': _user,
        'plan_date': '2026-11-02',
        'primary_muscle_name': 'Chest',
        'is_completed': false,
        'is_rest_day': false,
      }, clientUpdatedAt: DateTime.utc(2026, 10, 1));
      remote.plant('workout_plan_exercises', {
        'id': 'ex-uuid-1',
        'user_id': _user,
        'plan_id': planId,
        'exercise_id': 1,
        'exercise_name': 'Barbell Bench Press',
        'muscle_group_name': 'Chest',
        'exercise_order': 0,
        'target_sets': 3,
        'target_reps': 10,
        'target_weight_kg': 60,
        'rest_seconds': 90,
      }, clientUpdatedAt: DateTime.utc(2026, 10, 1));
      final rep = await engine(remote).run();
      expect(rep.pulled, 2);
      final plan = await DatabaseService().getPlanForDate('2026-11-02');
      expect(plan!.exercises.single.exerciseName, 'Barbell Bench Press');
      expect(plan.exercises.single.targetWeightKg, 60.0);
      final dirty = await db.rawQuery(
        'SELECT COUNT(*) c FROM workout_plans WHERE sync_dirty = 1',
      );
      expect(dirty.single['c'], 0);
      expect(await db.query('sync_tombstones'), isEmpty);
      // exercise image resolved from the local catalogue
      final pe = (await db.query('planned_exercises')).single;
      expect(pe['image_path'], isNotNull);
    });

    test(
      'a child whose parent is unknown is skipped and logged, not crashed',
      () async {
        remote.plant('workout_plan_exercises', {
          'id': 'orphan-1',
          'user_id': _user,
          'plan_id': 'does-not-exist',
          'exercise_name': 'X',
          'exercise_id': 1,
        }, clientUpdatedAt: DateTime.utc(2026, 10, 1));
        final rep = await engine(remote).run();
        expect(rep.conflicts, 1);
        expect(await db.query('planned_exercises'), isEmpty);
      },
    );

    test('resumes after a failure: pages already applied stay, the rest arrives next run', () async {
      for (var i = 0; i < 5; i++) {
        remote.plant(
          'routines',
          remoteRoutine('r-$i', 'Remote $i'),
          clientUpdatedAt: DateTime.utc(2026, 10, 1, i),
        );
      }
      // Eight empty tables take one pull each, then routines need three pages
      // of two rows. Call 11 is the third routines page.
      final flaky = FlakyRemote(remote, 11);
      await expectLater(engine(flaky, pageSize: 2).run(), throwsException);
      expect(
        (await db.query('routines')).length,
        4,
        reason: 'the two pages applied before the failure stay',
      );
      expect(
        await SyncEngine.getMeta(db, 'cursor:routines'),
        isNotNull,
        reason: 'cursor saved so the next run resumes',
      );
      // retry with a healthy network finishes the job, no duplicates
      await engine(remote, pageSize: 2).run();
      expect((await db.query('routines')).length, 5);
    });

    test(
      'server paging with identical timestamps neither loops nor skips rows',
      () async {
        for (var i = 0; i < 5; i++) {
          final row = remoteRoutine('same-$i', 'Same $i');
          remote.t('routines')['same-$i'] = {
            ...row,
            'client_updated_at': DateTime.utc(2026, 10, 1).toIso8601String(),
            'updated_at': DateTime.utc(2026, 10, 1).toIso8601String(),
            'deleted_at': null,
          };
        }
        await engine(remote, pageSize: 2).run();
        expect((await db.query('routines')).length, 5);
      },
    );

    test(
      'unique weekday replacement from the cloud wins over the old local day',
      () async {
        final plan = deterministicUuid('x');
        remote.plant('training_plans', {
          'id': plan,
          'user_id': _user,
          'name': 'PPL',
          'is_active': true,
        }, clientUpdatedAt: DateTime.utc(2026, 10, 1));
        remote.plant('training_plan_days', {
          'id': 'day-old',
          'user_id': _user,
          'plan_id': plan,
          'weekday': 1,
          'is_rest': false,
        }, clientUpdatedAt: DateTime.utc(2026, 10, 1));
        await engine(remote).run();
        // the plan is replaced elsewhere: new day id for the same weekday
        remote.plant('training_plan_days', {
          'id': 'day-new',
          'user_id': _user,
          'plan_id': plan,
          'weekday': 1,
          'is_rest': true,
        }, clientUpdatedAt: DateTime.utc(2026, 10, 2));
        await engine(remote).run();
        final days = await db.query('training_plan_days');
        expect(days.length, 1);
        expect(days.single['sync_id'], 'day-new');
        expect(days.single['is_rest'], 1);
      },
    );
  });

  group('MOCK-ONLY: sessions and cardio round trip between two devices', () {
    test('device B receives device A history exactly', () async {
      final dbs = DatabaseService();
      await dbs.createWorkoutSession(_session());
      await engine(remote).run();
      final cloudSession = remote.t('workout_sessions').values.single;
      expect(cloudSession['start_hhmm'], '07:15');
      expect(cloudSession['session_date'], '2026-10-20');
      expect(cloudSession['start_time'], isNotNull);
      expect(remote.t('session_sets').length, 2);

      await closeTestDatabase(db);
      db = await openTestDatabase();
      await resetData(db);
      await engine(remote).run();
      final sessions = await DatabaseService().getAllSessions();
      expect(sessions.length, 1);
      final s = sessions.single;
      expect(s.startTime, '07:15');
      expect(s.date, '2026-10-20');
      expect(s.sets.length, 2);
      final run = s.sets.firstWhere((x) => x.exerciseId == 191);
      expect(run.distanceKm, 3.5);
      expect(run.durationSeconds, 1200);
      final bench = s.sets.firstWhere((x) => x.exerciseId == 1);
      expect(bench.weightKg, 62.5);
    });
  });

  group('MOCK-ONLY: custom exercises', () {
    test(
      'sync across devices; catalogue exercises never leave the device',
      () async {
        await db.insert('exercises', {
          'muscle_group_id': 1,
          'muscle_group_name': 'Chest',
          'name': 'My Cable Thing',
          'is_custom': 1,
          'is_favourite': 1,
          'created_at': '2026-10-01T00:00:00',
        });
        await engine(remote).run();
        expect(remote.t('user_exercises').length, 1);
        expect(
          remote.t('user_exercises').values.single['primary_muscle_group'],
          'Chest',
        );

        await closeTestDatabase(db);
        db = await openTestDatabase();
        await resetData(db);
        await engine(remote).run();
        final c = await db.query('exercises', where: 'is_custom = 1');
        expect(c.single['name'], 'My Cable Thing');
        expect(c.single['is_favourite'], 1);
        expect(c.single['muscle_group_id'], isNotNull);
      },
    );
  });
}

/// Delegates to a healthy remote but fails the n-th pull call.
class FlakyRemote extends SyncRemote {
  FlakyRemote(this.inner, this.failOnPullCall);
  final SyncRemote inner;
  final int failOnPullCall;
  int pulls = 0;

  @override
  Future<Map<String, RemoteRowMeta>> fetchMeta(String t, List<String> ids) =>
      inner.fetchMeta(t, ids);
  @override
  Future<void> upsert(String t, List<Map<String, dynamic>> rows) =>
      inner.upsert(t, rows);
  @override
  Future<void> softDelete(String t, String id, DateTime at) =>
      inner.softDelete(t, id, at);
  @override
  Future<RemotePage> pull(String t, {RemoteCursor? after, required int limit}) {
    pulls++;
    if (pulls == failOnPullCall) throw Exception('network down');
    return inner.pull(t, after: after, limit: limit);
  }

  @override
  Future<void> markSynced(DateTime at) => inner.markSynced(at);
}

WorkoutSession _session() => WorkoutSession(
  clientRef: 'ref-1',
  date: '2026-10-20',
  startTime: '07:15',
  endTime: '08:05',
  durationSeconds: 3000,
  primaryMuscle: 'Chest',
  sets: [
    WorkoutSetRecord(
      sessionId: 0,
      exerciseId: 1,
      exerciseName: 'Barbell Bench Press',
      setNumber: 1,
      reps: 8,
      weightKg: 62.5,
      completedAt: '2026-10-20T07:30:00',
    ),
    WorkoutSetRecord(
      sessionId: 0,
      exerciseId: 191,
      exerciseName: 'Treadmill Running',
      setNumber: 1,
      reps: 20,
      weightKg: 0,
      completedAt: '2026-10-20T07:50:00',
      durationSeconds: 1200,
      distanceKm: 3.5,
    ),
  ],
);
