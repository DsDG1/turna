// Unit tests: AI credential security migration (Plan 2 §6.3 / S2-M03+M04)
// — the API key moves from the plaintext prefs blob into a secure store in a
// recoverable two-phase process, and never re-enters the blob afterwards.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

class _FakeSecureStore implements ICredentialStore {
  _FakeSecureStore({this.failWrites = false, this.failReads = false});

  final bool failWrites;
  final bool failReads;

  final Map<String, String> saved = {};
  final List<String> deleted = [];

  @override
  bool get isPersistent => true;

  @override
  Future<void> write(String id, String value) async {
    if (failWrites) throw StateError('secure write rejected');
    saved[id] = value;
  }

  @override
  Future<String?> read(String id) async {
    if (failReads) throw StateError('secure read rejected');
    return saved[id];
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    saved.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    saved.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    // The holder resolves AppPrefs through getIt in production.
    getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(sp));
  });

  tearDown(() => getIt.reset());

  Future<String> rawStoredConfig() => Future.value(
        sp
            .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
            .getValue(),
      );

  AiEngineConfigHolder bootstrap({required ICredentialStore store}) {
    final holder = AiEngineConfigHolder(store);
    return holder;
  }

  test('migrates a legacy plaintext key to the secure store and sanitizes '
      'the prefs blob', () async {
    final legacy = const AiEngineConfig(
      apiKey: 'sk-secret-123456',
      modelChat: 'deepseek-v4-flash',
    );
    await sp.setString(
      LocalStateKeys.aiEngineConfig,
      jsonEncode(legacy.toJson(includeApiKey: true)),
    );

    final store = _FakeSecureStore();
    final holder = bootstrap(store: store);
    await holder.loadPersisted();

    expect(holder.migrationStatus, AiCredentialMigrationStatus.done);
    expect(store.saved[AiEngineConfigHolder.apiKeyId], 'sk-secret-123456');
    // The engine still sees the key in memory.
    expect(holder.config.apiKey, 'sk-secret-123456');
    expect(holder.keyStorageKind, AiKeyStorageKind.secure);

    // The plaintext key is gone from prefs.
    final raw = await rawStoredConfig();
    expect(raw, isNotEmpty);
    expect(raw.contains('sk-secret-123456'), isFalse);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded.containsKey('apiKey'), isFalse);
    // Non-secret fields survive.
    expect(decoded['modelChat'], 'deepseek-v4-flash');
  });

  test('failed secure write keeps the plaintext key and reports failure',
      () async {
    final legacy = const AiEngineConfig(apiKey: 'sk-keep-me');
    await sp.setString(
      LocalStateKeys.aiEngineConfig,
      jsonEncode(legacy.toJson(includeApiKey: true)),
    );

    final holder = bootstrap(store: _FakeSecureStore(failWrites: true));
    await holder.loadPersisted();

    expect(holder.migrationStatus, AiCredentialMigrationStatus.failed);
    expect(holder.migrationFailedStage, 'migrate');
    // The user's credential is never lost on a failed migration.
    expect(holder.config.apiKey, 'sk-keep-me');
    final raw = await rawStoredConfig();
    expect(raw.contains('sk-keep-me'), isTrue,
        reason: 'plaintext must be kept when migration fails');
  });

  test('modern blob without key loads the secret from the secure store',
      () async {
    final store = _FakeSecureStore();
    await store.write(AiEngineConfigHolder.apiKeyId, 'sk-from-secure');
    await sp.setString(
      LocalStateKeys.aiEngineConfig,
      jsonEncode(
        const AiEngineConfig(apiKey: '').copyWith(modelChat: 'm1').toJson(),
      ),
    );

    final holder = bootstrap(store: store);
    await holder.loadPersisted();

    expect(holder.migrationStatus, AiCredentialMigrationStatus.done);
    expect(holder.config.apiKey, 'sk-from-secure');
    expect(holder.config.modelChat, 'm1');
  });

  test('updateConfig never writes the API key into the prefs blob', () async {
    final store = _FakeSecureStore();
    final holder = bootstrap(store: store);
    await holder.updateConfig(
      const AiEngineConfig(apiKey: 'sk-brand-new').copyWith(
        modelChat: 'fresh-model',
      ),
    );

    expect(store.saved[AiEngineConfigHolder.apiKeyId], 'sk-brand-new');
    final raw = await rawStoredConfig();
    expect(raw.contains('sk-brand-new'), isFalse);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['modelChat'], 'fresh-model');
    expect(decoded.containsKey('apiKey'), isFalse);
  });

  test('clearApiKey removes the secret but keeps provider/model preferences',
      () async {
    final store = _FakeSecureStore();
    final holder = bootstrap(store: store);
    await holder.updateConfig(
      const AiEngineConfig(apiKey: 'sk-soon-gone').copyWith(
        modelChat: 'keep-me',
      ),
    );

    await holder.clearApiKey();

    expect(holder.config.apiKey, '');
    expect(holder.config.modelChat, 'keep-me');
    expect(store.saved.containsKey(AiEngineConfigHolder.apiKeyId), isFalse);
    expect(store.deleted, contains(AiEngineConfigHolder.apiKeyId));
  });

  test('session-only fallback store reports non-persistent key storage',
      () async {
    final legacy = const AiEngineConfig(apiKey: 'sk-session');
    await sp.setString(
      LocalStateKeys.aiEngineConfig,
      jsonEncode(legacy.toJson(includeApiKey: true)),
    );

    final holder = bootstrap(store: _EphemeralStore());
    await holder.loadPersisted();

    expect(holder.keyStorageKind, AiKeyStorageKind.sessionOnly);
    expect(holder.keyPersistedAcrossRestarts, isFalse);
    // Plaintext is still removed — never silently kept as a fallback.
    final raw = await rawStoredConfig();
    expect(raw.contains('sk-session'), isFalse);
  });

  test('toJson default excludes apiKey; includeApiKey only for legacy reads',
      () {
    const config = AiEngineConfig(apiKey: 'sk-never-in-blob');
    expect(config.toJson().containsKey('apiKey'), isFalse);
    expect(config.toJson(includeApiKey: true)['apiKey'], 'sk-never-in-blob');
  });
}

class _EphemeralStore implements ICredentialStore {
  final Map<String, String> _map = {};

  @override
  bool get isPersistent => false;

  @override
  Future<void> write(String id, String value) async => _map[id] = value;

  @override
  Future<String?> read(String id) async => _map[id];

  @override
  Future<void> delete(String id) async => _map.remove(id);

  @override
  Future<void> deleteAll() async => _map.clear();
}
