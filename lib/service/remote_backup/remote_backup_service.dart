// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:turna/service/remote_backup/archive_io.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/remote_backup_store.dart';
import 'package:turna/service/remote_backup/restore_staging.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';
import 'package:turna/service/remote_backup/webdav_remote_backup_store.dart';

/// A backup cannot start while an Anki review session or import is running.
class RemoteBackupBusyException implements Exception {
  @override
  String toString() => '复习或导入正在进行中，请稍后再试';
}

/// Summary of one completed backup, also persisted locally as the
/// "last backup" record shown in the UI.
class RemoteBackupResult {
  const RemoteBackupResult({
    required this.backupId,
    required this.createdAtUtc,
    required this.coreZipBytes,
    required this.mediaUploaded,
    required this.mediaSkipped,
  });

  final String backupId;
  final DateTime createdAtUtc;
  final int coreZipBytes;
  final int mediaUploaded;
  final int mediaSkipped;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'backupId': backupId,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'coreZipBytes': coreZipBytes,
        'mediaUploaded': mediaUploaded,
        'mediaSkipped': mediaSkipped,
      };

  static RemoteBackupResult? fromJson(Map<String, dynamic>? json) =>
      json == null
          ? null
          : RemoteBackupResult(
              backupId: (json['backupId'] as String?) ?? '',
              createdAtUtc:
                  DateTime.tryParse((json['createdAtUtc'] as String?) ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
              coreZipBytes: (json['coreZipBytes'] as int?) ?? 0,
              mediaUploaded: (json['mediaUploaded'] as int?) ?? 0,
              mediaSkipped: (json['mediaSkipped'] as int?) ?? 0,
            );
}

/// Orchestrates manual remote backup / restore against a [RemoteBackupStore].
///
/// Upload ordering is deliberate: media objects first (content-addressed, an
/// interrupted upload only leaves harmless orphans), then the core archive,
/// then the manifest — atomically. Readers fetching the old manifest until
/// the very last moment never observe a half-published backup.
class RemoteBackupService {
  RemoteBackupService({
    required AppPrefs prefs,
    required RemoteBackupConfigStore configStore,
    required BackupSnapshotService snapshotService,
    required Directory appSupport,
    required RemoteBackupStore Function(RemoteBackupResolvedConfig config)
        storeFactory,
    bool Function()? busyGuard,
  })  : _prefs = prefs,
        _configStore = configStore,
        _snapshotService = snapshotService,
        _appSupport = appSupport,
        _storeFactory = storeFactory,
        _busyGuard = busyGuard;

  final AppPrefs _prefs;
  final RemoteBackupConfigStore _configStore;
  final BackupSnapshotService _snapshotService;
  final Directory _appSupport;
  final RemoteBackupStore Function(RemoteBackupResolvedConfig config)
      _storeFactory;
  final bool Function()? _busyGuard;

  Directory get _snapshotStaging =>
      Directory(p.join(_appSupport.path, 'backup_staging'));

  /// Endpoint + credential for one operation. The password comes from the
  /// platform secure store (see [RemoteBackupConfigStore.loadResolved]).
  Future<RemoteBackupResolvedConfig> _requireConfig() async {
    final config = await _configStore.loadResolved();
    if (config == null || !config.normalized().isConfigured) {
      throw const WebDavException('请先配置远程备份服务器');
    }
    return config.normalized();
  }

  /// Connectivity + credentials + write access probe. Also creates the
  /// remote layout so the first backup does not race folder creation.
  Future<WebDavProbeResult> testConnection() async {
    final config = await _requireConfig();
    final client = WebDavClient.fromConfig(config);
    try {
      final probe = await client.probe();
      await WebDavRemoteBackupStore(client, remoteRoot: config.remoteRoot)
          .ensureLayout();
      return probe;
    } finally {
      client.close();
    }
  }

