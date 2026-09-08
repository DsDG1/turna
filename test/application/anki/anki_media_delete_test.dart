// Uninstall media-deletion regression tests: one locked file used to abort
// `AnkiImportCleanupService.deleteAll` after the course tree was already
// gone, leaving an undeletable leftover directory with no retry entry. These
// tests pin the new contract — media deletion is best-effort, reports
// leftovers instead of throwing, and never interrupts the saga.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/anki_official/anki_import_cleanup_service.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/audio/anki_media_delete_report.dart';
import 'package:turna/domain/audio/anki_media_platform_io.dart'
    as media_platform;
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';
import '../../helpers/anki_import_seed.dart';

/// Resolver stand-in for the "one file stayed locked" case: the directory
/// survives the delete pass and the saga must carry on regardless.
class _StuckMediaResolver extends AnkiAudioResolver {
  int deleteCalls = 0;

  @override
  Future<AnkiMediaDeleteReport> deleteImportMedia(String importId) async {
    deleteCalls++;
    return const AnkiMediaDeleteReport(
      deletedFiles: 2,
      remainingFiles: 1,
      remainingPaths: ['locked.mp3'],
      remainingDirectories: ['anki_media/imp-stuck'],
    );
  }
}

class _CleanupRepo implements ICourseRepository {
  final List<String> deletedTags = [];
  final List<String> deletedSections;
  final List<String> sectionIds;

  _CleanupRepo(this.sectionIds)
      : deletedSections = [],
        super();

  @override
  Future<int> deleteByTag(String tag) async {
    deletedTags.add(tag);
    return 0;
  }

  @override
  Future<void> deleteSection(String sectionId) async {
    deletedSections.add(sectionId);
  }

  @override
  Future<List<Section>> sectionShells({String? languageCode}) async => [];

  @override
  Future<void> bulkInsertCourseTree(Section section) async {}

  @override
  Future<void> bulkInsertVocabulary(List<WordEntry> words) async {}

  @override
  Future<void> deleteOfficialProjection(String sourceId) async {}

  @override
  Future<Section> section(String id) async => throw UnimplementedError();

  @override
  Future<Lesson> lessonById(String id) async => throw UnimplementedError();

  @override
  Future<List<Lesson>> lessonsContainingAny(Iterable<String> needles) async =>
      const [];

  @override
  Future<String?> sectionIdForUnit(String unitId) async => null;

  @override
  Future<String?> sectionIdForLesson(String lessonId) async => null;

  @override
  Future<List<WordEntry>> vocabulary({String? languageCode}) async => [];

  @override
  Future<List<GrammarPoint>> grammarPoints({String? languageCode}) async => [];

  @override
  Future<GrammarPoint?> grammarPointById(String id) async => null;

  @override
  Future<List<Expression>> expressions({String? languageCode}) async => [];

  @override
  Future<Expression?> expressionById(String id) async => null;

  @override
  Future<List<db.AnkiImport>> ankiImports() async => [];
}

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
      final rollback = makeRollbackDir(importId, 'hash-new', withOldMedia: false);
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

  group('AnkiImportCleanupService.deleteAll', () {
    late db.CourseDatabase database;

    setUp(() {
      database = emptyInMemoryCourseDatabase();
    });

    tearDown(() async {
      await database.close();
    });

    Future<SrsProvider> srs() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPrefs(await StreamingSharedPreferences.instance);
      return SrsProvider(prefs, LessonLinkStore(prefs), SrsStateDao(database));
    }

    test('a locked media file no longer aborts the saga', () async {
      final dao = AnkiImportDao(database);
      await seedAnkiImportRow(
        database,
        AnkiImportRecord(
          importId: 'imp-stuck',
          sourcePath: '/tmp/x.apkg',
          sourceHash: 'hash-stuck',
          importedAt: 1700000000,
        ),
      );

      final resolver = _StuckMediaResolver();
      final service = AnkiImportCleanupService(
        repository: _CleanupRepo(['anki-imp-stuck-s1']),
        srsProvider: await srs(),
        importDao: dao,
        noteDao: AnkiNoteDao(database),
        audioResolver: resolver,
      );

      await service.deleteAll('imp-stuck');

      // The import record must be gone even though media files remained.
      expect(resolver.deleteCalls, 1);
      expect(await dao.getById('imp-stuck'), isNull);
    });

    test('happy path deletes media directory and import record', () async {
      final mediaRoot = Directory('${Directory.systemTemp.path}/anki_media');
      if (mediaRoot.existsSync()) mediaRoot.deleteSync(recursive: true);
      final importDir = Directory(
        '${Directory.systemTemp.path}/anki_media/imp-happy',
      )..createSync(recursive: true);
      File('${importDir.path}/a.mp3').writeAsStringSync('a');

      final dao = AnkiImportDao(database);
      await seedAnkiImportRow(
        database,
        AnkiImportRecord(
          importId: 'imp-happy',
          sourcePath: '/tmp/y.apkg',
          sourceHash: 'hash-happy',
          importedAt: 1700000000,
        ),
      );

      final service = AnkiImportCleanupService(
        repository: _CleanupRepo(['anki-imp-happy-s1']),
        srsProvider: await srs(),
        importDao: dao,
        noteDao: AnkiNoteDao(database),
        audioResolver: AnkiAudioResolver(),
      );

      await service.deleteAll('imp-happy');

      expect(importDir.existsSync(), isFalse);
      expect(await dao.getById('imp-happy'), isNull);
    });
  });
}
