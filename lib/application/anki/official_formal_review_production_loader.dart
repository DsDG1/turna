import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
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

/// Production loader that builds an Official formal-review batch for the
/// shared [AnkiReviewSessionPage] host (doc 34 W5, plan 34 R2).
///
/// Presentations come from [OfficialAnkiEngine.renderCard] with a
/// fidelity-first policy: rich HTML becomes [FidelityCardPresentation]
/// (rendered by the shared host's WebView); only genuinely plain-text
/// cards stay flip. The batch carries a live queue driver so the page
/// follows the scheduler's refreshed queue after every answer instead of a
/// fixed pre-assembled array. An empty importId plans a Review All across
/// EVERY official source — never just the first.
class OfficialFormalReviewProductionLoader {
  const OfficialFormalReviewProductionLoader({
    this.flags,
    this.engine,
    this.sessionFactory,
    this.resolveTarget,
    this.resolveReviewAllPlan,
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

  /// Test seam for the Review All planner. Production unions every
  /// official source and reports the ones that failed to resolve.
  final Future<OfficialReviewAllPlan?> Function()? resolveReviewAllPlan;

  /// Test-only override. Production leaves this null and renders via the
  /// engine so faces are never blank Fidelity stubs.
  final Future<Map<CanonicalCardKey, CardPresentation>> Function({
    required String sourceId,
    required Iterable<OfficialReviewQueueCard> cards,
  })? presentationsForCards;
  final Set<int> Function(String sourceId)? introducedCardIds;
  final Set<int> Function(String sourceId)? activePlacementCardIds;
  final String profileId;

  Future<OfficialFormalReviewBatch?> load({
    required String importId,
    required String courseId,
  }) async {
    final resolvedFlags = flags ?? OfficialAnkiFeatureFlags.current;
    if (!resolvedFlags.allowsOfficialScheduler) return null;

    final reviewAll = importId.isEmpty;
    final target = resolveTarget != null
        ? await resolveTarget!(importId)
        : (reviewAll
            ? await _resolveAnyProductionTarget()
            : await _resolveTargetProduction(importId));
    if (target == null && importId.isNotEmpty) return null;

    final resolvedEngine = engine ?? await _requireEngine();
    if (resolvedEngine == null) return null;

    final allowed = target?.cardIds;
    final session = sessionFactory != null
        ? await sessionFactory!(
            engine: resolvedEngine,
            allowedCardIds: allowed,
          )
        : OfficialReviewSession(
            engine: resolvedEngine,
            flags: resolvedFlags,
            allowedCardIds: allowed,
            profileId: profileId,
          );

    if (target != null && target.deckId >= 0) {
      await session.openDeck(target.deckId);
    } else {
      // Review All (and router targets without a deck): the whole due
      // queue inside the allowed set — every participating source.
      await session.openDueDeck();
    }
    final queue = session.queue;
    final sourceId =
        target?.sourceId ?? (reviewAll ? 'official-all' : importId);

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
      return const FormalReviewLauncher().assembleOfficialBatch(
        session: session,
        sourceId: sourceId,
        courseId: courseId,
        queueCards: const [],
        presentations: const {},
        activePlacementCardKeys: const {},
        introducedCardKeys: const {},
      );
    }

    final faces = <int, OfficialRenderedFace>{};
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
        } catch (_) {
          // Unrenderable cards stay out of the batch; the scheduler
          // re-serves them on a later session.
          continue;
        }
      }
      presentations = {
        for (final face in faces.values)
          face.presentation.cardKey: face.presentation,
      };
    }

    final introIds = introducedCardIds?.call(sourceId) ??
        (reviewAll
            ? {
                for (final id in OfficialAnkiHomeDue.officialImportIds)
                  ...CardIntroductionStore.resolve()
                      .introducedCardIdsForSource(id),
              }
            : CardIntroductionStore.resolve()
                .introducedCardIdsForSource(sourceId));
    final placementFromHome = reviewAll
        ? {
            for (final ids
                in OfficialAnkiHomeDue.activePlacementCardIdsByImport.values)
              ...ids,
          }
        : OfficialAnkiHomeDue.activePlacementCardIdsByImport[importId];
    final placementIds = activePlacementCardIds?.call(sourceId) ??
        (placementFromHome != null && placementFromHome.isNotEmpty
            ? placementFromHome
            : target?.cardIds ?? {for (final card in queue.cards) card.cardId});

    final placementKeys = {for (final id in placementIds) key(id)};
    final introducedKeys = {for (final id in introIds) key(id)};
    final suspendedKeys = {
      for (final id
          in (OfficialAnkiHomeDue.suspendedCardIdsByImport[importId] ??
              (reviewAll
                  ? {
                      for (final ids in OfficialAnkiHomeDue
                          .suspendedCardIdsByImport.values)
                        ...ids,
                    }
                  : const <int>{})))
        key(id),
    };
    final buriedKeys = {
      for (final id in (OfficialAnkiHomeDue.buriedCardIdsByImport[importId] ??
          (reviewAll
              ? {
                  for (final ids
                      in OfficialAnkiHomeDue.buriedCardIdsByImport.values)
                    ...ids,
                }
              : const <int>{})))
        key(id),
    };
    final retiredKeys = {
      for (final id in (OfficialAnkiHomeDue.retiredCardIdsByImport[importId] ??
          (reviewAll
              ? {
                  for (final ids
                      in OfficialAnkiHomeDue.retiredCardIdsByImport.values)
                    ...ids,
                }
              : const <int>{})))
        key(id),
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

    final plan = reviewAll
        ? (resolveReviewAllPlan != null
            ? await resolveReviewAllPlan!()
            : await _planReviewAll(target))
        : null;

    return OfficialFormalReviewBatch(
      items: batch.items,
      ledger: batch.ledger,
      session: batch.session,
      fidelityInteractions: fidelity,
      liveQueue: liveQueue,
      reviewAllPlan: plan,
    );
  }

  Future<OfficialAnkiEngine?> _requireEngine() async {
    final existing = OfficialAnkiCompositionRoot.engine;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
    return OfficialAnkiCompositionRoot.engine;
  }

  /// Review All (plan 34 R2-3): aggregate EVERY official source's formal
  /// due set — sources that fail to resolve are reported, never silently
  /// dropped, and never answered with "just the first source".
  Future<OfficialAnkiRoutedSource?> _resolveAnyProductionTarget() async {
    final support = await getApplicationSupportDirectory();
    const router = OfficialAnkiProductionRouter();
    final paths = router.pathsForDefaultProfile(support);
    if (!paths.catalogFile.existsSync()) return null;
    final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
    try {
      final dao = OfficialAnkiMigrationDao(catalog);
      final sources = OfficialAnkiSourceDao(catalog);
      final cardIds = <int>{};
      for (final id in router.officialImportIds(dao: dao)) {
        final target = router.reviewTargetForImport(
          dao: dao,
          sources: sources,
          importId: id,
          profileId: profileId,
        );
        if (target == null) continue;
        cardIds.addAll(target.cardIds);
      }
      if (cardIds.isEmpty) return null;
      // deckId -1 → openDueDeck inside the unioned allowed set.
      return OfficialAnkiRoutedSource(
        importId: '',
        sourceId: 'official-all',
        deckId: -1,
        cardIds: cardIds,
      );
    } finally {
      catalog.close();
    }
  }

  Future<OfficialReviewAllPlan> _planReviewAll(
    OfficialAnkiRoutedSource? aggregate,
  ) async {
    final support = await getApplicationSupportDirectory();
    const router = OfficialAnkiProductionRouter();
    final paths = router.pathsForDefaultProfile(support);
    final sourceIds = <String>[];
    final failed = <String>[];
    if (paths.catalogFile.existsSync()) {
      final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
      try {
        final dao = OfficialAnkiMigrationDao(catalog);
        final sources = OfficialAnkiSourceDao(catalog);
        for (final id in router.officialImportIds(dao: dao)) {
          final target = router.reviewTargetForImport(
            dao: dao,
            sources: sources,
            importId: id,
            profileId: profileId,
          );
          if (target == null) {
            failed.add(id);
          } else {
            sourceIds.add(target.sourceId);
          }
        }
      } finally {
        catalog.close();
      }
    }
    return OfficialReviewAllPlan(
      sourceIds: sourceIds,
      cardIds: aggregate?.cardIds ?? const <int>{},
      failedSourceIds: failed,
    );
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
