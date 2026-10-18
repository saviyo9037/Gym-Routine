import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/services/catalogue_sync_service.dart';
import 'package:reptrack/services/training_plan_service.dart';
import 'package:reptrack/models/training_plan.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_db.dart';

// MOCK-ONLY: FakeCatalogueRemote is an in-memory stand-in for the cloud catalogue.
class FakeCatalogueRemote implements CatalogueRemote {
  int latest = 0;
  List<Map<String, dynamic>> rows = [];
  int fetchCalls = 0;
  bool fail = false;
  int? failOnFetchCall;

  @override
  Future<int> latestVersion() async {
    if (fail) throw Exception('offline');
    return latest;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDelta(
    int afterVersion, {
    int afterId = 0,
    int limit = 500,
  }) async {
    fetchCalls++;
    if (failOnFetchCall != null && fetchCalls == failOnFetchCall) {
      throw Exception('network down');
    }
    final sorted =
        rows.where((r) {
          final v = r['catalogue_version'] as int;
          final id = r['id'] as int;
          return v > afterVersion || (v == afterVersion && id > afterId);
        }).toList()..sort((a, b) {
          final c = (a['catalogue_version'] as int).compareTo(
            b['catalogue_version'] as int,
          );
          return c != 0 ? c : (a['id'] as int).compareTo(b['id'] as int);
        });
    return sorted.take(limit).toList(); // honours the page cap like the server
  }

  @override
  Future<List<Map<String, dynamic>>> mediaFor(int exerciseId) async => [];
  @override
  Future<String?> signedUrl(String storagePath) async => null;
}

Map<String, dynamic> row(
  int id,
  String name, {
  int version = 2,
  String status = 'published',
  String group = 'Chest',
}) => {
  'id': id,
  'name': name,
  'primary_muscle_group': group,
  'status': status,
  'catalogue_version': version,
  'difficulty': 'Beginner',
  'default_sets': 5,
  'default_reps': 5,
  'default_weight_kg': 20,
  'rest_seconds': 120,
  'is_compound': true,
  'is_recommended': true,
  'description': 'from the cloud',
};

void main() {
  late Database db;
  late FakeCatalogueRemote remote;
  late CatalogueSyncService svc;

  setUp(() async {
    db = await openTestDatabase();
    remote = FakeCatalogueRemote();
    svc = CatalogueSyncService(remote);
  });
  tearDown(() => closeTestDatabase(db));

  test('no newer version: nothing is fetched or changed', () async {
    final r = await svc.sync();
    expect(r.changed, isFalse);
    expect(remote.fetchCalls, 0);
    expect(await svc.localVersion(), 0);
  });

  test(
    'delta updates by stable id and keeps favourites, notes and images',
    () async {
      await db.update('exercises', {
        'is_favourite': 1,
        'personal_notes': 'my note',
        'personal_photo_path': '/p/photo.jpg',
        'trainer_instructions': 'coach says',
      }, where: 'id = 1');
      final before = (await db.query('exercises', where: 'id = 1')).single;
      remote
        ..latest = 2
        ..rows = [row(1, 'Barbell Bench Press (renamed)')];
      final r = await svc.sync();
      expect(r.applied, 1);
      final after = (await db.query('exercises', where: 'id = 1')).single;
      expect(after['name'], 'Barbell Bench Press (renamed)');
      expect(after['default_sets'], 5);
      expect(after['is_favourite'], 1);
      expect(after['personal_notes'], 'my note');
      expect(after['personal_photo_path'], '/p/photo.jpg');
      expect(after['trainer_instructions'], 'coach says');
      expect(after['image_path'], before['image_path']);
      expect(after['is_custom'], 0);
      expect(await svc.localVersion(), 2);
    },
  );

  test(
    'new catalogue exercises are inserted; unchanged ids are untouched',
    () async {
      final count = (await db.query('exercises')).length;
      final untouched = (await db.query('exercises', where: 'id = 2')).single;
      remote
        ..latest = 3
        ..rows = [row(5001, 'Cloud Only Press', version: 3)];
      final r = await svc.sync();
      expect(r.inserted, 1);
      expect((await db.query('exercises')).length, count + 1);
      expect((await db.query('exercises', where: 'id = 2')).single, untouched);
      final inserted = (await db.query('exercises', where: 'id = 5001')).single;
      expect(inserted['muscle_group_name'], 'Chest');
      expect(inserted['muscle_group_id'], 1);
      expect(inserted['is_custom'], 0);
    },
  );

  test(
    'user-created exercises are never overwritten, even on an id collision',
    () async {
      final id = await db.insert('exercises', {
        'id': 6000,
        'muscle_group_id': 1,
        'muscle_group_name': 'Chest',
        'name': 'My Own Move',
        'is_custom': 1,
        'personal_notes': 'mine',
        'created_at': '2026-10-01T00:00:00',
      });
      expect(id, 6000);
      remote
        ..latest = 4
        ..rows = [row(6000, 'Cloud Impostor', version: 4)];
      final r = await svc.sync();
      expect(r.skippedCustomCollision, 1);
      final mine = (await db.query('exercises', where: 'id = 6000')).single;
      expect(mine['name'], 'My Own Move');
      expect(mine['personal_notes'], 'mine');
      expect(mine['is_custom'], 1);
    },
  );

  test(
    'archived exercises are flagged, never deleted, plans keep working',
    () async {
      final plans = TrainingPlanService();
      final planId = await plans.savePlan(
        TrainingPlan(
          name: 'P',
          days: [
            const TrainingPlanDay(
              weekday: 1,
              exercises: [
                TrainingPlanExercise(
                  exerciseId: 1,
                  exerciseName: 'Barbell Bench Press',
                  muscleGroupName: 'Chest',
                ),
              ],
            ),
            for (var d = 2; d <= 7; d++)
              TrainingPlanDay(weekday: d, isRest: true),
          ],
        ),
      );
      remote
        ..latest = 5
        ..rows = [
          row(1, 'Barbell Bench Press', version: 5, status: 'archived'),
        ];
      final r = await svc.sync();
      expect(r.archived, 1);
      final ex = (await db.query('exercises', where: 'id = 1')).single;
      expect(ex['catalogue_archived'], 1);
      expect(ex['name'], 'Barbell Bench Press');
      final plan = (await plans.getPlan(planId))!;
      expect(plan.dayFor(1).exercises.single.exerciseId, 1);
    },
  );

  test(
    'a failure leaves the database and version untouched (single transaction)',
    () async {
      remote
        ..latest = 2
        ..rows = [
          row(1, 'Changed'),
          {...row(2, 'Boom'), 'name': null}, // NOT NULL violation
        ];
      await expectLater(svc.sync(), throwsA(anything));
      expect(
        (await db.query('exercises', where: 'id = 1')).single['name'],
        'Barbell Bench Press',
      );
      expect(await svc.localVersion(), 0);
      // network failure also leaves everything alone
      remote.fail = true;
      await expectLater(svc.sync(), throwsA(anything));
      expect(await svc.localVersion(), 0);
    },
  );

  test(
    'syncing twice is idempotent and does not mark catalogue rows for upload',
    () async {
      remote
        ..latest = 2
        ..rows = [row(1, 'Renamed')];
      await svc.sync();
      final r2 = await svc.sync();
      expect(r2.changed, isFalse);
      final dirty = await db.rawQuery(
        'SELECT COUNT(*) c FROM exercises WHERE sync_dirty = 1',
      );
      expect(dirty.single['c'], 0);
    },
  );

  test('MOCK-ONLY: 1250 rows in ONE version arrive completely despite the 500-row page cap', () async {
    remote.latest = 2;
    remote.rows = [
      for (var i = 0; i < 1250; i++) row(5000 + i, 'Bulk $i', version: 2),
    ];
    final r = await svc.sync();
    expect(r.inserted, 1250);
    expect(remote.fetchCalls, 3);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM exercises WHERE id >= 5000'),
      ),
      1250,
    );
    expect(await svc.localVersion(), 2);
  });

  test('MOCK-ONLY: a failure on page 2 changes nothing and the version does not advance', () async {
    remote.latest = 2;
    remote.rows = [
      for (var i = 0; i < 700; i++) row(6000 + i, 'Bulk $i', version: 2),
    ];
    final before = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM exercises'),
    );
    remote.failOnFetchCall = 2;
    await expectLater(svc.sync(), throwsException);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM exercises'),
      ),
      before,
    );
    expect(await svc.localVersion(), 0);
    remote.failOnFetchCall = null;
    expect((await svc.sync()).inserted, 700);
  });
}
