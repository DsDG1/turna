import 'package:flutter/foundation.dart';

import 'package:turna/domain/repositories/i_credential_store.dart';

/// Uses in-memory credential storage fallback.
class SecureCredentialStore implements ICredentialStore {
  SecureCredentialStore();

  final Map<String, String> _ephemeral = <String, String>{};

  @override
  bool get isPersistent => false;

  @override
  Future<void> write(String id, String value) async {
    _ephemeral[id] = value;
  }

  @override
  Future<String?> read(String id) async {
    return _ephemeral[id];
  }

  @override
  Future<void> delete(String id) async {
    _ephemeral.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _ephemeral.clear();
  }
}
