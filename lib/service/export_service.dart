// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/application/backup/backup_restore_journal.dart';
import 'package:turna/application/backup/backup_schema.dart';
import 'package:turna/application/backup/backup_validator.dart';
import 'package:turna/application/restore/post_restore_reload_registry.dart';
import 'package:turna/application/restore_normalization_service.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Outcome of a validated, journaled import. Every field describes what
/// actually happened — there is no "success" state that hides skipped work.
class ImportOutcome {
  const ImportOutcome({
    required this.progressRestored,
    required this.legacyCoursePayloadIgnored,
    required this.reload,
  });

  /// True when the progress/settings snapshot was validated, written and
  /// committed.
  final bool progressRestored;

  /// v1 files may carry a `course` section with copies of the bundled course
  /// assets. They contain no user data and are never applied; this flag lets
  /// the UI say so instead of promising a restart that would do nothing.
  final bool legacyCoursePayloadIgnored;

  /// Per-step runtime reload report (providers, audio, reminders, …).
  final PostRestoreReloadReport reload;
}

/// Builds / restores the local JSON backup file.
///
/// Export writes the versioned v2 envelope (see [BackupEnvelopeWriter]) with
/// a single prefs snapshot driven by [BackupManifestPolicy] — the same policy
/// the remote WebDAV snapshot uses, so both paths carry an identical settings
/// and progress set.
///
/// Import is a validate-then-commit pipeline: nothing is written before
/// [BackupValidator] accepts the file (size / JSON shape / schema version /
/// app id / per-key types), the write runs under [BackupRestoreJournal] with
/// a before-image, and every runtime consumer is refreshed through
/// [PostRestoreReloadRegistry] before the journal commits. A failure at any
/// step rolls every touched key back to its pre-import value.
///
/// The legacy "include course content" export option is intentionally gone:
/// the `course` section only ever contained copies of bundled course assets
/// (no user data), so exporting it wasted space and importing it promised a
/// restart that would do nothing. Old files with a course section import
/// their progress and report the rest as ignored.
class ExportService {
  ExportService(this._prefs);

  final AppPrefs _prefs;

  /// Exports the unified progress + settings snapshot.
  Future<File> export() async {
    final info = await PackageInfo.fromPlatform();
    final payload = BackupEnvelopeWriter.build(
      appId: info.packageName,
      appVersion: info.version,
      buildNumber: info.buildNumber,
      language: _prefs.currentLanguage.getValue(),
      progress: _readProgress(),
    );

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/turna_export_$ts.json');
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  Future<void> share(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Turna export',
    );
  }

