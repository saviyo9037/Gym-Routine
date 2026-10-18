import 'package:reptrack/services/sync_remote.dart';

/// In-memory stand-in for the cloud: server-authoritative `updated_at`,
/// soft deletes, (updated_at, id) paging.
class FakeSyncRemote extends SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  DateTime _clock = DateTime.utc(2026, 1, 1);
  int upsertCalls = 0;
  int upsertedRows = 0;

  /// Throw on the n-th pull call (1-based) to simulate a network failure.
  int? failPullOnCall;
  int _pullCalls = 0;
  bool failUpsert = false;

  /// Remote tables whose upserts fail (network/permission error on one table).
  final Set<String> failUpsertTables = {};

  /// Throw after this many rows were upserted in total (simulates the app
  /// being killed or the network dying in the middle of a push).
  int? failAfterUpsertedRows;
  DateTime? syncedAt;

  /// The server's idea of "now"; null = the real clock.
  DateTime Function()? serverClock;
  bool serverTimeAvailable = true;

  /// Merged catalogue favourites {id: {f, t}} (what the SQL RPC stores).
  final Map<String, dynamic> favourites = {};
  bool favouritesSupported = true;

  DateTime _tick() => _clock = _clock.add(const Duration(seconds: 1));

  Map<String, Map<String, dynamic>> t(String table) =>
      tables.putIfAbsent(table, () => {});

  /// Test helper: plant a row as if another device wrote it.
  void plant(
    String table,
    Map<String, dynamic> row, {
    required DateTime clientUpdatedAt,
    DateTime? deletedAt,
  }) {
    final r = Map<String, dynamic>.from(row);
    r['client_updated_at'] = clientUpdatedAt.toUtc().toIso8601String();
    r['deleted_at'] = deletedAt?.toUtc().toIso8601String();
    r['updated_at'] = _tick().toIso8601String();
    t(table)[r['id'] as String] = r;
  }

  @override
  Future<Map<String, RemoteRowMeta>> fetchMeta(
    String table,
    List<String> ids,
  ) async {
    final out = <String, RemoteRowMeta>{};
    for (final id in ids) {
      final r = t(table)[id];
      if (r == null) continue;
      out[id] = RemoteRowMeta(
        clientUpdatedAt: DateTime.tryParse('${r['client_updated_at']}'),
        updatedAt: DateTime.tryParse('${r['updated_at']}'),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.tryParse('${r['deleted_at']}'),
      );
    }
    return out;
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (failUpsert || failUpsertTables.contains(table)) {
      throw Exception('network down');
    }
    upsertCalls++;
    for (final row in rows) {
      if (failAfterUpsertedRows != null &&
          upsertedRows >= failAfterUpsertedRows!) {
        throw Exception('connection lost');
      }
      upsertedRows++;
      final copy = Map<String, dynamic>.from(row);
      copy['updated_at'] = _tick().toIso8601String();
      t(table)[copy['id'] as String] = copy;
    }
  }

  @override
  Future<void> softDelete(String table, String id, DateTime at) async {
    final r = t(table)[id];
    if (r == null) return;
    r['deleted_at'] = at.toUtc().toIso8601String();
    r['client_updated_at'] = at.toUtc().toIso8601String();
    r['updated_at'] = _tick().toIso8601String();
  }

  @override
  Future<RemotePage> pull(
    String table, {
    RemoteCursor? after,
    required int limit,
  }) async {
    _pullCalls++;
    if (failPullOnCall != null && _pullCalls >= failPullOnCall!) {
      throw Exception('network down');
    }
    final all = t(table).values.toList()
      ..sort((a, b) {
        final c = (a['updated_at'] as String).compareTo(
          b['updated_at'] as String,
        );
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    final rest = after == null
        ? all
        : all.where((r) {
            final c = (r['updated_at'] as String).compareTo(after.updatedAt);
            return c > 0 ||
                (c == 0 && (r['id'] as String).compareTo(after.id) > 0);
          }).toList();
    final page = rest
        .take(limit)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    return RemotePage(page, hasMore: rest.length > limit);
  }

  @override
  Future<void> markSynced(DateTime at) async {
    syncedAt = at;
  }

  @override
  Future<DateTime?> serverTime() async => serverTimeAvailable
      ? (serverClock?.call() ?? DateTime.now().toUtc())
      : null;

  @override
  bool get supportsFavourites => favouritesSupported;

  @override
  Future<Map<String, dynamic>> mergeFavourites(
    Map<String, dynamic> items,
  ) async {
    for (final e in items.entries) {
      final cur = favourites[e.key];
      final newT = DateTime.parse('${e.value['t']}');
      if (cur == null || newT.isAfter(DateTime.parse('${cur['t']}'))) {
        favourites[e.key] = {'f': e.value['f'], 't': '${e.value['t']}'};
      }
    }
    return Map<String, dynamic>.from(favourites);
  }
}
