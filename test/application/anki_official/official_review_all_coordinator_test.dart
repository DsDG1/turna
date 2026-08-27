// Review All tests (plan 34 R2-3 / OS-13 + maintainability plan Wave 3):
// review-all runs through the sequential FormalReviewSourceCoordinator — one
// real source per loader call, real sourceIds on every card key, failures
// recorded per source — never a synthetic aggregate source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/formal_review_source_coordinator.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
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
    coordinator.recordFailure(
      StateError('source unavailable'),
      kind: FormalReviewFailureKind.load,
    );
    coordinator.advance();

    expect(coordinator.isComplete, isTrue);
    expect(coordinator.totalCount, 3);
    expect(coordinator.rememberedCount, 2);
    expect(coordinator.forgottenCount, 1);
    expect(coordinator.failures.single.target.importOrSourceId, 'src-b');
    expect(coordinator.failures.single.kind, FormalReviewFailureKind.load);
    expect(coordinator.failures.single.retryable, isTrue);
  });

  test('each source is loaded separately with its real sourceId', () async {
    final loadedSources = <String>[];
    Future<OfficialFormalReviewLoadResult> loadSource(String sourceId) {
      loadedSources.add(sourceId);
      return OfficialFormalReviewProductionLoader(
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
      ).load(importId: sourceId, courseId: 'anki-$sourceId');
    }

    final coordinator = FormalReviewSourceCoordinator(const [
      FormalReviewSourceTarget(
        importOrSourceId: 'src-a',
        displayName: 'Official A',
        owner: AnkiEngineKind.official,
      ),
      FormalReviewSourceTarget(
        importOrSourceId: 'src-b',
        displayName: 'Official B',
        owner: AnkiEngineKind.official,
      ),
    ]);
    while (!coordinator.isComplete) {
      final target = coordinator.current!;
      final result = await loadSource(target.importOrSourceId);
      if (result is OfficialFormalReviewReady) {
        expect(
          result.batch.items.every(
            (i) => i.cardKey.sourceId == target.importOrSourceId,
          ),
          isTrue,
          reason: 'every card keeps its real source identity',
        );
        coordinator.recordSession(
          total: result.batch.items.length,
          remembered: result.batch.items.length,
          forgotten: 0,
        );
      } else if (result is OfficialFormalReviewNoDue) {
        // auto-advance
      }
      coordinator.advance();
    }

    expect(loadedSources, ['src-a', 'src-b'],
        reason: 'the loader is called once per real source, in frozen order');
    expect(coordinator.totalCount, greaterThan(0));
  });

  test('production loader rejects an empty source id', () async {
    final loader = OfficialFormalReviewProductionLoader(
      flags: _flags,
      engine: engine,
      profileId: 'profile-test',
    );
    expect(
      () => loader.load(importId: '', courseId: 'anki'),
      throwsArgumentError,
      reason: 'the synthetic aggregate entry point must not exist',
    );
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

    final result = await loader.load(importId: 'src-a', courseId: 'anki-src-a');

    expect(result, isA<OfficialFormalReviewReady>());
    final batch = (result as OfficialFormalReviewReady).batch;
    expect(batch.items.map((i) => i.cardKey.cardId).toSet(), {1, 2});
  });

  test('unintroduced scheduler cards are NoDue, not a ready empty session',
      () async {
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
      introducedCardIds: (_) => const {},
      activePlacementCardIds: (_) => const {1, 2},
      profileId: 'profile-test',
    );

    final result = await loader.load(importId: 'src-new', courseId: 'anki-src-new');
    expect(result, isA<OfficialFormalReviewNoDue>());
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

    final result = await loader.load(importId: 'src-a', courseId: 'anki-src-a');

    final batch = (result as OfficialFormalReviewReady).batch;
    expect(batch.items.single.presentation.kind, CardPresentationKind.fidelity,
        reason: 'rich HTML must not be downgraded to a stripped flip card');
    expect(
      batch.fidelityInteractions[batch.items.single.sessionItemId]?.frontHtml,
      contains('<b>rich</b>'),
    );
  });

  test('lib contains no synthetic official-all source id', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('official-all')) {
        violations.add(entity.path);
        continue;
      }
      if (entity.readAsStringSync().contains('official-all')) {
        violations.add(entity.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join(', '));
  });
}
