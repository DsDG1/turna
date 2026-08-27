import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/course/interaction.dart';

/// Production loader that builds an Official formal-review batch for ONE
/// real source for the shared [AnkiReviewSessionPage] host (doc 34 W5,
/// plan 34 R2, maintainability plan Waves 2–3).
///
/// Presentations come from [OfficialAnkiEngine.renderCard] with a
/// fidelity-first policy: rich HTML becomes [FidelityCardPresentation]
/// (rendered by the shared host's WebView); only genuinely plain-text
/// cards stay flip. The batch carries a live queue driver so the page
/// follows the scheduler's refreshed queue after every answer instead of a
/// fixed pre-assembled array.
///
/// Contract (maintainability plan §9.2):
/// - [importId] MUST be a non-empty real source id — there is no
///   synthetic aggregate entry point; Review All is driven by
///   [FormalReviewSourceCoordinator] calling this loader once per source.
/// - Returns [OfficialFormalReviewReady] / [OfficialFormalReviewNoDue] /
///   [OfficialFormalReviewBlocked]; a non-empty queue with zero successful
///   renders is Blocked, never "no due".
/// - Render failures are structured [OfficialCardRenderFailure]s; the
///   loader never answers, buries or suspends anything.
class OfficialFormalReviewProductionLoader {
  const OfficialFormalReviewProductionLoader({
    this.flags,
    this.engine,
    this.sessionFactory,
    this.resolveTarget,
    this.presentationsForCards,
    this.introducedCardIds,
    this.activePlacementCardIds,
    this.profileId = CardIntroductionEligibility.defaultProfileId,
  });

  final OfficialAnkiFeatureFlags? flags;
  final OfficialAnkiEngine? engine;
  final Future<OfficialReviewSession> Function({
    required OfficialAnkiEngine engine,
    required Set<int>? allowedCardIds,
  })? sessionFactory;
  final Future<OfficialAnkiRoutedSource?> Function(String importId)?
      resolveTarget;

  /// Test-only override. Production leaves this null and renders via the
  /// engine so faces are never blank Fidelity stubs.
  final Future<Map<CanonicalCardKey, CardPresentation>> Function({
    required String sourceId,
    required Iterable<OfficialReviewQueueCard> cards,
  })? presentationsForCards;
  final Set<int> Function(String sourceId)? introducedCardIds;
  final Set<int> Function(String sourceId)? activePlacementCardIds;
  final String profileId;

  Future<OfficialFormalReviewLoadResult> load({
    required String importId,
    required String courseId,
  }) async {
    if (importId.isEmpty) {
      // Synthetic aggregate sources are forbidden (maintainability plan
      // §9.1) — Review All goes through the source coordinator.
      throw ArgumentError.value(
        importId,
        'importId',
        'must be a real non-empty source id',
      );
    }
    final resolvedFlags = flags ?? OfficialAnkiFeatureFlags.current;
    if (!resolvedFlags.allowsOfficialScheduler) {
      return const OfficialFormalReviewNoDue();
    }

    // Self-healing cold-start hydration: a fresh process has an empty
    // in-memory introduced set; without re-reading the ledger every due
    // card would be filtered out below and the session would end as NoDue
    // (the "暂无待复习" bug). Idempotent merge, no-op when already hydrated
    // in this pass.
    await CardIntroductionStore.resolve().hydrateFromLedger();

    final target = resolveTarget != null
        ? await resolveTarget!(importId)
        : await _resolveTargetProduction(importId);
    if (target == null) return const OfficialFormalReviewNoDue();

    final resolvedEngine = engine ?? await _requireEngine();
    if (resolvedEngine == null) return const OfficialFormalReviewNoDue();

    final session = sessionFactory != null
        ? await sessionFactory!(
            engine: resolvedEngine,
            allowedCardIds: target.cardIds,
          )
        : OfficialReviewSession(
            engine: resolvedEngine,
            flags: resolvedFlags,
            allowedCardIds: target.cardIds,
            profileId: profileId,
          );

    final sourceId = target.sourceId;

    if (target.deckId >= 0) {
      await session.openDeck(target.deckId);
    } else {
      // Router targets without a deck: the whole due queue inside the
      // allowed set of this one source.
      await session.openDueDeck();
    }
    final queue = session.queue;

    CanonicalCardKey key(int cardId) => CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: profileId,
          sourceId: sourceId,
          cardId: cardId,
        );

    final renderer = OfficialFormalReviewRenderer(
      engine: resolvedEngine,
      profileId: profileId,
    );

    if (queue == null || queue.cards.isEmpty) {
      session.dispose();
      return const OfficialFormalReviewNoDue();
    }

    final faces = <int, OfficialRenderedFace>{};
    final failures = <OfficialCardRenderFailure>[];
    Map<CanonicalCardKey, CardPresentation> presentations;
    if (presentationsForCards != null) {
      presentations = await presentationsForCards!(
        sourceId: sourceId,
        cards: queue.cards,
      );
    } else {
      for (final card in queue.cards) {
        try {
          faces[card.cardId] = await renderer.render(
            sourceId: sourceId,
            cardId: card.cardId,
          );
        } catch (error) {
          // Structured, visible, retryable (maintainability plan §8.1):
          // the card stays owed by the scheduler — never silently
          // dropped, never implicitly answered/buried/suspended.
          final failure = OfficialCardRenderFailure.fromError(
            error,
            sourceId: sourceId,
            cardId: card.cardId,
            stage: OfficialRenderFailureStage.load,
          );
          failures.add(failure);
          OfficialFormalReviewRenderAudit.recordRenderFailure(failure);
        }
      }
      presentations = {
        for (final face in faces.values) face.presentation.cardKey: face.presentation,
      };
    }

