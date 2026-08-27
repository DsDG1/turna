import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

// Regression for the "暂无待复习的 Anki 卡片" bug: the loader reads the
// introduced set from CardIntroductionStore (in-memory). With the ledger
// populated but the store never hydrated — the exact post-restart state —
// the batch must still assemble (Ready), not collapse to NoDue. The
// `introducedCardIds` override stays unset so the production read path is
// exercised.
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

  late CourseDatabase db;

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
    CardIntroductionStore.debugOverride = null;
    db = CourseDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    CardIntroductionStore.debugOverride = null;
    OfficialFormalDueRepository.instance.resetForTest();
    await db.close();
  });

  test('loader hydration turns a ledger-backed queue into Ready', () async {
    const importId = 'src-hydration';
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

    // Fresh store + populated ledger = the post-restart state.
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

    // Card 1 is introduced in the ledger (restored by hydration); card 2
    // is not — the eligibility intersection must still filter it out.
    expect(result, isA<OfficialFormalReviewReady>());
    final ready = result as OfficialFormalReviewReady;
    expect(
      ready.batch.items.map((item) => item.cardKey.cardId),
      [1],
    );
    expect(ready.batch.session.current?.cardId, 1);
  });
}