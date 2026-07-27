// Dart imports:
import 'dart:io';

// Package imports:
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';

/// Resolves Anki media assets (audio/images) from the extracted media directory.
///
/// Anki media files are stored in `<app docs>/anki_media/<importId>/` after
/// import. This resolver maps `anki://` prefixed paths to local file paths.
///
/// Implements [VocabAudioResolver] so it integrates with the existing
/// [AudioController] pipeline.
class AnkiAudioResolver implements VocabAudioResolver {
  /// Base directory for all Anki media files.
  static const String _mediaBaseDir = 'anki_media';

  /// Prefix used in asset paths to identify Anki media references.
  static const String ankiScheme = 'anki://';

  String? _cachedDocsDir;

  /// Get the base media directory path.
  Future<String> getMediaBasePath() async {
    if (_cachedDocsDir != null) return _cachedDocsDir!;
    final docs = await getApplicationDocumentsDirectory();
    _cachedDocsDir = docs.path;
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

    final file = File(fullPath);
    if (file.existsSync()) return fullPath;
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
    if (mediaMapping.isEmpty) return 0;

    final targetDir = Directory(await getImportMediaPath(importId));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    var copied = 0;
    for (final entry in mediaMapping.entries) {
      final numericName = entry.key;
      final originalName = entry.value;

      final sourceFile = File(p.join(sourceDir, numericName));
      if (!sourceFile.existsSync()) continue;

      final targetFile = File(p.join(targetDir.path, originalName));
      if (targetFile.existsSync()) continue; // Skip existing

      try {
        sourceFile.copySync(targetFile.path);
        copied++;
      } catch (_) {
        // Skip files that fail to copy (permission, disk space, etc.)
      }
    }

    return copied;
  }

  /// Delete all media files for an import (used during deck uninstall).
  Future<void> deleteImportMedia(String importId) async {
    final mediaPath = await getImportMediaPath(importId);
    final dir = Directory(mediaPath);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
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

  // ─── VocabAudioResolver implementation ──────────────────────────────

  @override
  ResolvedVocabAudio resolve(String wordId) {
    // Anki cards use TTS by default (no pre-recorded audio for most decks).
    // If the wordId corresponds to an Anki card with audio, the renderer
    // handles it via resolveMediaPath() directly.
    return ResolvedVocabAudio(speakText: wordId);
  }
}
