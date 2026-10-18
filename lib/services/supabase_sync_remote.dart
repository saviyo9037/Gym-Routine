import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_remote.dart';

/// Supabase/PostgREST implementation of [SyncRemote].
/// UNVERIFIED against a real project (no connection was available).
class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  @override
  Future<Map<String, RemoteRowMeta>> fetchMeta(
    String table,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from(table)
        .select('id, client_updated_at, updated_at, deleted_at')
        .inFilter('id', ids);
    return {
      for (final r in rows)
        r['id'] as String: RemoteRowMeta(
          clientUpdatedAt: DateTime.tryParse('${r['client_updated_at']}'),
          updatedAt: DateTime.tryParse('${r['updated_at']}'),
          deletedAt: r['deleted_at'] == null
              ? null
              : DateTime.tryParse('${r['deleted_at']}'),
        ),
    };
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows, onConflict: 'id');
  }

  @override
  Future<void> softDelete(String table, String id, DateTime at) async {
    final ts = at.toUtc().toIso8601String();
    await _client
        .from(table)
        .update({'deleted_at': ts, 'client_updated_at': ts})
        .eq('id', id);
  }

  @override
  Future<RemotePage> pull(
    String table, {
    RemoteCursor? after,
    required int limit,
  }) async {
    var q = _client.from(table).select();
    if (after != null) {
      final u = after.updatedAt;
      q = q.or('updated_at.gt.$u,and(updated_at.eq.$u,id.gt.${after.id})');
    }
    final rows = await q
        .order('updated_at', ascending: true)
        .order('id', ascending: true)
        .limit(limit + 1);
    final list = List<Map<String, dynamic>>.from(rows);
    final hasMore = list.length > limit;
    return RemotePage(
      hasMore ? list.sublist(0, limit) : list,
      hasMore: hasMore,
    );
  }

  @override
  Future<DateTime?> serverTime() async {
    try {
      final res = await _client.rpc('server_time');
      return DateTime.tryParse('$res');
    } catch (_) {
      return null; // older backend (before 0007): trust the device clock
    }
  }

  @override
  bool get supportsFavourites => true;

  @override
  Future<Map<String, dynamic>> mergeFavourites(
    Map<String, dynamic> items,
  ) async {
    final res = await _client.rpc(
      'merge_favourites',
      params: {'p_items': items},
    );
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  @override
  Future<void> markSynced(DateTime at) async {
    await _client
        .from('profiles')
        .update({
          'last_sync_at': at.toUtc().toIso8601String(),
          'last_seen_at': at.toUtc().toIso8601String(),
        })
        .eq('id', _uid);
  }
}