  Future<RemoteBackupManifest?> fetchRemoteStatus() async {
    final config = await _requireConfig();
    final client = WebDavClient.fromConfig(config);
    try {
      return await WebDavRemoteBackupStore(client,
              remoteRoot: config.remoteRoot)
          .fetchManifest();
    } finally {
      client.close();
    }
  }

  /// The last successful backup recorded on this device (independent of the
  /// remote manifest, so it also survives offline).
  RemoteBackupResult? lastLocalBackup() {
    final raw = _prefs.preferences
        .getString(LocalStateKeys.remoteBackupLastInfo, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return RemoteBackupResult.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt record - ignore.
    }
    return null;
  }

  Future<RemoteBackupResult> backupNow({
    void Function(BackupSnapshotPhase phase)? onPhase,
    void Function(int hashed, int total)? onMediaProgress,
    void Function(int uploaded, int skipped)? onMediaUploadProgress,
  }) async {
    if (_busyGuard?.call() ?? false) {
      throw RemoteBackupBusyException();
    }
    final config = await _requireConfig();
    final store = _storeFactory(config);
    final stopwatch = Stopwatch()..start();

    await store.ensureLayout();
    final snapshot = await _snapshotService.build(
      stagingDir: _snapshotStaging,
      includeMedia: config.includeMedia,
      onPhase: onPhase,
      onMediaProgress: onMediaProgress,
    );

    var uploaded = 0;
    var skipped = 0;
    for (final object in snapshot.mediaObjects.entries) {
      if (await store.hasMediaObject(object.key)) {
        skipped++;
      } else {
        await store.uploadMediaObject(object.key, File(object.value));
        uploaded++;
      }
      onMediaUploadProgress?.call(uploaded, skipped);
    }

    await store.uploadCoreZip(snapshot.backupId, snapshot.coreZip);

    final previous = await store.fetchManifest();
    final head = RemoteBackupManifestEntry(
      backupId: snapshot.backupId,
      createdAtUtc: snapshot.meta.createdAtUtc,
      coreZipObject:
          WebDavRemoteBackupStore.coreZipObjectFor(snapshot.backupId),
      coreZipSha256: snapshot.coreZipSha256,
      coreZipBytes: snapshot.coreZipBytes,
      mediaCount: snapshot.mediaManifest.length,
      mediaBytes:
          snapshot.mediaManifest.values.fold<int>(0, (sum, e) => sum + e.bytes),
    );
    final manifest = RemoteBackupManifest(
      backupId: snapshot.backupId,
      createdAtUtc: snapshot.meta.createdAtUtc,
      deviceId: ensureRemoteBackupDeviceId(_prefs),
      deviceLabel: snapshot.meta.deviceLabel,
      appVersion: snapshot.meta.appVersion,
      buildNumber: snapshot.meta.buildNumber,
      platform: snapshot.meta.platform,
      driftSchema: snapshot.meta.driftSchema,
      catalogSchema: snapshot.meta.catalogSchema,
      coreZipObject: head.coreZipObject,
      coreZipSha256: head.coreZipSha256,
      coreZipBytes: head.coreZipBytes,
      mediaCount: head.mediaCount,
      mediaBytes: head.mediaBytes,
      history: RemoteBackupManifest.mergeHistory(previous),
    );
    await store.publishManifest(manifest);

    // Retention: drop previous generations that fell out of the window.
    final keep = <String>{
      manifest.backupId,
      ...manifest.history.map((e) => e.backupId),
    };
    final candidates = <String>{
      if (previous != null) previous.backupId,
      if (previous != null) ...previous.history.map((e) => e.backupId),
    }.difference(keep);
    for (final backupId in candidates) {
      await store.deleteBackup(backupId);
    }

    final result = RemoteBackupResult(
      backupId: snapshot.backupId,
      createdAtUtc: snapshot.meta.createdAtUtc,
      coreZipBytes: snapshot.coreZipBytes,
      mediaUploaded: uploaded,
      mediaSkipped: skipped,
    );
    await _prefs.preferences.setString(
        LocalStateKeys.remoteBackupLastInfo, jsonEncode(result.toJson()));

    if (await _snapshotStaging.exists()) {
      await _snapshotStaging.delete(recursive: true);
    }
    stopwatch.stop();
    return result;
  }

