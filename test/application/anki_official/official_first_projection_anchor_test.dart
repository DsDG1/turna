// P5F-22/23 tests: placement/presentation publishing anchored on the
// official projection index, and bare-filename official media resolution.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/import/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('p5f publishFromProjection', () {
    late CourseDatabase db;

    setUp(() async {
      db = CourseDatabase(NativeDatabase.memory());
      await GetIt.instance.reset();
      GetIt.instance.registerSingleton<CourseDatabase>(db);
      GetIt.instance.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));
    });

    tearDown(() async {
      await GetIt.instance.reset();
      await db.close();
    });

    test('anchors placements on the projection index with real tree ids',
        () async {
      final store = OfficialAnkiCourseProjectionStore(db);
      await store.replaceOfficialProjection(
        sourceId: 'src-p22',
        plan: OfficialAnkiProjectionPlan(
          items: [
            OfficialAnkiProjectedItem(
              kind: OfficialAnkiProjectionKind.showWord,
              cardId: 101,
              wordId: 'official-anki-profile-default-01-c101',
              sectionId: 'official-anki-src-p22-s7',
              unitId: 'official-anki-src-p22-u7',
              lessonId: 'official-anki-src-p22-l7-p1',
              sectionName: 'S',
              unitName: 'U',
              lessonName: 'L',
              payload: const <String, Object?>{},
              sourceFingerprint: 'fp',
            ),
            OfficialAnkiProjectedItem(
              kind: OfficialAnkiProjectionKind.multipleChoice,
              cardId: 102,
              wordId: 'official-anki-profile-default-01-c102',
              sectionId: 'official-anki-src-p22-s7',
              unitId: 'official-anki-src-p22-u7',
              lessonId: 'official-anki-src-p22-l7-p1',
              sectionName: 'S',
              unitName: 'U',
              lessonName: 'L',
              payload: const <String, Object?>{},
              sourceFingerprint: 'fp',
            ),
          ],
          issues: const [],
        ),
      );

      final result = await UnifiedAnkiImportOrchestrator.instance
          .publishFromProjection(sourceId: 'src-p22', sourceHash: 'hash-p22');

      expect(result.cardinalityOk, isTrue);
      expect(result.canonicalCardCount, 2);
      expect(result.wroteTurnaSrs, isFalse);
      final placements = await db.customSelect(
        'SELECT placement_id, section_id, unit_id, lesson_id, display_order '
        'FROM anki_course_card_placements ORDER BY card_id',
      ).get();
      expect(placements.length, 2);
      expect(
        placements.map((r) => r.read<String>('section_id')).toSet(),
        {'official-anki-src-p22-s7'},
        reason: 'placements carry the real projected tree ids, not the '
            'courseId placeholder the Dart-parse path used',
      );
      final kinds = await db.customSelect(
        'SELECT presentation_kind FROM anki_card_presentations ORDER BY card_id',
      ).get();
      expect(kinds.map((r) => r.read<String>('presentation_kind')), [
        'showWord',
        'multipleChoice',
      ], reason: 'presentation kind follows the projected kind');
      // Re-publish is idempotent (unique conflicts swallowed, 1:1 kept).
      final again = await UnifiedAnkiImportOrchestrator.instance
          .publishFromProjection(sourceId: 'src-p22', sourceHash: 'hash-p22');
      expect(again.canonicalCardCount, 2);
      final count = await db.customSelect(
        'SELECT COUNT(*) AS n FROM anki_course_card_placements',
      ).getSingle();
      expect(count.read<int>('n'), 2);
    });
  });

  group('p5f official media candidate file', () {
    late Directory tmp;
    late OfficialAnkiPaths paths;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('p5f-media');
      final media = Directory('${tmp.path}/collection.media')
        ..createSync(recursive: true);
      File('${media.path}/hello.mp3').writeAsBytesSync([1, 2, 3]);
      paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot: Directory(tmp.path),
      );
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    test('resolves bare filenames from collection.media', () {
      final file = officialAnkiMediaCandidateFile('hello.mp3', paths);
      expect(file, isNotNull);
      expect(file!.path, endsWith('hello.mp3'));
    });

    test('rejects non-media, traversal, missing and unset paths', () {
      expect(officialAnkiMediaCandidateFile('merhaba', paths), isNull,
          reason: 'no extension — an ordinary TTS word');
      expect(officialAnkiMediaCandidateFile('.mp3', paths), isNull);
      expect(officialAnkiMediaCandidateFile('mp3.', paths), isNull);
      expect(
        officialAnkiMediaCandidateFile('../secret.txt', paths),
        isNull,
        reason: 'traversal must stay denied',
      );
      expect(officialAnkiMediaCandidateFile('missing.mp3', paths), isNull);
      expect(officialAnkiMediaCandidateFile('hello.mp3', null), isNull,
          reason: 'official engine never opened');
    });
  });
}
