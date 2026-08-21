// Tests for [AnkiAudioResolver.copyMedia], which runs its copy loop inside
// an [Isolate.run] so large media sets do not freeze the import UI.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:turna/domain/audio/anki_audio_resolver.dart';

// Test imports:
import '../helpers/in_memory_course_db.dart';

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late String targetDir;

  setUp(() {
    ensurePathProviderMockForTest();
    tempDir = Directory.systemTemp.createTempSync('anki_copy_media_test');
    sourceDir = Directory(p.join(tempDir.path, 'src'))..createSync();
    // The mocked path_provider reports the system temp as the documents
    // directory, so the resolver writes under <tmp>/anki_media/<importId>.
    targetDir = p.join(
      Directory.systemTemp.path,
      'anki_media',
      'anki_copy_media_test_import',
    );
    if (Directory(targetDir).existsSync()) {
      Directory(targetDir).deleteSync(recursive: true);
    }
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (Directory(targetDir).existsSync()) {
      Directory(targetDir).deleteSync(recursive: true);
    }
  });

  test('copies media on a background isolate and reports stats', () async {
    File(p.join(sourceDir.path, '0')).writeAsBytesSync([1, 2, 3]);
    File(p.join(sourceDir.path, '1')).writeAsBytesSync([4, 5, 6]);

    final report = await AnkiAudioResolver().copyMedia(
      sourceDir: sourceDir.path,
      importId: 'anki_copy_media_test_import',
      mediaMapping: const {
        '0': 'audio.mp3',
        '1': 'pic.png',
        '2': 'missing.wav',
        '3': '../evil.txt',
      },
    );

    expect(report.availableCount, 2);
    expect(report.missingCount, 1);
    expect(report.failedCount, 1);

    expect(File(p.join(targetDir, 'audio.mp3')).existsSync(), isTrue);
    expect(File(p.join(targetDir, 'pic.png')).existsSync(), isTrue);
    expect(File(p.join(targetDir, '../evil.txt')).existsSync(), isFalse);
  });

  test('re-running counts already-present files as available', () async {
    File(p.join(sourceDir.path, '0')).writeAsBytesSync([1, 2, 3]);

    final resolver = AnkiAudioResolver();
    await resolver.copyMedia(
      sourceDir: sourceDir.path,
      importId: 'anki_copy_media_test_import',
      mediaMapping: const {'0': 'audio.mp3'},
    );
    final second = await resolver.copyMedia(
      sourceDir: sourceDir.path,
      importId: 'anki_copy_media_test_import',
      mediaMapping: const {'0': 'audio.mp3'},
    );

    expect(second.availableCount, 1);
    expect(second.failedCount, 0);
  });
}
