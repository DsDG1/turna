import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

void main() {
  final repo = OfficialFormalDueRepository.instance;
  setUp(repo.resetForTest);
  tearDown(repo.resetForTest);

  test('collect + one commit lands scheduler due card ids atomically',
      () async {
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

    final intro = CardIntroductionStore();
    intro.resetForTest();
    await intro.markFromLesson(
      wordId: 'official-anki-src-due-c10',
      lessonId: 'official-anki-src-due-s1',
    );
    CardIntroductionStore.debugOverride = intro;
    addTearDown(() => CardIntroductionStore.debugOverride = null);

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

    var notifications = 0;
    void listener() => notifications++;
    repo.addListener(listener);
    final generationBefore = repo.generation;

    final collected = await const OfficialAnkiProductionRouter()
        .collectFormalDueCardIds(
      dao: migrations,
      sources: sources,
      setCurrentDeck: (_) async {},
      getReviewQueue: ({int fetchLimit = 500}) async => queue,
    );
    final result = repo.commit(
      const OfficialFormalDueSnapshotBuilder().build(
        sources: collected.inputs,
        rawDueBySource: collected.rawDueByImport,
      ),
      basedOnGeneration: generationBefore,
    );
    repo.removeListener(listener);

    expect(result, OfficialFormalDueCommitResult.committed);
    expect(notifications, 1,
        reason: 'one logical refresh = exactly one notification');
    expect(repo.generation, generationBefore + 1);
    expect(repo.schedulerDueCardIdsFor('src-due'), {10, 11});
    expect(repo.activePlacementCardIdsFor('src-due'), {10, 11, 12});

    // Only 10 introduced → formal due must be {10}, not count approx 2.
    expect(repo.formalDueCountForImport('src-due'), 1);
    expect(
      repo.formalDueCardKeysForImport('src-due').map((k) => k.cardId).toSet(),
      {10},
    );
  });

  test('collectFormalDueCardIds probes per-deck queues', () async {
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
    final collected = await const OfficialAnkiProductionRouter()
        .collectFormalDueCardIds(
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
    final input = collected.inputs.single;
    expect(input.schedulerDueCardIds, {2});
    expect(collected.rawDueByImport['src-a'], 1);
  });

  test('collect populates suspended, buried, retired and commit subtracts them',
      () async {
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

    final collected = await const OfficialAnkiProductionRouter()
        .collectFormalDueCardIds(
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

    final result = repo.commit(
      const OfficialFormalDueSnapshotBuilder().build(
        sources: collected.inputs,
        rawDueBySource: collected.rawDueByImport,
      ),
      basedOnGeneration: repo.generation,
    );
    expect(result, OfficialFormalDueCommitResult.committed);

    expect(repo.suspendedCardIdsFor('src-sub'), {20});
    expect(repo.buriedCardIdsFor('src-sub'), {30});
    expect(repo.retiredCardIdsFor('src-sub'), {40});

    // Formal due must only include card 10 (20 suspended, 30 buried, 40 retired).
    expect(repo.formalDueCountForImport('src-sub'), 1);
    expect(
      repo.formalDueCardKeysForImport('src-sub').map((k) => k.cardId).toSet(),
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
