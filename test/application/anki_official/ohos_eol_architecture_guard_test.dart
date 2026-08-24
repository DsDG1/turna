import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Doc 34 W2 / ADR 0041: active product trees must not reintroduce OHOS
/// runtime APIs, OpenHarmony dependency overrides, or the fork patch toolchain.
/// Historical hits in CHANGELOG / archive docs are allowed.
void main() {
  group('OHOS product EOL architecture guard', () {
    test('ohos product target and patch toolchain are gone', () {
      expect(Directory('ohos').existsSync(), isFalse);
      expect(File('tool/apply_patches.sh').existsSync(), isFalse);
      expect(Directory('tool/patches').existsSync(), isFalse);
      expect(File('lib/data/rdb_query_executor.dart').existsSync(), isFalse);
      expect(File('lib/utils/ohos_file_picker.dart').existsSync(), isFalse);
    });

    test('active trees do not contain forbidden OHOS markers', () {
      const needles = <String>[
        'HarmonyOsRdbExecutor',
        'OhosInitializationSettings',
        'OhosNotification',
        'openharmony',
        'tool/apply_patches.sh',
      ];

      final roots = <String>[
        'lib',
        'pubspec.yaml',
        'tool',
        '.github',
        'README.md',
        'CLAUDE.md',
        'docs/project-guide.md',
        'docs/android-build-setup.md',
      ];

      final violations = <String>[];
      for (final root in roots) {
        final entity = FileSystemEntity.typeSync(root);
        if (entity == FileSystemEntityType.notFound) {
          // Optional CI dirs may be absent in some checkouts.
          if (root == '.github') continue;
          violations.add('missing scan root: $root');
          continue;
        }
        if (entity == FileSystemEntityType.file) {
          _scanFile(File(root), needles, violations);
        } else {
          for (final file in Directory(root)
              .listSync(recursive: true)
              .whereType<File>()) {
            if (_shouldSkip(file.path)) continue;
            _scanFile(file, needles, violations);
          }
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('capability matrix never requires Legacy fallback writers', () {
      final text = File(
        'lib/application/anki_official/migration/official_anki_engine_kind.dart',
      ).readAsStringSync();
      expect(text.contains('legacyFallbackRequired: true'), isFalse);
      // Retired platform must not keep an explicit Legacy-writer branch.
      expect(
        RegExp(r"case\s+'ohos'\s*:").hasMatch(text),
        isFalse,
      );
    });

    test('Official native ABI packaging is arm64-only (doc 34 §14.2)', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      // Active abiFilters assignment would conflict with Flutter's
      // --target-platform split; comments documenting that rule are fine.
      expect(
        RegExp(r'^\s*ndk\s*\{[^}]*abiFilters', multiLine: true, dotAll: true)
            .hasMatch(gradle),
        isFalse,
      );
      expect(
        RegExp(r'^\s*abiFilters\b', multiLine: true).hasMatch(gradle),
        isFalse,
      );
      expect(gradle.contains('target-platform android-arm64'), isTrue);

      final release = File('tool/build_release.py').readAsStringSync();
      expect(release.contains('--target-platform'), isTrue);
      expect(release.contains('android-arm64'), isTrue);
      expect(release.contains('app-arm64-v8a-release.apk'), isTrue);

      final setup = File('docs/android-build-setup.md').readAsStringSync();
      expect(
        setup.contains(
          'flutter build apk --release --split-per-abi --target-platform android-arm64',
        ),
        isTrue,
      );

      final so = File('android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so');
      expect(so.existsSync(), isTrue,
          reason: 'arm64 Official native library must be packaged');
    });
  });
}

bool _shouldSkip(String path) {
  final normalized = path.replaceAll('\\', '/');
  if (normalized.contains('/archive/')) return true;
  if (normalized.endsWith('CHANGELOG.md')) return true;
  if (normalized.contains('/.dart_tool/')) return true;
  if (normalized.endsWith('.png') ||
      normalized.endsWith('.jpg') ||
      normalized.endsWith('.jar') ||
      normalized.endsWith('.so')) {
    return true;
  }
  return false;
}

void _scanFile(File file, List<String> needles, List<String> violations) {
  late final String content;
  try {
    content = file.readAsStringSync();
  } catch (_) {
    return;
  }
  for (final needle in needles) {
    if (content.contains(needle)) {
      // ADR / doc 34 may mention the forbidden strings while documenting EOL.
      final path = file.path.replaceAll('\\', '/');
      if (path.endsWith('0041-ohos-product-eol.md')) continue;
      if (path.contains('34-official-anki-production-cutover')) continue;
      if (path.contains('ohos_eol_architecture_guard_test.dart')) continue;
      violations.add('$path -> $needle');
    }
  }
}
