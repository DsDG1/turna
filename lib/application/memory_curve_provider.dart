// Dart imports:
import 'dart:math';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/core/fsrs_engine.dart';
import 'package:varnamala/core/srs_scheduler.dart';
import 'package:varnamala/data/review_history_dao.dart';
import 'package:varnamala/domain/course/srs_word.dart';

/// Computes the memory-curve / retention snapshot shown on the profile stats
/// dashboard. Reads current SRS state from [SrsProvider] + [GrammarReviewProvider]
/// (in-memory caches) and per-card review history from [ReviewHistoryDao].
///
/// Retention model (ADR 0028): for each reviewed card, \(R = R_{\text{FSRS}}(t,S)\)
/// using true [SrsWord.stability] when present (fallback: intervalDays). The
/// aggregate is the mean \(R\) across reviewed cards. Maturity chips are
/// **workload buckets only** — not a four-stage “mastered” graduation.
@lazySingleton
class MemoryCurveProvider {
  MemoryCurveProvider(this._reviewDao, this._srs, this._grammar);

  final ReviewHistoryDao _reviewDao;
  final SrsProvider _srs;
  final GrammarReviewProvider _grammar;

  /// Shared FSRS math for \(R(t,S)\) (no fuzz / no side effects).
  final SrsScheduler _scheduler = FsrsEngine(enableFuzzing: false);

  /// Interval buckets (days) used to bin the empirical retention curve.
  static const List<int> intervalBuckets = [1, 4, 7, 14, 21, 30, 60, 90, 180];

  Future<MemoryCurveSnapshot> snapshot() async {
    final all = <SrsWord>[..._srs.state.values, ..._grammar.state.values];
    final now = DateTime.now();

    // Current retention: mean FSRS R over reviewed cards.
    var retentionSum = 0.0;
    var masterySum = 0.0;
    var tracked = 0;
    for (final w in all) {
      if (w.lastReviewedAt != null) {
        final r = _scheduler.retrievability(w, now: now);
        retentionSum += r;
        masterySum += _scheduler.masteryScore(w, now: now);
        tracked++;
      }
    }
    final currentRetention = tracked > 0 ? retentionSum / tracked : 1.0;
    final meanMastery = tracked > 0 ? masterySum / tracked : 0.0;

    // Forecast: cards due within 1 / 7 / 30 days (inclusive of overdue).
    var dueToday = 0;
    var due7Days = 0;
    var due30Days = 0;
    for (final w in all) {
      final diffDays = w.dueAt.difference(now).inMinutes / 1440.0;
      if (diffDays <= 0) dueToday++;
      if (diffDays <= 7) due7Days++;
      if (diffDays <= 30) due30Days++;
    }

    // Maturity breakdown.
    var newCards = 0, young = 0, mature = 0, leech = 0;
    for (final w in all) {
      if (w.isLeech) {
        leech++;
      } else if (w.reps == 0) {
        newCards++;
      } else if (w.intervalDays < 21) {
        young++;
      } else {
        mature++;
      }
    }

    // Empirical retention curve: recall rate bucketed by the interval that was
    // in effect *before* each review (prevIntervalDays).
    final events = await _reviewDao.allEvents();
    final bucketRecalled = <int, int>{};
    final bucketTotal = <int, int>{};
    for (final e in events) {
      final b = _bucketFor(e.prevIntervalDays);
      bucketTotal[b] = (bucketTotal[b] ?? 0) + 1;
      if (e.recalled) bucketRecalled[b] = (bucketRecalled[b] ?? 0) + 1;
    }
    final curve = <RetentionPoint>[];
    for (final b in intervalBuckets) {
      final total = bucketTotal[b] ?? 0;
      if (total == 0) continue;
      final recalled = bucketRecalled[b] ?? 0;
      curve.add(RetentionPoint(
        intervalBucketDays: b,
        retention: recalled / total,
        sampleSize: total,
      ));
    }

    return MemoryCurveSnapshot(
      currentRetention: currentRetention,
      meanMastery: meanMastery,
      trackedCards: tracked,
      totalCards: all.length,
      forecast: Forecast(dueToday: dueToday, due7Days: due7Days, due30Days: due30Days),
      maturity: MaturityBreakdown(
        newCards: newCards,
        young: young,
        mature: mature,
        leech: leech,
      ),
      retentionByInterval: curve,
      totalReviews: events.length,
    );
  }

  int _bucketFor(int intervalDays) {
    for (final b in intervalBuckets) {
      if (intervalDays <= b) return b;
    }
    return intervalBuckets.last;
  }
}

/// Immutable snapshot of memory-curve metrics for the stats dashboard.
class MemoryCurveSnapshot {
  final double currentRetention; // 0..1 predicted recall (mean R)
  /// Continuous mastery mean in [0,1] — not a discrete stage fraction.
  final double meanMastery;
  final int trackedCards; // cards with a lastReviewedAt
  final int totalCards; // all registered SRS items
  final Forecast forecast;
  final MaturityBreakdown maturity;
  final List<RetentionPoint> retentionByInterval;
  final int totalReviews;

  const MemoryCurveSnapshot({
    required this.currentRetention,
    this.meanMastery = 0.0,
    required this.trackedCards,
    required this.totalCards,
    required this.forecast,
    required this.maturity,
    required this.retentionByInterval,
    required this.totalReviews,
  });
}

class Forecast {
  final int dueToday;
  final int due7Days;
  final int due30Days;
  const Forecast({
    required this.dueToday,
    required this.due7Days,
    required this.due30Days,
  });
}

class MaturityBreakdown {
  final int newCards;
  final int young;
  final int mature;
  final int leech;
  const MaturityBreakdown({
    required this.newCards,
    required this.young,
    required this.mature,
    required this.leech,
  });
}

class RetentionPoint {
  final int intervalBucketDays;
  final double retention; // 0..1
  final int sampleSize;
  const RetentionPoint({
    required this.intervalBucketDays,
    required this.retention,
    required this.sampleSize,
  });
}
