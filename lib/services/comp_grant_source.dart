import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_config.dart';

/// "Comp" access granted by RepTrack staff (admin panel, migration 0009).
/// Server side it is the signed-in user's own `entitlements` row with
/// entitlement_id = 'premium_comp'; row level security lets a user read only
/// their own rows.
class CompGrant {
  const CompGrant({required this.isActive, this.expiresAt});
  final bool isActive;
  final DateTime? expiresAt;
}

abstract class CompGrantSource {
  /// The signed-in account (null when signed out). A cached grant belongs to
  /// ONE account and is ignored for any other.
  String? get userId;

  /// null = the account has no comp row. Throws when the server is
  /// unreachable (the caller keeps its cache).
  Future<CompGrant?> fetch();
}

class SupabaseCompGrantSource implements CompGrantSource {
  bool get _ready => CloudConfig.supabaseConfigured;

  @override
  String? get userId {
    if (!_ready) return null;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<CompGrant?> fetch() async {
    final uid = userId;
    if (uid == null) return null;
    final row = await Supabase.instance.client
        .from('entitlements')
        .select('is_active, expires_at')
        .eq('user_id', uid)
        .eq('entitlement_id', 'premium_comp')
        .maybeSingle();
    if (row == null) return null;
    final exp = row['expires_at'];
    return CompGrant(
      isActive: row['is_active'] == true,
      expiresAt: exp == null ? null : DateTime.tryParse('$exp'),
    );
  }
}