  /// Validates, applies and commits a backup file. Throws
  /// [BackupSchemaException] with a stable code for every rejection; on any
  /// failure after writing began, the before-image is restored first.
  Future<ImportOutcome> importFromFile(String path) async {
    String? expectedAppId;
    try {
      expectedAppId = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {
      // PackageInfo unavailable (tests): skip the app-id cross-check.
    }

    final validation = await BackupValidator.validateLocalExportFile(
      path,
      expectedAppId: expectedAppId,
    );
    final fatalIssue =
        validation.issues.where((issue) => issue.fatal).firstOrNull;
    if (!validation.isValid || fatalIssue != null) {
      final issue = fatalIssue ?? validation.issues.first;
      throw BackupSchemaException(issue.code, issue.userMessage);
    }
    final document = validation.document!;
    final progress = document.progress;
    if (progress == null) {
      // A v1 file with only a course payload: nothing user-owned to apply.
      return ImportOutcome(
        progressRestored: false,
        legacyCoursePayloadIgnored: document.hasCoursePayload,
        reload: PostRestoreReloadReport(reloaded: const [], failures: const {}),
      );
    }

    final beforeImage = _captureBeforeImage(progress);
    final restoreId = 'import-${DateTime.now().millisecondsSinceEpoch}';
    await BackupRestoreJournal.begin(_prefs, restoreId, beforeImage);

    PostRestoreReloadReport reloadReport;
    try {
      await _writeProgress(progress);
      if (getIt.isRegistered<RestoreNormalizationService>()) {
        await getIt<RestoreNormalizationService>().normalize();
      }
      reloadReport =
          await PostRestoreReloadRegistry.withDefaultSteps().reloadAll();
    } catch (error) {
      // Roll the touched keys back to the before-image, then resync whatever
      // providers already picked up the half-applied values.
      await BackupRestoreJournal.rollbackPending(_prefs);
      try {
        await PostRestoreReloadRegistry.withDefaultSteps().reloadAll();
      } catch (_) {
        // Best-effort resync — the prefs rollback itself already succeeded.
      }
      throw BackupSchemaException(
        'backup.applyFailed',
        '导入过程中出现错误，已恢复到导入前的状态。',
      );
    }
    await BackupRestoreJournal.commit(_prefs);

    return ImportOutcome(
      progressRestored: true,
      legacyCoursePayloadIgnored: document.hasCoursePayload,
      reload: reloadReport,
    );
  }

  /// Reads every backup-eligible prefs key (exact + prefix) with its policy
  /// type, sanitizing secrets at this boundary.
  Map<String, dynamic> _readProgress() {
    final out = <String, dynamic>{};
    final prefs = _prefs.preferences;
    // Only export keys that actually exist in the store — the streaming
    // getters require a non-null default and cannot distinguish a missing
    // key from a default value, so we filter by the live key set.
    final keys = prefs.getKeys().getValue();
    for (final key in keys) {
      final entry = BackupManifestPolicy.entryFor(key);
      if (entry == null) continue;
      final Object? value;
      switch (entry.primaryType) {
        case BackupPrefType.bool_:
          value = prefs.getBool(key, defaultValue: false).getValue();
        case BackupPrefType.int_:
          value = prefs.getInt(key, defaultValue: 0).getValue();
        case BackupPrefType.double_:
          value = prefs.getDouble(key, defaultValue: 0.0).getValue();
        case BackupPrefType.string:
          value = prefs.getString(key, defaultValue: '').getValue();
        case BackupPrefType.stringList:
          value = prefs.getStringList(key, defaultValue: const []).getValue();
      }
      final sanitized =
          BackupManifestPolicy.sanitizeForSerialization(key, value);
      if (sanitized != null) out[key] = sanitized;
    }
    return out;
  }

  /// Snapshot of every key the import is about to touch, used by the restore
  /// journal for rollback. Keys absent from the store map to null.
  Map<String, Object?> _captureBeforeImage(Map<String, dynamic> progress) {
    final before = <String, Object?>{};
    final prefs = _prefs.preferences;
    final liveKeys = prefs.getKeys().getValue();
    for (final key in progress.keys) {
      final entry = BackupManifestPolicy.entryFor(key);
      if (entry == null) continue; // unknown keys are never written
      if (!liveKeys.contains(key)) {
        before[key] = null;
        continue;
      }
      switch (entry.primaryType) {
        case BackupPrefType.bool_:
          before[key] = prefs.getBool(key, defaultValue: false).getValue();
        case BackupPrefType.int_:
          before[key] = prefs.getInt(key, defaultValue: 0).getValue();
        case BackupPrefType.double_:
          before[key] = prefs.getDouble(key, defaultValue: 0.0).getValue();
        case BackupPrefType.string:
          before[key] = prefs.getString(key, defaultValue: '').getValue();
        case BackupPrefType.stringList:
          before[key] =
              prefs.getStringList(key, defaultValue: const []).getValue();
      }
    }
    return before;
  }

  /// Writes the validated progress snapshot with range clamping. Only keys
  /// covered by the manifest policy are ever written — unknown keys in the
  /// file are ignored (the validator already flagged them).
  Future<void> _writeProgress(Map<String, dynamic> data) async {
    for (final key in data.keys) {
      final entry = BackupManifestPolicy.entryFor(key);
      if (entry == null) continue;
      final value = BackupValidator.clampValue(key, data[key]);
      switch (entry.primaryType) {
        case BackupPrefType.bool_:
          if (value is bool) await _prefs.setBool(key, value: value);
        case BackupPrefType.int_:
          if (value is int) await _prefs.setInt(key, value);
        case BackupPrefType.double_:
          if (value is num) await _prefs.setDouble(key, value.toDouble());
        case BackupPrefType.string:
          if (value is String) await _prefs.setString(key, value);
        case BackupPrefType.stringList:
          if (value is List) {
            await _prefs.setStringList(
              key,
              value.whereType<String>().toList(),
            );
          }
      }
    }
  }
}
