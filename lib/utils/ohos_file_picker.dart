// OHos-compatible file picker shim.
//
// The `file_picker` Flutter plugin does not support HarmonyOS (OHos). This
// helper routes `pickFiles` calls to a native ArkTS plugin via MethodChannel
// when running on OHos, and falls through to `FilePicker` on other platforms.
//
// Native channel: 'com.varnamala/file_picker' -> methods 'pickFile',
// 'scanForFiles', 'importFromPath'. The native side opens DocumentViewPicker
// (preferred), scans well-known directories, or opens a path the user
// supplies, copies the picked file into the app sandbox, and returns the
// sandbox file path (or null if cancelled).

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

  /// Scan well-known locations for files matching [allowedExtensions].
  ///
  /// OHos-only. Returns at most ~200 matches (the native side caps the scan
  /// depth and total). Returns an empty list when the scan completes but no
  /// matches are found, or the platform is not OHos.
  ///
  /// This is the recovery path for environments where the system FilePicker
  /// sheet (`com.huawei.hmos.security.pickersheet`) is missing — e.g.
  /// trimmed emulator ROMs and some test devices. The native side walks
  /// `filesDir`, `cacheDir`, and any 'Download' sub-folders.
  static Future<List<PlatformFile>> scanForFiles({
    required List<String> allowedExtensions,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.ohos) {
      return const <PlatformFile>[];
    }
    final raw = await _channel.invokeMethod<List<Object?>>(
      'scanForFiles',
      <String, dynamic>{
        'extensions': allowedExtensions
            .map((e) => e.startsWith('.') ? e : '.$e')
            .toList(),
      },
    );
    if (raw == null) return const <PlatformFile>[];
    return raw.map((e) {
      final m = (e as Map).cast<String, Object?>();
      return PlatformFile(
        path: m['path'] as String?,
        name: m['name'] as String? ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// Import a file by absolute [path].
  ///
  /// OHos-only. Used as a fully manual fallback: the user types or pastes
  /// a full path (e.g. copied out of a file manager) and we open it
  /// directly, after verifying the path exists, is a regular file, and has
  /// one of [allowedExtensions] (suffix check, case-insensitive).
  ///
  /// Returns the matching [PlatformFile] on success. Throws a
  /// [PlatformException] with a code from the native side on failure
  /// (`EMPTY_PATH`, `BAD_EXTENSION`, `NOT_FOUND`, `NOT_A_FILE`,
  /// `ACCESS_ERROR`).
  static Future<PlatformFile> importFromPath({
    required String path,
    required List<String> allowedExtensions,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.ohos) {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'importFromPath is only supported on OpenHarmony',
      );
    }
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'importFromPath',
      <String, dynamic>{
        'path': path,
        'extensions': allowedExtensions
            .map((e) => e.startsWith('.') ? e : '.$e')
            .toList(),
      },
    );
    if (raw == null) {
      throw PlatformException(
        code: 'NO_RESULT',
        message: 'native side returned no result',
      );
    }
    return PlatformFile(
      path: raw['path'] as String?,
      name: raw['name'] as String? ?? '',
      size: (raw['size'] as num?)?.toInt() ?? 0,
    );
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
