// Package imports:
import 'dart:isolate';

import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'anki_media_delete_report.dart';
import 'anki_media_platform_stub.dart'
    if (dart.library.io) 'anki_media_platform_io.dart' as platform;
import 'package:turna/domain/audio/vocab_audio_resolver.dart';

/// Resolves Anki media assets (audio/images) from the extracted media directory.
///
/// Anki media files are stored in `<app docs>/anki_media/<importId>/` after
/// import. This resolver maps `anki://` prefixed paths to local file paths.
///
/// Implements [VocabAudioResolver] so it integrates with the existing
/// [AudioController] pipeline.
@lazySingleton
class AnkiAudioResolver implements VocabAudioResolver {
  /// Base directory for all Anki media files.
  static const String _mediaBaseDir = 'anki_media';
  static const String _rollbackSeparator = '.__rollback__';
  static const String _rollbackGenerationSeparator = '.__generation__';

  /// Prefix used in asset paths to identify Anki media references.
  static const String ankiScheme = 'anki://';

  String? _cachedDocsDir;

  /// Result of copying one import's media. `availableCount` includes files
  /// that were already present, which keeps re-import diagnostics truthful.
  Future<AnkiMediaCopyReport> copyMedia({
    required String sourceDir,
    required String importId,
    required Map<String, String> mediaMapping,
  }) async {
    // Resolve the target directory here: getAnkiDocumentsPath goes through
    // path_provider, which is only usable on the platform (main) isolate.
    final targetDir = await getImportMediaPath(importId);
    if (mediaMapping.isEmpty) {
      platform.ankiCreateDirectory(targetDir);
      return const AnkiMediaCopyReport();
    }

    // The copy loop is thousands of synchronous file I/O calls — running it
    // on the main isolate froze the import screen's progress animation.
    return Isolate.run(() => _copyMediaEntries(
          sourceDir: sourceDir,
          targetDir: targetDir,
          mediaMapping: mediaMapping,
        ));
  }

  /// Get the base media directory path.
  Future<String> getMediaBasePath() async {
    if (_cachedDocsDir != null) return _cachedDocsDir!;
    _cachedDocsDir = await platform.getAnkiDocumentsPath();
    return _cachedDocsDir!;
  }

  /// Get the media directory for a specific import.
  Future<String> getImportMediaPath(String importId) async {
    final base = await getMediaBasePath();
    return p.join(base, _mediaBaseDir, importId);
  }

  /// Allocate a private sibling directory for an in-place re-import.
  ///
  /// Cards continue to reference [importId]; only the copy target uses this
  /// staging id until the database transaction is ready to commit.
  static String stagingImportId(String importId) =>
      '$importId.__staging__${DateTime.now().microsecondsSinceEpoch}';

  /// Atomically replace [targetImportId]'s media directory with a completely
  /// copied [stagingImportId] directory. The old directory remains available
  /// through the returned receipt until the surrounding database transaction
  /// commits, so a failure can restore it without mixing old and new files.
  Future<AnkiMediaSwapReceipt> swapStagedMedia({
    required String stagingImportId,
    required String targetImportId,
    required String sourceHash,
  }) async {
    final stagingPath = await getImportMediaPath(stagingImportId);
    final targetPath = await getImportMediaPath(targetImportId);
    final backupPath = '$targetPath$_rollbackSeparator'
        '${Uri.encodeComponent(sourceHash)}$_rollbackGenerationSeparator'
        '${DateTime.now().microsecondsSinceEpoch}';
    if (!platform.ankiDirectoryExists(stagingPath)) {
      throw StateError('staged Anki media directory is missing');
    }

    final hadPrevious = platform.ankiDirectoryExists(targetPath);
    var previousMoved = false;
    try {
      if (hadPrevious) {
        platform.ankiRenameDirectory(targetPath, backupPath);
        previousMoved = true;
      } else {
        // An empty rollback directory is still a durable crash marker. It
        // distinguishes "old import had no media" from "swap was committed".
        platform.ankiCreateDirectory(backupPath);
      }
      platform.ankiRenameDirectory(stagingPath, targetPath);
      return AnkiMediaSwapReceipt(
        targetPath: targetPath,
        backupPath: backupPath,
        hadPrevious: hadPrevious,
      );
    } catch (_) {
      if (previousMoved &&
          !platform.ankiDirectoryExists(targetPath) &&
          platform.ankiDirectoryExists(backupPath)) {
        platform.ankiRenameDirectory(backupPath, targetPath);
      } else if (!hadPrevious && platform.ankiDirectoryExists(backupPath)) {
        platform.ankiDeleteDirectoryBestEffort(backupPath);
      }
      rethrow;
    }
  }

