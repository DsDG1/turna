// Review All tests (plan 34 R2-3 / OS-13): a review-all session plans
// across EVERY official source's formal due set — never just the first
// source with due cards — and reports sources that failed to resolve.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/formal_review_source_coordinator.dart';
import 'package:turna/application/anki/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/domain/anki/card_presentation.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

void main() {
  late FakeOfficialAnkiEngine engine;

  setUp(() {
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'x.apkg', notes: 4, cards: 4);
  });

  test('mixed-owner review all advances sequentially and aggregates results',
      () {
    final coordinator = FormalReviewSourceCoordinator(const [
      FormalReviewSourceTarget(
        importOrSourceId: 'legacy-a',
        displayName: 'Legacy A',
        owner: AnkiEngineKind.legacy,
      ),
      FormalReviewSourceTarget(
        importOrSourceId: 'src-b',
        displayName: 'Official B',
        owner: AnkiEngineKind.official,
      ),
    ]);

    expect(coordinator.current?.owner, AnkiEngineKind.legacy);
    coordinator.recordSession(total: 3, remembered: 2, forgotten: 1);
    coordinator.advance();
    expect(coordinator.current?.owner, AnkiEngineKind.official);
    coordinator.recordFailure(StateError('source unavailable'));
    coordinator.advance();

    expect(coordinator.isComplete, isTrue);
    expect(coordinator.totalCount, 3);
    expect(coordinator.rememberedCount, 2);
    expect(coordinator.forgottenCount, 1);
    expect(coordinator.failures.single.target.importOrSourceId, 'src-b');
  });

  test('review all plans across every source, reporting failures', () {
    const plan = OfficialReviewAllPlan(
      sourceIds: ['src-a', 'src-b'],
      cardIds: {1, 2, 3, 4},
      failedSourceIds: ['src-c'],
    );
    expect(plan.sourceIds, hasLength(2));
    expect(plan.cardIds, {1, 2, 3, 4});
    expect(plan.isPartial, isTrue, reason: 'src-c failed and must surface');
    expect(plan.isEmpty, isFalse);
  });

  test('a complete plan is not partial', () {
    const plan = OfficialReviewAllPlan(
      sourceIds: ['src-a'],
      cardIds: {1},
      failedSourceIds: [],
    );
    expect(plan.isPartial, isFalse);
  });

  test('empty importId loads an aggregate multi-source batch', () async {
    // Two sources' due sets: 1/2 from source A, 3/4 from source B. The
    // router target for '' must union them instead of answering with the
    // first source.
    final loader = OfficialFormalReviewProductionLoader(
      flags: _flags,
      engine: engine,
      resolveTarget: (importId) async => OfficialAnkiRoutedSource(
        importId: '',
        sourceId: 'official-all',
        deckId: -1,
        cardIds: const {1, 2, 3, 4},
      ),
      resolveReviewAllPlan: () async => const OfficialReviewAllPlan(
        sourceIds: ['src-a', 'src-b'],
        cardIds: {1, 2, 3, 4},
        failedSourceIds: [],
      ),
      sessionFactory: ({
        required engine,
        required allowedCardIds,
      }) async =>
          OfficialReviewSession(
        engine: engine,
        flags: _flags,
        allowedCardIds: allowedCardIds,
        profileId: 'profile-test',
      ),
      // Placement/introduction gate open for every card.
      introducedCardIds: (sourceId) => const {1, 2, 3, 4},
      activePlacementCardIds: (sourceId) => const {1, 2, 3, 4},
      profileId: 'profile-test',
    );

    final batch = await loader.load(importId: '', courseId: 'anki');

    expect(batch, isNotNull);
    // Both sources' cards are consumed in one session — the whole point of
    // review-all (previously only the FIRST source was served).
    expect(batch!.items.map((i) => i.cardKey.cardId).toSet(), {1, 2, 3, 4});
    expect(batch.reviewAllPlan?.sourceIds, ['src-a', 'src-b']);
    expect(batch.reviewAllPlan?.isPartial, isFalse);
    expect(batch.liveQueue, isNotNull,
        reason: 'engine-rendered batches must carry the live queue driver');
  });

  test('a per-source deck review still opens that deck only', () async {
    final loader = OfficialFormalReviewProductionLoader(
      flags: _flags,
      engine: engine,
      resolveTarget: (importId) async => OfficialAnkiRoutedSource(
        importId: importId,
        sourceId: importId,
        deckId: 1,
        cardIds: const {1, 2},
      ),
      sessionFactory: ({
        required engine,
        required allowedCardIds,
      }) async =>
          OfficialReviewSession(
        engine: engine,
        flags: _flags,
        allowedCardIds: allowedCardIds,
        profileId: 'profile-test',
      ),
      introducedCardIds: (sourceId) => const {1, 2},
      activePlacementCardIds: (sourceId) => const {1, 2},
      profileId: 'profile-test',
    );

    final batch = await loader.load(importId: 'src-a', courseId: 'anki-src-a');

    expect(batch, isNotNull);
    expect(batch!.items.map((i) => i.cardKey.cardId).toSet(), {1, 2});
    expect(batch.reviewAllPlan, isNull,
        reason: 'deck review is not review-all');
  });

  test('fidelity-first presentations reach the batch items', () async {
    engine.renders[1] = OfficialAnkiRenderedCard(
      cardId: 1,
      questionHtml: '<b>rich</b>',
      answerHtml: '<i>answer</i>',
      questionDisplayHtml: 'rich',
      answerDisplayHtml: 'answer',
      css: '.card{}',
      templateOrdinal: 0,
      bodyClass: 'card card1',
    );
    final loader = OfficialFormalReviewProductionLoader(
      flags: _flags,
      engine: engine,
      resolveTarget: (importId) async => OfficialAnkiRoutedSource(
        importId: 'src-a',
        sourceId: 'src-a',
        deckId: 1,
        cardIds: const {1},
      ),
      sessionFactory: ({
        required engine,
        required allowedCardIds,
      }) async =>
          OfficialReviewSession(
        engine: engine,
        flags: _flags,
        allowedCardIds: allowedCardIds,
        profileId: 'profile-test',
      ),
      introducedCardIds: (sourceId) => const {1},
      activePlacementCardIds: (sourceId) => const {1},
      profileId: 'profile-test',
    );

    final batch = await loader.load(importId: 'src-a', courseId: 'anki-src-a');

    expect(batch!.items.single.presentation.kind, CardPresentationKind.fidelity,
        reason: 'rich HTML must not be downgraded to a stripped flip card');
    expect(
      batch.fidelityInteractions[batch.items.single.sessionItemId]?.frontHtml,
      contains('<b>rich</b>'),
    );
  });
}
