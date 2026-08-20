import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A [LocalStorage] implementation backed by OS-level secure storage
/// (Android Keystore-backed encryption today; iOS Keychain automatically
/// once an iOS target exists -- flutter_secure_storage handles that
/// split internally via [FlutterSecureStorage]'s default options, so no
/// platform-conditional code is needed here).
///
/// The persisted session string Supabase hands to [persistSession] is
/// always treated as opaque: this class never parses, reconstructs, or
/// logs it -- only stores, retrieves, and moves it between backends
/// verbatim.
///
/// On first use after upgrading from the SDK's previous default
/// (`SharedPreferencesLocalStorage`, plaintext), migrates any existing
/// session across exactly once -- see [_migrateLegacySessionIfNeeded].
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({
    required String legacyPersistSessionKey,
    FlutterSecureStorage? secureStorage,
  }) : // An initializing formal here would make the parameter's public
       // name the private `_...` field name itself, which callers
       // outside this library couldn't use -- so this stays explicit.
       // ignore: prefer_initializing_formals
       _legacyPersistSessionKey = legacyPersistSessionKey,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// The key this session is stored under in secure storage. Deliberately
  /// not the same string as the legacy SharedPreferences key -- the two
  /// storage backends are unrelated after migration completes.
  static const _secureStorageKey = 'supabase_session';

  final String _legacyPersistSessionKey;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<void> initialize() => _migrateLegacySessionIfNeeded();

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _secureStorage.containsKey(key: _secureStorageKey);
    } on PlatformException {
      // A decryption/Keystore failure (e.g. after an Android
      // backup/restore onto a different device -- the wrapping key never
      // transfers) is treated the same as "nothing persisted", never a
      // crash.
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _secureStorage.read(key: _secureStorageKey);
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() =>
      _secureStorage.delete(key: _secureStorageKey);

  @override
  Future<void> persistSession(String persistSessionString) => _secureStorage
      .write(key: _secureStorageKey, value: persistSessionString);

  /// One-time migration from the SDK's previous default storage
  /// (`SharedPreferencesLocalStorage`, plaintext) to this secure storage.
  ///
  /// Reuses Supabase's own [SharedPreferencesLocalStorage] to read the
  /// legacy value rather than reimplementing SharedPreferences access --
  /// the session string is never parsed or reconstructed, only copied
  /// verbatim. The legacy plaintext entry is deleted only after the
  /// secure write is confirmed by reading it back and comparing it to
  /// what was written; if the write throws, or the read-back doesn't
  /// match, the legacy value is left in place rather than risking losing
  /// the user's session.
  Future<void> _migrateLegacySessionIfNeeded() async {
    final legacy = SharedPreferencesLocalStorage(
      persistSessionKey: _legacyPersistSessionKey,
    );
    await legacy.initialize();

    if (!await legacy.hasAccessToken()) return;

    final legacySession = await legacy.accessToken();
    if (legacySession == null) return;

    try {
      await _secureStorage.write(
        key: _secureStorageKey,
        value: legacySession,
      );
      final confirmed = await _secureStorage.read(key: _secureStorageKey);
      if (confirmed != legacySession) return;
    } on PlatformException {
      return;
    }

    await legacy.removePersistedSession();
  }
}
