import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/stats/official_anki_retention_curve_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/memory_curve_provider.dart';

enum OfficialStatsAvailability {
  available,
  sourceMissing,
  engineUnavailable,
  staleEvidence,
}

/// Exact-source stats. Inventory remains useful when scheduler evidence is
/// unavailable, while every scheduler/revlog field is guarded by
/// [availability] so an error can never masquerade as a successful zero.
class OfficialAnkiSourceAwareStatsSnapshot {
  const OfficialAnkiSourceAwareStatsSnapshot({
    required this.sourceId,
    required this.owner,
    required this.totalCards,
    required this.availability,
    this.newCount,
    this.learningCount,
    this.reviewCount,
    this.suspendedCount,
    this.buriedCount,
    this.todayAnswerCount,
    this.todayLearnCount,
    this.todayReviewCount,
    this.todayRelearnCount,
    this.forecastDueToday,
    this.forecastDue7Days,
    this.forecastDue30Days,
    this.revlogCount,
    this.retentionPassed,
    this.retentionFailed,
    this.retentionByInterval = const [],
    this.unintroducedCount = 0,
    this.userSuspendedCount = 0,
    this.note = 'official_stats_available',
  });

  final String sourceId;
  final AnkiEngineKind owner;
  final int totalCards;
  final OfficialStatsAvailability availability;
  final int? newCount;
  final int? learningCount;
  final int? reviewCount;
  final int? suspendedCount;
  final int? buriedCount;
  final int? todayAnswerCount;
  final int? todayLearnCount;
  final int? todayReviewCount;
  final int? todayRelearnCount;
  final int? forecastDueToday;
  final int? forecastDue7Days;
  final int? forecastDue30Days;
  final int? revlogCount;
  final int? retentionPassed;
  final int? retentionFailed;
  final List<RetentionPoint> retentionByInterval;
  final int unintroducedCount;
  final int userSuspendedCount;
  final String note;

  bool get metricsProven => availability == OfficialStatsAvailability.available;

  int? get retentionSample => retentionPassed == null || retentionFailed == null
      ? null
      : retentionPassed! + retentionFailed!;

  double? get retention {
    final sample = retentionSample;
    if (sample == null || sample == 0) return null;
    return retentionPassed! / sample;
  }
}

class OfficialAnkiSourceAwareStats {
  const OfficialAnkiSourceAwareStats({required this.sources, this.engine});

  static const _batchSize = 200;

  final OfficialAnkiSourceDao sources;
  final OfficialAnkiEngine? engine;

  Future<OfficialAnkiSourceAwareStatsSnapshot> forOfficialSource(
    String sourceId,
  ) async {
    final src = sources.findById(sourceId);
    if (src == null) {
      return _unavailable(
        sourceId,
        0,
        OfficialStatsAvailability.sourceMissing,
        'official_source_missing',
      );
    }
    final cards = sources.listCardsForImport(
      sourceId: src.sourceId,
      profileId: src.profileId,
    );
    final total = cards.length;
    final engine = this.engine;
    if (engine == null) {
      return _unavailable(
        sourceId,
        total,
        OfficialStatsAvailability.engineUnavailable,
        'official_engine_unavailable',
      );
    }
    if (cards.isEmpty) {
      return _fromTotals(sourceId: sourceId, totalCards: 0);
    }

    final ids = cards.map((card) => card.cardId).toList(growable: false);
    var newCards = 0;
    var learningCards = 0;
    var reviewCards = 0;
    var suspendedCards = 0;
    var buriedCards = 0;
    var todayAnswers = 0;
    var todayLearn = 0;
    var todayReview = 0;
    var todayRelearn = 0;
    var dueToday = 0;
    var due7 = 0;
    var due30 = 0;
    var revlogs = 0;
    var retentionPassed = 0;
    var retentionFailed = 0;
    try {
      for (var start = 0; start < ids.length; start += _batchSize) {
        final end = (start + _batchSize).clamp(0, ids.length);
        final batch = await engine.statsForCardsBatch(ids.sublist(start, end));
        if (batch.requestedCardCount != batch.foundCardCount) {
          return _unavailable(
            sourceId,
            total,
            OfficialStatsAvailability.staleEvidence,
            'official_catalog_collection_drift',
          );
        }
        newCards += batch.newCards;
        learningCards += batch.learningCards;
        reviewCards += batch.reviewCards;
        suspendedCards += batch.suspendedCards;
        buriedCards += batch.buriedCards;
        todayAnswers += batch.todayAnswerCount;
        todayLearn += batch.todayLearnCount;
        todayReview += batch.todayReviewCount;
        todayRelearn += batch.todayRelearnCount;
        dueToday += batch.forecastDueToday;
        due7 += batch.forecastDue7Days;
        due30 += batch.forecastDue30Days;
        revlogs += batch.revlogCount;
        retentionPassed += batch.retentionPassed;
        retentionFailed += batch.retentionFailed;
      }
    } catch (_) {
      return _unavailable(
        sourceId,
        total,
        OfficialStatsAvailability.engineUnavailable,
        'official_stats_query_failed',
      );
    }

    List<RetentionPoint> retentionCurve = const [];
    var unintroducedCount = 0;
    var userSuspended = 0;
    try {
      retentionCurve = await const OfficialAnkiRetentionCurveService()
          .retentionCurveForCards(ids);
      final introduced = await CardIntroductionStore.resolve()
          .introducedCardIdsFromLedger(src.sourceId);
      unintroducedCount =
          cards.where((c) => !introduced.contains(c.cardId)).length;
      userSuspended = (suspendedCards > unintroducedCount)
          ? suspendedCards - unintroducedCount
          : 0;
    } catch (_) {}

    return _fromTotals(
      sourceId: sourceId,
      totalCards: total,
      newCards: newCards,
      learningCards: learningCards,
      reviewCards: reviewCards,
      suspendedCards: suspendedCards,
      buriedCards: buriedCards,
      todayAnswers: todayAnswers,
      todayLearn: todayLearn,
      todayReview: todayReview,
      todayRelearn: todayRelearn,
      dueToday: dueToday,
      due7: due7,
      due30: due30,
      revlogs: revlogs,
      retentionPassed: retentionPassed,
      retentionFailed: retentionFailed,
      retentionByInterval: retentionCurve,
      unintroducedCount: unintroducedCount,
      userSuspendedCount: userSuspended,
    );
  }

