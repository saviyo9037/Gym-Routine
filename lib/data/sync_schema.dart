import 'package:sqflite/sqflite.dart';

import '../services/sync_tables.dart';

/// Schema v7: change tracking for cloud sync.
///
/// Everything is additive and works through SQLite triggers, so no existing
/// code path (plans, sessions, routines, backups...) had to change:
///  * every synced table gets `sync_id`, `sync_updated_at`, `sync_dirty`;
///  * INSERT/UPDATE triggers stamp them, DELETE triggers write a tombstone;
///  * while the sync engine applies remote rows it sets `sync_meta.applying=1`
///    so its own writes never mark rows dirty.
/// Nothing leaves the device unless the user is signed in AND premium.
class SyncSchema {
  static const String _now = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";

  /// Random v4 uuid in pure SQL.
  static const String _uuid =
      "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || "
      "substr(lower(hex(randomblob(2))),2) || '-' || "
      "substr('89ab', abs(random()) % 4 + 1, 1) || "
      "substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))";

  static const String _notApplying =
      "COALESCE((SELECT value FROM sync_meta WHERE key = 'applying'), '0') <> '1'";

  /// Idempotent: safe to call on a fresh DB and on every upgrade.
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_tombstones (
        table_name TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        pushed INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (table_name, sync_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        sync_id TEXT,
        kind TEXT NOT NULL,
        detail TEXT,
        at TEXT NOT NULL
      )
    ''');
    // Catalogue merge support (does not affect user data).
    await _addColumn(
      db,
      'exercises',
      'catalogue_archived',
      'INTEGER NOT NULL DEFAULT 0',
    );

    for (final spec in syncTables) {
      final t = spec.local;
      await _addColumn(db, t, 'sync_id', 'TEXT');
      await _addColumn(db, t, 'sync_updated_at', 'TEXT');
      await _addColumn(db, t, 'sync_dirty', 'INTEGER NOT NULL DEFAULT 0');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_sync_id '
        'ON $t(sync_id) WHERE sync_id IS NOT NULL',
      );

      // Backfill: existing rows are marked dirty so the first premium sync
      // uploads them. Deterministic-id tables get their id from Dart later.
      final cond = spec.localCondition == null
          ? ''
          : ' AND ${spec.localCondition}';
      final idExpr = spec.deterministicId == null
          ? 'COALESCE(sync_id, $_uuid)'
          : 'sync_id';
      await db.execute(
        "UPDATE $t SET sync_id = $idExpr, "
        "sync_updated_at = COALESCE(sync_updated_at, $_now), sync_dirty = 1 "
        'WHERE sync_updated_at IS NULL$cond',
      );

      await _createTriggers(db, spec);
    }
  }

  /// Revision of the sync-related schema extras that are applied on open
  /// (idempotent, no database version bump needed):
  ///  2 = catalogue favourite tracking (favourite_sync table + trigger)
  static const int extrasRevision = 2;

  /// Runs on every open; only does work when the stored revision is old.
  static Future<void> ensureCurrent(Database db) async {
    final hasMeta = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_meta'",
    );
    if (hasMeta.isEmpty) return; // not a v7 database (yet)
    final r = await db.query(
      'sync_meta',
      columns: ['value'],
      where: "key = 'schema_extras_rev'",
      limit: 1,
    );
    final current = r.isEmpty ? 0 : int.tryParse('${r.first['value']}') ?? 0;
    if (current >= extrasRevision) return;
    await installExtras(db);
    await db.insert('sync_meta', {
      'key': 'schema_extras_rev',
      'value': '$extrasRevision',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Per-exercise change tracking for the favourites of CATALOGUE exercises
  /// (custom exercises carry `is_favourite` inside their own synced row).
  static Future<void> installExtras(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favourite_sync (
        exercise_id INTEGER PRIMARY KEY,
        is_favourite INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_favourite_au');
    await db.execute('''
      CREATE TRIGGER trg_sync_favourite_au AFTER UPDATE OF is_favourite ON exercises
      WHEN NEW.is_custom = 0 AND NEW.is_favourite IS NOT OLD.is_favourite AND $_notApplying
      BEGIN
        INSERT OR REPLACE INTO favourite_sync (exercise_id, is_favourite, updated_at, dirty)
        VALUES (NEW.id, NEW.is_favourite, $_now, 1);
      END
    ''');
    // Existing favourites are uploaded by the first premium sync.
    await db.execute('''
      INSERT OR IGNORE INTO favourite_sync (exercise_id, is_favourite, updated_at, dirty)
      SELECT id, 1, $_now, 1 FROM exercises WHERE is_custom = 0 AND is_favourite = 1
    ''');
  }

  static String _newCond(SyncTableSpec s) =>
      s.localCondition == null ? '1' : _qualify(s.localCondition!, 'NEW');
  static String _oldCond(SyncTableSpec s) =>
      s.localCondition == null ? '1' : _qualify(s.localCondition!, 'OLD');

  /// `is_custom = 1` -> `NEW.is_custom = 1` (single simple condition only).
  static String _qualify(String cond, String row) =>
      cond.replaceAllMapped(RegExp(r'^\s*(\w+)'), (m) => '$row.${m[1]}');

  static Future<void> _createTriggers(
    DatabaseExecutor db,
    SyncTableSpec s,
  ) async {
    final t = s.local;
    final idSet = s.deterministicId == null
        ? 'sync_id = COALESCE(sync_id, $_uuid), '
        : '';
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_${t}_ai');
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_${t}_au');
    await db.execute('DROP TRIGGER IF EXISTS trg_sync_${t}_ad');
    await db.execute('''
      CREATE TRIGGER trg_sync_${t}_ai AFTER INSERT ON $t
      WHEN ${_newCond(s)} AND $_notApplying
      BEGIN
        UPDATE $t SET ${idSet}sync_updated_at = $_now, sync_dirty = 1
        WHERE rowid = NEW.rowid;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_sync_${t}_au AFTER UPDATE ON $t
      WHEN ${_newCond(s)} AND $_notApplying
        AND NEW.sync_dirty IS OLD.sync_dirty
        AND NEW.sync_updated_at IS OLD.sync_updated_at
        AND NEW.sync_id IS OLD.sync_id
      BEGIN
        UPDATE $t SET sync_updated_at = $_now, sync_dirty = 1
        WHERE rowid = NEW.rowid;
      END
    ''');
    await db.execute('''
      CREATE TRIGGER trg_sync_${t}_ad AFTER DELETE ON $t
      WHEN OLD.sync_id IS NOT NULL AND ${_oldCond(s)} AND $_notApplying
      BEGIN
        INSERT OR REPLACE INTO sync_tombstones (table_name, sync_id, deleted_at, pushed)
        VALUES ('$t', OLD.sync_id, $_now, 0);
      END
    ''');
  }

  static Future<void> _addColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String ddl,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.any((r) => r['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $ddl');
  }
}