  /// Restore the old directory after the enclosing database transaction
  /// fails. The staged/new directory was never product-visible at this point.
  Future<void> rollbackMediaSwap(AnkiMediaSwapReceipt receipt) async {
    final failedPath =
        '${receipt.targetPath}.__failed__${DateTime.now().microsecondsSinceEpoch}';
    if (platform.ankiDirectoryExists(receipt.targetPath)) {
      // Rename first so the canonical target name becomes available even if
      // best-effort deletion later encounters a locked file.
      platform.ankiRenameDirectory(receipt.targetPath, failedPath);
    }
    if (receipt.hadPrevious &&
        platform.ankiDirectoryExists(receipt.backupPath) &&
        !platform.ankiDirectoryExists(receipt.targetPath)) {
      platform.ankiRenameDirectory(receipt.backupPath, receipt.targetPath);
    } else if (!receipt.hadPrevious &&
        platform.ankiDirectoryExists(receipt.backupPath)) {
      platform.ankiDeleteDirectoryBestEffort(receipt.backupPath);
    }
    if (platform.ankiDirectoryExists(failedPath)) {
      platform.ankiDeleteDirectoryBestEffort(failedPath);
    }
  }

  /// Release the rollback copy after the database commit. Deletion is
  /// best-effort: a locked old file is left for the normal orphan sweep.
  Future<void> finalizeMediaSwap(AnkiMediaSwapReceipt receipt) async {
    try {
      if (platform.ankiDirectoryExists(receipt.backupPath)) {
        platform.ankiDeleteDirectoryBestEffort(receipt.backupPath);
      }
    } catch (_) {
      // The database and new canonical media are already committed. A locked
      // rollback copy is owner-less and the normal orphan sweep will retry.
    }
  }

  /// Resolve an Anki media reference to a local file path.
  ///
  /// [assetPath] format: `anki://<importId>/<filename>`
  /// Returns the absolute local file path, or null if not found.
  Future<String?> resolveMediaPath(String assetPath) async {
    if (!assetPath.startsWith(ankiScheme)) return null;

    final relativePath = assetPath.substring(ankiScheme.length);
    final base = await getMediaBasePath();
    final fullPath = p.join(base, _mediaBaseDir, relativePath);

    if (!_isWithin(p.join(base, _mediaBaseDir), fullPath)) return null;

    if (platform.ankiFileExists(fullPath)) return fullPath;
    return null;
  }

  /// Copy media files from the extracted archive to the persistent directory.
  ///
  /// [sourceDir] is the temporary extraction directory.
  /// [importId] is the import UUID.
  /// [mediaMapping] maps numeric filenames to original names.
  /// Returns the number of files copied.
  Future<int> copyMediaFiles({
    required String sourceDir,
    required String importId,
    required Map<String, String> mediaMapping,
  }) async {
    final report = await copyMedia(
      sourceDir: sourceDir,
      importId: importId,
      mediaMapping: mediaMapping,
    );
    return report.availableCount;
  }

  /// Delete all media files for an import (used during deck uninstall).
  ///
  /// Best-effort and never throws: a file still held by the audio player or
  /// a WebView stays on disk and is reported, so the uninstall saga can
  /// always finish its database steps. Leftovers become owner-less and are
  /// retried by [sweepOrphanMedia] on a later app start.
  Future<AnkiMediaDeleteReport> deleteImportMedia(String importId) async {
    final mediaPath = await getImportMediaPath(importId);
    try {
      if (!platform.ankiDirectoryExists(mediaPath)) {
        return const AnkiMediaDeleteReport();
      }
      return platform.ankiDeleteDirectoryBestEffort(mediaPath);
    } catch (_) {
      return AnkiMediaDeleteReport(
        remainingFiles: 1,
        remainingPaths: [mediaPath],
        remainingDirectories: [mediaPath],
      );
    }
  }

