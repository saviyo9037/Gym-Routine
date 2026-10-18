// MOCK-ONLY: every test here runs the real SyncEngine against FakeSyncRemote (an
// in-memory stand-in for the cloud). Nothing here proves behaviour against a real
// Supabase project.
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/clock.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:reptrack/data/sync_schema.dart';
import 'package:reptrack/services/sync_engine.dart';
import 'package:reptrack/services/sync_tables.dart';
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
  await db.delete('sync_meta', where: "key <> 'schema_extras_rev'");
  await db.delete('sync_conflicts');
  await db.delete('favourite_sync');
}

Future<int> insertRoutine(Database db, String title) => db.insert('routines', {
  'title': title,
  'category': 'Gym',
  'start_time': '07:00',
  'end_time': '08:00',
  'repeat_days': '1,2,3',
  'created_at': '2026-10-01T00:00:00',
  'updated_at': '2026-10-01T00:00:00',
});

Future<Map<String, Object?>> routineRow(Database db, int id) async =>
    (await db.query('routines', where: 'id = ?', whereArgs: [id])).single;

Map<String, dynamic> remoteRoutine(String id, String title) => {
  'id': id,
  'user_id': _user,
  'title': title,
  'category': 'Gym',
  'start_time': '09:00',
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

SyncEngine engine(
  FakeSyncRemote remote, {
  String user = _user,
  int batchSize = 100,
  DateTime Function()? clock,
}) => SyncEngine(
  remote: remote,
  userId: user,
  batchSize: batchSize,
  clock: clock,
);

Future<void> setLocalTs(Database db, int id, DateTime ts) => db.update(
  'routines',
  {'sync_updated_at': ts.toUtc().toIso8601String()},
  where: 'id = ?',
  whereArgs: [id],
);

/// Starts a fresh "device": a new in-memory database.
Future<Database> newDevice(Database old) async {
  await closeTestDatabase(old);
  final db = await openTestDatabase();
  await resetData(db);
  return db;
}

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

  group('MOCK-ONLY: clock skew', () {
    test('phone clock 3 h BEHIND: its real, newer edit still beats an older cloud edit', () async {
      final id = await insertRoutine(db, 'Edited just now on the slow phone');
      final syncId = (await routineRow(db, id))['sync_id'] as String;
      final realNow = DateTime.now().toUtc();
      // The slow phone stamped its edit 3 h in the past...
      await setLocalTs(db, id, realNow.subtract(const Duration(hours: 3)));
      // ...while another device edited 1 h ago (truly OLDER than our edit).
      remote.plant(
        'routines',
        remoteRoutine(syncId, 'Older cloud edit'),
        clientUpdatedAt: realNow.subtract(const Duration(hours: 1)),
      );
      final e = engine(
        remote,
        clock: () => realNow.subtract(const Duration(hours: 3)),
      );
      await e.run();
      expect(e.clockSkew.inMinutes, closeTo(180, 1));
      expect(
        (await routineRow(db, id))['title'],
        'Edited just now on the slow phone',
      );
      expect(
        remote.t('routines')[syncId]!['title'],
        'Edited just now on the slow phone',
      );
    });

    test(
      'phone clock 5 days AHEAD cannot overwrite a genuinely newer cloud edit',
      () async {
        final id = await insertRoutine(db, 'Fast-clock edit from 1 h ago');
        final syncId = (await routineRow(db, id))['sync_id'] as String;
        final realNow = DateTime.now().toUtc();
        const ahead = Duration(days: 5);
        // Edit really happened 1 h ago but was stamped with the fast clock.
        await setLocalTs(
          db,
          id,
          realNow.subtract(const Duration(hours: 1)).add(ahead),
        );
        // A correct device edited the same row 10 minutes ago (truly newer).
        remote.plant(
          'routines',
          remoteRoutine(syncId, 'Truly newer cloud edit'),
          clientUpdatedAt: realNow.subtract(const Duration(minutes: 10)),
        );
        final e = engine(remote, clock: () => realNow.add(ahead));
        await e.run();
        expect(e.clockSkew.inHours, closeTo(-120, 1));
        expect((await routineRow(db, id))['title'], 'Truly newer cloud edit');
        expect(
          remote.t('routines')[syncId]!['title'],
          'Truly newer cloud edit',
        );
      },
    );

    test(
      'pushed timestamps are normalised to server time and never in the future',
      () async {
        final id = await insertRoutine(db, 'Fast clock row');
        final syncId = (await routineRow(db, id))['sync_id'] as String;
        final realNow = DateTime.now().toUtc();
        const ahead = Duration(days: 30);
        await setLocalTs(db, id, realNow.add(ahead)); // stamped 30 days ahead
        await engine(remote, clock: () => realNow.add(ahead)).run();
        final sent = DateTime.parse(
          '${remote.t('routines')[syncId]!['client_updated_at']}',
        );
        expect(sent.isAfter(realNow.add(const Duration(minutes: 2))), isFalse);
        expect(
          sent.isBefore(realNow.subtract(const Duration(minutes: 2))),
          isFalse,
        );
      },
    );

    test(
      'server time unavailable (old backend): falls back to the device clock',
      () async {
        remote.serverTimeAvailable = false;
        await insertRoutine(db, 'A');
        final e = engine(remote);
        await e.run();
        expect(e.clockSkew, Duration.zero);
        expect(remote.t('routines').length, 1);
      },
    );
  });

  group('MOCK-ONLY: ties and conflicts', () {
    test(
      'equal timestamps: the cloud copy wins on every device (convergence)',
      () async {
        final id = await insertRoutine(db, 'Device B version');
        final syncId = (await routineRow(db, id))['sync_id'] as String;
        final ts = DateTime.parse(
          (await routineRow(db, id))['sync_updated_at'] as String,
        );
        remote.plant(
          'routines',
          remoteRoutine(syncId, 'Device A version'),
          clientUpdatedAt: ts,
        );
        await engine(remote).run();
        expect((await routineRow(db, id))['title'], 'Device A version');
        expect(remote.t('routines')[syncId]!['title'], 'Device A version');
        final kinds = (await db.query('sync_conflicts')).map((e) => e['kind']);
        expect(kinds, contains('tie-remote-wins'));
      },
    );

    test('equal timestamps, local DELETE vs cloud edit: the delete wins consistently', () async {
      final id = await insertRoutine(db, 'Doomed');
      final syncId = (await routineRow(db, id))['sync_id'] as String;
      await engine(remote).run(); // now clean + in the cloud
      // Local delete stamped at T; cloud edit stamped at exactly T.
      await db.delete('routines', where: 'id = ?', whereArgs: [id]);
      final tomb = (await db.query('sync_tombstones')).single;
      final t = DateTime.parse(tomb['deleted_at'] as String);
      remote.plant(
        'routines',
        remoteRoutine(syncId, 'Edited elsewhere'),
        clientUpdatedAt: t,
      );
      await engine(remote).run();
      expect(remote.t('routines')[syncId]!['deleted_at'], isNotNull);
      expect(await db.query('routines'), isEmpty);
    });

    test(
      'a later cloud edit resurrects a row deleted earlier on this device',
      () async {
        final id = await insertRoutine(db, 'Deleted early');
        final syncId = (await routineRow(db, id))['sync_id'] as String;
        await engine(remote).run();
        await db.delete('routines', where: 'id = ?', whereArgs: [id]);
        remote.plant(
          'routines',
          remoteRoutine(syncId, 'Edited later elsewhere'),
          clientUpdatedAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );
        await engine(remote).run();
        final rows = await db.query('routines');
        expect(rows.single['title'], 'Edited later elsewhere');
      },
    );
  });

  group('MOCK-ONLY: partial failure and resume', () {
    test('one failing table does not stop the others; its children are skipped; next run completes', () async {
      final rid = await insertRoutine(db, 'Routine ok');
      // A dated plan with an exercise (parent: workout_plans, child: planned_exercises).
      final planId = await db.insert('workout_plans', {
        'date': '2026-10-20',
        'created_at': '2026-10-20T00:00:00',
        'updated_at': '2026-10-20T00:00:00',
      });
      await db.insert('planned_exercises', {
        'plan_id': planId,
        'exercise_id': 1,
        'exercise_name': 'Barbell Bench Press',
        'muscle_group_name': 'Chest',
      });
      remote.failUpsertTables.add('workout_plans');
      await expectLater(
        engine(remote).run(),
        throwsA(isA<SyncPartialFailure>()),
      );
      // The healthy table was pushed and marked clean.
      expect((await routineRow(db, rid))['sync_dirty'], 0);
      expect(remote.t('routines').length, 1);
      // The failed table and its child are still dirty and untouched locally.
      expect((await db.query('workout_plans')).single['sync_dirty'], 1);
      expect((await db.query('planned_exercises')).single['sync_dirty'], 1);
      expect(remote.t('workout_plan_exercises'), isEmpty);
      // Not marked as a successful sync.
      expect(await SyncEngine.getMeta(db, 'last_synced_at'), isNull);

      remote.failUpsertTables.clear();
      final rep = await engine(remote).run();
      expect(rep.failures, isEmpty);
      expect(remote.t('workout_plans').length, 1);
      expect(remote.t('workout_plan_exercises').length, 1);
      expect((await db.query('workout_plans')).single['sync_dirty'], 0);
    });

    test('connection lost in the middle of a push: pushed rows stay clean, the rest resume, no duplicates', () async {
      for (var i = 0; i < 7; i++) {
        await insertRoutine(db, 'R$i');
      }
      remote.failAfterUpsertedRows = 3;
      await expectLater(
        engine(remote, batchSize: 2).run(),
        throwsA(isA<SyncPartialFailure>()),
      );
      final dirtyAfterCrash = (await db.query(
        'routines',
        where: 'sync_dirty = 1',
      )).length;
      expect(dirtyAfterCrash, greaterThan(0));
      expect(dirtyAfterCrash, lessThan(7));
      expect(remote.t('routines').length, 3);

      remote.failAfterUpsertedRows = null;
      await engine(remote, batchSize: 2).run();
      expect(await db.query('routines', where: 'sync_dirty = 1'), isEmpty);
      expect(remote.t('routines').length, 7);
    });

    test('the app is killed after the upload but before the row was marked clean: the retry is idempotent', () async {
      final id = await insertRoutine(db, 'Retry me');
      final syncId = (await routineRow(db, id))['sync_id'] as String;
      await engine(remote).run();
      // Simulate "killed before markClean": flag it dirty again with the same stamp.
      await db.execute(
        "INSERT OR REPLACE INTO sync_meta(key,value) VALUES('applying','1')",
      );
      await db.update(
        'routines',
        {'sync_dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.delete('sync_meta', where: "key = 'applying'");
      await engine(remote).run();
      expect(remote.t('routines').length, 1);
      expect(remote.t('routines')[syncId]!['title'], 'Retry me');
      expect((await routineRow(db, id))['sync_dirty'], 0);
      expect((await db.query('routines')).length, 1);
    });
  });

  group('MOCK-ONLY: one active plan', () {
    Future<void> addPlan(
      Database d,
      String name, {
      required bool active,
    }) async {
      await d.insert('training_plans', {
        'name': name,
        'is_active': active ? 1 : 0,
        'created_at': '2026-10-01T00:00:00',
        'updated_at': '2026-10-01T00:00:00',
      });
    }

    test('two plans active (two devices) end up with exactly one, locally and in the cloud', () async {
      await addPlan(db, 'Plan A', active: true);
      await addPlan(db, 'Plan B', active: true);
      await engine(remote).run();
      final active = await db.query('training_plans', where: 'is_active = 1');
      expect(active.length, 1);
      final cloudActive = remote
          .t('training_plans')
          .values
          .where((r) => r['is_active'] == true || r['is_active'] == 1);
      expect(cloudActive.length, 1);
      expect(
        cloudActive.single['id'],
        active.single['sync_id'],
        reason: 'the cloud and the device agree on the winner',
      );
      expect(
        (await db.query('sync_conflicts')).map((e) => e['kind']),
        contains('two-active-plans'),
      );
    });

    test(
      'the winner is deterministic for equal timestamps (highest sync id)',
      () async {
        await addPlan(db, 'Plan A', active: true);
        await addPlan(db, 'Plan B', active: true);
        await db.execute(
          "UPDATE training_plans SET sync_updated_at = '2026-10-01T10:00:00.000Z'",
        );
        final ids = (await db.query(
          'training_plans',
          columns: ['sync_id'],
        )).map((e) => e['sync_id'] as String).toList()..sort();
        await engine(remote).run();
        final winner = (await db.query(
          'training_plans',
          where: 'is_active = 1',
        )).single;
        expect(winner['sync_id'], ids.last);
      },
    );
  });

  group(
    'MOCK-ONLY: custom exercise references survive different local ids',
    () {
      test('a plan using a custom exercise points at the right exercise on another device', () async {
        // Device A: custom exercise + plan day exercise referencing it.
        final exId = await db.insert('exercises', {
          'muscle_group_id': 1,
          'muscle_group_name': 'Chest',
          'name': 'Landmine Thing',
          'is_custom': 1,
          'created_at': '2026-10-01T00:00:00',
        });
        final planId = await db.insert('training_plans', {
          'name': 'With custom',
          'created_at': '2026-10-01T00:00:00',
          'updated_at': '2026-10-01T00:00:00',
        });
        final dayId = await db.insert('training_plan_days', {
          'plan_id': planId,
          'weekday': 1,
        });
        await db.insert('training_plan_day_exercises', {
          'day_id': dayId,
          'exercise_id': exId,
          'exercise_name': 'Landmine Thing',
          'muscle_group_name': 'Chest',
        });
        await engine(remote).run();
        final sent = remote.t('training_plan_day_exercises').values.single;
        expect(
          sent['exercise_id'],
          isNull,
          reason: 'device-specific id not sent',
        );
        expect(sent['exercise_sync_id'], isNotNull);

        // Device B already has another custom exercise, so local ids differ.
        db = await newDevice(db);
        final other = await db.insert('exercises', {
          'muscle_group_id': 1,
          'muscle_group_name': 'Back',
          'name': 'Some other custom',
          'is_custom': 1,
          'created_at': '2026-10-01T00:00:00',
        });
        await engine(remote).run();
        final mine = (await db.query(
          'exercises',
          where: "name = 'Landmine Thing'",
        )).single;
        expect(
          mine['id'],
          isNot(exId == other ? -1 : exId),
          reason: 'local ids are device specific',
        );
        final row = (await db.query('training_plan_day_exercises')).single;
        expect(row['exercise_id'], mine['id']);
      });

      test('catalogue exercises keep their stable integer id', () async {
        final planId = await db.insert('training_plans', {
          'name': 'Catalogue',
          'created_at': '2026-10-01T00:00:00',
          'updated_at': '2026-10-01T00:00:00',
        });
        final dayId = await db.insert('training_plan_days', {
          'plan_id': planId,
          'weekday': 2,
        });
        await db.insert('training_plan_day_exercises', {
          'day_id': dayId,
          'exercise_id': 1,
          'exercise_name': 'Barbell Bench Press',
          'muscle_group_name': 'Chest',
        });
        await engine(remote).run();
        final sent = remote.t('training_plan_day_exercises').values.single;
        expect(sent['exercise_id'], 1);
        expect(sent['exercise_sync_id'], isNull);
      });
    },
  );

  group('MOCK-ONLY: accounts', () {
    test('a different account is never synced silently; linking re-uploads this device data', () async {
      await insertRoutine(db, 'Mine');
      await engine(remote).run();
      expect(remote.t('routines').length, 1);

      final other = FakeSyncRemote();
      await expectLater(
        engine(other, user: 'user-2').run(),
        throwsA(isA<SyncAccountMismatch>()),
      );
      expect(other.t('routines'), isEmpty, reason: 'nothing was uploaded');

      await SyncEngine.linkAccount(DatabaseHelper.instance, 'user-2');
      await engine(other, user: 'user-2').run();
      expect(other.t('routines').length, 1);
      expect(
        (await db.query('routines')).single['title'],
        'Mine',
        reason: 'local data was never touched',
      );
    });

    test(
      'after account deletion a new account receives everything again',
      () async {
        await insertRoutine(db, 'Survivor');
        await engine(remote).run();
        expect(await SyncEngine.pendingChanges(db), 0);
        await SyncEngine.linkAccount(DatabaseHelper.instance, null);
        expect(await SyncEngine.pendingChanges(db), greaterThan(0));
        expect(await SyncEngine.getMeta(db, 'last_synced_at'), isNull);
        final fresh = FakeSyncRemote();
        await engine(fresh, user: 'user-new').run();
        expect(fresh.t('routines').length, 1);
      },
    );

    test('pending change counter counts dirty rows and tombstones', () async {
      final id = await insertRoutine(db, 'X');
      await insertRoutine(db, 'Y');
      expect(await SyncEngine.pendingChanges(db), 2);
      await engine(remote).run();
      expect(await SyncEngine.pendingChanges(db), 0);
      await db.delete('routines', where: 'id = ?', whereArgs: [id]);
      expect(await SyncEngine.pendingChanges(db), 1);
    });
  });

  group('MOCK-ONLY: catalogue favourites', () {
    test('a favourite toggled on one device appears on the other; a newer unfavourite wins', () async {
      await db.update('exercises', {'is_favourite': 1}, where: 'id = 1');
      expect((await db.query('favourite_sync')).length, 1);
      await engine(remote).run();
      expect(remote.favourites['1']['f'], true);
      expect((await db.query('favourite_sync')).single['dirty'], 0);

      db = await newDevice(db);
      await engine(remote).run();
      expect(
        (await db.query('exercises', where: 'id = 1')).single['is_favourite'],
        1,
      );
      // Device B un-favourites later.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.update('exercises', {'is_favourite': 0}, where: 'id = 1');
      await engine(remote).run();
      expect(remote.favourites['1']['f'], false);

      // Device A (offline until now) still believes it is a favourite but its
      // change is older than the cloud one: it must end up un-favourited.
      db = await newDevice(db);
      await db.update('exercises', {'is_favourite': 1}, where: 'id = 1');
      await db.execute(
        "UPDATE favourite_sync SET updated_at = '2020-01-01T00:00:00.000Z'",
      );
      await engine(remote).run();
      expect(
        (await db.query('exercises', where: 'id = 1')).single['is_favourite'],
        0,
      );
    });

    test('a backend without the favourites RPC only leaves a note, sync still succeeds', () async {
      remote.favouritesSupported = false;
      await db.update('exercises', {'is_favourite': 1}, where: 'id = 2');
      await insertRoutine(db, 'Fine');
      final rep = await engine(remote).run();
      expect(rep.failures, isEmpty);
      expect(remote.t('routines').length, 1);
    });
  });

  group('schema extras (applied on open, no version bump)', () {
    test(
      'existing favourites are backfilled once and re-running changes nothing',
      () async {
        // Simulate a database from before the favourites tracking existed.
        await db.execute('DROP TRIGGER IF EXISTS trg_sync_favourite_au');
        await db.execute('DROP TABLE IF EXISTS favourite_sync');
        await db.delete('sync_meta', where: "key = 'schema_extras_rev'");
        await db.execute(
          'UPDATE exercises SET is_favourite = 1 WHERE id IN (3, 4)',
        );

        await SyncSchema.ensureCurrent(db);
        var rows = await db.query('favourite_sync', orderBy: 'exercise_id');
        expect(rows.map((r) => r['exercise_id']), [3, 4]);
        expect(rows.every((r) => r['dirty'] == 1), isTrue);

        // user data untouched, second call is a no-op
        await db.update('favourite_sync', {'dirty': 0});
        await SyncSchema.ensureCurrent(db);
        rows = await db.query('favourite_sync', orderBy: 'exercise_id');
        expect(rows.length, 2);
        expect(rows.every((r) => r['dirty'] == 0), isTrue);
        expect(
          (await db.query(
            'exercises',
            where: 'id IN (3, 4) AND is_favourite = 1',
          )).length,
          2,
        );
        // the trigger is live again
        await db.update('exercises', {'is_favourite': 0}, where: 'id = 3');
        expect(
          (await db.query(
            'favourite_sync',
            where: 'exercise_id = 3',
          )).single['dirty'],
          1,
        );
      },
    );
  });
}
