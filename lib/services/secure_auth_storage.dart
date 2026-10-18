import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal async key/value store for secrets. The production implementation
/// uses the Android Keystore (flutter_secure_storage); tests use a memory fake.
abstract class SecureKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValue implements SecureKeyValue {
  const FlutterSecureKeyValue([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // A keystore that cannot be read behaves like "not signed in".
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

/// Supabase session (access + refresh token) in the Android Keystore instead
/// of plain SharedPreferences.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage(this._kv, {this.sessionKey = defaultSessionKey});

  static const defaultSessionKey = 'reptrack.supabase.session';
  final SecureKeyValue _kv;
  final String sessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _kv.read(sessionKey)) != null;

  @override
  Future<String?> accessToken() => _kv.read(sessionKey);

  @override
  Future<void> removePersistedSession() => _kv.delete(sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _kv.write(sessionKey, persistSessionString);
}

/// PKCE code verifier (and other gotrue async items) in the Keystore too.
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  SecureGotrueAsyncStorage(this._kv, {this.prefix = 'reptrack.gotrue.'});
  final SecureKeyValue _kv;
  final String prefix;

  @override
  Future<String?> getItem({required String key}) => _kv.read('$prefix$key');

  @override
  Future<void> removeItem({required String key}) => _kv.delete('$prefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _kv.write('$prefix$key', value);
}
