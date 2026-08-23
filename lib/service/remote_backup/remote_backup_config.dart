// Dart imports:
import 'dart:convert';
import 'dart:math';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/locator.dart';

/// WebDAV endpoint + account configuration that is safe to persist in
/// ordinary SharedPreferences: server URL, username, remote root and the
/// media toggle. The password NEVER lives here — see
/// [RemoteBackupConfigStore.loadPassword], which reads it from the platform
/// secure credential store.
class RemoteBackupEndpointConfig {
  const RemoteBackupEndpointConfig({
    this.serverUrl = '',
    this.username = '',
    this.includeMedia = true,
    this.remoteRoot = 'TurnaBackup',
  });

  /// Server base URL, e.g. `https://dav.example.com` or
  /// `https://cloud.example.com/remote.php/dav`. No trailing slash needed.
  final String serverUrl;

  final String username;

  /// Whether media objects are uploaded / downloaded (content-addressed,
  /// incremental). Core data is always included.
  final bool includeMedia;

  /// Remote folder name under the server root that holds the whole layout.
  final String remoteRoot;

  /// Endpoint readiness ignoring the credential — used by the UI to decide
  /// whether the "save & test" action can run.
  bool get hasEndpointInput =>
      serverUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  RemoteBackupEndpointConfig copyWith({
    String? serverUrl,
    String? username,
    bool? includeMedia,
    String? remoteRoot,
  }) =>
      RemoteBackupEndpointConfig(
        serverUrl: serverUrl ?? this.serverUrl,
        username: username ?? this.username,
        includeMedia: includeMedia ?? this.includeMedia,
        remoteRoot: remoteRoot ?? this.remoteRoot,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'serverUrl': serverUrl,
        'username': username,
        'includeMedia': includeMedia,
        'remoteRoot': remoteRoot,
      };

  /// Accepts the legacy shape (which had a `password` field) and silently
  /// ignores the password — reading it back is exclusively the secure
  /// store's job (see [RemoteBackupConfigStore.migrateLegacyPlaintext]).
  static RemoteBackupEndpointConfig fromJson(Map<String, dynamic> json) =>
      RemoteBackupEndpointConfig(
        serverUrl: (json['serverUrl'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        includeMedia: (json['includeMedia'] as bool?) ?? true,
        remoteRoot: (json['remoteRoot'] as String?)?.trim().isEmpty == true
            ? 'TurnaBackup'
            : ((json['remoteRoot'] as String?) ?? 'TurnaBackup'),
      );

  RemoteBackupEndpointConfig normalized() => copyWith(
        serverUrl: serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        username: username.trim(),
        remoteRoot: remoteRoot
            .trim()
            .replaceAll(RegExp(r'^/+|/+$'), '')
            .replaceAll(RegExp(r'[^\w.\-]+'), '_'),
      );
}

/// Runtime combination of the endpoint config and the secure-store password.
/// Created on demand, never serialized, never logged — treat every field as
/// sensitive-by-association.
class RemoteBackupResolvedConfig {
  const RemoteBackupResolvedConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.includeMedia,
    required this.remoteRoot,
  });

  final String serverUrl;
  final String username;
  final String password;
  final bool includeMedia;
  final String remoteRoot;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  RemoteBackupResolvedConfig normalized() => RemoteBackupResolvedConfig(
        serverUrl: serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        username: username.trim(),
        password: password,
        includeMedia: includeMedia,
        remoteRoot: remoteRoot
            .trim()
            .replaceAll(RegExp(r'^/+|/+$'), '')
            .replaceAll(RegExp(r'[^\w.\-]+'), '_'),
      );
}

/// Outcome of the one-shot legacy plaintext migration (Plan §9.2).
enum RemoteBackupCredentialMigrationStatus {
  /// Nothing to do: no legacy password found, or already migrated.
  notNeeded,

