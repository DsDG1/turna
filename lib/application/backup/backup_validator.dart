// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/application/backup/backup_schema.dart';
import 'package:turna/service/locator.dart';

/// One validation finding: a stable machine code plus a user-presentable
/// message. Never contains raw exception text, file paths or secrets.
class BackupValidationIssue {
  const BackupValidationIssue(this.code, this.userMessage, {this.fatal = true});

  final String code;
  final String userMessage;

  /// Non-fatal issues (e.g. unknown keys from a newer backup) are reported
  /// but do not block the import — the apply step skips what it does not
  /// know, which is safe because it only ever writes policy-covered keys.
  final bool fatal;

  @override
  String toString() => '$code: $userMessage';
}

/// Outcome of validating a candidate backup before anything is written.
class BackupValidationResult {
  const BackupValidationResult({required this.document, required this.issues});

  /// Parsed document when valid, otherwise null.
  final LocalBackupDocument? document;

  /// All issues found (empty when valid).
  final List<BackupValidationIssue> issues;

  bool get isValid => document != null && issues.every((issue) => !issue.fatal);

  static BackupValidationResult fail(BackupValidationIssue issue) =>
      BackupValidationResult(document: null, issues: [issue]);
}

/// Pre-import validation gate. Everything here must pass BEFORE any user
/// state is touched — a file that fails validation never reaches prefs, the
/// database or the filesystem.
abstract final class BackupValidator {
  /// Hard upper bound for a local export file. A legit prefs snapshot is a
  /// few hundred KB; anything past this is a wrong file (or an attempt to
  /// smuggle a course/media archive through the JSON import path).
  static const int maxLocalExportBytes = 32 * 1024 * 1024;

  /// Validates a local export file: size, JSON shape, schema version, app
  /// id, per-key types/ranges and the v2 integrity digest.
  static Future<BackupValidationResult> validateLocalExportFile(
    String path, {
    String? expectedAppId,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return BackupValidationResult.fail(const BackupValidationIssue(
        'backup.fileMissing',
        '找不到所选文件，可能已被移动或删除。',
      ));
    }
    final size = await file.length();
    if (size > maxLocalExportBytes) {
      return BackupValidationResult.fail(BackupValidationIssue(
        'backup.tooLarge',
        '文件过大（${(size / (1024 * 1024)).toStringAsFixed(1)} MB），'
            '不是有效的设置与进度备份。',
      ));
    }
    final raw = await file.readAsString();
    return validateLocalExportJson(raw, expectedAppId: expectedAppId);
  }

  /// Pure-JSON variant used by tests and the remote restore staging path.
  static BackupValidationResult validateLocalExportJson(
    String raw, {
    String? expectedAppId,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return BackupValidationResult.fail(const BackupValidationIssue(
        'backup.notJson',
        '文件内容不是有效的 JSON，无法作为备份导入。',
      ));
    }
    if (decoded is! Map<String, dynamic>) {
      return BackupValidationResult.fail(const BackupValidationIssue(
        'backup.notObject',
        '备份文件的顶层结构不正确，可能已损坏。',
      ));
    }

    final LocalBackupDocument document;
    try {
      document = LocalBackupDocument.fromMap(decoded);
    } on BackupSchemaException catch (error) {
      return BackupValidationResult.fail(
        BackupValidationIssue(error.code, error.userMessage),
      );
    }

    if (document.appId.isEmpty) {
      return BackupValidationResult.fail(const BackupValidationIssue(
        'backup.missingAppId',
        '备份文件未标明来源应用，无法确认数据归属。',
      ));
    }
    if (expectedAppId != null &&
        document.appId.isNotEmpty &&
        document.appId != expectedAppId) {
      return BackupValidationResult.fail(BackupValidationIssue(
        'backup.foreignApp',
        '该备份来自其他应用（${document.appId}），不能导入到本应用。',
      ));
    }

    final progress = document.progress;
    if (progress == null && !document.hasCoursePayload) {
      return BackupValidationResult.fail(const BackupValidationIssue(
        'backup.empty',
        '备份文件不包含任何可导入的内容。',
      ));
    }

    if (progress != null) {
      final issues = _validateProgress(progress);
      if (issues.any((issue) => issue.fatal)) {
        return BackupValidationResult(document: null, issues: issues);
      }
      final integrityIssue = _validateIntegrity(decoded, progress);
      if (integrityIssue != null) {
        return BackupValidationResult.fail(integrityIssue);
      }
    }

    return BackupValidationResult(document: document, issues: const []);
  }

