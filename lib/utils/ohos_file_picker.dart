// OHos-compatible file picker shim.
//
// The `file_picker` Flutter plugin does not support HarmonyOS (OHos). This
// helper routes `pickFiles` calls to a native ArkTS plugin via MethodChannel
// when running on OHos, and falls through to `FilePicker` on other platforms.
//
// Native channel: 'com.varnamala/file_picker' -> method 'pickFile'.
// The native side opens DocumentViewPicker, copies the picked file into the
// app sandbox, and returns the sandbox file path (or null if cancelled).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

class OhosFilePicker {
  static const MethodChannel _channel = MethodChannel('com.varnamala/file_picker');

  /// Picks a single file restricted (by suffix) to [allowedExtensions].
  ///
  /// Returns a [FilePickerResult] with a single file whose `path` points to a
  /// sandbox copy, or null if the user cancelled.
  ///
  /// [allowedExtensions] is honored uniformly across platforms as a suffix
  /// filter:
  /// - On OHos it is forwarded to the native DocumentViewPicker, which only
  ///   lets the user pick matching files.
  /// - On other platforms the system chooser is opened with `FileType.any`
  ///   (some extensions such as `.apkg`/`.colpkg`/`.md` have no registered
  ///   Android MIME, so `FileType.custom` makes the plugin throw "Unsupported
  ///   filter" before the picker even opens) and the picked file's suffix is
  ///   validated here. A mismatch throws [OhosFilePickerInvalidExtension].
  ///
  /// Callers therefore never need to know about the MIME-registry quirk: just
  /// pass the extensions you accept and handle the exception (or null) if the
  /// user picks something else.
  static Future<FilePickerResult?> pickFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    final suffixes = _normalizedSuffixes(allowedExtensions);

    if (defaultTargetPlatform != TargetPlatform.ohos) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: dialogTitle,
      );
      final path = result?.files.single.path;
      if (path == null) return null;
      if (!_hasAllowedSuffix(path, suffixes)) {
        throw const OhosFilePickerInvalidExtension();
      }
      return result;
    }

    final path = await _channel.invokeMethod<String>('pickFile', <String, dynamic>{
      // Native DocumentSelectOptions.fileSuffixFilters expects extensions
      // with a leading dot (e.g. '.apkg'). Normalize the caller's input.
      'extensions':
          allowedExtensions.map((e) => e.startsWith('.') ? e : '.$e').toList(),
      'dialogTitle': dialogTitle ?? '',
    });
    if (path == null) return null;

    final name = path.split('/').last;
    return FilePickerResult([PlatformFile(path: path, name: name, size: 0)]);
  }

  /// Normalize extensions to a set of lowercase suffixes with a leading dot
  /// (e.g. `['apkg', '.colpkg']` -> `{'.apkg', '.colpkg'}`).
  static Set<String> _normalizedSuffixes(List<String> extensions) {
    return {
      for (final e in extensions)
        '.${e.toLowerCase().replaceFirst(RegExp(r'^\.'), '')}',
    };
  }

  static bool _hasAllowedSuffix(String path, Set<String> suffixes) {
    final lower = path.toLowerCase();
    return suffixes.any(lower.endsWith);
  }
}

/// Thrown by [OhosFilePicker.pickFiles] (non-OHos path) when the user picks a
/// file whose extension is not in the requested [allowedExtensions].
class OhosFilePickerInvalidExtension implements Exception {
  const OhosFilePickerInvalidExtension();

  @override
  String toString() =>
      'OhosFilePickerInvalidExtension: picked file suffix is not allowed';
}
