// Package imports:
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'anki_media_delete_report.dart';
import 'anki_media_platform_stub.dart'
    if (dart.library.io) 'anki_media_platform_io.dart' as platform;
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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

  // Doc 39 P1-F: the Legacy in-place re-import staging/swap family
  // (copyMedia / stagingImportId / swapStagedMedia / rollbackMediaSwap /
  // finalizeMediaSwap / copyMediaFiles / buildAssetPath) was deleted — its
  // only caller was the Legacy re-import flow retired in doc 35 L1.
  // [sweepOrphanMedia] still understands the on-disk `.__rollback__`
  // directories that flow could leave behind after a process kill.

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
    } catch (suppressed) {
      debugPrint('[AnkiAudioResolver] suppressed error: $suppressed');
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

  /// Check if an asset path is an Anki media reference.
  static bool isAnkiAsset(String? path) {
    return path != null && path.startsWith(ankiScheme);
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
