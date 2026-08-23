// Unit tests for the split endpoint/credential WebDAV config model and the
// idempotent plaintext migration (Plan §9).

// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';

/// In-memory credential store with injectable health, used to exercise the
/// migration's success / verify-failure / unavailable paths.
class FakeCredentialStore implements ICredentialStore {
  FakeCredentialStore({this.persistent = true, this.failReads = false});

  final bool persistent;
  final bool failReads;
  final Map<String, String> storage = <String, String>{};

  @override
  bool get isPersistent => persistent;

  @override
  Future<void> write(String id, String value) async {
    if (!persistent) throw StateError('plugin unavailable');
    storage[id] = value;
  }

  @override
  Future<String?> read(String id) async {
    if (!persistent || failReads) throw StateError('plugin unavailable');
    return storage[id];
  }

  @override
  Future<void> delete(String id) async => storage.remove(id);

  @override
  Future<void> deleteAll() async => storage.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;

  // Legacy JSON as stored by pre-migration releases (plaintext password
  // inside the prefs value).
  final legacyJson = jsonEncode({
    'serverUrl': 'https://dav.example.com/dav/',
    'username': ' alice ',
    'password': 'plain-secret-42',
    'includeMedia': false,
    'remoteRoot': '/my backups: v2/',
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    // StreamingSharedPreferences caches its instance for the whole process,
    // so setMockInitialValues alone does not reset state between tests —
    // clear the keys under test explicitly.
    await sp.remove(LocalStateKeys.remoteBackupConfig);
    await sp.remove(RemoteBackupConfigStore.migrationMarkerKey);
    prefs = AppPrefs(sp);
  });

  group('RemoteBackupEndpointConfig', () {
    test('defaults are empty', () {
      const config = RemoteBackupEndpointConfig();
      expect(config.hasEndpointInput, isFalse);
      expect(config.includeMedia, isTrue);
      expect(config.remoteRoot, 'TurnaBackup');
    });

    test('normalized trims URL slashes and sanitizes the remote root', () {
      const config = RemoteBackupEndpointConfig(
        serverUrl: ' https://dav.example.com/ ',
        username: ' alice ',
        remoteRoot: '/my backups: v2/',
      );
      final normalized = config.normalized();
      expect(normalized.serverUrl, 'https://dav.example.com');
      expect(normalized.username, 'alice');
      expect(normalized.remoteRoot, 'my_backups_v2');
    });

    test('toJson never contains a password field', () {
      const config = RemoteBackupEndpointConfig(
        serverUrl: 'https://dav.example.com',
        username: 'alice',
      );
      expect(config.toJson().containsKey('password'), isFalse);
    });

    test('fromJson ignores a legacy password field', () {
      final config = RemoteBackupEndpointConfig.fromJson(
        Map<String, dynamic>.from(jsonDecode(legacyJson) as Map),
      );
      expect(config.serverUrl, 'https://dav.example.com/dav/');
      expect(config.username, ' alice ');
      expect(config.includeMedia, isFalse);
    });

    test('endpoint round-trips through prefs without secrets', () async {
      final store = RemoteBackupConfigStore(prefs);
      await store.saveEndpoint(const RemoteBackupEndpointConfig(
        serverUrl: 'https://dav.example.com',
        username: 'alice',
        includeMedia: false,
        remoteRoot: 'TurnaBackup',
      ));
      final raw = prefs.preferences
          .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
          .getValue();
      expect(raw.contains('password'), isFalse);
      final loaded = store.loadEndpoint();
      expect(loaded.serverUrl, 'https://dav.example.com');
      expect(loaded.username, 'alice');
      expect(loaded.includeMedia, isFalse);
    });

    test('corrupt persisted JSON degrades to defaults', () async {
      await prefs.preferences
          .setString(LocalStateKeys.remoteBackupConfig, 'not-json{');
      final store = RemoteBackupConfigStore(prefs);
      expect(store.loadEndpoint().serverUrl, isEmpty);
    });
  });

