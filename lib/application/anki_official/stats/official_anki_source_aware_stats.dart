import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// Proven, source-aware stats for Anki decks (doc 34 W7).
///
/// Official sources never invent Turna-FSRS "official retention". Catalog
/// card counts are inventory only ([metricsProven] false). Scheduler
/// new/review counts are proven when an [OfficialAnkiEngine] supplies them.
class OfficialAnkiSourceAwareStatsSnapshot {
  const OfficialAnkiSourceAwareStatsSnapshot({
    required this.sourceId,
    required this.owner,
    required this.totalCards,
    required this.metricsProven,
    this.newCount,
    this.reviewCount,
    this.note = 'catalog_card_count_only',
  });

  final String sourceId;
  final AnkiEngineKind owner;
  final int totalCards;
  final int? newCount;
  final int? reviewCount;

  /// True only for Official scheduler counts, never for FSRS retention.
  final bool metricsProven;
  final String note;
}

class OfficialAnkiSourceAwareStats {
  const OfficialAnkiSourceAwareStats({
    required this.sources,
    this.engine,
  });

  final OfficialAnkiSourceDao sources;
  final OfficialAnkiEngine? engine;

  Future<OfficialAnkiSourceAwareStatsSnapshot> forOfficialSource(
    String sourceId,
  ) async {
    final src = sources.findById(sourceId);
    if (src == null) {
      return OfficialAnkiSourceAwareStatsSnapshot(
        sourceId: sourceId,
        owner: AnkiEngineKind.official,
        totalCards: 0,
        metricsProven: false,
        note: 'official_source_missing',
      );
    }
    final total = sources.cardCount(sourceId);
    final engine = this.engine;
    if (engine == null) {
      return OfficialAnkiSourceAwareStatsSnapshot(
        sourceId: sourceId,
        owner: AnkiEngineKind.official,
        totalCards: total,
        metricsProven: false,
        note: 'official_catalog_counts_only',
      );
    }
    final cards = sources.listCardsForImport(
      sourceId: src.sourceId,
      profileId: src.profileId,
    );
    final deckId = cards.isEmpty ? 0 : cards.first.deckId;
    if (deckId <= 0) {
      return OfficialAnkiSourceAwareStatsSnapshot(
        sourceId: sourceId,
        owner: AnkiEngineKind.official,
        totalCards: total,
        metricsProven: false,
        note: 'official_catalog_counts_only',
      );
    }
    final counts = await engine.countsForDeckToday(deckId);
    return OfficialAnkiSourceAwareStatsSnapshot(
      sourceId: sourceId,
      owner: AnkiEngineKind.official,
      totalCards: total,
      newCount: counts.newCount,
      reviewCount: counts.reviewCount,
      metricsProven: true,
      note: 'official_deck_counts',
    );
  }

  /// Aggregate across Official sources only — never merges writers.
  OfficialAnkiSourceAwareStatsSnapshot aggregateOfficial(String profileId) {
    var total = 0;
    for (final src in sources.listSources(profileId)) {
      if (src.state != 'active') continue;
      total += sources.cardCount(src.sourceId);
    }
    return OfficialAnkiSourceAwareStatsSnapshot(
      sourceId: '*',
      owner: AnkiEngineKind.official,
      totalCards: total,
      metricsProven: false,
      note: 'official_catalog_aggregate',
    );
  }
}
