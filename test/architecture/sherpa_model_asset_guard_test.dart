// The bundled sherpa-onnx TTS model is copied out of `rawfile/` into the app
// sandbox on first use, and `stage-manifest.tsv` pins the byte size of the three
// files the engine actually parses. `SherpaTtsPlugin.firstIncomplete()` treats a
// size mismatch as "not staged" and re-copies — which is the runtime repair for
// a bad copy, not for a bad build. These are the build-time facts, so they are
// asserted here rather than discovered on a device:
//
//  * **EOL conversion.** `core.autocrlf=true` on Windows rewrites `tokens.txt`
//    from LF to CRLF on checkout. sherpa-onnx's tokens parser then reads the
//    "space" token line `  3` (one space, id 3) as a *second* `3` token — the
//    next line `3 133` already owns that symbol — and its duplicate handling is
//    `exit(-1)`, not an exception. The process dies with code 255 roughly a
//    second after launch: no Dart stack, no crash file, nothing in the app log
//    after the parse line. That is what the real device showed on 2026-10-20.
//    `.gitattributes` protects `assets/anki_reviewer/**` from exactly this
//    conversion for the same class of reason; this tree is now covered too.
//  * **A manifest that describes a different model revision** than the tree
//    holds.
//
// Both make the plugin re-stage 35 MB on every launch and then refuse to load
// the model, so neither can be allowed to reach a build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const modelDir =
      'ohos/entry/src/main/resources/rawfile/sherpa/vits-piper-tr_TR-dfki-medium-int8';
  const manifestPath = '$modelDir/stage-manifest.tsv';

  /// `#SIZE <relative> <bytes>` entries: the files whose exact bytes matter.
  Map<String, int> declaredSizes(String manifest) {
    final sizes = <String, int>{};
    for (final raw in manifest.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('#SIZE\t')) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      sizes[parts[1]] = int.parse(parts[2]);
    }
    return sizes;
  }

  /// `#FILE <rawName> <relative>` entries: what staging actually copies.
  Set<String> stagedPaths(String manifest) {
    final paths = <String>{};
    for (final raw in manifest.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('#FILE\t')) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      paths.add(parts[2]);
    }
    return paths;
  }

  test('every declared size matches the shipped bytes', () {
    final manifest = File(manifestPath).readAsStringSync();
    final sizes = declaredSizes(manifest);

    expect(
      sizes,
      isNotEmpty,
      reason: 'a manifest with no #SIZE entry pins nothing, so a truncated or '
          'EOL-mangled model would be staged and loaded without complaint',
    );

    for (final entry in sizes.entries) {
      final file = File('$modelDir/${entry.key}');
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} is size-checked by the manifest but not in the '
            'tree, so the plugin would re-stage on every launch and then fail',
      );
      expect(
        file.lengthSync(),
        entry.value,
        reason: '${entry.key} is ${file.lengthSync()} bytes, manifest says '
            '${entry.value}. The usual cause is a checkout-time EOL '
            'conversion: `.gitattributes` must keep this tree binary.',
      );
    }
  });

  test('tokens.txt carries no CR, for the reason sherpa cannot survive it', () {
    final bytes = File('$modelDir/tokens.txt').readAsBytesSync();

    expect(
      bytes.contains(0x0D),
      isFalse,
      reason: 'sherpa-onnx parses tokens.txt line by line and a trailing CR '
          'defeats its end-of-line test, so the space token line `  3` is '
          'registered as a duplicate of the `3 133` token that follows it. Its '
          'duplicate handling calls exit(-1): the whole process disappears '
          'during model load, with no Dart exception to catch.',
    );
  });

  test('every size-checked file is also staged, so a mismatch is repairable',
      () {
    final manifest = File(manifestPath).readAsStringSync();
    final staged = stagedPaths(manifest);

    expect(staged, isNotEmpty, reason: 'the manifest stages nothing');
    for (final relative in declaredSizes(manifest).keys) {
      expect(
        staged,
        contains(relative),
        reason: '$relative is size-checked but never copied, so '
            'firstIncomplete() would report it forever while staging rewrites '
            'everything else — a permanent init failure instead of a repair',
      );
    }
  });
}