  /// Per-key type and range checks driven by the shared manifest policy.
  /// Values that are merely out of range are clamped during apply; values
  /// with the wrong type are rejected — silently coercing them could corrupt
  /// unrelated state.
  static List<BackupValidationIssue> _validateProgress(
    Map<String, dynamic> progress,
  ) {
    final issues = <BackupValidationIssue>[];
    progress.forEach((key, value) {
      final entry = BackupManifestPolicy.entryFor(key);
      if (entry == null) {
        // Unknown keys are skipped at apply time, but a file whose payload
        // is full of unknown keys is suspicious — surface the first few.
        if (issues.length < 3) {
          issues.add(BackupValidationIssue(
            'backup.unknownKey',
            '备份包含本版本不认识的设置项（$key），该项将被忽略。',
            fatal: false,
          ));
        }
        return;
      }
      if (!_typeMatches(entry, value)) {
        issues.add(BackupValidationIssue(
          'backup.typeMismatch',
          '设置项 $key 的数据类型不正确，为避免损坏数据已停止导入。',
        ));
      }
    });
    return issues;
  }

  static bool _typeMatches(BackupPrefEntry entry, Object? value) {
    BackupPrefType? actual;
    if (value is bool) {
      actual = BackupPrefType.bool_;
    } else if (value is int) {
      actual = BackupPrefType.int_;
    } else if (value is double) {
      actual = BackupPrefType.double_;
    } else if (value is String) {
      actual = BackupPrefType.string;
    } else if (value is List) {
      actual = BackupPrefType.stringList;
    }
    if (actual == null) return false;
    if (actual == BackupPrefType.stringList) {
      return (value as List).every((item) => item is String);
    }
    // JSON has no int/double distinction — accept an int literal for a
    // double-declared key (the apply step converts it).
    if (actual == BackupPrefType.int_ &&
        entry.acceptsType(BackupPrefType.double_)) {
      return true;
    }
    return entry.acceptsType(actual);
  }

  static BackupValidationIssue? _validateIntegrity(
    Map<String, dynamic> decoded,
    Map<String, dynamic> progress,
  ) {
    final integrity = decoded['integrity'];
    if (integrity is! Map<String, dynamic>) return null; // v1: no digest
    final expected = integrity['progressSha256'];
    if (expected is! String || expected.isEmpty) return null;
    if (BackupEnvelopeWriter.progressDigest(progress) != expected) {
      return const BackupValidationIssue(
        'backup.integrityMismatch',
        '备份内容校验失败，文件可能在导出后被修改或损坏。',
      );
    }
    return null;
  }

  /// Range clamps applied when a backup is written into prefs. Out-of-range
  /// values never enter live state; the clamp mirrors each setter's own
  /// normalization so restore behaves exactly like manual input.
  static Object? clampValue(String key, Object? value) {
    switch (key) {
      case LocalStateKeys.ttsSpeed:
        return value is num ? value.toDouble().clamp(0.5, 2.0) : value;
      case LocalStateKeys.dailyReminderHour:
        return value is num ? value.toInt().clamp(0, 23) : value;
      case LocalStateKeys.dailyReminderMinute:
        return value is num ? value.toInt().clamp(0, 59) : value;
      case LocalStateKeys.textScale:
        return value is num ? value.toInt().clamp(100, 200) : value;
      case LocalStateKeys.cardTextScale:
        return value is num ? value.toInt().clamp(100, 200) : value;
      case LocalStateKeys.srsDesiredRetention:
        return value is num ? value.toDouble().clamp(0.8, 0.95) : value;
      case LocalStateKeys.ankiLiteThreshold:
        return value is num ? value.toInt().clamp(0, 10000) : value;
      case 'anki.dailyNewLimit':
        return value is num ? value.toInt().clamp(0, 999) : value;
      case 'anki.dailyReviewLimit':
        return value is num ? value.toInt().clamp(0, 999) : value;
      default:
        return value;
    }
  }
}