  OfficialAnkiSourceAwareStatsSnapshot _fromTotals({
    required String sourceId,
    required int totalCards,
    int newCards = 0,
    int learningCards = 0,
    int reviewCards = 0,
    int suspendedCards = 0,
    int buriedCards = 0,
    int todayAnswers = 0,
    int todayLearn = 0,
    int todayReview = 0,
    int todayRelearn = 0,
    int dueToday = 0,
    int due7 = 0,
    int due30 = 0,
    int revlogs = 0,
    int retentionPassed = 0,
    int retentionFailed = 0,
    List<RetentionPoint> retentionByInterval = const [],
    int unintroducedCount = 0,
    int userSuspendedCount = 0,
  }) {
    return OfficialAnkiSourceAwareStatsSnapshot(
      sourceId: sourceId,
      owner: AnkiEngineKind.official,
      totalCards: totalCards,
      availability: OfficialStatsAvailability.available,
      newCount: newCards,
      learningCount: learningCards,
      reviewCount: reviewCards,
      suspendedCount: suspendedCards,
      buriedCount: buriedCards,
      todayAnswerCount: todayAnswers,
      todayLearnCount: todayLearn,
      todayReviewCount: todayReview,
      todayRelearnCount: todayRelearn,
      forecastDueToday: dueToday,
      forecastDue7Days: due7,
      forecastDue30Days: due30,
      revlogCount: revlogs,
      retentionPassed: retentionPassed,
      retentionFailed: retentionFailed,
      retentionByInterval: retentionByInterval,
      unintroducedCount: unintroducedCount,
      userSuspendedCount: userSuspendedCount,
    );
  }

  OfficialAnkiSourceAwareStatsSnapshot _unavailable(
    String sourceId,
    int total,
    OfficialStatsAvailability availability,
    String reason,
  ) {
    return OfficialAnkiSourceAwareStatsSnapshot(
      sourceId: sourceId,
      owner: AnkiEngineKind.official,
      totalCards: total,
      availability: availability,
      note: reason,
    );
  }

  /// Inventory-only aggregate. Scheduler metrics require an async exact-card
  /// query per source and are intentionally not guessed here.
  OfficialAnkiSourceAwareStatsSnapshot aggregateOfficial(String profileId) {
    var total = 0;
    for (final src in sources.listSources(profileId)) {
      if (src.state != 'active') continue;
      total += sources.cardCount(src.sourceId);
    }
    return _unavailable(
      '*',
      total,
      OfficialStatsAvailability.engineUnavailable,
      'official_catalog_aggregate',
    );
  }
}
