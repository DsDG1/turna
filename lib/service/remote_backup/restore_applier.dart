// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

// Project imports:
import 'package:turna/application/anki/anki_import_platform_io.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/restore_staging.dart';

enum RestoreApplyOutcome {
  /// No staged restore pending — normal boot.
  noPending,

  /// Restore applied and staging cleaned.
  applied,

  /// Restore refused (backup from a newer app / failed verification);
  /// staging kept for a retry after an app upgrade.
  blocked,

  /// Apply started but failed midway; marker kept so the next boot retries
  /// (every apply step is idempotent).
  retryScheduled,
}

/// Applies a staged remote restore at boot, before any database is opened.
///
/// Mounted inside `setupLocator()` right after prefs are ready and before
/// `_openAndSeedCourseDatabase()` — at that point neither the drift database
/// nor the official Anki engine has touched the files, so plain
/// `.restore-partial` → rename replacement is safe.
///
/// Crash safety: the marker file is the commit point (written last by the
/// downloader). Every apply step is idempotent, so a crash mid-apply simply
/// re-runs on the next boot.
class RestoreApplier {
  RestoreApplier({
    required AppPrefs prefs,
    required Directory appSupport,
    required Directory appDocuments,
    required Directory officialProfileRoot,
    required int currentDriftSchema,
    required int currentCatalogSchema,
  })  : _prefs = prefs,
        _appSupport = appSupport,
        _appDocuments = appDocuments,
        _officialProfileRoot = officialProfileRoot,
        _currentDriftSchema = currentDriftSchema,
        _currentCatalogSchema = currentCatalogSchema;

  final AppPrefs _prefs;
  final Directory _appSupport;
  final Directory _appDocuments;
  final Directory _officialProfileRoot;
  final int _currentDriftSchema;
  final int _currentCatalogSchema;

  Directory get _staging => RestoreStagingLayout.root(_appSupport);

  Future<RestoreApplyOutcome> applyIfPending() async {
    final marker = RestoreStagingLayout.marker(_appSupport);
    if (!await marker.exists()) return RestoreApplyOutcome.noPending;
    final markerPayload =
        RestoreStagingLayout.decodeMarker(await marker.readAsString());
    if (markerPayload == null) {
      await _discardStaging();
      return RestoreApplyOutcome.noPending;
    }

    try {
      await _verify();
    } on Object catch (e) {
      await _setBlockedReason('远程恢复未执行：$e');
      await _discardStaging();
      return RestoreApplyOutcome.blocked;
    }

    try {
      await _applyPrefs();
      await _applyDatabases();
      await _applyMedia();
      await _prefs.preferences.setString(LocalStateKeys.remoteBackupLastRestoredAt,
          DateTime.now().toUtc().toIso8601String());
      await _prefs.preferences
          .remove(LocalStateKeys.remoteBackupRestoreBlockedReason);
      await _discardStaging();
      return RestoreApplyOutcome.applied;
    } on Object {
      // Keep the marker: next boot re-applies from scratch (idempotent).
      return RestoreApplyOutcome.retryScheduled;
    }
  }

  /// Refuses backups this app cannot safely open.
  Future<void> _verify() async {
    final meta = _readMeta();
    if (meta.driftSchema > _currentDriftSchema ||
        meta.catalogSchema > _currentCatalogSchema) {
      throw '备份来自更新的应用版本（需 schema ≤ $_currentDriftSchema/$_currentCatalogSchema，备份为 ${meta.driftSchema}/${meta.catalogSchema}），请先升级应用';
    }

    final stagedCourse = _stagedFile(RestoreStagingLayout.courseDbEntry);
    ensureOfficialAnkiSqlite();
    final db = sql.sqlite3.open(stagedCourse.path, mode: sql.OpenMode.readOnly);
    try {
      final version = db.select('PRAGMA user_version').first['user_version']
          as int?;
      if (version == null || version > _currentDriftSchema) {
        throw '备份内数据库 schema ($version) 高于当前应用支持版本';
      }
    } finally {
      db.dispose();
    }

    // SHA256SUMS re-verification: the archive was checked at download time,
    // but the staging area sat on disk across at least one reboot.
    final sums = _stagedFile(RestoreStagingLayout.sumsEntry);
    if (!await sums.exists()) {
      throw '缺少 SHA256SUMS';
    }
    for (final line in sums.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final match = RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(line.trim());
      if (match == null) throw 'SHA256SUMS 行格式错误';
      final digest =
          ankiHashFileSha256(_stagedFile(match.group(2)!).path);
      if (digest != match.group(1)!) throw '文件校验失败: ${match.group(2)}';
    }
  }

