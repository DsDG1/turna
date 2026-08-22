// Dart imports:
import 'dart:io';

// Project imports:
import 'package:turna/service/remote_backup/backup_manifest.dart';

/// Remote storage contract for the backup layout:
///
/// ```
/// /<root>/manifest.json                  # published atomically (tmp+MOVE)
/// /<root>/backups/<backupId>/core.zip
/// /<root>/media/<sha256>                 # content-addressed, append-only
/// ```
///
/// The WebDAV implementation is the only production implementation; tests
/// use in-memory fakes.
abstract class RemoteBackupStore {
  /// Creates the remote layout (and doubles as a write-access check).
  Future<void> ensureLayout();

  /// Latest published manifest, or `null` when the server holds none.
  Future<RemoteBackupManifest?> fetchManifest();

  /// Publishes the manifest atomically — readers never see a partial file.
  Future<void> publishManifest(RemoteBackupManifest manifest);

  Future<void> uploadCoreZip(String backupId, File coreZip);

  /// Cheap existence probe so unchanged media objects are not re-uploaded.
  Future<bool> hasMediaObject(String sha256);

  Future<void> uploadMediaObject(String sha256, File source);

  /// Downloads the manifest's core archive to [dest] (streamed to disk).
  Future<void> downloadCoreZip(RemoteBackupManifest manifest, File dest);

  Future<void> downloadMediaObject(String sha256, File dest);

  /// Removes `backups/<backupId>/`; a missing directory is not an error.
  Future<void> deleteBackup(String backupId);
}
