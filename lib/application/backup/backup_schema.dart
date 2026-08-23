// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:crypto/crypto.dart' as crypto;

/// Backup envelope schema versions.
///
/// * v1 — legacy local export: `meta.schema == 1`, `meta.app`, sections
///   `progress` (prefs snapshot) and `course` (bundled course assets, no user
///   data). Read-only compatibility.
/// * v2 — current unified envelope: `meta.schemaVersion == 2`, `meta.appId`,
///   sections `progress` + `integrity`. Written by the local export; the
///   remote WebDAV archive keeps its own manifest format (see
///   backup_manifest.dart) but shares the prefs policy.
abstract final class BackupSchemaVersion {
  static const int v1 = 1;
  static const int v2 = 2;

  /// Highest version this build can write.
  static const int currentWritable = v2;

  /// Highest version this build can read.
  static const int currentReadable = v2;
}

/// Structured, user-presentable backup failure. Codes are stable identifiers
/// used by tests and (future) localized message lookup — never show raw
/// exception text to users.
class BackupSchemaException implements Exception {
  const BackupSchemaException(this.code, this.userMessage);

  /// Stable machine code, e.g. `backup.futureSchema`.
  final String code;

  /// Human-readable, secret-free message.
  final String userMessage;

  @override
  String toString() => 'BackupSchemaException($code): $userMessage';
}

/// Parsed, version-normalized view of a local export file.
///
/// Handles both v1 and v2 envelopes on read; v1 `meta` fields are mapped onto
/// the v2 names so downstream validation sees one shape.
class LocalBackupDocument {
  LocalBackupDocument({
    required this.schemaVersion,
    required this.appId,
    required this.appVersion,
    required this.createdAtUtc,
    required this.progress,
    required this.hasCoursePayload,
  });

  final int schemaVersion;
  final String appId;
  final String appVersion;
  final String createdAtUtc;

  /// Raw progress section (prefs snapshot) — validated separately by
  /// BackupValidator before anything is written.
  final Map<String, dynamic>? progress;

  /// v1 files may carry a `course` section (bundled course asset copies).
  /// They contain no user data and are never applied; the flag exists only so
  /// the import UI can explain that honestly instead of promising a restart
  /// that would do nothing.
  final bool hasCoursePayload;

  factory LocalBackupDocument.fromMap(Map<String, dynamic> decoded) {
    final meta = decoded['meta'];
    if (meta is! Map<String, dynamic>) {
      throw const BackupSchemaException(
        'backup.missingMeta',
        '备份文件缺少元数据，可能已损坏。',
      );
    }
    final schemaVersion = _readSchemaVersion(meta);
    if (schemaVersion > BackupSchemaVersion.currentReadable) {
      throw BackupSchemaException(
        'backup.futureSchema',
        '该备份来自更新版本的应用（格式 v$schemaVersion）。请先升级应用后再导入。',
      );
    }
    return LocalBackupDocument(
      schemaVersion: schemaVersion,
      appId: _readAppId(meta),
      appVersion: (meta['appVersion'] ?? meta['version']) as String? ?? '',
      createdAtUtc:
          (meta['createdAtUtc'] ?? meta['exportedAt']) as String? ?? '',
      progress: decoded['progress'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded['progress'] as Map)
          : null,
      hasCoursePayload: decoded['course'] is Map,
    );
  }

  static int _readSchemaVersion(Map<String, dynamic> meta) {
    final raw = meta['schemaVersion'] ?? meta['schema'];
    if (raw is int && raw >= 1) return raw;
    if (raw is num && raw >= 1) return raw.toInt();
    throw const BackupSchemaException(
      'backup.invalidSchemaVersion',
      '备份文件的格式版本无法识别，可能已损坏。',
    );
  }

  static String _readAppId(Map<String, dynamic> meta) {
    final appId = meta['appId'] ?? meta['app'];
    return appId is String ? appId : '';
  }
}

/// Builds the v2 envelope written by the local export path. The progress map
/// is written with sorted keys and the `integrity` section carries its
/// sha256, so tampering or truncation is detectable on import.
abstract final class BackupEnvelopeWriter {
  static Map<String, dynamic> build({
    required String appId,
    required String appVersion,
    required String buildNumber,
    required String language,
    required Map<String, dynamic> progress,
  }) {
    final sortedProgress = Map<String, dynamic>.fromEntries(
      progress.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return <String, dynamic>{
      'meta': <String, dynamic>{
        'schemaVersion': BackupSchemaVersion.v2,
        'appId': appId,
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'language': language,
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'contents': <String>['progress'],
      },
      'progress': sortedProgress,
      'integrity': <String, dynamic>{
        'algorithm': 'sha256',
        'progressSha256': progressDigest(sortedProgress),
        'progressKeyCount': sortedProgress.length,
      },
    };
  }

  /// Canonical digest of a progress snapshot: keys sorted, then JSON encoded.
  static String progressDigest(Map<String, dynamic> progress) {
    final sorted = Map<String, dynamic>.fromEntries(
      progress.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return crypto.sha256.convert(utf8.encode(jsonEncode(sorted))).toString();
  }
}
