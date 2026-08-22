// Dart imports:
import 'dart:convert';

/// Schema of the remote `manifest.json` document. Bump when the shape changes
/// in a way old clients cannot parse.
const int kRemoteBackupManifestSchema = 1;

/// How many `backups/<id>/core.zip` generations are kept on the server.
/// Media objects are content-addressed and never garbage-collected (v1).
const int kRemoteBackupRetention = 5;

class RemoteBackupManifestFutureVersion implements Exception {
  @override
  String toString() => 'Remote manifest uses a newer schema than this app';
}

/// One entry of the manifest history — enough to list / pick a backup without
/// downloading archives.
class RemoteBackupManifestEntry {
  const RemoteBackupManifestEntry({
    required this.backupId,
    required this.createdAtUtc,
    required this.coreZipObject,
    required this.coreZipSha256,
    required this.coreZipBytes,
    required this.mediaCount,
    required this.mediaBytes,
  });

  final String backupId;
  final DateTime createdAtUtc;
  final String coreZipObject;
  final String coreZipSha256;
  final int coreZipBytes;
  final int mediaCount;
  final int mediaBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'backupId': backupId,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'coreZipObject': coreZipObject,
        'coreZipSha256': coreZipSha256,
        'coreZipBytes': coreZipBytes,
        'mediaCount': mediaCount,
        'mediaBytes': mediaBytes,
      };

  static RemoteBackupManifestEntry fromJson(Map<String, dynamic> json) =>
      RemoteBackupManifestEntry(
        backupId: (json['backupId'] as String?) ?? '',
        createdAtUtc:
            DateTime.tryParse((json['createdAtUtc'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        coreZipObject: (json['coreZipObject'] as String?) ?? '',
        coreZipSha256: (json['coreZipSha256'] as String?) ?? '',
        coreZipBytes: (json['coreZipBytes'] as int?) ?? 0,
        mediaCount: (json['mediaCount'] as int?) ?? 0,
        mediaBytes: (json['mediaBytes'] as int?) ?? 0,
      );
}

/// The remote `manifest.json` — the only entry point for restores. Written
/// atomically (`.tmp` + MOVE) as the last step of a successful upload.
class RemoteBackupManifest {
  const RemoteBackupManifest({
    required this.backupId,
    required this.createdAtUtc,
    required this.deviceId,
    required this.deviceLabel,
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.driftSchema,
    required this.catalogSchema,
    required this.coreZipObject,
    required this.coreZipSha256,
    required this.coreZipBytes,
    required this.mediaCount,
    required this.mediaBytes,
    required this.history,
  });

  final String backupId;
  final DateTime createdAtUtc;
  final String deviceId;
  final String deviceLabel;
  final String appVersion;
  final String buildNumber;
  final String platform;

  /// Schema versions the archives were produced with — restore guards refuse
  /// when a backup comes from an app newer than the local one.
  final int driftSchema;
  final int catalogSchema;

  final String coreZipObject;
  final String coreZipSha256;
  final int coreZipBytes;
  final int mediaCount;
  final int mediaBytes;

  /// Previous generations, most recent first, capped at
  /// [kRemoteBackupRetention] (current backup excluded — see
  /// [mergeHistory]).
  final List<RemoteBackupManifestEntry> history;

  /// This manifest summarized as a history entry — the previous server state
  /// collapses into this when a new backup is published.
  RemoteBackupManifestEntry toEntry() => RemoteBackupManifestEntry(
        backupId: backupId,
        createdAtUtc: createdAtUtc,
        coreZipObject: coreZipObject,
        coreZipSha256: coreZipSha256,
        coreZipBytes: coreZipBytes,
        mediaCount: mediaCount,
        mediaBytes: mediaBytes,
      );

  /// Composes the next manifest's history: the previous manifest's head and
  /// its tail, deduplicated by backupId and capped at
  /// [kRemoteBackupRetention]. The *new* head is not part of its own
  /// history — it lives in the manifest's own fields.
  static List<RemoteBackupManifestEntry> mergeHistory(
    RemoteBackupManifest? previous,
  ) {
    final candidates = <RemoteBackupManifestEntry>[
      if (previous != null) previous.toEntry(),
      if (previous != null) ...previous.history,
    ];
    final seen = <String>{};
    return candidates
        .where((e) => e.backupId.isNotEmpty && seen.add(e.backupId))
        .take(kRemoteBackupRetention)
        .toList();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': kRemoteBackupManifestSchema,
        'backupId': backupId,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'deviceLabel': deviceLabel,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'platform': platform,
        'driftSchema': driftSchema,
        'catalogSchema': catalogSchema,
        'coreZipObject': coreZipObject,
        'coreZipSha256': coreZipSha256,
        'coreZipBytes': coreZipBytes,
        'mediaCount': mediaCount,
        'mediaBytes': mediaBytes,
        'history': [for (final e in history) e.toJson()],
      };

  static RemoteBackupManifest fromJson(Map<String, dynamic> json) {
    final schema = (json['schema'] as int?) ?? 0;
    if (schema > kRemoteBackupManifestSchema) {
      throw RemoteBackupManifestFutureVersion();
    }
    final historyRaw = json['history'];
    return RemoteBackupManifest(
      backupId: (json['backupId'] as String?) ?? '',
      createdAtUtc:
          DateTime.tryParse((json['createdAtUtc'] as String?) ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deviceId: (json['deviceId'] as String?) ?? '',
      deviceLabel: (json['deviceLabel'] as String?) ?? '',
      appVersion: (json['appVersion'] as String?) ?? '',
      buildNumber: (json['buildNumber'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? '',
      driftSchema: (json['driftSchema'] as int?) ?? 0,
      catalogSchema: (json['catalogSchema'] as int?) ?? 0,
      coreZipObject: (json['coreZipObject'] as String?) ?? '',
      coreZipSha256: (json['coreZipSha256'] as String?) ?? '',
      coreZipBytes: (json['coreZipBytes'] as int?) ?? 0,
      mediaCount: (json['mediaCount'] as int?) ?? 0,
      mediaBytes: (json['mediaBytes'] as int?) ?? 0,
      history: [
        if (historyRaw is List)
          for (final e in historyRaw)
            if (e is Map<String, dynamic>) RemoteBackupManifestEntry.fromJson(e),
      ],
    );
  }

  static RemoteBackupManifest fromBytes(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Remote manifest is not a JSON object');
    }
    return fromJson(decoded);
  }
}

/// `meta.json` inside `core.zip` — describes the archive for restore-side
/// guards (schema versions, source app version).
class BackupArchiveMeta {
  const BackupArchiveMeta({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.deviceLabel,
    required this.driftSchema,
    required this.catalogSchema,
    required this.createdAtUtc,
    required this.hasCollection,
    required this.hasCatalog,
    required this.hasMediaDb,
    required this.prefsCount,
  });

  final String appVersion;
  final String buildNumber;
  final String platform;
  final String deviceLabel;
  final int driftSchema;
  final int catalogSchema;
  final DateTime createdAtUtc;

  /// Whether the official-Anki files existed at snapshot time. A missing
  /// collection (engine never used) must restore as "delete nothing", not
  /// "overwrite with garbage".
  final bool hasCollection;
  final bool hasCatalog;
  final bool hasMediaDb;
  final int prefsCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'platform': platform,
        'deviceLabel': deviceLabel,
        'driftSchema': driftSchema,
        'catalogSchema': catalogSchema,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'hasCollection': hasCollection,
        'hasCatalog': hasCatalog,
        'hasMediaDb': hasMediaDb,
        'prefsCount': prefsCount,
      };

  static BackupArchiveMeta fromJson(Map<String, dynamic> json) =>
      BackupArchiveMeta(
        appVersion: (json['appVersion'] as String?) ?? '',
        buildNumber: (json['buildNumber'] as String?) ?? '',
        platform: (json['platform'] as String?) ?? '',
        deviceLabel: (json['deviceLabel'] as String?) ?? '',
        driftSchema: (json['driftSchema'] as int?) ?? 0,
        catalogSchema: (json['catalogSchema'] as int?) ?? 0,
        createdAtUtc:
            DateTime.tryParse((json['createdAtUtc'] as String?) ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        hasCollection: (json['hasCollection'] as bool?) ?? false,
        hasCatalog: (json['hasCatalog'] as bool?) ?? false,
        hasMediaDb: (json['hasMediaDb'] as bool?) ?? false,
        prefsCount: (json['prefsCount'] as int?) ?? 0,
      );
}

/// One media object in `media_manifest.json`: the content hash doubles as the
/// remote object name, so uploads are naturally deduplicated.
class MediaManifestEntry {
  const MediaManifestEntry({required this.sha256, required this.bytes});

  final String sha256;
  final int bytes;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'sha256': sha256, 'bytes': bytes};

  static MediaManifestEntry fromJson(Map<String, dynamic> json) =>
      MediaManifestEntry(
        sha256: (json['sha256'] as String?) ?? '',
        bytes: (json['bytes'] as int?) ?? 0,
      );
}

Map<String, MediaManifestEntry> parseMediaManifest(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('media_manifest.json is not a JSON object');
  }
  return <String, MediaManifestEntry>{
    for (final entry in decoded.entries)
      if (entry.value is Map<String, dynamic>)
        entry.key: MediaManifestEntry.fromJson(
          entry.value as Map<String, dynamic>,
        ),
  };
}

String encodeMediaManifest(Map<String, MediaManifestEntry> manifest) =>
    jsonEncode(<String, dynamic>{
      for (final entry in manifest.entries) entry.key: entry.value.toJson(),
    });
