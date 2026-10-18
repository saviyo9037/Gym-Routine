import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

/// How a column is converted between SQLite and the cloud row.
enum ColType { text, integer, real, boolean, timestamp }

/// local column <-> remote column.
class ColMap {
  const ColMap(this.local, this.remote, [this.type = ColType.text]);
  final String local;
  final String remote;
  final ColType type;
}

/// Local integer foreign key that is sent to the cloud as the parent's
/// `sync_id` (uuid).
class ParentRef {
  const ParentRef({
    required this.localCol,
    required this.remoteCol,
    required this.parentTable,
    this.optional = false,
  });
  final String localCol;
  final String remoteCol;
  final String parentTable; // local parent table name
  final bool optional;
}

typedef RowHook = Future<void> Function(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
);

/// Declarative description of one synced table.
class SyncTableSpec {
  const SyncTableSpec({
    required this.local,
    required this.remote,
    required this.cols,
    this.parents = const [],
    this.localCondition,
    this.deterministicId,
    this.uniqueKey = const [],
    this.toRemoteExtra,
    this.fromRemoteExtra,
  });

  final String local;
  final String remote;
  final List<ColMap> cols;
  final List<ParentRef> parents;

  /// SQL condition on `NEW`/`OLD`/the row (for example `is_custom = 1`).
  final String? localCondition;

  /// When set, ids are derived from natural keys (so the same date / routine
  /// completion created on two devices maps to ONE cloud row) instead of being
  /// random. Receives the local row (+ resolved parent sync ids by local
  /// column name) and returns the name to hash.
  final String Function(
    Map<String, Object?> row,
    Map<String, String?> parentIds,
  )?
  deterministicId;

  /// Local columns that must be unique (used to resolve replace-style updates).
  final List<String> uniqueKey;

  /// Adds remote-only fields (for example timestamps derived from local text).
  final RowHook? toRemoteExtra;

  /// Adds local-only fields when inserting/updating from a remote row.
  final RowHook? fromRemoteExtra;
}

