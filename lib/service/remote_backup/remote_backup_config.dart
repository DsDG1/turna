// Dart imports:
import 'dart:convert';
import 'dart:math';

// Project imports:
import 'package:turna/service/locator.dart';

/// Remote backup endpoint + account configuration for one WebDAV server.
///
/// The password is stored in plain text in SharedPreferences — same trade-off
/// the AI engine config makes (see [AiEngineConfigHolder]); writes bypass
/// `AppPrefs.printBefore` so the secret never reaches logs. Backup archives
/// must never contain this config.
class RemoteBackupConfig {
  const RemoteBackupConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.includeMedia = true,
    this.remoteRoot = 'TurnaBackup',
  });

  /// Server base URL, e.g. `https://dav.example.com` or
  /// `https://cloud.example.com/remote.php/dav`. No trailing slash needed.
  final String serverUrl;

  final String username;
  final String password;

  /// Whether media objects are uploaded / downloaded (content-addressed,
  /// incremental). Core data is always included.
  final bool includeMedia;

  /// Remote folder name under the server root that holds the whole layout.
  final String remoteRoot;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.isNotEmpty;

  RemoteBackupConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    bool? includeMedia,
    String? remoteRoot,
  }) =>
      RemoteBackupConfig(
        serverUrl: serverUrl ?? this.serverUrl,
        username: username ?? this.username,
        password: password ?? this.password,
        includeMedia: includeMedia ?? this.includeMedia,
        remoteRoot: remoteRoot ?? this.remoteRoot,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'includeMedia': includeMedia,
        'remoteRoot': remoteRoot,
      };

  static RemoteBackupConfig fromJson(Map<String, dynamic> json) =>
      RemoteBackupConfig(
        serverUrl: (json['serverUrl'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        includeMedia: (json['includeMedia'] as bool?) ?? true,
        remoteRoot:
            (json['remoteRoot'] as String?)?.trim().isEmpty == true
                ? 'TurnaBackup'
                : ((json['remoteRoot'] as String?) ?? 'TurnaBackup'),
      );

  RemoteBackupConfig normalized() => copyWith(
        serverUrl: serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        username: username.trim(),
        remoteRoot: remoteRoot
            .trim()
            .replaceAll(RegExp(r'^/+|/+$'), '')
            .replaceAll(RegExp(r'[^\w.\-]+'), '_'),
      );
}

/// Loads / persists [RemoteBackupConfig] under the single
/// [LocalStateKeys.remoteBackupConfig] key.
///
/// Reads are synchronous (streaming_shared_preferences exposes sync getters)
/// so callers never await a load; saves go through the raw
/// `StreamingSharedPreferences` to bypass `AppPrefs.printBefore` — the
/// password must not be emitted to logs (same approach as
/// `AiEngineConfigHolder._persist`).
class RemoteBackupConfigStore {
  RemoteBackupConfigStore(this._prefs);

  final AppPrefs _prefs;

  RemoteBackupConfig load() {
    final raw = _prefs.preferences
        .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return const RemoteBackupConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return RemoteBackupConfig.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt / partial JSON - fall through to defaults rather than crash.
    }
    return const RemoteBackupConfig();
  }

  Future<void> save(RemoteBackupConfig config) =>
      _prefs.preferences.setString(
        LocalStateKeys.remoteBackupConfig,
        jsonEncode(config.toJson()),
      );
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
