// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';

/// Platform-backed credential storage (Android Keystore via EncryptedShared-
/// Preferences, Keychain on iOS/macOS, libsecret on Linux, DPAPI on Windows,
/// RSA+AES encrypted preferences on HarmonyOS).
///
/// Degrades to an in-memory session store when the platform plugin is missing
/// or fails (tests, exotic platforms): [isPersistent] then reports `false` so
/// callers can surface "re-enter after restart" instead of silently falling
/// back to plaintext prefs (Plan 2 §6.3).
///
/// [isPersistent] is only trustworthy after the store has been exercised, which
/// is why [probePersistence] exists: the first write of a session is verified by
/// reading the value back, and [probePersistence] does the same with a sentinel
/// so a fresh process can report the truth before any credential is written.
class SecureCredentialStore
    implements ICredentialStore, IPersistentCredentialProbe {
  SecureCredentialStore({FlutterSecureStorage? plugin})
      : _plugin = plugin ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// Sentinel key used by [probePersistence]; deleted again immediately.
  static const String _probeId = 'turna.credentials.probe';

  final FlutterSecureStorage _plugin;

  /// Null until the first operation resolves; `false` once the plugin has
  /// failed, which latches the session-only fallback for this process.
  bool? _pluginHealthy;

  final Map<String, String> _ephemeral = <String, String>{};

  @override
  bool get isPersistent => _pluginHealthy != false;

  @override
  Future<bool> probePersistence() async {
    if (_pluginHealthy == false) return false;
    try {
      await _plugin.write(key: _probeId, value: 'ok');
      final echo = await _plugin.read(key: _probeId);
      await _plugin.delete(key: _probeId);
      _pluginHealthy = echo == 'ok';
      if (_pluginHealthy == false) {
        _degrade(StateError('probe readback mismatch'));
      }
    } catch (error) {
      _degrade(error);
    }
    return _pluginHealthy == true;
  }

  @override
  Future<void> write(String id, String value) async {
    if (_pluginHealthy == false) {
      _ephemeral[id] = value;
      return;
    }
    try {
      await _plugin.write(key: id, value: value);
      // The first write of a session is verified by reading it back: a plug-in
      // that accepts the call but drops the value (missing native side, wrong
      // channel) must not be reported as durable storage.
      if (_pluginHealthy != true) {
        final echo = await _plugin.read(key: id);
        if (echo != value) {
          throw StateError('secure-store readback mismatch');
        }
      }
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
      logger.w('SecureCredentialStore: plugin unavailable ($error), '
          'degrading to session-only storage.');
    }
    _pluginHealthy = false;
  }
}