/// Name-based (UUID v5 style) id: the same natural key always gives the same
/// uuid on every device.
String deterministicUuid(String name) {
  final bytes = sha1.convert(('reptrack:$name').codeUnits).bytes;
  final b = List<int>.from(bytes.take(16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int from, int to) => b
      .sublist(from, to)
      .map((e) => e.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

DateTime? parseTs(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// Local text timestamp -> UTC ISO string (accepts local ISO without zone).
String? tsToRemote(Object? v) => parseTs(v)?.toUtc().toIso8601String();

/// Remote timestamptz -> local ISO string (device time, no zone), the format
/// the app has always stored.
String? tsFromRemote(Object? v) => parseTs(v)?.toLocal().toIso8601String();

Future<void> _exerciseFromRemote(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) async {
  final name = local['muscle_group_name'] as String?;
  var groupId = 0;
  if (name != null) {
    final r = await db.query(
      'muscle_groups',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (r.isNotEmpty) groupId = r.first['id'] as int;
  }
  local['muscle_group_id'] = groupId;
  local['is_custom'] = 1;
  local['created_at'] ??= DateTime.now().toIso8601String();
}

/// Custom exercises have device-specific integer ids, so rows that reference
/// one carry its stable `sync_id` instead (catalogue ids are identical on
/// every device and are sent as before).
Future<void> _exerciseRefToRemote(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) async {
  final id = local['exercise_id'];
  if (id == null) return;
  final r = await db.query(
    'exercises',
    columns: ['sync_id', 'is_custom'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  if (r.isNotEmpty &&
      (r.first['is_custom'] as int? ?? 0) == 1 &&
      r.first['sync_id'] != null) {
    remote['exercise_sync_id'] = r.first['sync_id'];
    remote['exercise_id'] = null;
  }
}

Future<void> _exerciseRefFromRemote(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) async {
  final sid = remote['exercise_sync_id'];
  if (sid == null) {
    local['exercise_id'] ??= 0;
    return;
  }
  final r = await db.query(
    'exercises',
    columns: ['id'],
    where: 'sync_id = ?',
    whereArgs: [sid],
    limit: 1,
  );
  // 0 = the custom exercise is not on this device (the row keeps its name).
  local['exercise_id'] = r.isEmpty ? 0 : r.first['id'];
}

Future<void> _plannedFromRemote(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) async {
  await _exerciseRefFromRemote(db, local, remote);
  final id = local['exercise_id'];
  if (id != null) {
    final r = await db.query(
      'exercises',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (r.isNotEmpty) local['image_path'] = r.first['image_path'];
  }
}

Future<void> _sessionToRemote(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) async {
  final date = local['date'] as String?;
  final start = local['start_time'] as String?;
  if (date != null && start != null) {
    remote['start_time'] = DateTime.tryParse(
      '$date ${start.length == 5 ? start : '00:00'}:00',
    )?.toUtc().toIso8601String();
  }
  remote['start_time'] ??= DateTime.now().toUtc().toIso8601String();
}

Future<void> _sessionFromRemote(
  DatabaseExecutor db,
  Map<String, Object?> local,
  Map<String, Object?> remote,
) async {
  // start_time / end_time locally are 'HH:mm' (copied from start_hhmm/end_hhmm).
  if (local['start_time'] == null) {
    final t = parseTs(remote['start_time'])?.toLocal();
    local['start_time'] = t == null
        ? '00:00'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  local['created_at'] ??= DateTime.now().toIso8601String();
}

/// The synced tables, parents before children.
final List<SyncTableSpec> syncTables = [
  const SyncTableSpec(
    local: 'exercises',
    remote: 'user_exercises',
    localCondition: 'is_custom = 1',
    cols: [
      ColMap('name', 'name'),
      ColMap('muscle_group_name', 'primary_muscle_group'),
      ColMap('secondary_muscles', 'secondary_muscles'),
      ColMap('target', 'target'),
      ColMap('description', 'description'),
      ColMap('starting_position', 'starting_position'),
      ColMap('instructions', 'instructions'),
      ColMap('breathing_guidance', 'breathing_guidance'),
      ColMap('beginner_modification', 'beginner_modification'),
      ColMap('equipment', 'equipment'),
      ColMap('difficulty', 'difficulty'),
      ColMap('suggested_sets_reps', 'suggested_sets_reps'),
      ColMap('common_mistakes', 'common_mistakes'),
      ColMap('default_sets', 'default_sets', ColType.integer),
      ColMap('default_reps', 'default_reps', ColType.integer),
      ColMap('default_weight_kg', 'default_weight_kg', ColType.real),
      ColMap('rest_seconds', 'rest_seconds', ColType.integer),
      ColMap('personal_notes', 'personal_notes'),
      ColMap('trainer_instructions', 'trainer_instructions'),
      ColMap('is_compound', 'is_compound', ColType.boolean),
      ColMap('is_favourite', 'is_favourite', ColType.boolean),
    ],
    fromRemoteExtra: _exerciseFromRemote,
  ),
  const SyncTableSpec(
    local: 'training_plans',
    remote: 'training_plans',
    cols: [
      ColMap('name', 'name'),
      ColMap('notes', 'notes'),
      ColMap('is_active', 'is_active', ColType.boolean),
      ColMap('deleted_at', 'deleted_at', ColType.timestamp),
    ],
  ),
  const SyncTableSpec(
    local: 'training_plan_days',
    remote: 'training_plan_days',
    uniqueKey: ['plan_id', 'weekday'],
    parents: [
      ParentRef(
        localCol: 'plan_id',
        remoteCol: 'plan_id',
        parentTable: 'training_plans',
      ),
    ],
    cols: [
      ColMap('weekday', 'weekday', ColType.integer),
      ColMap('is_rest', 'is_rest', ColType.boolean),
      ColMap('title', 'title'),
      ColMap('notes', 'notes'),
    ],
  ),
  const SyncTableSpec(
    local: 'training_plan_day_exercises',
    remote: 'training_plan_day_exercises',
    parents: [
      ParentRef(
        localCol: 'day_id',
        remoteCol: 'day_id',
        parentTable: 'training_plan_days',
      ),
    ],
    cols: [
      ColMap('exercise_id', 'exercise_id', ColType.integer),
      ColMap('exercise_name', 'exercise_name'),
      ColMap('muscle_group_name', 'muscle_group_name'),
      ColMap('exercise_order', 'exercise_order', ColType.integer),
      ColMap('target_sets', 'target_sets', ColType.integer),
      ColMap('target_reps', 'target_reps', ColType.integer),
      ColMap('target_weight_kg', 'target_weight_kg', ColType.real),
      ColMap('rest_seconds', 'rest_seconds', ColType.integer),
      ColMap(
        'target_duration_seconds',
        'target_duration_seconds',
        ColType.integer,
      ),
      ColMap('target_distance_km', 'target_distance_km', ColType.real),
      ColMap('notes', 'notes'),
    ],
    toRemoteExtra: _exerciseRefToRemote,
    fromRemoteExtra: _exerciseRefFromRemote,
  ),
  SyncTableSpec(
    local: 'workout_plans',
    remote: 'workout_plans',
    uniqueKey: const ['date'],
    deterministicId: (row, _) => 'plan:${row['date']}',
    cols: const [
      ColMap('date', 'plan_date'),
      ColMap('primary_muscle_id', 'primary_muscle_id', ColType.integer),
      ColMap('primary_muscle_name', 'primary_muscle_name'),
      ColMap('secondary_muscle_id', 'secondary_muscle_id', ColType.integer),
      ColMap('secondary_muscle_name', 'secondary_muscle_name'),
      ColMap('notes', 'notes'),
      ColMap('trainer_instructions', 'trainer_instructions'),
      ColMap('is_completed', 'is_completed', ColType.boolean),
      ColMap('is_rest_day', 'is_rest_day', ColType.boolean),
    ],
  ),
  const SyncTableSpec(
    local: 'planned_exercises',
    remote: 'workout_plan_exercises',
    parents: [
      ParentRef(
        localCol: 'plan_id',
        remoteCol: 'plan_id',
        parentTable: 'workout_plans',
      ),
    ],
    cols: [
      ColMap('exercise_id', 'exercise_id', ColType.integer),
      ColMap('exercise_name', 'exercise_name'),
      ColMap('muscle_group_name', 'muscle_group_name'),
      ColMap('exercise_order', 'exercise_order', ColType.integer),
      ColMap('target_sets', 'target_sets', ColType.integer),
      ColMap('target_reps', 'target_reps', ColType.integer),
      ColMap('target_weight_kg', 'target_weight_kg', ColType.real),
      ColMap('rest_seconds', 'rest_seconds', ColType.integer),
      ColMap('notes', 'notes'),
      ColMap(
        'target_duration_seconds',
        'target_duration_seconds',
        ColType.integer,
      ),
      ColMap('target_distance_km', 'target_distance_km', ColType.real),
    ],
    toRemoteExtra: _exerciseRefToRemote,
    fromRemoteExtra: _plannedFromRemote,
  ),
  const SyncTableSpec(
    local: 'workout_sessions',
    remote: 'workout_sessions',
    parents: [
      ParentRef(
        localCol: 'plan_id',
        remoteCol: 'plan_id',
        parentTable: 'workout_plans',
        optional: true,
      ),
    ],
    cols: [
      ColMap('date', 'session_date'),
      ColMap('start_time', 'start_hhmm'),
      ColMap('end_time', 'end_hhmm'),
      ColMap('duration_seconds', 'duration_seconds', ColType.integer),
      ColMap('primary_muscle', 'primary_muscle'),
      ColMap('secondary_muscle', 'secondary_muscle'),
      ColMap('notes', 'notes'),
    ],
    toRemoteExtra: _sessionToRemote,
    fromRemoteExtra: _sessionFromRemote,
  ),
  const SyncTableSpec(
    local: 'workout_sets',
    remote: 'session_sets',
    parents: [
      ParentRef(
        localCol: 'session_id',
        remoteCol: 'session_id',
        parentTable: 'workout_sessions',
      ),
    ],
    cols: [
      ColMap('exercise_id', 'exercise_id', ColType.integer),
      ColMap('exercise_name', 'exercise_name'),
      ColMap('set_number', 'set_number', ColType.integer),
      ColMap('reps', 'reps', ColType.integer),
      ColMap('weight_kg', 'weight_kg', ColType.real),
      ColMap('is_completed', 'is_completed', ColType.boolean),
      ColMap('completed_at', 'completed_at', ColType.timestamp),
      ColMap('duration_seconds', 'duration_seconds', ColType.integer),
      ColMap('distance_km', 'distance_km', ColType.real),
    ],
    toRemoteExtra: _exerciseRefToRemote,
    fromRemoteExtra: _exerciseRefFromRemote,
  ),
  const SyncTableSpec(
    local: 'routines',
    remote: 'routines',
    cols: [
      ColMap('title', 'title'),
      ColMap('category', 'category'),
      ColMap('start_time', 'start_time'),
      ColMap('end_time', 'end_time'),
      ColMap('repeat_days', 'repeat_days'),
      ColMap('notes', 'notes'),
      ColMap('food_details', 'food_details'),
      ColMap('is_reminder_enabled', 'is_reminder_enabled', ColType.boolean),
      ColMap(
        'reminder_minutes_before',
        'reminder_minutes_before',
        ColType.integer,
      ),
      ColMap('alarm_type', 'alarm_type'),
      ColMap('is_alarm_enabled', 'is_alarm_enabled', ColType.boolean),
      ColMap('sound_name', 'sound_name'),
      ColMap('is_vibration_enabled', 'is_vibration_enabled', ColType.boolean),
      ColMap('snooze_minutes', 'snooze_minutes', ColType.integer),
      ColMap('is_enabled', 'is_enabled', ColType.boolean),
      ColMap('color_hex', 'color_hex'),
    ],
  ),
  SyncTableSpec(
    local: 'routine_completions',
    remote: 'routine_completions',
    uniqueKey: const ['routine_id', 'date'],
    deterministicId: (row, parents) =>
        'rc:${parents['routine_id']}:${row['date']}',
    parents: const [
      ParentRef(
        localCol: 'routine_id',
        remoteCol: 'routine_id',
        parentTable: 'routines',
      ),
    ],
    cols: const [
      ColMap('date', 'completion_date'),
      ColMap('status', 'status'),
      ColMap('notes', 'notes'),
      ColMap('completed_at', 'completed_at', ColType.timestamp),
    ],
  ),
];

SyncTableSpec specFor(String localTable) =>
    syncTables.firstWhere((s) => s.local == localTable);
