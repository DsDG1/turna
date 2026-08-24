import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/core/html_stripper.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/course/interaction.dart';

/// Production loader that builds an Official formal-review batch for the
/// shared [AnkiReviewSessionPage] host (doc 34 W5).
///
/// Default presentations come from [OfficialAnkiEngine.renderCard] — never
/// empty Fidelity stubs. Flip faces use stripped display HTML; fidelity HTML
/// is also returned so the shared host can render WebView when needed.
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

  Future<OfficialFormalReviewBatch?> load({
    required String importId,
    required String courseId,
  }) async {
    final resolvedFlags = flags ?? OfficialAnkiFeatureFlags.current;
    if (!resolvedFlags.allowsOfficialScheduler) return null;

    final target = resolveTarget != null
        ? await resolveTarget!(importId)
        : (importId.isEmpty
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

    if (target != null) {
      await session.openDeck(target.deckId);
    } else {
      await session.openDueDeck();
    }
    final queue = session.queue;
    final sourceId = target?.sourceId ??
        (importId.isEmpty ? 'official-all' : importId);

    CanonicalCardKey key(int cardId) => CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: profileId,
          sourceId: sourceId,
          cardId: cardId,
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

    final rendered = presentationsForCards != null
        ? null
        : await _renderPresentations(
            engine: resolvedEngine,
            sourceId: sourceId,
            cards: queue.cards,
          );
    final presentations = presentationsForCards != null
        ? await presentationsForCards!(
            sourceId: sourceId,
            cards: queue.cards,
          )
        : rendered!.presentations;

    final introIds = introducedCardIds?.call(sourceId) ??
        (importId.isEmpty
            ? {
                for (final id in OfficialAnkiHomeDue.officialImportIds)
                  ...CardIntroductionStore.resolve()
                      .introducedCardIdsForSource(id),
              }
            : CardIntroductionStore.resolve()
                .introducedCardIdsForSource(sourceId));
    final placementFromHome = importId.isEmpty
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

    final batch = const FormalReviewLauncher().assembleOfficialBatch(
      session: session,
      sourceId: sourceId,
      courseId: courseId,
      queueCards: queue.cards,
      presentations: presentations,
      activePlacementCardKeys: {for (final id in placementIds) key(id)},
      introducedCardKeys: {for (final id in introIds) key(id)},
      suspendedCardKeys: {
        for (final id
            in OfficialAnkiHomeDue.suspendedCardIdsByImport[importId] ??
                const <int>{})
          key(id),
      },
      buriedCardKeys: {
        for (final id
            in OfficialAnkiHomeDue.buriedCardIdsByImport[importId] ??
                const <int>{})
          key(id),
      },
      retiredCardKeys: {
        for (final id
            in OfficialAnkiHomeDue.retiredCardIdsByImport[importId] ??
                const <int>{})
          key(id),
      },
    );

    final assembledIds = {
      for (final item in batch.items) item.cardKey.cardId,
    };
    if (assembledIds.isNotEmpty) {
      session.restrictAllowedCards(assembledIds);
    }

    // Key HTML faces by the assembled sessionItemId (mode-source-card).
    final byCardId = rendered?.htmlByCardId ?? const <int, AnkiHtmlCard>{};
    final fidelity = <String, AnkiHtmlCard>{
      for (final item in batch.items)
        if (byCardId.containsKey(item.cardKey.cardId))
          item.sessionItemId: byCardId[item.cardKey.cardId]!,
    };
    return OfficialFormalReviewBatch(
      items: batch.items,
      ledger: batch.ledger,
      session: batch.session,
      fidelityInteractions: fidelity,
    );
  }

  Future<_RenderedPresentations> _renderPresentations({
    required OfficialAnkiEngine engine,
    required String sourceId,
    required Iterable<OfficialReviewQueueCard> cards,
  }) async {
    final presentations = <CanonicalCardKey, CardPresentation>{};
    final htmlByCardId = <int, AnkiHtmlCard>{};
    for (final card in cards) {
      final cardKey = CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: sourceId,
        cardId: card.cardId,
      );
      final rendered = await engine.renderCard(cardId: card.cardId);
      final frontPlain = stripHtml(rendered.questionDisplayHtml).trim();
      final backPlain = stripHtml(rendered.answerDisplayHtml).trim();
      final frontText =
          frontPlain.isNotEmpty ? frontPlain : rendered.questionHtml.trim();
      final backText =
          backPlain.isNotEmpty ? backPlain : rendered.answerHtml.trim();
      if (frontText.isEmpty && backText.isEmpty) {
        // Never assemble a blank face — skip rather than stub empty Fidelity.
        continue;
      }
      presentations[cardKey] = FlipCardPresentation(
        cardKey: cardKey,
        frontText: frontText.isEmpty ? '—' : frontText,
        backText: backText.isEmpty ? '—' : backText,
        sourceFingerprint: 'official-render-${card.cardId}',
      );
      htmlByCardId[card.cardId] = AnkiHtmlCard(
        id: 'official-$sourceId-${card.cardId}',
        frontHtml: rendered.questionHtml,
        backHtml: rendered.answerHtml,
        css: rendered.css,
        sourceCardId: '${card.cardId}',
        wordId: 'official-anki-$sourceId-c${card.cardId}',
      );
    }
    return _RenderedPresentations(
      presentations: presentations,
      htmlByCardId: htmlByCardId,
    );
  }

  Future<OfficialAnkiEngine?> _requireEngine() async {
    final existing = OfficialAnkiCompositionRoot.engine;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    await OfficialAnkiCompositionRoot.requireImporter(supportDir: support);
    return OfficialAnkiCompositionRoot.engine;
  }

  Future<OfficialAnkiRoutedSource?> _resolveAnyProductionTarget() async {
    final support = await getApplicationSupportDirectory();
    const router = OfficialAnkiProductionRouter();
    final paths = router.pathsForDefaultProfile(support);
    if (!paths.catalogFile.existsSync()) return null;
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
        if (target != null) return target;
      }
      return null;
    } finally {
      catalog.close();
    }
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

class _RenderedPresentations {
  const _RenderedPresentations({
    required this.presentations,
    required this.htmlByCardId,
  });

  final Map<CanonicalCardKey, CardPresentation> presentations;
  final Map<int, AnkiHtmlCard> htmlByCardId;
}
