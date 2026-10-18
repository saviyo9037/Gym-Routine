// MOCK-ONLY: SyncService is driven with fake auth, fake entitlement and FakeSyncRemote.
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/data/db_helper.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/premium_service.dart';
import 'package:reptrack/services/sync_remote.dart';
import 'package:reptrack/services/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/cloud_fakes.dart';
import 'helpers/fake_sync_remote.dart';
import 'helpers/test_db.dart';

final _now = DateTime(2026, 10, 20, 12);

Future<PremiumService> premium(bool active) async {
  final p = PremiumService(
    source: FakeEntitlementSource(
      active: active,
      expiresAt: active ? _now.add(const Duration(days: 30)) : null,
      now: _now,
    ),
    store: MemorySettingsStore(),
    clock: () => _now,
  );
  await p.initialize();
  return p;
}

Future<void> addRoutine(Database db, String title) => db.insert('routines', {
  'title': title,
  'category': 'Gym',
  'start_time': '07:00',
  'end_time': '08:00',
  'repeat_days': '1',
  'created_at': '2026-10-01T00:00:00',
  'updated_at': '2026-10-01T00:00:00',
});

void main() {
  late Database db;

  setUp(() async {
    db = await openTestDatabase();
    await db.delete('routines');
    await db.delete('sync_tombstones');
    await db.delete('sync_meta', where: "key <> 'schema_extras_rev'");
  });
  tearDown(() => closeTestDatabase(db));

  test(
    'MOCK-ONLY: not configured / signed out / free: nothing is synced',
    () async {
      await addRoutine(db, 'Local');
      final remote = FakeSyncRemote();
      var built = 0;
      SyncRemote make(CloudUser u) {
        built++;
        return remote;
      }

      final off = SyncService(
        auth: FakeAuthService(configured: false),
        premium: await premium(true),
        remoteFactory: make,
      );
      await off.syncNow();
      expect(off.state, SyncState.notConfigured);

      final out = SyncService(
        auth: FakeAuthService(),
        premium: await premium(true),
        remoteFactory: make,
      );
      await out.syncNow();
      expect(out.state, SyncState.signedOut);

      final free = SyncService(
        auth: FakeAuthService(signedIn: const CloudUser(id: 'u-1')),
        premium: await premium(false),
        remoteFactory: make,
      );
      await free.syncNow();
      expect(free.state, SyncState.needsPremium);
      expect(built, 0, reason: 'no cloud client was even created');
      expect(remote.t('routines'), isEmpty);
    },
  );

  test('MOCK-ONLY: another account needs confirmation; confirming uploads, local data untouched', () async {
    await addRoutine(db, 'Mine');
    final auth = FakeAuthService(signedIn: const CloudUser(id: 'user-1'));
    final remotes = <String, FakeSyncRemote>{
      'user-1': FakeSyncRemote(),
      'user-2': FakeSyncRemote(),
    };
    final svc = SyncService(
      auth: auth,
      premium: await premium(true),
      remoteFactory: (u) => remotes[u.id]!,
    );
    await svc.syncNow();
    expect(svc.state, SyncState.idle);
    expect(remotes['user-1']!.t('routines').length, 1);

    auth.setUser(const CloudUser(id: 'user-2'));
    await svc.syncNow();
    expect(svc.state, SyncState.needsAccountLink);
    expect(remotes['user-2']!.t('routines'), isEmpty);

    await svc.linkLocalDataToCurrentAccount();
    expect(svc.state, SyncState.idle);
    expect(remotes['user-2']!.t('routines').length, 1);
    expect((await db.query('routines')).single['title'], 'Mine');
  });

  test('MOCK-ONLY: signing out clears the warning states', () async {
    await addRoutine(db, 'Mine');
    final auth = FakeAuthService(signedIn: const CloudUser(id: 'user-1'));
    final remote = FakeSyncRemote()..failUpsertTables.add('routines');
    final svc = SyncService(
      auth: auth,
      premium: await premium(true),
      remoteFactory: (_) => remote,
    );
    await svc.syncNow();
    expect(svc.state, SyncState.partial);
    expect(svc.lastReport!.failures.keys, contains('routines'));
    await auth.signOut();
    expect(svc.state, SyncState.signedOut);
    auth.setUser(const CloudUser(id: 'user-1'));
    remote.failUpsertTables.clear();
    await svc.syncNow();
    expect(svc.state, SyncState.idle);
    expect(remote.t('routines').length, 1);
  });

  test('MOCK-ONLY: after account deletion this device re-uploads to a future account', () async {
    await addRoutine(db, 'Survivor');
    final auth = FakeAuthService(signedIn: const CloudUser(id: 'user-1'));
    final svc = SyncService(
      auth: auth,
      premium: await premium(true),
      remoteFactory: (_) => FakeSyncRemote(),
    );
    await svc.syncNow();
    expect(await svc.pendingChanges(), 0);
    await auth.deleteAccount();
    await svc.forgetAccount();
    expect(await svc.pendingChanges(), greaterThan(0));
    expect(svc.lastSyncedAt, isNull);
    // a brand-new account on the same device gets everything
    final fresh = FakeSyncRemote();
    auth.setUser(const CloudUser(id: 'user-new'));
    final svc2 = SyncService(
      auth: auth,
      premium: await premium(true),
      remoteFactory: (_) => fresh,
    );
    await svc2.syncNow();
    expect(svc2.state, SyncState.idle);
    expect(fresh.t('routines').length, 1);
    expect(DatabaseHelper.instance, isNotNull);
  });
}
