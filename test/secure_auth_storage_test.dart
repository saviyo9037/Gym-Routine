// MOCK-ONLY: MemoryKv stands in for the Android Keystore; this proves the adapter
// logic, not the Keystore itself (UNVERIFIED on a device).
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/services/secure_auth_storage.dart';

class MemoryKv implements SecureKeyValue {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  group('MOCK-ONLY: secure session storage', () {
    test('persists, reads and removes the session', () async {
      final kv = MemoryKv();
      final s = SecureLocalStorage(kv);
      expect(await s.hasAccessToken(), isFalse);
      await s.persistSession('{"access_token":"abc"}');
      expect(await s.hasAccessToken(), isTrue);
      expect(await s.accessToken(), '{"access_token":"abc"}');
      await s.removePersistedSession();
      expect(await s.hasAccessToken(), isFalse);
      expect(await s.accessToken(), isNull);
    });

    test('the session is stored under the secure key only', () async {
      final kv = MemoryKv();
      await SecureLocalStorage(kv).persistSession('x');
      expect(kv.data.keys, [SecureLocalStorage.defaultSessionKey]);
    });

    test('pkce verifier items are namespaced and removable', () async {
      final kv = MemoryKv();
      final g = SecureGotrueAsyncStorage(kv);
      await g.setItem(key: 'code-verifier', value: 'v');
      expect(await g.getItem(key: 'code-verifier'), 'v');
      expect(kv.data.keys.single, startsWith('reptrack.gotrue.'));
      await g.removeItem(key: 'code-verifier');
      expect(await g.getItem(key: 'code-verifier'), isNull);
    });
  });
}
