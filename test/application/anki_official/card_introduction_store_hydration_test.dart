import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

import '../../helpers/in_memory_course_db.dart';

// Regression coverage for the "暂无待复习的 Anki 卡片" bug: the store is
// write-through, so after a restart the ledger held the introduced rows
// while the in-memory set was empty and formal-due filtered out every
// card. hydrateFromLedger() must restore the set from the ledger.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
  });

  tearDown(() {
    CardIntroductionStore.debugOverride = null;
    OfficialFormalDueRepository.instance.resetForTest();
  });

  CanonicalCardKey key(String sourceId, int cardId) => CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: 'profile-default-01',
        sourceId: sourceId,
        cardId: cardId,
      );

  test('fresh process: ledger rows restore the introduced set', () async {
    final db = emptyInMemoryCourseDatabase();
    addTearDown(db.close);
    final dao = AnkiUnificationDao(db);
    await dao.upsertIntroduction(
      courseId: 'official-anki-src-a',
      key: key('src-a', 11),
      status: CardIntroductionStatus.introduced,
      introducedBy: CardIntroducedBy.course,
    );
    await dao.upsertIntroduction(
      courseId: 'official-anki-src-a',
      key: key('src-a', 12),
      status: CardIntroductionStatus.unintroduced,
    );
    await dao.upsertIntroduction(
      courseId: 'official-anki-src-b',
      key: key('src-b', 21),
      status: CardIntroductionStatus.introduced,
      introducedBy: CardIntroducedBy.course,
    );

    // A fresh store models the post-restart state: the ledger is
    // populated, the in-memory set is not.
    final store = CardIntroductionStore(dao: dao);
    expect(store.introducedCardIdsForSource('src-a'), isEmpty);
    expect(store.introducedCardIdsForSource('src-b'), isEmpty);

    await store.hydrateFromLedger();

    expect(store.introducedCardIdsForSource('src-a'), {11});
    expect(store.introducedCardIdsForSource('src-b'), {21});
    expect(store.introducedCountForSource('src-a'), 1);
    expect(store.introducedCountForSource('src-b'), 1);
  });

  test('hydrate is an idempotent merge and coexists with markFromLesson',
      () async {
    final db = emptyInMemoryCourseDatabase();
    addTearDown(db.close);
    final dao = AnkiUnificationDao(db);
    await dao.upsertIntroduction(
      courseId: 'official-anki-src',
      key: key('src', 7),
      status: CardIntroductionStatus.introduced,
    );

    final store = CardIntroductionStore(dao: dao);
    await store.hydrateFromLedger();
    await store.hydrateFromLedger();
    expect(store.introducedCardIdsForSource('src'), {7});
    expect(store.introducedCountForSource('src'), 1);

    // Re-marking the SAME card under a fresh word-id must not inflate the
    // count or duplicate the card id.
    await store.markFromLesson(
      wordId: 'official-anki-src-c7',
      lessonId: 'official-anki-src-l0123456789ab-p1',
    );
    expect(store.introducedCardIdsForSource('src'), {7});
    expect(store.introducedCountForSource('src'), 1);

    // A genuinely new card still lands, in memory and in the ledger.
    await store.markFromLesson(
      wordId: 'official-anki-src-c8',
      lessonId: 'official-anki-src-l0123456789ab-p1',
    );
    expect(store.introducedCardIdsForSource('src'), {7, 8});
    expect(store.introducedCountForSource('src'), 2);

    // A later hydration merges the ledger rows without losing the
    // in-memory-only card.
    await store.hydrateFromLedger();
    expect(store.introducedCardIdsForSource('src'), {7, 8});
    expect(store.introducedCountForSource('src'), 2);
  });

  test('store without DAO hydrates as a no-op', () async {
    final store = CardIntroductionStore();
    await store.hydrateFromLedger();
    expect(store.introducedCardIdsForSource('any'), isEmpty);
  });
}