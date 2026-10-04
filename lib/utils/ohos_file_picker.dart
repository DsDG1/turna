// OpenHarmony file picker shim.
//
// The `file_picker` Flutter plugin has no HarmonyOS implementation, so on the
// companion build the pick goes through a hand-written ArkTS plugin
// (`FilePickerPlugin.ets`) over a MethodChannel. Everything above this file
// keeps using `ValidatedFilePicker` and never learns which side ran.
//
// The native side returns the staged copy's real name and size alongside its
// path. Both matter: an earlier version returned only a path, and the Dart side
// filled the rest in with a split of that path and a hardcoded `size: 0`, so
// callers saw a synthesised filename and a file that claimed to be empty.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:turna/core/ohos_target.dart';

/// Result of a native pick: the staged copy plus the metadata the picker gave
/// us about the original file.
class OhosPickedFile {
  const OhosPickedFile({
    required this.path,
    required this.name,
    required this.size,
  });

  /// Absolute path of the copy inside the app cache directory.
  final String path;

  /// The picked file's own name, extension included.
  final String name;

  /// Byte length of the staged copy.
  final int size;
}

class OhosFilePicker {
  OhosFilePicker._();

  static const MethodChannel _channel =
      MethodChannel('me.dsdogs.turna/file_picker');

  /// Whether this build needs the native picker. False on Android/iOS, where
  /// the `file_picker` plugin works and callers should use it directly.
  static bool get isRequired => isHarmonyOsTarget;

  /// Picks a single file restricted (by suffix) to [allowedExtensions].
  ///
  /// Returns null when the user cancels.
  ///
  /// Deliberately does **not** re-check the suffix or throw on a mismatch. The
  /// authoritative check is `ValidatedFilePicker.resolvePickedFilePath`, which
  /// throws the one exception type every caller already handles and also
  /// stages files whose name carries no extension. A second check here would
  /// need its own exception type, and that type would slip past the
  /// `on ValidatedFilePickerInvalidExtension` handlers at all four call sites —
  /// a correctly picked file would surface as an unhandled error instead of the
  /// handled "wrong file type" message.
  static Future<OhosPickedFile?> pickFiles({
    required List<String> allowedExtensions,
  }) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'pickFile',
      <String, dynamic>{
        'extensions': _normalizedSuffixes(allowedExtensions).toList(),
      },
    );
    if (raw == null) return null;

    final path = raw['path'] as String?;
    if (path == null || path.isEmpty) {
      throw PlatformException(
        code: 'NO_RESULT',
        message: 'native picker returned no usable path',
      );
    }
    return OhosPickedFile(
      path: path,
      name: raw['name'] as String? ?? _lastSegment(path),
      size: (raw['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// Wraps a native pick in the [PlatformFile] the shared
  /// `ValidatedFilePicker` contract returns, so callers above it do not branch
  /// on platform.
  static FilePickerResult toPickerResult(OhosPickedFile picked) {
    return FilePickerResult([
      PlatformFile(name: picked.name, size: picked.size, path: picked.path),
    ]);
  }

  /// Normalize extensions to a set of lowercase suffixes with a leading dot
  /// (e.g. `['apkg', '.colpkg']` -> `{'.apkg', '.colpkg'}`).
  static Set<String> _normalizedSuffixes(List<String> extensions) {
    return {
      for (final e in extensions)
        '.${e.toLowerCase().replaceFirst(RegExp(r'^\.'), '')}',
    };
  }

  static String _lastSegment(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }
}
