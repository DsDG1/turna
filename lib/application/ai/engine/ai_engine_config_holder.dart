// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/diagnostics/storage_write_telemetry.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/secure_credential_store.dart';

/// Outcome of the plaintext->secure-store credential migration (Plan 2 §6.3).
enum AiCredentialMigrationStatus {
  /// Nothing left to migrate (already migrated, or no key was ever stored).
  notNeeded,

  /// Migration finished: verified in the secure store, plaintext removed.
  done,

  /// The old blob still carries a plaintext key — retried on next startup.
  pending,

  /// A stage failed; the plaintext key is intentionally kept so the user's
  /// credential is never lost. The UI should offer a retry.
  failed,
}

/// Where the in-memory API key is backed by.
enum AiKeyStorageKind {
  /// Platform secure storage (Keystore/Keychain/…): survives restarts.
  secure,

  /// Session-only fallback store: the user must re-enter after restart.
  sessionOnly,

  /// Not determined yet ([loadPersisted] has not completed).
  unknown,
}

/// Owns the single [AiEngineConfig] the engine reads.
///
/// `@lazySingleton` so constructor-injected collaborators (the engine, the
/// providers) resolve the same instance the UI watches via
/// `ChangeNotifierProvider<AiEngineConfigHolder>` in `providers.dart`.
///
/// Persistence is split (Plan 2 §6.3): non-secret fields are serialized to
/// SharedPreferences under [LocalStateKeys.aiEngineConfig] **without** the API
/// key; the key itself lives in the platform secure store
/// ([ICredentialStore], backed by Android Keystore & friends). When the secure
/// store is unavailable (tests, exotic platforms) the key is kept in a
/// session-only in-memory store — never written back to plaintext prefs — and
/// [keyStorageKind] reports [AiKeyStorageKind.sessionOnly] so the UI can say
/// "re-enter after restart".
@lazySingleton
class AiEngineConfigHolder extends ChangeNotifier {
  AiEngineConfigHolder([ICredentialStore? credentialStore])
      : _credentials = credentialStore ?? _resolveDefaultStore(),
        _config = const AiEngineConfig(apiKey: '');

  /// Storage id for the API key inside [ICredentialStore].
  static const String apiKeyId = 'aiEngine.apiKey';

  final ICredentialStore _credentials;

  /// Bumped whenever the credential migration advances so UI can react.
  AiCredentialMigrationStatus _migrationStatus =
      AiCredentialMigrationStatus.notNeeded;

  AiKeyStorageKind _keyStorageKind = AiKeyStorageKind.unknown;

  /// Last failed migration stage name, for diagnostics only. Never contains
  /// the key, headers or config JSON — stage identifiers only.
  String? migrationFailedStage;

  AiEngineConfig _config;

  /// Last key value known to be durably written, so no-op updates don't
  /// rewrite the Keystore entry.
  String? _lastPersistedKey;

  /// Current engine config. The engine reads this at call time; the AI
  /// connection page commits drafts via [updateConfig].
  AiEngineConfig get config => _config;

  AiCredentialMigrationStatus get migrationStatus => _migrationStatus;

  AiKeyStorageKind get keyStorageKind => _keyStorageKind;

  /// True when the current API key survives an app restart.
  bool get keyPersistedAcrossRestarts =>
      _keyStorageKind == AiKeyStorageKind.secure;

  /// Replace the config, persist it (secret and non-secret split), and notify
  /// listeners. Callers should build the next config with
  /// [AiEngineConfig.copyWith] (or construct fresh) and pass it in.
  Future<void> updateConfig(AiEngineConfig next) async {
    _config = next;
    notifyListeners();
    await _persist();
  }

  /// Remove only the API key (provider/model/base-url prefs stay). Returns
  /// false when the durable deletion failed.
  Future<bool> clearApiKey() async {
    final next = _config.copyWith(apiKey: '');
    final ok = await _deleteStoredKey();
    _config = next;
    _lastPersistedKey = '';
    notifyListeners();
    _persistConfigJson();
    return ok;
  }

