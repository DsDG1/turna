// Tests for the OpenHarmony file picker shim and the seam it plugs into.
//
// The ArkTS half cannot run here, so these pin the contract the native side
// must satisfy: the picked file's real name and size travel with the staged
// path, and the argument Dart sends is named the same as the one the plugin
// reads. Both drifted apart in the version this replaces, and neither
// symptom would have failed a test anywhere -- the app compiled, the picker
// opened, and every in-scope flow then rejected the file the user had just
// correctly chosen.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/utils/ohos_file_picker.dart';
import 'package:turna/utils/validated_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('me.dsdogs.turna/file_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the next `pickFile` with [response] and records the call.
  void respondWith(Object? response, List<MethodCall> calls) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  }

  setUp(() {});
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('OhosFilePicker', () {
    test('is not required on the host SDK, so Android/iOS keep the plugin', () {
      expect(OhosFilePicker.isRequired, isFalse);
    });

    test('decodes path, name and size from the native envelope', () async {
      final calls = <MethodCall>[];
      respondWith(
        <String, Object?>{
          'path': '/data/storage/el2/base/cache/backup.zip',
          'name': 'backup.zip',
          'size': 4096,
        },
        calls,
      );

      final picked = await OhosFilePicker.pickFiles(
        allowedExtensions: const ['zip'],
      );

      expect(picked, isNotNull);
      expect(picked!.path, '/data/storage/el2/base/cache/backup.zip');
      expect(picked.name, 'backup.zip');
      expect(picked.size, 4096);
    });

    test('sends the filter under "extensions", dotted and lowercased',
        () async {
      final calls = <MethodCall>[];
      respondWith(null, calls);

      await OhosFilePicker.pickFiles(
        allowedExtensions: const ['turnapack', '.JSON'],
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'pickFile');
      // The plugin reads `call.argument('extensions')`. When this was sent as
      // `suffixes` the filter was silently dropped and every pick came back
      // narrowed to a stale hardcoded pair.
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args.containsKey('extensions'), isTrue);
      expect(args.containsKey('suffixes'), isFalse);
      expect(args['extensions'], ['.turnapack', '.json']);
    });

    test('returns null when the user cancels', () async {
      respondWith(null, <MethodCall>[]);
      expect(
        await OhosFilePicker.pickFiles(allowedExtensions: const ['json']),
        isNull,
      );
    });

    test('falls back to the path tail when the native side omits a name',
        () async {
      respondWith(
        <String, Object?>{'path': '/cache/dir/lesson.md', 'size': 12},
        <MethodCall>[],
      );

      final picked =
          await OhosFilePicker.pickFiles(allowedExtensions: const ['md']);

      expect(picked!.name, 'lesson.md');
    });

    test('rejects an envelope with no usable path', () async {
      respondWith(<String, Object?>{'size': 0}, <MethodCall>[]);

      expect(
        () => OhosFilePicker.pickFiles(allowedExtensions: const ['json']),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'NO_RESULT'),
        ),
      );
    });

    test('toPickerResult keeps the real name and size', () {
      // The old shim reported `size: 0` under a name split off the path, so a
      // caller that shows the file or checks its length saw a file that
      // claimed to be empty.
      final result = OhosFilePicker.toPickerResult(
        const OhosPickedFile(
          path: '/cache/deck.turnapack',
          name: 'deck.turnapack',
          size: 8192,
        ),
      );

      expect(result.files.single.name, 'deck.turnapack');
      expect(result.files.single.size, 8192);
      expect(result.files.single.path, '/cache/deck.turnapack');
    });
  });

  group('picked files survive the shared resolver', () {
    /// The suffix sets this app actually asks for, none of which is `.apkg`.
    const inScope = <List<String>>[
      ['zip'],
      ['json'],
      ['turnapack', 'json'],
    ];

    for (final extensions in inScope) {
      test('accepts a $extensions pick staged under its own name', () async {
        final name = 'sample.${extensions.first}';
        final calls = <MethodCall>[];
        respondWith(
          <String, Object?>{
            'path': '/data/storage/el2/base/cache/$name',
            'name': name,
            'size': 128,
          },
          calls,
        );

        final picked = await OhosFilePicker.pickFiles(
          allowedExtensions: extensions,
        );
        final resolved = await ValidatedFilePicker.resolvePickedFilePath(
          OhosFilePicker.toPickerResult(picked!).files.single,
          ValidatedFilePicker.normalizedSuffixes(extensions),
        );

        expect(resolved, '/data/storage/el2/base/cache/$name');
      });
    }

    test('rejects a wrong suffix with the type every caller catches', () async {
      // Regression guard for the hardcoded `.apkg` staging name: the picker
      // returned `anki_import_<ts>.apkg` whatever the user chose, and callers
      // only handle `ValidatedFilePickerInvalidExtension`. The failure had to
      // land on that one type or it would have escaped the handlers.
      final calls = <MethodCall>[];
      respondWith(
        <String, Object?>{
          'path': '/data/storage/el2/base/cache/anki_import_1759000000.apkg',
          'name': 'anki_import_1759000000.apkg',
          'size': 10,
        },
        calls,
      );

      final picked =
          await OhosFilePicker.pickFiles(allowedExtensions: const ['zip']);
      final result = OhosFilePicker.toPickerResult(picked!);

      // A null here is what makes `ValidatedFilePicker.pickFiles` throw
      // `ValidatedFilePickerInvalidExtension` — the single type all four call
      // sites catch. A shim that threw something of its own would escape them.
      final resolved = await ValidatedFilePicker.resolvePickedFilePath(
        result.files.single,
        ValidatedFilePicker.normalizedSuffixes(const ['zip']),
      );

      expect(resolved, isNull);
    });
  });
}
