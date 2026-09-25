// Uninstall media-deletion regression tests: one locked file used to abort
// `AnkiImportCleanupService.deleteAll` after the course tree was already
// gone, leaving an undeletable leftover directory with no retry entry. These
// tests pin the new contract — media deletion is best-effort, reports
// leftovers instead of throwing, and never interrupts the saga.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:

import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/audio/anki_media_delete_report.dart';
import 'package:turna/domain/audio/anki_media_platform_io.dart'
    as media_platform;

import '../../helpers/in_memory_course_db.dart';

/// Resolver stand-in for the "one file stayed locked" case: the directory
/// survives the delete pass and the saga must carry on regardless.

void main() {
  setUpAll(() {
    ensurePathProviderMockForTest();
  });

  group('ankiDeleteDirectoryBestEffort', () {
    test('deletes nested files and directories, reports success', () {
      final root = Directory.systemTemp.createTempSync('anki_best_effort_del_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final sub = Directory('${root.path}/sub')..createSync();
      File('${sub.path}/a.mp3').writeAsStringSync('a');
      File('${root.path}/b.jpg').writeAsStringSync('b');

      final report = media_platform.ankiDeleteDirectoryBestEffort(root.path);

      expect(report.fullyDeleted, isTrue);
      expect(report.deletedFiles, 2);
      expect(report.remainingFiles, 0);
      expect(root.existsSync(), isFalse);
    });

    test('missing directory yields an empty successful report', () {
      final report = media_platform
          .ankiDeleteDirectoryBestEffort('${Directory.systemTemp.path}/nope');
      expect(report.fullyDeleted, isTrue);
      expect(report.deletedFiles, 0);
    });

    test('a surviving root directory is not reported as fully deleted', () {
      const report = AnkiMediaDeleteReport(
        deletedFiles: 1,
        remainingDirectories: ['anki_media/imp-root'],
      );

      expect(report.remainingFiles, 0);
      expect(report.fullyDeleted, isFalse);
    });
  });

  group('AnkiAudioResolver.deleteImportMedia + sweepOrphanMedia', () {
    late AnkiAudioResolver resolver;

    setUp(() {
      resolver = AnkiAudioResolver();
      // The media root is shared under the mocked documents directory —
      // start every test from a clean slate.
      final mediaRoot = Directory('${Directory.systemTemp.path}/anki_media');
      if (mediaRoot.existsSync()) mediaRoot.deleteSync(recursive: true);
    });

    test('deletes the import directory and reports success', () async {
      final importDir = Directory(
        '${Directory.systemTemp.path}/anki_media/imp-del',
      )..createSync(recursive: true);
      File('${importDir.path}/sound.mp3').writeAsStringSync('x');

      final report = await resolver.deleteImportMedia('imp-del');

      expect(report.fullyDeleted, isTrue);
      expect(report.deletedFiles, 1);
      expect(importDir.existsSync(), isFalse);
    });

    test('sweep removes owner-less dirs and keeps owned ones', () async {
      final orphanDir = Directory(
        '${Directory.systemTemp.path}/anki_media/orphan-a',
      )..createSync(recursive: true);
      File('${orphanDir.path}/x.mp3').writeAsStringSync('x');
      final liveDir = Directory(
        '${Directory.systemTemp.path}/anki_media/live-b',
      )..createSync(recursive: true);
      File('${liveDir.path}/y.mp3').writeAsStringSync('y');

      final swept = await resolver.sweepOrphanMedia(
        (importId) async => importId == 'live-b',
      );

      expect(swept, 1);
      expect(orphanDir.existsSync(), isFalse);
      expect(liveDir.existsSync(), isTrue);
    });

    // The Legacy in-place re-import staging/swap API was deleted (doc 39
    // P1-F); the sweep tests below reconstruct the on-disk `.__rollback__`
    // crash state directly, the way an interrupted legacy swap would have
    // left it, because sweepOrphanMedia still repairs those directories.
    Directory makeRollbackDir(
      String importId,
      String incomingHash, {
      bool withOldMedia = true,
    }) {
      final rollback = Directory(
        '${Directory.systemTemp.path}/anki_media/$importId.__rollback__'
        '${Uri.encodeComponent(incomingHash)}'
        '.__generation__${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);
      if (withOldMedia) {
        File('${rollback.path}/old.mp3').writeAsStringSync('old');
      }
      return rollback;
    }

    test('startup sweep restores old media after a pre-commit process kill',
        () async {
      const importId = 'imp-swap-crash-rollback';
      final target = Directory(await resolver.getImportMediaPath(importId))
        ..createSync(recursive: true);
      // Post-kill on-disk state: the staged (new) media had already been
      // swapped into the canonical directory, the old media sits in the
      // rollback copy, and the DB commit never happened.
      File('${target.path}/new.mp3').writeAsStringSync('new');
      makeRollbackDir(importId, 'hash-new');

      await resolver.sweepOrphanMedia(
        (candidate) async => candidate == importId,
        sourceHashForImport: (candidate) async => 'hash-old',
      );

      expect(File('${target.path}/old.mp3').readAsStringSync(), 'old');
      expect(File('${target.path}/new.mp3').existsSync(), isFalse);
    });

    test('startup sweep keeps new media after a post-commit process kill',
        () async {
      const importId = 'imp-swap-crash-commit';
      final target = Directory(await resolver.getImportMediaPath(importId))
        ..createSync(recursive: true);
      File('${target.path}/new.mp3').writeAsStringSync('new');
      final rollback = makeRollbackDir(importId, 'hash-new');

      await resolver.sweepOrphanMedia(
        (candidate) async => candidate == importId,
        sourceHashForImport: (candidate) async => 'hash-new',
      );

      expect(File('${target.path}/new.mp3').readAsStringSync(), 'new');
      expect(File('${target.path}/old.mp3').existsSync(), isFalse);
      expect(rollback.existsSync(), isFalse);
    });

    test('crash recovery handles an old import with no media directory',
        () async {
      const importId = 'imp-swap-crash-empty-old';
      final targetPath = await resolver.getImportMediaPath(importId);
      // No previous media: the legacy swap left an empty rollback directory
      // as the durable crash marker.
      final rollback =
          makeRollbackDir(importId, 'hash-new', withOldMedia: false);
      expect(rollback.listSync(), isEmpty);

      await resolver.sweepOrphanMedia(
        (candidate) async => candidate == importId,
        sourceHashForImport: (candidate) async => 'hash-old',
      );

      expect(Directory(targetPath).existsSync(), isTrue);
      expect(File('$targetPath/new.mp3').existsSync(), isFalse);
      expect(Directory(targetPath).listSync(), isEmpty);
    });
  });
}
