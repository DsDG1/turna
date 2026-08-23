// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Project imports:
import 'package:turna/domain/repositories/i_credential_store.dart';

/// Platform-backed credential storage (Android Keystore via EncryptedShared-
/// Preferences, Keychain on iOS/macOS, libsecret on Linux, DPAPI on Windows).
///
/// Degrades to an in-memory session store when the platform plugin is missing
/// or fails (tests, exotic platforms): [isPersistent] then reports `false` so
/// callers can surface "re-enter after restart" instead of silently falling
/// back to plaintext prefs (Plan 2 §6.3).
class SecureCredentialStore implements ICredentialStore {
  SecureCredentialStore({FlutterSecureStorage? plugin})
      : _plugin = plugin ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _plugin;

  /// Null until the first operation resolves; `false` once the plugin has
  /// failed, which latches the session-only fallback for this process.
  bool? _pluginHealthy;

  final Map<String, String> _ephemeral = <String, String>{};

  @override
  bool get isPersistent => _pluginHealthy != false;

  @override
  Future<void> write(String id, String value) async {
    if (_pluginHealthy == false) {
      _ephemeral[id] = value;
      return;
    }
    try {
      await _plugin.write(key: id, value: value);
      _pluginHealthy = true;
    } catch (error) {
      _degrade(error);
      _ephemeral[id] = value;
    }
  }

  @override
  Future<String?> read(String id) async {
    if (_pluginHealthy == false) return _ephemeral[id];
    try {
      final value = await _plugin.read(key: id);
      _pluginHealthy = true;
      return value;
    } catch (error) {
      _degrade(error);
      return _ephemeral[id];
    }
  }

  @override
  Future<void> delete(String id) async {
    _ephemeral.remove(id);
    if (_pluginHealthy == false) return;
    try {
      await _plugin.delete(key: id);
      _pluginHealthy = true;
    } catch (error) {
      _degrade(error);
    }
  }

  @override
  Future<void> deleteAll() async {
    _ephemeral.clear();
    if (_pluginHealthy == false) return;
    try {
      await _plugin.deleteAll();
      _pluginHealthy = true;
    } catch (error) {
      _degrade(error);
    }
  }

  void _degrade(Object error) {
    if (kDebugMode) {
      debugPrint('SecureCredentialStore: plugin unavailable ($error), '
          'degrading to session-only storage.');
    }
    _pluginHealthy = false;
  }
}