  BackupArchiveMeta _readMeta() {
    final raw = _stagedFile(RestoreStagingLayout.metaEntry).readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('meta.json 格式错误');
    }
    return BackupArchiveMeta.fromJson(decoded);
  }

  Future<void> _applyPrefs() async {
    final raw = _stagedFile(RestoreStagingLayout.prefsEntry).readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('prefs.json 格式错误');
    }
    final preferences = _prefs.preferences;
    for (final entry in decoded.entries) {
      if (entry.key.startsWith('remoteBackup.')) continue;
      final value = entry.value;
      switch (value) {
        case bool v:
          await preferences.setBool(entry.key, v);
        case int v:
          await preferences.setInt(entry.key, v);
        case double v:
          await preferences.setDouble(entry.key, v);
        case String v:
          await preferences.setString(entry.key, v);
        case List v:
          await preferences.setStringList(
              entry.key, v.map((e) => e.toString()).toList());
        case null:
          // Skip nulls (defensive; the packer never writes them).
          break;
      }
    }
  }

  Future<void> _applyDatabases() async {
    final meta = _readMeta();
    await _replaceDatabase(
      staged: _stagedFile(RestoreStagingLayout.courseDbEntry),
      target: File(p.join(_appDocuments.path, 'course.db')),
      mustExist: true,
    );
    if (meta.hasCollection) {
      await _replaceDatabase(
        staged: _stagedFile(RestoreStagingLayout.collectionEntry),
        target: File(p.join(_officialProfileRoot.path, 'collection.anki2')),
        mustExist: true,
      );
    }
    if (meta.hasCatalog) {
      await _replaceDatabase(
        staged: _stagedFile(RestoreStagingLayout.catalogEntry),
        target:
            File(p.join(_officialProfileRoot.path, 'official_catalog.sqlite')),
        mustExist: true,
      );
    }
    if (meta.hasMediaDb) {
      await _replaceDatabase(
        staged: _stagedFile(RestoreStagingLayout.mediaDbEntry),
        target: File(p.join(_officialProfileRoot.path, 'collection.media.db2')),
        mustExist: true,
      );
    }
  }

  /// Copy + atomic rename, dropping stale WAL/SHM sidecars so the fresh
  /// database never replays the previous instance's journal.
  Future<void> _replaceDatabase({
    required File staged,
    required File target,
    required bool mustExist,
  }) async {
    if (!await staged.exists()) {
      if (mustExist) {
        throw StateError('staged file missing: ${p.basename(staged.path)}');
      }
      return;
    }
    await target.parent.create(recursive: true);
    for (final sidecar in [
      File('${target.path}-wal'),
      File('${target.path}-shm'),
      File('${target.path}-journal'),
    ]) {
      if (await sidecar.exists()) await sidecar.delete();
    }
    final partial = File('${target.path}.restore-partial');
    if (await partial.exists()) await partial.delete();
    await staged.copy(partial.path);
    await partial.rename(target.path);
  }

  Future<void> _applyMedia() async {
    final mediaManifest = parseMediaManifest(
        _stagedFile(RestoreStagingLayout.mediaManifestEntry)
            .readAsStringSync());
    final mediaDir = RestoreStagingLayout.media(_appSupport);
    for (final entry in mediaManifest.entries) {
      final logical = entry.key;
      if (logical.contains('..') || p.isAbsolute(logical)) {
        throw FormatException('不安全的媒体路径: $logical');
      }
      final String targetPath;
      if (logical.startsWith('anki_media/')) {
        targetPath = p.join(_appDocuments.path, logical);
      } else if (logical.startsWith('official/collection.media/')) {
        targetPath = p.join(_officialProfileRoot.path,
            logical.substring('official/'.length));
      } else {
        throw FormatException('未知媒体前缀: $logical');
      }
      final source = File(p.join(mediaDir.path, entry.value.sha256));
      if (!await source.exists()) {
        throw StateError('媒体对象缺失: ${entry.value.sha256.substring(0, 8)}…');
      }
      final target = File(targetPath);
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    }
  }

  File _stagedFile(String name) => File(p.join(_staging.path, name));

  Future<void> _setBlockedReason(String reason) =>
      _prefs.preferences.setString(
          LocalStateKeys.remoteBackupRestoreBlockedReason, reason);

  Future<void> _discardStaging() async {
    if (await _staging.exists()) {
      await _staging.delete(recursive: true);
    }
  }
}