  /// Legacy password moved to the secure store, verified, and removed from
  /// prefs.
  migrated,

  /// The secure store is unavailable (plugin missing / failed). The
  /// plaintext config is kept untouched and the migration retries on the
  /// next launch — never silently fall back to storing plaintext.
  secureStoreUnavailable,

  /// The secure write could not be verified. Old config kept intact; the
  /// migration retries on the next launch.
  verifyFailed,
}

/// Loads / persists the WebDAV endpoint under
/// [LocalStateKeys.remoteBackupConfig] and the password exclusively in the
/// platform [ICredentialStore].
///
/// Also owns the idempotent legacy migration: old releases stored the
/// password inside the prefs JSON. [migrateLegacyPlaintext] moves it to the
/// secure store, reads it back to verify, only then rewrites the prefs JSON
/// without the password and records a completion marker. Any failure keeps
/// the old config so the next launch can retry.
class RemoteBackupConfigStore {
  RemoteBackupConfigStore(this._prefs, {ICredentialStore? credentialStore})
      : _credentialStore = credentialStore;

  static const String securePasswordId = 'remoteBackup.webdavPassword';
  static const String migrationMarkerKey = 'remoteBackup.credentialMigrated';

  final AppPrefs _prefs;
  final ICredentialStore? _credentialStore;

  ICredentialStore? get _credentials =>
      _credentialStore ??
      (getIt.isRegistered<ICredentialStore>()
          ? getIt<ICredentialStore>()
          : null);

  // ── endpoint ──

