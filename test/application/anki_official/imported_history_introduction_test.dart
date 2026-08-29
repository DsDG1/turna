import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/introduction/imported_history_introducer.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

import '../../helpers/in_memory_course_db.dart';

// Imported review history (cards.reps >= 1) counts as introduced: the
// publish-time seed and the self-healing adopt must both write `introduced`
// rows (introducedBy=importedHistory) without ever rewriting the
// course-taught or retired lifecycle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AnkiUnificationDao dao;
  late CardIntroductionStore store;

  setUp(() {
    db = CourseDatabase(NativeDatabase.memory());
    dao = AnkiUnificationDao(db);
    store = CardIntroductionStore(dao: dao);
  });

  tearDown(() async {
    await db.close();
  });

  CanonicalCardKey key(int cardId, {String sourceId = 'src-hist'}) =>
      CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: 'profile-default-01',
        sourceId: sourceId,
        cardId: cardId,
      );

  test('seed marks studied cards introduced, the rest unintroduced', () async {
    await store.seedOfficialProjection(
      sourceId: 'src-hist',
      cardIds: const [1, 2, 3],
      studiedCardIds: const {2},
    );

    final studied =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(2));
    expect(studied.status, CardIntroductionStatus.introduced);
    expect(studied.introducedBy, CardIntroducedBy.importedHistory);

    for (final fresh in [1, 3]) {
      final state = await dao.introductionState(
        courseId: 'official-anki-src-hist',
        key: key(fresh),
      );
      expect(state.status, CardIntroductionStatus.unintroduced);
      expect(state.introducedBy, isNull);
    }

    expect(store.introducedCardIdsForSource('src-hist'), {2});
  });

  test('re-seed never clobbers a course-introduced row', () async {
    await store.markFromLesson(
      wordId: 'official-anki-profile-default-01-c7',
      lessonId: 'official-anki-src-hist-s1',
    );
    await store.seedOfficialProjection(
      sourceId: 'src-hist',
      cardIds: const [7],
      studiedCardIds: const {7},
    );

    final state =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(7));
    expect(state.status, CardIntroductionStatus.introduced);
    expect(state.introducedBy, CardIntroducedBy.course);
    expect(state.firstLessonId, 'official-anki-src-hist-s1');
  });

  test('adopt upgrades only unintroduced and missing rows', () async {
    // Card 1: seeded unintroduced (the pre-fix state to repair).
    await dao.ensureInitial(
      courseId: 'official-anki-src-hist',
      key: key(1),
      status: CardIntroductionStatus.unintroduced,
    );
    // Card 2: course-introduced — must survive untouched.
    await dao.upsertIntroduction(
      courseId: 'official-anki-src-hist',
      key: key(2),
      status: CardIntroductionStatus.introduced,
      introducedBy: CardIntroducedBy.course,
    );
    // Card 3: retired — must stay retired even though it has history.
    await dao.upsertIntroduction(
      courseId: 'official-anki-src-hist',
      key: key(3),
      status: CardIntroductionStatus.retired,
    );

    final events = <CardIntroductionChanged>[];
    final sub = CardIntroductionStore.changes.listen(events.add);

    await store.adoptImportedHistory(
      sourceId: 'src-hist',
      cardIds: const [1, 2, 3, 4], // 4: missing row entirely.
    );

    await pumpEventQueue();
    await sub.cancel();

    final card1 =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(1));
    expect(card1.status, CardIntroductionStatus.introduced);
    expect(card1.introducedBy, CardIntroducedBy.importedHistory);

    final card2 =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(2));
    expect(card2.introducedBy, CardIntroducedBy.course);
    expect(card2.version, 1, reason: 'already introduced — no rewrite');

    final card3 =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(3));
    expect(card3.status, CardIntroductionStatus.retired);

    final card4 =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(4));
    expect(card4.status, CardIntroductionStatus.introduced);
    expect(card4.introducedBy, CardIntroducedBy.importedHistory);

    expect(
      events.where((e) => e.kind == CardIntroductionChangeKind.introduced)
          .map((e) => e.cardId)
          .toSet(),
      {1, 4},
      reason: 'only rows that actually changed are announced',
    );
    expect(store.introducedCardIdsForSource('src-hist'), {1, 4},
        reason: 'adopt only folds rows it changed; card 2 was written '
            'behind the store and only lives in the ledger');
    // P1: the ledger is the durable truth — a direct read sees every
    // introduced row regardless of what the in-memory cache holds.
    expect(await store.introducedCardIdsFromLedger('src-hist'), {1, 2, 4});
  });

  test('introducer pages the prop:reps>=1 search and adopts per source',
      () async {
    final seenQueries = <String>[];
    var calls = 0;

    Future<OfficialAnkiCardPage> searchPage({
      String search = '',
      int pageSize = 200,
      String? pageToken,
    }) async {
      seenQueries.add(search);
      calls++;
      if (pageToken == null) {
        return const OfficialAnkiCardPage(
          cardIds: [11, 12],
          nextPageToken: '2',
        );
      }
      return const OfficialAnkiCardPage(cardIds: [13]);
    }

    final studied = await const ImportedHistoryIntroducer().fetchStudiedCardIds(
      searchPage: searchPage,
    );
    expect(studied, {11, 12, 13});
    expect(calls, 2);
    expect(seenQueries.every((q) => q == kImportedHistorySearchQuery), isTrue);

    await dao.ensureInitial(
      courseId: 'official-anki-src-hist',
      key: key(11),
      status: CardIntroductionStatus.unintroduced,
    );
    await const ImportedHistoryIntroducer().adopt(
      searchPage: searchPage,
      cardIdsBySource: const {
        'src-hist': {11, 99},
        'src-other': {12},
      },
      store: store,
    );

    final adopted =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(11));
    expect(adopted.status, CardIntroductionStatus.introduced);
    final untouched =
        await dao.introductionState(courseId: 'official-anki-src-hist', key: key(99));
    expect(untouched.status, CardIntroductionStatus.unintroduced);
    expect(store.introducedCardIdsForSource('src-hist'), {11});
    expect(store.introducedCardIdsForSource('src-other'), {12});
  });

  test('fake engine answers the studied-card search', () async {
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'hist.apkg', notes: 3, cards: 3);
    engine.studiedCardIds.addAll([1, 3]);

    final studied = await const ImportedHistoryIntroducer().fetchStudiedCardIds(
      searchPage: engine.searchCardsPage,
    );
    expect(studied, {1, 3});
  });
}