  /// Downloads and verifies a remote backup into the local staging area and
  /// arms the boot-time restore marker. The actual apply happens on next app
  /// start (all databases are closed then).
  Future<void> restoreToStaging(
    RemoteBackupManifest manifest, {
    void Function(int done, int total)? onMediaProgress,
  }) async {
    final config = await _requireConfig();
    final store = _storeFactory(config);

    final staging = RestoreStagingLayout.root(_appSupport);
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    final coreZip = File(p.join(staging.path, 'core.zip'));
    await store.downloadCoreZip(manifest, coreZip);
    final coreSha = archiveFileSha256(coreZip.path);
    if (coreSha != manifest.coreZipSha256) {
      throw WebDavException('核心包校验失败（下载数据损坏）');
    }

    await extractArchiveToDisk(
      coreZip.path,
      staging.path,
      resolveEntryPath: _safeEntryPath,
      onEntry: (_, __) {},
    );
    _verifySha256Sums(staging);
    final meta = _readMeta(staging);

    final mediaManifest = parseMediaManifest(await File(
            p.join(staging.path, RestoreStagingLayout.mediaManifestEntry))
        .readAsString());
    final objects = mediaManifest.values.map((e) => e.sha256).toSet().toList()
      ..sort();
    final mediaDir = RestoreStagingLayout.media(_appSupport);
    await mediaDir.create(recursive: true);
    var done = 0;
    for (final sha in objects) {
      final dest = File(p.join(mediaDir.path, sha));
      final alreadyStaged =
          await dest.exists() && archiveFileSha256(dest.path) == sha;
      if (!alreadyStaged) {
        await store.downloadMediaObject(sha, dest);
        if (archiveFileSha256(dest.path) != sha) {
          throw WebDavException('媒体对象校验失败: ${sha.substring(0, 8)}…');
        }
      }
      onMediaProgress?.call(++done, objects.length);
    }

    // Marker last: its presence is the commit point for the boot applier.
    await File(
      RestoreStagingLayout.marker(_appSupport).path,
    ).writeAsString(
      RestoreStagingLayout.encodeMarker(
        backupId: manifest.backupId,
        createdAtUtc: manifest.createdAtUtc,
        sourceAppVersion: meta.appVersion,
      ),
      flush: true,
    );
  }

  /// Entry names inside core.zip are produced by our own packer; still,
  /// reject anything unexpected before it touches disk.
  String _safeEntryPath(String entryName) {
    if (entryName.contains('..') ||
        p.isAbsolute(entryName) ||
        entryName.startsWith('/')) {
      throw FormatException('不安全的备份包条目: $entryName');
    }
    return entryName;
  }

  void _verifySha256Sums(Directory staging) {
    final sumsFile = File(p.join(staging.path, RestoreStagingLayout.sumsEntry));
    if (!sumsFile.existsSync()) {
      throw const FormatException('备份包缺少 SHA256SUMS');
    }
    for (final line in sumsFile.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final match = RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(line.trim());
      if (match == null) {
        throw FormatException('SHA256SUMS 行格式错误: $line');
      }
      final digest = archiveFileSha256(p.join(staging.path, match.group(2)!));
      if (digest != match.group(1)!) {
        throw FormatException('备份包文件校验失败: ${match.group(2)}');
      }
    }
  }

  BackupArchiveMeta _readMeta(Directory staging) {
    final file = File(p.join(staging.path, RestoreStagingLayout.metaEntry));
    if (!file.existsSync()) {
      throw const FormatException('备份包缺少 meta.json');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('meta.json 格式错误');
    }
    return BackupArchiveMeta.fromJson(decoded);
  }
}