  group('credential handling', () {
    test('password round-trips through the secure store only', () async {
      final credentials = FakeCredentialStore();
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);
      await store.savePassword('secret');
      expect(credentials.storage[RemoteBackupConfigStore.securePasswordId],
          'secret');
      expect(await store.loadPassword(), 'secret');
      expect(await store.hasStoredPassword(), isTrue);

      // And it never leaked into prefs.
      final keys = sp.getKeys().getValue();
      expect(
        keys.any((key) => key.startsWith('remoteBackup.')),
        isFalse,
      );
    });

    test('savePassword verifies the write and throws on mismatch', () async {
      final credentials = FakeCredentialStore(failReads: true);
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);
      await expectLater(store.savePassword('secret'), throwsA(anything));
    });

    test('empty password clears the stored credential', () async {
      final credentials = FakeCredentialStore();
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);
      await store.savePassword('secret');
      await store.savePassword('');
      expect(await store.loadPassword(), isNull);
    });

    test('loadResolved requires both endpoint and credential', () async {
      final credentials = FakeCredentialStore();
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);
      await store.saveEndpoint(const RemoteBackupEndpointConfig(
        serverUrl: 'https://dav.example.com',
        username: 'alice',
      ));
      expect(await store.loadResolved(), isNull); // no password yet
      await store.savePassword('secret');
      final resolved = await store.loadResolved();
      expect(resolved, isNotNull);
      expect(resolved!.isConfigured, isTrue);
      expect(resolved.password, 'secret');
    });
  });

  group('legacy plaintext migration', () {
    test('migrates plaintext to secure store and scrubs prefs', () async {
      await prefs.preferences
          .setString(LocalStateKeys.remoteBackupConfig, legacyJson);
      final credentials = FakeCredentialStore();
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);

      final status = await store.migrateLegacyPlaintext();
      expect(status, RemoteBackupCredentialMigrationStatus.migrated);

      expect(
        credentials.storage[RemoteBackupConfigStore.securePasswordId],
        'plain-secret-42',
      );
      final raw = prefs.preferences
          .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
          .getValue();
      expect(raw.contains('plain-secret-42'), isFalse);
      expect(raw.contains('password'), isFalse);
      expect(store.loadEndpoint().username, ' alice ');
      expect(
        prefs.preferences
            .getBool(RemoteBackupConfigStore.migrationMarkerKey,
                defaultValue: false)
            .getValue(),
        isTrue,
      );
    });

    test('is idempotent - rerunning does not touch migrated data', () async {
      await prefs.preferences
          .setString(LocalStateKeys.remoteBackupConfig, legacyJson);
      final credentials = FakeCredentialStore();
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);

      await store.migrateLegacyPlaintext();
      final rawAfterFirst = prefs.preferences
          .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
          .getValue();
      final status = await store.migrateLegacyPlaintext();
      final rawAfterSecond = prefs.preferences
          .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
          .getValue();

      expect(status, RemoteBackupCredentialMigrationStatus.notNeeded);
      expect(rawAfterFirst, rawAfterSecond);
      expect(
        credentials.storage[RemoteBackupConfigStore.securePasswordId],
        'plain-secret-42',
      );
    });

    test('keeps plaintext when the secure store is unavailable', () async {
      await prefs.preferences
          .setString(LocalStateKeys.remoteBackupConfig, legacyJson);
      final credentials = FakeCredentialStore(persistent: false);
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);

      final status = await store.migrateLegacyPlaintext();
      expect(
          status, RemoteBackupCredentialMigrationStatus.secureStoreUnavailable);
      final raw = prefs.preferences
          .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
          .getValue();
      expect(raw, legacyJson);
    });

    test('reports verify failure when the read-back mismatches', () async {
      await prefs.preferences
          .setString(LocalStateKeys.remoteBackupConfig, legacyJson);
      final credentials = _WriteOnlyStore();
      final store =
          RemoteBackupConfigStore(prefs, credentialStore: credentials);

      final status = await store.migrateLegacyPlaintext();
      expect(status, RemoteBackupCredentialMigrationStatus.verifyFailed);
      expect(
        prefs.preferences
            .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
            .getValue(),
        legacyJson,
      );
    });

    test('no-op when there is nothing to migrate', () async {
      final store = RemoteBackupConfigStore(prefs,
          credentialStore: FakeCredentialStore());
      expect(await store.migrateLegacyPlaintext(),
          RemoteBackupCredentialMigrationStatus.notNeeded);
    });
  });
}

/// Accepts writes but always reads back a different value, simulating a
/// corrupted secure-store write.
class _WriteOnlyStore extends FakeCredentialStore {
  @override
  Future<String?> read(String id) async => 'corrupted';
}