  /// Hydrate the config from SharedPreferences + secure store and run the
  /// two-stage plaintext-key migration. Call once during app startup (after
  /// [setupLocator]); no-op when nothing is stored. Notifies listeners when a
  /// stored config is loaded.
  Future<void> loadPersisted() async {
    final prefs = _prefs;
    if (prefs == null) return;
    AiEngineConfig? stored;
    var legacyPlaintextKey = '';
    try {
      final raw = prefs.preferences
          .getString(LocalStateKeys.aiEngineConfig, defaultValue: '')
          .getValue();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          stored = AiEngineConfig.fromJson(decoded);
          legacyPlaintextKey = (decoded['apiKey'] as String?)?.trim() ?? '';
        }
      }
    } catch (_) {
      // Corrupt / partial JSON - keep the in-memory default rather than crash.
      return;
    }

    _keyStorageKind = _credentials.isPersistent
        ? AiKeyStorageKind.secure
        : AiKeyStorageKind.sessionOnly;

    if (stored == null) {
      _migrationStatus = AiCredentialMigrationStatus.notNeeded;
      return;
    }

    if (legacyPlaintextKey.isEmpty) {
      // Modern shape: key already lives in the secure store.
      final secureKey = await _readStoredKey();
      _migrationStatus = AiCredentialMigrationStatus.done;
      _lastPersistedKey = secureKey ?? '';
      _config = stored.copyWith(apiKey: secureKey ?? '');
      notifyListeners();
      return;
    }

    // ── Two-phase migration (Plan 2 §6.3 / S2-M03+M04) ──────────────────
    // write secure -> read back verify -> rewrite blob without key ->
    // only then remove the plaintext value. Any failure keeps the plaintext
    // intact and reports [AiCredentialMigrationStatus.failed].
    _migrationStatus = AiCredentialMigrationStatus.pending;
    try {
      await _credentials.write(apiKeyId, legacyPlaintextKey);
      final readBack = await _credentials.read(apiKeyId);
      if (readBack != legacyPlaintextKey) {
        throw StateError('secure-store verify mismatch');
      }
      // Rewrite the prefs blob without the key before removing anything.
      final sanitized = stored.copyWith(apiKey: '');
      final raw = jsonEncode(sanitized.toJson());
      await prefs.preferences.setString(LocalStateKeys.aiEngineConfig, raw);
      _lastPersistedKey = legacyPlaintextKey;
      _config = sanitized.copyWith(apiKey: legacyPlaintextKey);
      _migrationStatus = AiCredentialMigrationStatus.done;
      await prefs.setBool(LocalStateKeys.aiCredentialMigrated, value: true);
    } catch (error) {
      migrationFailedStage = 'migrate';
      if (kDebugMode) {
        debugPrint('AiEngineConfigHolder: credential migration failed at '
            'stage migrate (${error.runtimeType}); plaintext kept.');
      }
      // Never delete the plaintext on failure — the user's key must survive.
      _config = stored;
      _migrationStatus = AiCredentialMigrationStatus.failed;
    }
    notifyListeners();
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  Future<void> _persist() async {
    _persistConfigJson();
    final key = _config.apiKey;
    if (key == _lastPersistedKey) return;
    try {
      if (key.isEmpty) {
        await _credentials.delete(apiKeyId);
      } else {
        await _credentials.write(apiKeyId, key);
      }
      _lastPersistedKey = key;
      _keyStorageKind = _credentials.isPersistent
          ? AiKeyStorageKind.secure
          : AiKeyStorageKind.sessionOnly;
    } catch (error) {
      migrationFailedStage = 'persistKey';
      if (kDebugMode) {
        debugPrint('AiEngineConfigHolder: secure key write failed '
            '(${error.runtimeType}).');
      }
    }
  }

  void _persistConfigJson() {
    final prefs = _prefs;
    if (prefs == null) return;
    // Secrets never enter the prefs blob; writing on `prefs.preferences`
    // (not `AppPrefs.setString`) keeps the value out of debug logs too.
    final encoded = jsonEncode(_config.toJson());
    final stopwatch = Stopwatch()..start();
    prefs.preferences
        .setString(LocalStateKeys.aiEngineConfig, encoded)
        .then((_) {
      stopwatch.stop();
      StorageWriteTelemetry.instance.record(
        key: LocalStateKeys.aiEngineConfig,
        estimatedBytes: utf8.encode(encoded).length,
        elapsed: stopwatch.elapsed,
      );
    });
  }

  Future<String?> _readStoredKey() {
    return _credentials.read(apiKeyId).catchError((Object error) {
      if (kDebugMode) {
        debugPrint('AiEngineConfigHolder: secure key read failed '
            '(${error.runtimeType}).');
      }
      return null;
    });
  }

  Future<bool> _deleteStoredKey() async {
    try {
      await _credentials.delete(apiKeyId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolve [AppPrefs] if it is registered, else `null`. Guarded so the
  /// holder works in test contexts that skip [setupLocator].
  AppPrefs? get _prefs {
    if (!getIt.isRegistered<AppPrefs>()) return null;
    try {
      return getIt<AppPrefs>();
    } catch (_) {
      return null;
    }
  }

  static ICredentialStore _resolveDefaultStore() {
    if (getIt.isRegistered<ICredentialStore>()) {
      try {
        return getIt<ICredentialStore>();
      } catch (_) {
        // fall through to a fresh store
      }
    }
    return SecureCredentialStore();
  }
}
