import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:turna/domain/repositories/i_credential_store.dart';

/// Uses platform keychain / keystore implementations where available.
///
/// Web deliberately stays session-only: browser storage cannot offer the same
/// at-rest guarantee as a device keychain. A missing OHos or desktop plugin
/// also degrades to memory instead of silently returning the key to prefs.
class SecureCredentialStore implements ICredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Map<String, String> _ephemeral = <String, String>{};
  bool _nativeAvailable = !kIsWeb;

  static const String namespace = 'turna.ai.';

  @override
  bool get isPersistent => !kIsWeb && _nativeAvailable;

  @override
  Future<void> write(String id, String value) async {
    if (kIsWeb || !_nativeAvailable) {
      _ephemeral[id] = value;
      return;
    }
    try {
      await _storage.write(key: '$namespace$id', value: value);
    } on MissingPluginException {
      _nativeAvailable = false;
      _ephemeral[id] = value;
    } on PlatformException {
      _nativeAvailable = false;
      _ephemeral[id] = value;
    }
  }

  @override
  Future<String?> read(String id) async {
    if (kIsWeb || !_nativeAvailable) return _ephemeral[id];
    try {
      return await _storage.read(key: '$namespace$id');
    } on MissingPluginException {
      _nativeAvailable = false;
      return _ephemeral[id];
    } on PlatformException {
      _nativeAvailable = false;
      return _ephemeral[id];
    }
  }

  @override
  Future<void> delete(String id) async {
    _ephemeral.remove(id);
    if (kIsWeb || !_nativeAvailable) return;
    try {
      await _storage.delete(key: '$namespace$id');
    } on MissingPluginException {
      _nativeAvailable = false;
    } on PlatformException {
      _nativeAvailable = false;
    }
  }

  @override
  Future<void> deleteAll() async {
    _ephemeral.clear();
    if (kIsWeb || !_nativeAvailable) return;
    try {
      final all = await _storage.readAll();
      for (final key in all.keys.where((key) => key.startsWith(namespace))) {
        await _storage.delete(key: key);
      }
    } on MissingPluginException {
      _nativeAvailable = false;
    } on PlatformException {
      _nativeAvailable = false;
    }
  }
}
