import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/card_presentation.dart';

import '../../helpers/in_memory_course_db.dart';

// Successor of the "暂无待复习的 Anki 卡片" regression: a cold process no
// longer hydrates any in-memory set — the loader reconciles the scheduler
// lock (ledger says card 1 is introduced, card 2 is not) and the queue
// itself is the gate. The batch must assemble Ready with exactly card 1.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  const flags = OfficialAnkiFeatureFlags(
    engine: true,
    import: true,
    catalogReady: true,
    runtimeCapable: true,
    platformReady: true,
    renderer: true,
    scheduler: true,
    projection: true,
    courseEntry: true,
    officialFirstImport: true,
  );

  const importId = 'src-hydration';

  late CourseDatabase db;

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
    CardIntroductionStore.debugOverride = null;
    db = CourseDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    CardIntroductionStore.debugOverride = null;
    OfficialFormalDueRepository.instance.resetForTest();
    await GetIt.instance.reset();
    await db.close();
  });

  test('a cold process needs no hydration — the loader reconciles the lock '
      'and the queue is the gate', () async {
    final dao = AnkiUnificationDao(db);
    await dao.upsertIntroduction(
      courseId: 'official-anki-$importId',
      key: const CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: 'profile-default-01',
        sourceId: importId,
        cardId: 1,
      ),
      status: CardIntroductionStatus.introduced,
      introducedBy: CardIntroducedBy.course,
    );
    // The projection index the lock reconciler reads: cards 1 and 2 of this
    // source (a real publish writes these rows).
    await db.customStatement(
      "INSERT INTO official_anki_projection_index "
      "(source_id, card_id, word_id, section_id, unit_id, lesson_id, "
      " projection_kind, source_fingerprint, projection_version) VALUES "
      "('$importId', 1, 'w1', 's', 'u', 'l', 'flip', 'fp', 1),"
      "('$importId', 2, 'w2', 's', 'u', 'l', 'flip', 'fp', 1)",
    );
    GetIt.instance.registerSingleton<CourseDatabase>(db);

    // Fresh store, populated ledger — the exact post-restart state. No
    // hydration call exists anymore; nothing reads this memory set.
    CardIntroductionStore.debugOverride = CardIntroductionStore(dao: dao);

    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'hydration.apkg', notes: 2, cards: 2);

    final loader = OfficialFormalReviewProductionLoader(
      flags: flags,
      engine: engine,
      resolveTarget: (_) async => const OfficialAnkiRoutedSource(
        importId: importId,
        sourceId: importId,
        deckId: 1,
        cardIds: {1, 2},
      ),
      presentationsForCards: ({
        required String sourceId,
        required Iterable<OfficialReviewQueueCard> cards,
      }) async {
        return {
          for (final card in cards)
            CanonicalCardKey(
              backend: AnkiBackendKind.official,
              profileId: 'profile-default-01',
              sourceId: sourceId,
              cardId: card.cardId,
            ): FlipCardPresentation(
              cardKey: CanonicalCardKey(
                backend: AnkiBackendKind.official,
                profileId: 'profile-default-01',
                sourceId: sourceId,
                cardId: card.cardId,
              ),
              frontText: 'front-${card.cardId}',
              backText: 'back-${card.cardId}',
              sourceFingerprint: 't',
            ),
        };
      },
      sessionFactory: ({
        required engine,
        required allowedCardIds,
      }) async {
        return OfficialReviewSession(
          engine: engine,
          flags: flags,
          allowedCardIds: allowedCardIds,
        );
      },
    );

    final result = await loader.load(
      importId: importId,
      courseId: 'anki-$importId',
    );

    expect(result, isA<OfficialFormalReviewReady>());
    final ready = result as OfficialFormalReviewReady;
    expect(
      ready.batch.items.map((item) => item.cardKey.cardId),
      [1],
      reason: 'the loader reconciled the lock before fetching the queue, so '
          'card 2 never reached it',
    );
    expect(ready.batch.session.current?.cardId, 1);
    expect(engine.suspended, {2},
        reason: 'the lock suspension is the durable record of "course not '
            'completed yet"');
  });
}