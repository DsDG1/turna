// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;

// Project imports:
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/remote_backup_store.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';

/// WebDAV-backed [RemoteBackupStore]. Object paths recorded in manifests are
/// relative to the remote root so renaming the root keeps old manifests
/// usable.
class WebDavRemoteBackupStore extends RemoteBackupStore {
  WebDavRemoteBackupStore(this._client, {required this.remoteRoot});

  final WebDavClient _client;
  final String remoteRoot;

  String get _root => '/$remoteRoot';
  String get _backupsDir => '$_root/backups';
  String get _mediaDir => '$_root/media';
  String get _manifestPath => '$_root/manifest.json';
  String _backupDir(String backupId) => '$_backupsDir/$backupId';

  /// Path recorded inside manifests, relative to the remote root.
  static String coreZipObjectFor(String backupId) =>
      'backups/$backupId/core.zip';

  @override
  Future<void> ensureLayout() async {
    await _client.mkcolRecursive(_backupsDir);
    await _client.mkcolRecursive(_mediaDir);
  }

  @override
  Future<RemoteBackupManifest?> fetchManifest() async {
    try {
      final bytes = await _client.getBytes(_manifestPath);
      return RemoteBackupManifest.fromBytes(bytes);
    } on WebDavNotFoundException {
      return null;
    }
  }

  @override
  Future<void> publishManifest(RemoteBackupManifest manifest) async {
    final tmp = '$_manifestPath.tmp';
    await _client.putBytes(tmp, utf8.encode(jsonEncode(manifest.toJson())));
    await _client.move(tmp, _manifestPath);
  }

  @override
  Future<void> uploadCoreZip(String backupId, File coreZip) async {
    await _client.mkcolRecursive(_backupDir(backupId));
    await _client.putFile('${_backupDir(backupId)}/core.zip', coreZip);
  }

  @override
  Future<bool> hasMediaObject(String sha256) =>
      _client.exists('$_mediaDir/$sha256');

  @override
  Future<void> uploadMediaObject(String sha256, File source) =>
      _client.putFile('$_mediaDir/$sha256', source);

  @override
  Future<void> downloadCoreZip(RemoteBackupManifest manifest, File dest) async {
    final object = manifest.coreZipObject;
    final remote =
        object.startsWith('/') ? object : p.posix.join(_root, object);
    await _client.getToFile(remote, dest);
  }

  @override
  Future<void> downloadMediaObject(String sha256, File dest) =>
      _client.getToFile('$_mediaDir/$sha256', dest);

  @override
  Future<void> deleteBackup(String backupId) =>
      _client.delete(_backupDir(backupId));
}