    if (presentations.isEmpty && failures.isNotEmpty) {
      // Queue non-empty + zero successful renders → Blocked. The page
      // shows the error and offers retry; nothing is scheduled implicitly.
      session.dispose();
      return OfficialFormalReviewBlocked(
        sourceId: sourceId,
        failures: failures,
        schedulerCardCount: queue.cards.length,
      );
    }

    final introIds = introducedCardIds?.call(sourceId) ??
        CardIntroductionStore.resolve().introducedCardIdsForSource(sourceId);
    final dueRepo = OfficialFormalDueRepository.instance;
    final perSource = dueRepo.snapshot.byImport[importId];
    final placementIds = activePlacementCardIds?.call(sourceId) ??
        (perSource != null && perSource.activePlacementCardIds.isNotEmpty
            ? perSource.activePlacementCardIds
            : target.cardIds);

    final placementKeys = {for (final id in placementIds) key(id)};
    final introducedKeys = {for (final id in introIds) key(id)};
    final suspendedKeys = {
      for (final id in (perSource?.suspendedCardIds ?? const <int>{})) key(id),
    };
    final buriedKeys = {
      for (final id in (perSource?.buriedCardIds ?? const <int>{})) key(id),
    };
    final retiredKeys = {
      for (final id in (perSource?.retiredCardIds ?? const <int>{})) key(id),
    };

    final batch = const FormalReviewLauncher().assembleOfficialBatch(
      session: session,
      sourceId: sourceId,
      courseId: courseId,
      queueCards: queue.cards,
      presentations: presentations,
      activePlacementCardKeys: placementKeys,
      introducedCardKeys: introducedKeys,
      suspendedCardKeys: suspendedKeys,
      buriedCardKeys: buriedKeys,
      retiredCardKeys: retiredKeys,
      // The assembler must key eligibility with the SAME profile the
      // loader builds card keys with, or every eligibility set misses.
      assembler: OfficialStudyBatchAssembler(profileId: profileId),
    );

    final assembledIds = {
      for (final item in batch.items) item.cardKey.cardId,
    };
    if (assembledIds.isNotEmpty) {
      session.restrictAllowedCards(assembledIds);
    }

    // Key fidelity HTML faces by the assembled sessionItemId.
    final byCardId = {
      for (final entry in faces.entries) entry.key: entry.value.htmlCard,
    };
    final fidelity = <String, AnkiHtmlCard>{
      for (final item in batch.items)
        if (byCardId.containsKey(item.cardKey.cardId))
          item.sessionItemId: byCardId[item.cardKey.cardId]!,
    };

    if (batch.items.isEmpty) {
      session.dispose();
      if (failures.isNotEmpty) {
        // Every card that rendered was filtered by eligibility, but some
        // renders also failed — the scheduler still owes those. Surface as
        // Blocked rather than pretending the source is done.
        return OfficialFormalReviewBlocked(
          sourceId: sourceId,
          failures: failures,
          schedulerCardCount: queue.cards.length,
        );
      }
      // Queue may still hold unintroduced new cards. Formal review is
      // empty — not a successful zero-card session.
      return const OfficialFormalReviewNoDue();
    }

    // Live queue driver: the page rebuilds the batch from the scheduler's
    // refreshed queue after every mutation (plan 34 D4). Legacy test
    // overrides without faces run without a live queue.
    final liveQueue = faces.isEmpty
        ? null
        : OfficialFormalReviewLiveQueue(
            session: session,
            sourceId: sourceId,
            courseId: courseId,
            renderer: renderer,
            assembler: OfficialStudyBatchAssembler(profileId: profileId),
            items: batch.items,
            activePlacementCardKeys: placementKeys,
            introducedCardKeys: introducedKeys,
            suspendedCardKeys: suspendedKeys,
            buriedCardKeys: buriedKeys,
            retiredCardKeys: retiredKeys,
          );
    liveQueue?.fidelityInteractions.addAll(fidelity);
    if (faces.isNotEmpty) {
      liveQueue!.adoptFaces(faces);
    }

    return OfficialFormalReviewReady(
      OfficialFormalReviewBatch(
        items: batch.items,
        ledger: batch.ledger,
        session: batch.session,
        fidelityInteractions: fidelity,
        liveQueue: liveQueue,
        failures: failures,
      ),
    );
  }

  Future<OfficialAnkiEngine?> _requireEngine() async {
    final existing = OfficialAnkiCompositionRoot.engine;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
    return OfficialAnkiCompositionRoot.engine;
  }

  Future<OfficialAnkiRoutedSource?> _resolveTargetProduction(
    String importId,
  ) async {
    final support = await getApplicationSupportDirectory();
    const router = OfficialAnkiProductionRouter();
    final paths = router.pathsForDefaultProfile(support);
    if (!paths.catalogFile.existsSync()) return null;
    final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
    try {
      return router.reviewTargetForImport(
        dao: OfficialAnkiMigrationDao(catalog),
        sources: OfficialAnkiSourceDao(catalog),
        importId: importId,
        profileId: profileId,
      );
    } finally {
      catalog.close();
    }
  }
}
