// Cross-platform file picker with suffix validation.
//
// Some extensions (`.apkg` / `.colpkg` / `.md`) have no registered Android
// MIME type, so `FileType.custom` throws "Unsupported filter" before the
// picker opens. This helper always opens with `FileType.any` and validates
// the picked path's suffix here.

import 'dart:io';

import 'package:file_picker/file_picker.dart';

class ValidatedFilePicker {
  ValidatedFilePicker._();

  /// Picks a single file restricted (by suffix) to [allowedExtensions].
  ///
  /// Returns a [FilePickerResult] with a single file whose path has a valid
  /// allowed extension, or null if cancelled.
  /// Throws [ValidatedFilePickerInvalidExtension] when the picked file does
  /// not match any allowed extension (and cannot be resolved to one).
  static Future<FilePickerResult?> pickFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    final suffixes = normalizedSuffixes(allowedExtensions);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: dialogTitle,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final resolvedPath = await resolvePickedFilePath(file, suffixes);
    if (resolvedPath == null) {
      throw const ValidatedFilePickerInvalidExtension();
    }

    return FilePickerResult([
      PlatformFile(
        name: file.name,
        size: file.size,
        path: resolvedPath,
        bytes: file.bytes,
        readStream: file.readStream,
        identifier: file.identifier,
      ),
    ]);
  }

  /// Normalize extensions to lowercase suffixes with a leading dot
  /// (e.g. `['apkg', '.colpkg']` -> `{'.apkg', '.colpkg'}`).
  static Set<String> normalizedSuffixes(List<String> extensions) {
    return {
      for (final e in extensions)
        '.${e.toLowerCase().replaceFirst(RegExp(r'^\.'), '')}',
    };
  }

  static bool hasAllowedSuffix(String path, Set<String> suffixes) {
    final lower = path.trim().toLowerCase();
    return suffixes.any(lower.endsWith);
  }

  /// Finds a direct allowed suffix match on [text] (e.g. `deck.apkg` -> `.apkg`).
  static String? findMatchingSuffix(String text, Set<String> suffixes) {
    final lower = text.trim().toLowerCase();
    for (final s in suffixes) {
      if (lower.endsWith(s)) {
        return s;
      }
    }
    return null;
  }

  /// Finds a wrapped allowed suffix on [text].
  /// Handles common Android/mobile scenarios:
  /// - WeChat appends `.1`, `.2`, etc. (`deck.apkg.1` -> `.apkg`)
  /// - Mobile browsers append `.bin`, `.zip`, `.download`, etc. (`deck.apkg.bin` -> `.apkg`)
  /// - File download counters like `deck.apkg(1)` or `deck.apkg_1` -> `.apkg`
  static String? findWrappedSuffix(String text, Set<String> suffixes) {
    final lower = text.trim().toLowerCase();
    for (final s in suffixes) {
      final pattern = RegExp(
        '${RegExp.escape(s)}(?:(?:\\.[a-zA-Z0-9_#-]+)+|\\(\\d+\\)|_\\d+)?\$',
      );
      if (pattern.hasMatch(lower)) {
        return s;
      }
    }
    return null;
  }

  /// Resolves the file path from [file] to a concrete file path on disk
  /// that ends with one of the [suffixes].
  ///
  /// If the picked path already has an allowed suffix and exists, returns it directly.
  /// If the path lacks an extension (common on Android SAF/cache) or has a
  /// wrapped suffix (WeChat `.1`, browser `.bin`), copies/stages it into a
  /// temporary cache file ending with the proper extension.
  /// Also inspects zip archives for Anki `collection.anki2` if `.apkg` is expected.
  static Future<String?> resolvePickedFilePath(
    PlatformFile file,
    Set<String> suffixes,
  ) async {
    final rawPath = file.path?.trim();
    final name = file.name.trim();

    // 1. Direct suffix match on raw path
    if (rawPath != null && hasAllowedSuffix(rawPath, suffixes)) {
      return rawPath;
    }

    // 2. Direct suffix match on display name (e.g. path is a cache hash without extension)
    final nameSuffix = findMatchingSuffix(name, suffixes);
    if (nameSuffix != null) {
      return stageFileWithExtension(file, nameSuffix);
    }

    // 3. Wrapped suffix match (e.g. deck.apkg.1 from WeChat, deck.apkg.bin from mobile browsers)
    final wrappedSuffix = findWrappedSuffix(name, suffixes) ??
        (rawPath != null ? findWrappedSuffix(rawPath, suffixes) : null);
    if (wrappedSuffix != null) {
      return stageFileWithExtension(file, wrappedSuffix);
    }

    // 4. Content-based probe for Anki packages if .apkg is among allowed suffixes
    if (suffixes.contains('.apkg')) {
      if (await isAnkiPackageFile(file)) {
        return stageFileWithExtension(file, '.apkg');
      }
    }

    return null;
  }

  /// Copies or writes [file] to a temporary file ending with [targetExtension].
  static Future<String?> stageFileWithExtension(
    PlatformFile file,
    String targetExtension,
  ) async {
    final rawPath = file.path?.trim();
    if (rawPath != null &&
        rawPath.toLowerCase().endsWith(targetExtension) &&
        File(rawPath).existsSync()) {
      return rawPath;
    }

    try {
      final tempDir =
          Directory('${Directory.systemTemp.path}/turna_staged_imports');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      var cleanBase = file.name.trim();
      if (cleanBase.isEmpty) {
        cleanBase = rawPath != null
            ? rawPath.split(RegExp(r'[/\\]')).last
            : 'import';
      }

      final lower = cleanBase.toLowerCase();
      final idx = lower.indexOf(targetExtension);
      if (idx != -1) {
        cleanBase = cleanBase.substring(0, idx + targetExtension.length);
      } else {
        final dot = cleanBase.lastIndexOf('.');
        if (dot > 0) {
          cleanBase = cleanBase.substring(0, dot);
        }
        cleanBase = '$cleanBase$targetExtension';
      }

      final targetPath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$cleanBase';
      final targetFile = File(targetPath);

      if (rawPath != null && File(rawPath).existsSync()) {
        await File(rawPath).copy(targetPath);
      } else if (file.bytes != null) {
        await targetFile.writeAsBytes(file.bytes!);
      } else {
        return null;
      }
      return targetPath;
    } catch (_) {
      return null;
    }
  }

  /// Inspects whether [file] is a zip archive containing `collection.anki2` or `collection.anki21`.
  static Future<bool> isAnkiPackageFile(PlatformFile file) async {
    final rawPath = file.path?.trim();
    if (rawPath == null || !File(rawPath).existsSync()) {
      if (file.bytes == null) return false;
      return _bufferContainsAnkiSignature(file.bytes!);
    }

    try {
      final f = File(rawPath);
      final len = await f.length();
      if (len < 30) return false;

      final raf = await f.open();
      try {
        final header = await raf.read(4);
        if (header.length < 4 ||
            header[0] != 0x50 ||
            header[1] != 0x4B ||
            header[2] != 0x03 ||
            header[3] != 0x04) {
          return false;
        }

        await raf.setPosition(0);
        final readLen = len < 262144 ? len : 262144;
        final buffer = await raf.read(readLen);
        if (_bufferContainsAnkiSignature(buffer)) {
          return true;
        }

        if (len > 65536) {
          await raf.setPosition(len - 65536);
          final tail = await raf.read(65536);
          if (_bufferContainsAnkiSignature(tail)) {
            return true;
          }
        }
        return false;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  static bool _bufferContainsAnkiSignature(List<int> bytes) {
    const sig1 = [
      99,
      111,
      108,
      108,
      101,
      99,
      116,
      105,
      111,
      110,
      46,
      97,
      110,
      107,
      105,
      50,
    ]; // collection.anki2
    if (bytes.length < sig1.length) return false;
    final limit = bytes.length - sig1.length;
    for (var i = 0; i <= limit; i++) {
      if (bytes[i] == 99) {
        var match = true;
        for (var j = 1; j < sig1.length; j++) {
          if (bytes[i + j] != sig1[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
    }
    return false;
  }
}

/// Thrown by [ValidatedFilePicker.pickFiles] when the user picks a file whose
/// extension is not in the requested [allowedExtensions].
class ValidatedFilePickerInvalidExtension implements Exception {
  const ValidatedFilePickerInvalidExtension();

  @override
  String toString() =>
      'ValidatedFilePickerInvalidExtension: picked file suffix is not allowed';
}
