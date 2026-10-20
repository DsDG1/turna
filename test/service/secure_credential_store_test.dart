// Unit tests: credential-store persistence verification.
//
// Regression guard for the "API key disappears after restart" report: the
// platform plug-in was absent on HarmonyOS, every call threw, and the key only
// ever lived in the in-memory fallback — while the settings page still claimed
// the key was stored securely. A store must prove persistence (round-trip a
// value) before it is reported as durable.

// Package imports:
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/secure_credential_store.dart';

/// A plug-in that accepts writes and silently drops them — the exact failure
/// mode of a registered-but-dead native side (missing platform implementation,
/// wrong method channel).
class _DroppingPlugin extends FlutterSecureStorage {
  const _DroppingPlugin();

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      null;

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('probePersistence reports true when the platform store round-trips',
      () async {
    final store = SecureCredentialStore();
    expect(await store.probePersistence(), isTrue);
    expect(store.isPersistent, isTrue);
    // The probe sentinel never leaks into the credential namespace.
    expect(await store.read('turna.credentials.probe'), isNull);
  });

  test('a store that accepts and drops writes is reported as session-only',
      () async {
    final store = SecureCredentialStore(plugin: const _DroppingPlugin());

    expect(await store.probePersistence(), isFalse);
    expect(store.isPersistent, isFalse);

    await store.write('aiEngine.apiKey', 'sk-dropped');
    // The value is still usable for this session, but never claimed durable.
    expect(await store.read('aiEngine.apiKey'), 'sk-dropped');
    expect(store.isPersistent, isFalse);
  });

  test('the first write of a session is verified by reading it back', () async {
    final store = SecureCredentialStore(plugin: const _DroppingPlugin());
    await store.write('aiEngine.apiKey', 'sk-dropped');
    expect(store.isPersistent, isFalse,
        reason: 'a silently dropped write must latch the session-only verdict');
  });

  test('SecureCredentialStore exposes the probe capability', () {
    expect(SecureCredentialStore(), isA<IPersistentCredentialProbe>());
  });
}
