// OHos-compatible file picker shim.
//
// The `file_picker` Flutter plugin does not support HarmonyOS (OHos). This
// helper routes `pickFiles` calls to a native ArkTS plugin via MethodChannel
// when running on OHos, and falls through to `FilePicker` on other platforms.
//
// Native channel: 'com.varnamala/file_picker' → method 'pickFile'.
// The native side opens DocumentViewPicker, copies the picked file into the
// app sandbox, and returns the sandbox file path (or null if cancelled).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

class OhosFilePicker {
  static const MethodChannel _channel = MethodChannel('com.varnamala/file_picker');

  /// Picks a single file. On OHos, [allowedExtensions] is forwarded to the
  /// native DocumentViewPicker as a suffix filter. Returns a [FilePickerResult]
  /// with a single file whose `path` points to a sandbox copy, or null if the
  /// user cancelled.
  static Future<FilePickerResult?> pickFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.ohos) {
      return FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      );
    }

    final path = await _channel.invokeMethod<String>('pickFile', <String, dynamic>{
      // Native DocumentSelectOptions.fileSuffixFilters expects extensions
      // with a leading dot (e.g. '.apkg'). Normalize the caller's input.
      'extensions': allowedExtensions
          .map((e) => e.startsWith('.') ? e : '.$e')
          .toList(),
      'dialogTitle': dialogTitle ?? '',
    });
    if (path == null) return null;

    final name = path.split('/').last;
    return FilePickerResult([PlatformFile(path: path, name: name, size: 0)]);
  }
}