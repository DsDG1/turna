// P0 tests: the projection index is the single source for "which Official
// cards belong to one course lesson" — no interaction-id string guessing.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/projection/official_anki_lesson_card_index.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/srs_word.dart';

import '../../../helpers/in_memory_course_db.dart';

OfficialAnkiProjectedItem _item({
  required int cardId,
  required String lessonId,
  OfficialAnkiProjectionKind kind = OfficialAnkiProjectionKind.flip,
}) {
  return OfficialAnkiProjectedItem(
    kind: kind,
    cardId: cardId,
    wordId: 'official-anki-key-c$cardId',
    sectionId: 'official-anki-src-lci-s1',
    unitId: 'official-anki-src-lci-u1',
    lessonId: lessonId,
    sectionName: 'S',
    unitName: 'U',
    lessonName: 'L',
    payload: const <String, Object?>{},
    sourceFingerprint: 'fp',
  );
}

Future<void> _publish(CourseDatabase db, List<OfficialAnkiProjectedItem> items) {
  return OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
    sourceId: 'src-lci',
    plan: OfficialAnkiProjectionPlan(items: items, issues: const []),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('OfficialAnkiCourseProjectionStore.indexRowsForLesson', () {
    late CourseDatabase db;

    setUp(() async {
      db = CourseDatabase(NativeDatabase.memory());
      await GetIt.instance.reset();
    });

    tearDown(() async {
      OfficialAnkiLessonCardIndex.debugResolver = null;
      await GetIt.instance.reset();
      await db.close();
    });

    test('returns only the lesson rows, in stable card-id order', () async {
      await _publish(db, [
        _item(cardId: 42, lessonId: 'official-anki-src-lci-la-p1'),
        _item(cardId: 21, lessonId: 'official-anki-src-lci-la-p1'),
        _item(cardId: 77, lessonId: 'official-anki-src-lci-lb-p1'),
      ]);

      final rows = await OfficialAnkiCourseProjectionStore(db)
          .indexRowsForLesson('official-anki-src-lci-la-p1');
      expect(rows.map((r) => r.cardId), [21, 42]);
      expect(rows.map((r) => r.sourceId).toSet(), {'src-lci'});
      expect(rows.map((r) => r.wordId), [
        'official-anki-key-c21',
        'official-anki-key-c42',
      ]);
    });

    test('is empty for lessons this database never projected', () async {
      await _publish(db, [
        _item(cardId: 42, lessonId: 'official-anki-src-lci-la-p1'),
      ]);

      final rows = await OfficialAnkiCourseProjectionStore(db)
          .indexRowsForLesson('some-legacy-lesson');
      expect(rows, isEmpty);
    });

    test('resolveForLesson resolves through the registered database',
        () async {
      await _publish(db, [
        _item(
          cardId: 42,
          lessonId: 'official-anki-src-lci-la-p1',
          kind: OfficialAnkiProjectionKind.showWord,
        ),
        _item(cardId: 43, lessonId: 'official-anki-src-lci-la-p1'),
      ]);
      GetIt.instance.registerSingleton<CourseDatabase>(db);

      final index = await OfficialAnkiLessonCardIndex.resolveForLesson(
        'official-anki-src-lci-la-p1',
      );
      expect(index, isNotNull);
      expect(index!.sourceId, 'src-lci');
      expect(index.cardIds, [42, 43]);
    });

    test('resolveForLesson returns null without rows or database',
        () async {
      GetIt.instance.registerSingleton<CourseDatabase>(db);
      expect(
        await OfficialAnkiLessonCardIndex.resolveForLesson('legacy-lesson'),
        isNull,
        reason: 'a legacy lesson has no projection rows',
      );
      await GetIt.instance.reset();
      expect(
        await OfficialAnkiLessonCardIndex.resolveForLesson(
          'official-anki-src-lci-la-p1',
        ),
        isNull,
        reason: 'no registered CourseDatabase means nothing to resolve from',
      );
    });

    test('resolveForLesson fails closed when the read throws', () async {
      await _publish(db, [
        _item(cardId: 42, lessonId: 'official-anki-src-lci-la-p1'),
      ]);
      GetIt.instance.registerSingleton<CourseDatabase>(db);
      await db.close();

      expect(
        await OfficialAnkiLessonCardIndex.resolveForLesson(
          'official-anki-src-lci-la-p1',
        ),
        isNull,
        reason: 'a failed read must not degrade into id-string guessing',
      );
    });
  });

  group('OfficialAnkiLessonCardIndex matching', () {
    test('entries dedupe by card across projection kinds', () {
      final index = OfficialAnkiLessonCardIndex(
        lessonId: 'l',
        sourceId: 'src',
        entries: const [
          OfficialAnkiLessonCardEntry(
            wordId: 'official-anki-key-c42',
            cardId: 42,
          ),
          OfficialAnkiLessonCardEntry(
            wordId: 'official-anki-key-c42',
            cardId: 42,
          ),
          OfficialAnkiLessonCardEntry(
            wordId: 'official-anki-key-c21',
            cardId: 21,
          ),
        ],
      );
      expect(index.cardIds, [42, 21]);
    });

    test('matches wordId, itemId prefix, and ShowWord wordId', () {
      final index = OfficialAnkiLessonCardIndex(
        lessonId: 'l',
        sourceId: 'src',
        entries: const [
          OfficialAnkiLessonCardEntry(
            wordId: 'official-anki-key-c42',
            cardId: 42,
          ),
          OfficialAnkiLessonCardEntry(
            wordId: 'official-anki-key-c421',
            cardId: 421,
          ),
        ],
      );

      // Bare wordId (ShowWord.wordId carries it).
      expect(index.cardIdForInteractionId('official-anki-key-c42'), 42);
      // Projector item id: '$wordId-p{kind}-$ordinal'.
      expect(
        index.cardIdForInteractionId('official-anki-key-c42-pflip-0'),
        42,
      );
      expect(
        index.cardIdForInteractionId('official-anki-key-c421-pflip-0'),
        421,
        reason: 'prefix match must not confuse -c42 with -c421',
      );
      // ShowWord interaction resolves through its wordId.
      expect(
        index.cardIdForInteraction(
          const Interaction.showWord(
            id: 'official-anki-key-c42-pshowWord-0',
            wordId: 'official-anki-key-c42',
            term: 'a',
            translation: 'b',
          ),
        ),
        42,
      );
      // canonicalLink items carry a link wordId but the standard item id.
      expect(
        index.cardIdForInteraction(
          const Interaction.showWord(
            id: 'official-anki-key-c421-pcanonicalLink-0',
            wordId: 'official-anki-link-src-c421',
          ),
        ),
        421,
      );
      // Unknown ids resolve to nothing — never a guess.
      expect(index.cardIdForInteractionId('unrelated-id'), isNull);
      expect(index.cardIdForInteractionId('official-anki-key-c99-pflip-0'),
          isNull);
    });
  });

  group('CardIntroductionStore.markIntroducedCard', () {
    test('persists the ledger row and folds word + card into memory',
        () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = AnkiUnificationDao(db);
      final store = CardIntroductionStore(dao: dao);

      await store.markIntroducedCard(
        sourceId: 'src-mic',
        cardId: 42,
        wordId: 'official-anki-key-c42',
        lessonId: 'official-anki-src-mic-la-p1',
      );

      final state = await dao.introductionState(
        courseId: 'official-anki-src-mic',
        key: CanonicalCardKeyAdapter.fromOfficial(
          profileId: 'profile-default-01',
          sourceId: 'src-mic',
          cardId: 42,
        ),
      );
      expect(state.status.name, 'introduced');
      expect(state.introducedBy?.name, 'course');
      expect(
        state.firstLessonId,
        'official-anki-src-mic-la-p1',
        reason: 'the structured lesson id is recorded verbatim',
      );
      expect(store.isIntroducedCard(sourceId: 'src-mic', cardId: 42), isTrue);
      expect(
        store.isFormallyEligibleWord(
          SrsWord(wordId: 'official-anki-key-c42', dueAt: DateTime.now()),
        ),
        isTrue,
        reason: 'the wordId token keeps word-level eligibility',
      );
    });
  });
}