  /// Delete every `anki_media/<dir>` whose id no longer owns an import
  /// record. [importExists] is queried per directory name. Returns how many
  /// directories were fully removed; partially-locked ones are retried on
  /// the next call.
  Future<int> sweepOrphanMedia(
      Future<bool> Function(String importId) importExists,
      {Future<String?> Function(String importId)? sourceHashForImport}) async {
    final base = await getMediaBasePath();
    final mediaRoot = p.join(base, _mediaBaseDir);
    if (!platform.ankiDirectoryExists(mediaRoot)) return 0;
    var swept = 0;
    final directories = platform.ankiListSubdirectories(mediaRoot);

    // Resolve interrupted re-import swaps before the generic orphan pass.
    // The rollback directory name carries the incoming package hash;
    // CourseDB carries the committed hash. Their equality tells us which
    // side of the SQLite commit survived a process kill without guessing by
    // timestamps or reserving a filename that could collide with deck media.
    for (final rollbackPath in directories.where(
      (path) => p.basename(path).contains(_rollbackSeparator),
    )) {
      final rollbackName = p.basename(rollbackPath);
      final separatorAt = rollbackName.indexOf(_rollbackSeparator);
      if (separatorAt <= 0) continue;
      final importId = rollbackName.substring(0, separatorAt);
      final hashStart = separatorAt + _rollbackSeparator.length;
      final generationAt = rollbackName.indexOf(
        _rollbackGenerationSeparator,
        hashStart,
      );
      if (generationAt <= hashStart) continue;
      final incomingHash = Uri.decodeComponent(
        rollbackName.substring(hashStart, generationAt),
      );
      if (!await importExists(importId)) {
        final report = platform.ankiDeleteDirectoryBestEffort(rollbackPath);
        if (report.fullyDeleted) swept++;
        continue;
      }
      final lookupHash = sourceHashForImport;
      if (lookupHash == null) continue;
      final committedHash = await lookupHash(importId);
      final targetPath = p.join(mediaRoot, importId);
      if (committedHash != null && committedHash == incomingHash) {
        final report = platform.ankiDeleteDirectoryBestEffort(rollbackPath);
        if (report.fullyDeleted) swept++;
        continue;
      }

      final failedPath =
          '$targetPath.__failed__${DateTime.now().microsecondsSinceEpoch}';
      if (platform.ankiDirectoryExists(targetPath)) {
        platform.ankiRenameDirectory(targetPath, failedPath);
      }
      if (!platform.ankiDirectoryExists(targetPath)) {
        platform.ankiRenameDirectory(rollbackPath, targetPath);
      }
      if (platform.ankiDirectoryExists(failedPath)) {
        final report = platform.ankiDeleteDirectoryBestEffort(failedPath);
        if (report.fullyDeleted) swept++;
      }
    }

    for (final dirPath in platform.ankiListSubdirectories(mediaRoot)) {
      final importId = p.basename(dirPath);
      if (importId.contains(_rollbackSeparator)) continue;
      if (await importExists(importId)) continue;
      final report = await deleteImportMedia(importId);
      if (report.fullyDeleted) swept++;
    }
    return swept;
  }

  /// Build an `anki://` asset path for a media file.
  static String buildAssetPath(String importId, String filename) {
    return '$ankiScheme$importId/$filename';
  }

  /// Check if an asset path is an Anki media reference.
  static bool isAnkiAsset(String? path) {
    return path != null && path.startsWith(ankiScheme);
  }

  static String? _safeRelativePath(String raw) {
    final normalized = raw.replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      return null;
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '..')) return null;
    return parts.join(p.separator);
  }

  static bool _isWithin(String root, String candidate) {
    final rootPath = p.normalize(root);
    final candidatePath = p.normalize(candidate);
    if (p.equals(rootPath, candidatePath)) return true;
    final prefix =
        rootPath.endsWith(p.separator) ? rootPath : '$rootPath${p.separator}';
    return candidatePath.startsWith(prefix);
  }

  // ─── VocabAudioResolver implementation ──────────────────────────────

  @override
  ResolvedVocabAudio resolve(String wordId) {
    // Anki cards use TTS by default (no pre-recorded audio for most decks).
    // If the wordId corresponds to an Anki card with audio, the renderer
    // handles it via resolveMediaPath() directly.
    return ResolvedVocabAudio(speakText: wordId);
  }
}

class AnkiMediaCopyReport {
  final int availableCount;
  final int missingCount;
  final int failedCount;

  const AnkiMediaCopyReport({
    this.availableCount = 0,
    this.missingCount = 0,
    this.failedCount = 0,
  });
}

class AnkiMediaSwapReceipt {
  const AnkiMediaSwapReceipt({
    required this.targetPath,
    required this.backupPath,
    required this.hadPrevious,
  });

  final String targetPath;
  final String backupPath;
  final bool hadPrevious;
}

/// Runs inside the [Isolate.run] spawned by [AnkiAudioResolver.copyMedia].
/// Only receives and returns plain data, and touches pure `dart:io` platform
/// helpers — no plugins, so it is isolate-safe.
AnkiMediaCopyReport _copyMediaEntries({
  required String sourceDir,
  required String targetDir,
  required Map<String, String> mediaMapping,
}) {
  platform.ankiCreateDirectory(targetDir);

  var available = 0;
  var missing = 0;
  var failed = 0;
  for (final entry in mediaMapping.entries) {
    final numericName = AnkiAudioResolver._safeRelativePath(entry.key);
    final originalName = AnkiAudioResolver._safeRelativePath(entry.value);
    if (numericName == null || originalName == null) {
      failed++;
      continue;
    }
    final sourcePath = p.join(sourceDir, numericName);
    if (!platform.ankiFileExists(sourcePath)) {
      missing++;
      continue;
    }

    final targetPath = p.join(targetDir, originalName);
    if (!AnkiAudioResolver._isWithin(targetDir, targetPath)) {
      failed++;
      continue;
    }
    if (platform.ankiFileExists(targetPath)) {
      available++;
      continue;
    }
    try {
      platform.ankiCreateDirectory(p.dirname(targetPath));
      platform.ankiCopyFile(sourcePath, targetPath);
      available++;
    } catch (_) {
      failed++;
    }
  }

  return AnkiMediaCopyReport(
    availableCount: available,
    missingCount: missing,
    failedCount: failed,
  );
}