  RemoteBackupEndpointConfig loadEndpoint() {
    final raw = _prefs.preferences
        .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return const RemoteBackupEndpointConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return RemoteBackupEndpointConfig.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt / partial JSON - fall through to defaults rather than crash.
    }
    return const RemoteBackupEndpointConfig();
  }

  Future<void> saveEndpoint(RemoteBackupEndpointConfig config) =>
      _prefs.preferences.setString(
        LocalStateKeys.remoteBackupConfig,
        jsonEncode(config.toJson()),
      );

  // ── credential ──

  Future<String?> loadPassword() async {
    final credentials = _credentials;
    if (credentials == null) return null;
    final value = await credentials.read(securePasswordId);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<bool> hasStoredPassword() => loadPassword().then((p) => p != null);

  /// Writes the password to the secure store and verifies the write by
  /// reading it back. An empty [password] clears the stored credential.
  Future<void> savePassword(String password) async {
    final credentials = _credentials;
    if (credentials == null) {
      throw const RemoteBackupSecureStoreException();
    }
    if (password.isEmpty) {
      await credentials.delete(securePasswordId);
      return;
    }
    await credentials.write(securePasswordId, password);
    final readBack = await credentials.read(securePasswordId);
    if (readBack != password) {
      throw const RemoteBackupSecureStoreException(
        '安全存储写入后校验失败，请重试。',
      );
    }
  }

  // ── resolved runtime config ──

  /// Endpoint + credential for one operation, or null when the password is
  /// not stored (yet). Never cache the result longer than the operation.
  Future<RemoteBackupResolvedConfig?> loadResolved() async {
    final endpoint = loadEndpoint();
    if (!endpoint.hasEndpointInput) return null;
    final password = await loadPassword();
    if (password == null) return null;
    return RemoteBackupResolvedConfig(
      serverUrl: endpoint.serverUrl,
      username: endpoint.username,
      includeMedia: endpoint.includeMedia,
      remoteRoot: endpoint.remoteRoot,
      password: password,
    );
  }

  // ── legacy plaintext migration ──

  /// Moves a legacy plaintext password (stored inside the prefs JSON by old
  /// releases) into the secure store. Idempotent; safe to call on every
  /// boot. Only after the secure copy is written AND read back verified is
  /// the plaintext removed from prefs.
  Future<RemoteBackupCredentialMigrationStatus> migrateLegacyPlaintext() async {
    final raw = _prefs.preferences
        .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return RemoteBackupCredentialMigrationStatus.notNeeded;

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) decoded = parsed;
    } catch (_) {
      // Corrupt JSON: nothing we can migrate. Leave it for loadEndpoint's
      // graceful degradation.
      return RemoteBackupCredentialMigrationStatus.notNeeded;
    }
    final legacyJson = decoded;
    if (legacyJson == null) {
      return RemoteBackupCredentialMigrationStatus.notNeeded;
    }
    final legacyPassword = legacyJson['password'];
    if (legacyPassword is! String || legacyPassword.isEmpty) {
      return RemoteBackupCredentialMigrationStatus.notNeeded;
    }

    final credentials = _credentials;
    if (credentials == null || !credentials.isPersistent) {
      // Do NOT touch the old config: removing the plaintext now would lock
      // the user out with nowhere left to read the password from.
      return RemoteBackupCredentialMigrationStatus.secureStoreUnavailable;
    }

    // Already migrated on a previous run (marker present, plaintext left by
    // an old app version writing it back): just scrub the field again.
    final alreadyMigrated = _prefs.preferences
        .getBool(migrationMarkerKey, defaultValue: false)
        .getValue();
    if (alreadyMigrated) {
      final verified = await credentials.read(securePasswordId);
      if (verified == legacyPassword) {
        await _writeEndpointWithoutPassword(legacyJson);
        return RemoteBackupCredentialMigrationStatus.notNeeded;
      }
      // Marker set but secure value differs/missing — fall through and
      // re-run the full migration below.
    }

    await credentials.write(securePasswordId, legacyPassword);
    final readBack = await credentials.read(securePasswordId);
    if (readBack != legacyPassword) {
      return RemoteBackupCredentialMigrationStatus.verifyFailed;
    }

    await _writeEndpointWithoutPassword(legacyJson);
    await _prefs.preferences.setBool(migrationMarkerKey, true);
    return RemoteBackupCredentialMigrationStatus.migrated;
  }

  /// Rewrites the endpoint JSON without the password field and verifies the
  /// stored document really no longer contains it.
  Future<void> _writeEndpointWithoutPassword(
    Map<String, dynamic> legacyJson,
  ) async {
    final endpoint = RemoteBackupEndpointConfig.fromJson(legacyJson);
    await saveEndpoint(endpoint);
    final rawAfter = _prefs.preferences
        .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
        .getValue();
    try {
      final after = jsonDecode(rawAfter);
      if (after is Map<String, dynamic> &&
          (after['password'] as String?)?.isNotEmpty == true) {
        throw StateError('password field still present after rewrite');
      }
    } catch (_) {
      throw const RemoteBackupSecureStoreException(
        '清理旧配置失败，迁移将在下次启动时重试。',
      );
    }
  }
}

/// Raised when the platform secure store is unavailable or a write could not
/// be verified. Users see an actionable message; the app never falls back to
/// storing the password in plaintext prefs.
class RemoteBackupSecureStoreException implements Exception {
  const RemoteBackupSecureStoreException([this.message = '']);

  final String message;

  @override
  String toString() => message.isEmpty ? '安全存储不可用，无法保存远程备份凭据。' : message;
}

/// Stable per-install identity used in remote manifests so a future
/// multi-device view can tell backups apart. Not included in backup payloads,
/// so restoring on another device keeps that device's own id.
String ensureRemoteBackupDeviceId(AppPrefs prefs) {
  final existing = prefs.preferences
      .getString(LocalStateKeys.remoteBackupDeviceId, defaultValue: '')
      .getValue();
  if (existing.isNotEmpty) return existing;
  final rng = Random.secure();
  final id = List.generate(
    16,
    (_) => rng.nextInt(16).toRadixString(16),
  ).join();
  prefs.preferences.setString(LocalStateKeys.remoteBackupDeviceId, id);
  return id;
}
