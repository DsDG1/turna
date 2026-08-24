// Cross-platform file picker with suffix validation.
//
// Some extensions (`.apkg` / `.colpkg` / `.md`) have no registered Android
// MIME type, so `FileType.custom` throws "Unsupported filter" before the
// picker opens. This helper always opens with `FileType.any` and validates
// the picked path's suffix here.

import 'package:file_picker/file_picker.dart';

class ValidatedFilePicker {
  ValidatedFilePicker._();

  /// Picks a single file restricted (by suffix) to [allowedExtensions].
  ///
  /// Returns a [FilePickerResult] with a single file, or null if cancelled.
  /// Throws [ValidatedFilePickerInvalidExtension] when the picked path does
  /// not end with one of the allowed suffixes (case-insensitive).
  static Future<FilePickerResult?> pickFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    final suffixes = normalizedSuffixes(allowedExtensions);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: dialogTitle,
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    if (!hasAllowedSuffix(path, suffixes)) {
      throw const ValidatedFilePickerInvalidExtension();
    }
    return result;
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
    final lower = path.toLowerCase();
    return suffixes.any(lower.endsWith);
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
