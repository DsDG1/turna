// Package imports:
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'anki_media_platform_stub.dart'
    if (dart.library.io) 'anki_media_platform_io.dart' as platform;
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';

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
    if (mediaMapping.isEmpty) return const AnkiMediaCopyReport();

    final targetDir = await getImportMediaPath(importId);
    platform.ankiCreateDirectory(targetDir);

    var available = 0;
    var missing = 0;
    var failed = 0;
    for (final entry in mediaMapping.entries) {
      final numericName = _safeRelativePath(entry.key);
      final originalName = _safeRelativePath(entry.value);
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
      if (!_isWithin(targetDir, targetPath)) {
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
  Future<void> deleteImportMedia(String importId) async {
    final mediaPath = await getImportMediaPath(importId);
    if (platform.ankiDirectoryExists(mediaPath)) {
      platform.ankiDeleteDirectory(mediaPath);
    }
  }

  /// Build an `anki://` asset path for a media file.
  static String buildAssetPath(String importId, String filename) {
    return '$ankiScheme$importId/$filename';
  }

  /// Check if an asset path is an Anki media reference.
  static bool isAnkiAsset(String? path) {
    return path != null && path.startsWith(ankiScheme);
  }

  String? _safeRelativePath(String raw) {
    final normalized = raw.replaceAll('\\', '/');
    if (normalized.isEmpty || normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      return null;
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '..')) return null;
    return parts.join(p.separator);
  }

  bool _isWithin(String root, String candidate) {
    final rootPath = p.normalize(root);
    final candidatePath = p.normalize(candidate);
    if (p.equals(rootPath, candidatePath)) return true;
    final prefix = rootPath.endsWith(p.separator)
        ? rootPath
        : '$rootPath${p.separator}';
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
