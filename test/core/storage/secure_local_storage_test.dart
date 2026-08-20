import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vilvia/core/storage/secure_local_storage.dart';

// A configurable fake of the platform channel flutter_secure_storage talks
// to, so tests can simulate an Android Keystore/decryption failure (a
// PlatformException) on specific operations without needing a real device
// or the package's own in-memory test double (which never throws).
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  _FakeSecureStoragePlatform({
    this.throwOnWrite = false,
    this.throwOnRead = false,
    this.throwOnContainsKey = false,
    this.corruptReadBack = false,
  });

  final bool throwOnWrite;
  final bool throwOnRead;
  final bool throwOnContainsKey;
  // Writes succeed and are stored normally, but read() always returns a
  // fixed, different value -- simulates a write that "succeeds" yet can't
  // be verified by reading it back, without needing a real mismatch at
  // the storage layer.
  final bool corruptReadBack;
  final Map<String, String> data = {};

  PlatformException get _simulatedFailure =>
      PlatformException(code: 'simulated_failure', message: 'simulated');

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    if (throwOnContainsKey) throw _simulatedFailure;
    return data.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => data.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      data.clear();

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (throwOnRead) throw _simulatedFailure;
    if (corruptReadBack) return 'not-what-was-written';
    return data[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => data;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (throwOnWrite) throw _simulatedFailure;
    data[key] = value;
  }
}

const _legacyKey = 'sb-test-project-auth-token';

Future<void> _seedLegacySession(String sessionString) async {
  SharedPreferences.setMockInitialValues({});
  final legacy = SharedPreferencesLocalStorage(persistSessionKey: _legacyKey);
  await legacy.initialize();
  await legacy.persistSession(sessionString);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform();
    SharedPreferences.setMockInitialValues({});
  });

  group('persist/read/hasAccessToken', () {
    test('persistSession then accessToken round-trips the exact string', () async {
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);

      await storage.persistSession('{"access_token":"abc","refresh_token":"def"}');

      expect(
        await storage.accessToken(),
        '{"access_token":"abc","refresh_token":"def"}',
      );
    });

    test('hasAccessToken is false before anything is persisted', () async {
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);
      expect(await storage.hasAccessToken(), isFalse);
    });

    test('hasAccessToken is true after persisting a session', () async {
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);
      await storage.persistSession('some-session-string');
      expect(await storage.hasAccessToken(), isTrue);
    });
  });

  group('removePersistedSession (logout)', () {
    test('removes the session so hasAccessToken/accessToken reflect logout', () async {
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);
      await storage.persistSession('some-session-string');
      expect(await storage.hasAccessToken(), isTrue);

      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });
  });

  group('legacy migration', () {
    test('migrates a legacy session into secure storage and deletes the legacy entry', () async {
      await _seedLegacySession('{"access_token":"legacy-token"}');

      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);
      await storage.initialize();

      expect(await storage.accessToken(), '{"access_token":"legacy-token"}');

      // The legacy plaintext entry must be gone -- confirmed by asking
      // Supabase's own SharedPreferencesLocalStorage, not by inspecting
      // shared_preferences internals directly.
      final legacy = SharedPreferencesLocalStorage(
        persistSessionKey: _legacyKey,
      );
      await legacy.initialize();
      expect(await legacy.hasAccessToken(), isFalse);
    });

    test('leaves the legacy value in place if the secure write fails', () async {
      await _seedLegacySession('{"access_token":"legacy-token"}');
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(
        throwOnWrite: true,
      );

      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);
      await storage.initialize();

      // Nothing made it into secure storage...
      expect(await storage.hasAccessToken(), isFalse);

      // ...and the legacy plaintext value was never deleted.
      final legacy = SharedPreferencesLocalStorage(
        persistSessionKey: _legacyKey,
      );
      await legacy.initialize();
      expect(await legacy.accessToken(), '{"access_token":"legacy-token"}');
    });

    test('leaves the legacy value in place if the read-back does not match', () async {
      await _seedLegacySession('{"access_token":"legacy-token"}');
      // The write "succeeds" (no exception), but reading it back always
      // returns something else -- migration must treat this the same as
      // a failed write and not delete the legacy value.
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(
        corruptReadBack: true,
      );
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);

      await storage.initialize();

      final legacy = SharedPreferencesLocalStorage(
        persistSessionKey: _legacyKey,
      );
      await legacy.initialize();
      expect(await legacy.accessToken(), '{"access_token":"legacy-token"}');
    });

    test('no legacy value is a no-op and does not touch secure storage', () async {
      // No _seedLegacySession call -- nothing under the legacy key.
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);

      await storage.initialize();

      expect(await storage.hasAccessToken(), isFalse);
    });
  });

  group('fail-safe reads', () {
    test('accessToken() returns null on a decryption/platform failure, not a crash', () async {
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(
        throwOnRead: true,
      );
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);

      expect(await storage.accessToken(), isNull);
    });

    test('hasAccessToken() returns false on a decryption/platform failure, not a crash', () async {
      FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform(
        throwOnContainsKey: true,
      );
      final storage = SecureLocalStorage(legacyPersistSessionKey: _legacyKey);

      expect(await storage.hasAccessToken(), isFalse);
    });
  });
}
