import '../data/db_helper.dart';
import 'premium_service.dart';
import 'sync_engine.dart';

/// Detects "a different account signed in on a phone that already belongs to
/// someone else" so the app can ask instead of silently mixing data.
///
/// The phone's data is never deleted or merged here: the user either links
/// this phone's data to the new account (explicit upload) or signs out.
class AccountSwitch {
  AccountSwitch({SettingsStore? store, DatabaseHelper? helper})
    : _store = store ?? DbSettingsStore(),
      _helper = helper ?? DatabaseHelper.instance;

  static const lastUserKey = 'auth_last_user_id';

  final SettingsStore _store;
  final DatabaseHelper _helper;

  /// The account this phone's data was last tied to: the sync binding when
  /// there is one, otherwise the last account that signed in on this phone.
  Future<String?> previousUserId() async {
    try {
      final db = await _helper.database;
      final bound = await SyncEngine.getMeta(db, 'account_user_id');
      if (bound != null && bound.isNotEmpty) return bound;
    } catch (_) {
      // sync tables missing: fall back to the settings marker
    }
    try {
      final last = await _store.read(lastUserKey);
      return (last == null || last.isEmpty) ? null : last;
    } catch (_) {
      return null;
    }
  }

  /// True when [currentUserId] differs from the account the phone belongs to.
  Future<bool> needsDecision(String currentUserId) async {
    final prev = await previousUserId();
    return prev != null && prev != currentUserId;
  }

  /// The account was deleted: the phone no longer belongs to anyone.
  Future<void> forget() async {
    try {
      await _store.write(lastUserKey, '');
    } catch (_) {
      // best effort
    }
  }

  /// Remember who this phone belongs to now (first sign-in, or after the user
  /// confirmed linking this phone to the new account).
  Future<void> remember(String userId) async {
    try {
      await _store.write(lastUserKey, userId);
    } catch (_) {
      // best effort
    }
  }
}
