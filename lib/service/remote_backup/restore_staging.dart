// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;

/// Shared layout of the local restore staging area, used by both the
/// downloader ([RemoteBackupService.restoreToStaging]) and the boot-time
/// [RestoreApplier]. The staging area lives under the app-support directory
/// and is crash-safe: the marker file is written last, so a download
/// interrupted at any point is simply ignored on next boot.
abstract final class RestoreStagingLayout {
  static const String rootName = 'restore_staging';
  static const String markerName = 'restore_pending.json';
  static const String mediaDirName = 'media';

  static const String prefsEntry = 'prefs.json';
  static const String metaEntry = 'meta.json';
  static const String mediaManifestEntry = 'media_manifest.json';
  static const String courseDbEntry = 'course.db';
  static const String collectionEntry = 'collection.anki2';
  static const String catalogEntry = 'official_catalog.sqlite';
  static const String mediaDbEntry = 'collection.media.db2';
  static const String sumsEntry = 'SHA256SUMS';

  static Directory root(Directory appSupport) =>
      Directory(p.join(appSupport.path, rootName));

  static File marker(Directory appSupport) =>
      File(p.join(root(appSupport).path, markerName));

  static Directory media(Directory appSupport) =>
      Directory(p.join(root(appSupport).path, mediaDirName));

  /// Marker payload: enough for the boot applier and the post-restore UI
  /// prompt to know what happened without re-reading the archive.
  static String encodeMarker({
    required String backupId,
    required DateTime createdAtUtc,
    required String sourceAppVersion,
  }) =>
      jsonEncode(<String, dynamic>{
        'backupId': backupId,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'sourceAppVersion': sourceAppVersion,
        'stagedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });

  static Map<String, dynamic>? decodeMarker(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Corrupt marker - treat as absent.
    }
    return null;
  }
}
