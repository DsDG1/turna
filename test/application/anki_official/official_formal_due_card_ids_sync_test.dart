import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

void main() {
  setUp(OfficialAnkiHomeDue.reset);
  tearDown(OfficialAnkiHomeDue.reset);

  test('refreshHomeDueFromQueue writes scheduler due card ids', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final sources = OfficialAnkiSourceDao(db);
    final migrations = OfficialAnkiMigrationDao(db);

    sources.upsertSource(
      sourceId: 'src-due',
      profileId: 'profile-default-01',
      sourceHash: 'h1',
      sourceSize: 1,
      displayName: 'due',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-due', 10, 1, 7, 'g', 0), "
      "('src-due', 11, 1, 7, 'g2', 0), "
      "('src-due', 12, 2, 7, 'g3', 0)",
    );
    migrations.insertDetected(
      migrationId: 'mig-due',
      profileId: 'profile-default-01',
      legacyImportId: 'src-due',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    migrations.setOfficialSourceAndRecordedKind(
      migrationId: 'mig-due',
      officialSourceId: 'src-due',
      recordedKind: 'official',
      nowMillis: 2,
    );

    final queue = OfficialReviewQueue(
      sessionId: 's-due',
      queueEpoch: 1,
      learningCount: 0,
      newCount: 1,
      reviewCount: 1,
      cards: [
        _card(10, deckId: 7),
        _card(11, deckId: 7),
        _card(99, deckId: 7), // not in this source
      ],
    );

    await const OfficialAnkiProductionRouter().refreshHomeDueFromQueue(
      dao: migrations,
      sources: sources,
      getReviewQueue: () async => queue,
    );

    expect(
      OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport['src-due'],
      {10, 11},
    );
    expect(
      OfficialAnkiHomeDue.activePlacementCardIdsByImport['src-due'],
      {10, 11, 12},
    );

    // Mark only 10 introduced → formal due must be {10}, not count approx 2.
    final intro = CardIntroductionStore();
    intro.resetForTest();
    // Directly seed introduced tokens via markFromLesson word ids.
    await intro.markFromLesson(
      wordId: 'official-anki-src-due-c10',
      lessonId: 'official-anki-src-due-s1',
    );
    CardIntroductionStore.debugOverride = intro;
    addTearDown(() => CardIntroductionStore.debugOverride = null);

    expect(OfficialAnkiHomeDue.formalOfficialDueForImport('src-due'), 1);
    expect(
      OfficialAnkiHomeDue.formalDueCardKeysForImport('src-due')
          .map((k) => k.cardId)
          .toSet(),
      {10},
    );
  });

  test('refreshFormalDueCardIds probes per-deck queues', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final sources = OfficialAnkiSourceDao(db);
    final migrations = OfficialAnkiMigrationDao(db);
    sources.upsertSource(
      sourceId: 'src-a',
      profileId: 'profile-default-01',
      sourceHash: 'ha',
      sourceSize: 1,
      displayName: 'a',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-a', 1, 1, 3, 'g', 0), ('src-a', 2, 1, 3, 'g2', 0)",
    );
    migrations.insertDetected(
      migrationId: 'mig-a',
      profileId: 'profile-default-01',
      legacyImportId: 'src-a',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    migrations.setOfficialSourceAndRecordedKind(
      migrationId: 'mig-a',
      officialSourceId: 'src-a',
      recordedKind: 'official',
      nowMillis: 2,
    );

    final setDecks = <int>[];
    await const OfficialAnkiProductionRouter().refreshFormalDueCardIds(
      dao: migrations,
      sources: sources,
      setCurrentDeck: (deckId) async => setDecks.add(deckId),
      getReviewQueue: ({int fetchLimit = 500}) async => OfficialReviewQueue(
        sessionId: 's-a',
        queueEpoch: 1,
        learningCount: 0,
        newCount: 0,
        reviewCount: 1,
        cards: [_card(2, deckId: 3)],
      ),
    );

    expect(setDecks, [3]);
    expect(
      OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport['src-a'],
      {2},
    );
    expect(OfficialAnkiHomeDue.officialDueByImport['src-a'], 1);
    // Without stuffing the static map in the unit under test beyond what
    // refreshFormalDueCardIds wrote, formal due uses intersection.
    final intro = CardIntroductionStore()..resetForTest();
    await intro.markFromLesson(
      wordId: 'official-anki-src-a-c2',
      lessonId: 'official-anki-src-a-s1',
    );
    CardIntroductionStore.debugOverride = intro;
    addTearDown(() => CardIntroductionStore.debugOverride = null);
    expect(OfficialAnkiHomeDue.formalOfficialDueForImport('src-a'), 1);
  });

  test('refreshFormalDueCardIds populates suspended, buried, retired and subtracts them', () async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final sources = OfficialAnkiSourceDao(db);
    final migrations = OfficialAnkiMigrationDao(db);
    sources.upsertSource(
      sourceId: 'src-sub',
      profileId: 'profile-default-01',
      sourceHash: 'hsub',
      sourceSize: 1,
      displayName: 'sub',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    db.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-sub', 10, 1, 5, 'g1', 0), "
      "('src-sub', 20, 2, 5, 'g2', 0), "
      "('src-sub', 30, 3, 5, 'g3', 0), "
      "('src-sub', 40, 4, 5, 'g4', 0)",
    );
    migrations.insertDetected(
      migrationId: 'mig-sub',
      profileId: 'profile-default-01',
      legacyImportId: 'src-sub',
      policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
      nowMillis: 1,
    );
    migrations.setOfficialSourceAndRecordedKind(
      migrationId: 'mig-sub',
      officialSourceId: 'src-sub',
      recordedKind: 'official',
      nowMillis: 2,
    );

    var notifyCount = 0;
    OfficialAnkiHomeDue.instance.addListener(() {
      notifyCount++;
    });

    final intro = CardIntroductionStore()..resetForTest();
    await intro.markFromLesson(
      wordId: 'official-anki-src-sub-c10',
      lessonId: 'official-anki-src-sub-s1',
    );
    await intro.markFromLesson(
      wordId: 'official-anki-src-sub-c20',
      lessonId: 'official-anki-src-sub-s1',
    );
    await intro.markFromLesson(
      wordId: 'official-anki-src-sub-c30',
      lessonId: 'official-anki-src-sub-s1',
    );
    await intro.markFromLesson(
      wordId: 'official-anki-src-sub-c40',
      lessonId: 'official-anki-src-sub-s1',
    );
    CardIntroductionStore.debugOverride = intro;
    addTearDown(() => CardIntroductionStore.debugOverride = null);

    // Initial sync without suspensions: all 4 cards in queue.
    await const OfficialAnkiProductionRouter().refreshFormalDueCardIds(
      dao: migrations,
      sources: sources,
      setCurrentDeck: (deckId) async {},
      getReviewQueue: ({int fetchLimit = 500}) async => OfficialReviewQueue(
        sessionId: 's-sub',
        queueEpoch: 1,
        learningCount: 0,
        newCount: 0,
        reviewCount: 4,
        cards: [
          _card(10, deckId: 5),
          _card(20, deckId: 5),
          _card(30, deckId: 5),
          _card(40, deckId: 5),
        ],
      ),
      getSuspendedCardIds: ({int? deckId}) async => {20},
      getBuriedCardIds: ({int? deckId}) async => {30},
      getRetiredCardIds: ({int? deckId}) async => {40},
    );

    expect(OfficialAnkiHomeDue.suspendedCardIdsByImport['src-sub'], {20});
    expect(OfficialAnkiHomeDue.buriedCardIdsByImport['src-sub'], {30});
    expect(OfficialAnkiHomeDue.retiredCardIdsByImport['src-sub'], {40});
    expect(notifyCount, greaterThan(0));

    // Formal due must only include card 10 (20 suspended, 30 buried, 40 retired).
    expect(OfficialAnkiHomeDue.formalOfficialDueForImport('src-sub'), 1);
    expect(
      OfficialAnkiHomeDue.formalDueCardKeysForImport('src-sub')
          .map((k) => k.cardId)
          .toSet(),
      {10},
    );
  });
}

OfficialReviewQueueCard _card(int id, {required int deckId}) {
  return OfficialReviewQueueCard(
    cardId: id,
    noteId: id,
    deckId: deckId,
    templateOrdinal: 0,
    queueKind: 'review',
    answerToken: 'tok-$id',
    labels: const OfficialReviewIntervalLabels(
      again: '1m',
      hard: '10m',
      good: '1d',
      easy: '4d',
    ),
  );
}
