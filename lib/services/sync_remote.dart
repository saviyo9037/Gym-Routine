/// Server-side facts about one row, used for last-write-wins decisions.
class RemoteRowMeta {
  const RemoteRowMeta({this.clientUpdatedAt, this.updatedAt, this.deletedAt});
  final DateTime? clientUpdatedAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// The moment the row's content (or deletion) was decided by a client.
  DateTime? get effective => clientUpdatedAt ?? updatedAt;
}

/// Position in a table's change feed: (updated_at, id) of the last row applied.
class RemoteCursor {
  const RemoteCursor(this.updatedAt, this.id);
  final String updatedAt;
  final String id;

  Map<String, String> toJson() => {'u': updatedAt, 'i': id};
  static RemoteCursor? fromJson(Map<String, dynamic>? j) =>
      j == null ? null : RemoteCursor(j['u'] as String, j['i'] as String);
}

class RemotePage {
  const RemotePage(this.rows, {required this.hasMore});
  final List<Map<String, dynamic>> rows;
  final bool hasMore;
}

/// Everything the sync engine needs from the cloud. The Supabase
/// implementation lives in `supabase_sync_remote.dart`; tests use a fake.
abstract class SyncRemote {
  Future<Map<String, RemoteRowMeta>> fetchMeta(String table, List<String> ids);

  /// Insert-or-update by primary key (idempotent).
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  Future<void> softDelete(String table, String id, DateTime at);

  /// Rows changed after [after], ordered by (updated_at, id), at most [limit].
  Future<RemotePage> pull(
    String table, {
    RemoteCursor? after,
    required int limit,
  });

  Future<void> markSynced(DateTime at);

  /// The server's clock, used to measure how far this phone's clock is off.
  /// Return null when unknown (sync then trusts the device clock).
  Future<DateTime?> serverTime() async => null;

  /// Whether [mergeFavourites] is implemented.
  bool get supportsFavourites => false;

  /// Merges catalogue favourites `{exerciseId: {f: bool, t: iso}}` per item
  /// (newest `t` wins on the server) and returns the merged map.
  Future<Map<String, dynamic>> mergeFavourites(Map<String, dynamic> items) =>
      throw UnsupportedError('favourites sync is not supported');
}
