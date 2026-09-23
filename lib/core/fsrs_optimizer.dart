// Dart imports:
import 'dart:math';

// Package imports:
import 'package:fsrs/fsrs.dart' as fsrs;

// Project imports:
import 'package:turna/data/review_history_dao.dart';

/// Minimum review events before local weight fitting is allowed.
const int kFsrsOptimizeMinReviews = 300;

/// Result of a local FSRS weight fit attempt (ADR 0029).
class FsrsOptimizeResult {
  final bool accepted;
  final List<double> parameters;
  final double baselineLoss;
  final double optimizedLoss;
  final int reviewCount;
  final int cardCount;
  final String message;

  const FsrsOptimizeResult({
    required this.accepted,
    required this.parameters,
    required this.baselineLoss,
    required this.optimizedLoss,
    required this.reviewCount,
    required this.cardCount,
    required this.message,
  });
}

/// One review step for training (binary: fail/pass).
class FsrsTrainReview {
  final double deltaDays;
  final bool recalled;
  const FsrsTrainReview({required this.deltaDays, required this.recalled});
}

/// Per-card chronological review sequence.
class FsrsTrainCard {
  final List<FsrsTrainReview> reviews;
  const FsrsTrainCard(this.reviews);
}

/// Lite local FSRS parameter fitter (pure Dart, no FFI).
///
/// Uses binary cross-entropy on pass/fail labels and projected gradient
/// descent with package bound constraints. Accepts new weights only when
/// train loss improves by [minRelativeImprove].
///
/// The forward simulation mirrors the fsrs 2.0.1 scheduler the fitted
/// weights are fed back into, formula for formula (see `_simulateCard`):
/// FSRS-5 initial S/D, the damped w[7] mean-reversion difficulty update,
/// the recall/lapse stability recursions including the w[17]·w[18]
/// short-term cap, and the 0.9-anchored forgetting curve. A fit against a
/// divergent model would tune weights that degrade real scheduling.
///
/// Weights the binary model never exercises are neither trained nor
/// consumed: w[15] (hard penalty), w[16] (easy bonus), w[19] (short-term
/// learning-step increase — training deltas are day-scale).
class FsrsLiteOptimizer {
  FsrsLiteOptimizer({
    this.minReviews = kFsrsOptimizeMinReviews,
    this.epochs = 40,
    this.learningRate = 0.02,
    this.minRelativeImprove = 0.005,
  });

  final int minReviews;
  final int epochs;
  final double learningRate;
  final double minRelativeImprove;

  /// Binary grade mapping: a pass grades Good, a fail grades Again — the
  /// same mapping the production queues use (`ratingForOutcome`).
  static const int _goodRating = 3;
  static const int _againRating = 1;

  /// Package `stabilityMin` (fsrs 2.0.1).
  static const double _stabilityMin = 0.001;

  /// Build train cards from flat review history (oldest-first preferred).
  static List<FsrsTrainCard> cardsFromEvents(List<ReviewEventRecord> events) {
    final byCard = <String, List<ReviewEventRecord>>{};
    for (final e in events) {
      byCard.putIfAbsent(e.cardId, () => []).add(e);
    }
    final cards = <FsrsTrainCard>[];
    for (final list in byCard.values) {
      list.sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
      if (list.length < 2) continue;
      final reviews = <FsrsTrainReview>[];
      for (var i = 0; i < list.length; i++) {
        final cur = list[i];
        final delta = i == 0
            ? 0.0
            : max(
                0.0,
                cur.reviewedAt.difference(list[i - 1].reviewedAt).inMinutes /
                    1440.0,
              );
        reviews.add(FsrsTrainReview(
          deltaDays: delta,
          recalled: cur.recalled,
        ));
      }
      cards.add(FsrsTrainCard(reviews));
    }
    return cards;
  }

  int countReviews(List<FsrsTrainCard> cards) =>
      cards.fold<int>(0, (n, c) => n + c.reviews.length);

  /// Fit weights. Returns [FsrsOptimizeResult]; never throws on empty data.
  FsrsOptimizeResult optimize(List<ReviewEventRecord> events) {
    final cards = cardsFromEvents(events);
    final nReviews = countReviews(cards);
    final defaults = List<double>.from(fsrs.defaultParameters);

    if (nReviews < minReviews) {
      return FsrsOptimizeResult(
        accepted: false,
        parameters: defaults,
        baselineLoss: 0,
        optimizedLoss: 0,
        reviewCount: nReviews,
        cardCount: cards.length,
        message: 'need_more_reviews',
      );
    }

    final baselineLoss = _meanLoss(cards, defaults);
    var w = List<double>.from(defaults);

    for (var epoch = 0; epoch < epochs; epoch++) {
      final grad = List<double>.filled(w.length, 0.0);
      var samples = 0;
      for (final card in cards) {
        samples += _accumulateGrad(card, w, grad);
      }
      if (samples == 0) break;
      for (var i = 0; i < w.length; i++) {
        w[i] -= learningRate * (grad[i] / samples);
        w[i] = w[i].clamp(
          fsrs.lowerBoundsParameters[i],
          fsrs.upperBoundsParameters[i],
        );
      }
    }

    final optimizedLoss = _meanLoss(cards, w);
    final improved = optimizedLoss < baselineLoss * (1.0 - minRelativeImprove);

    return FsrsOptimizeResult(
      accepted: improved,
      parameters: improved ? w : defaults,
      baselineLoss: baselineLoss,
      optimizedLoss: optimizedLoss,
      reviewCount: nReviews,
      cardCount: cards.length,
      message: improved ? 'accepted' : 'no_improvement',
    );
  }

  double _meanLoss(List<FsrsTrainCard> cards, List<double> w) {
    var loss = 0.0;
    var n = 0;
    for (final card in cards) {
      final r = _simulateCard(card, w);
      loss += r.loss;
      n += r.samples;
    }
    return n == 0 ? 0.0 : loss / n;
  }

  int _accumulateGrad(
    FsrsTrainCard card,
    List<double> w,
    List<double> grad,
  ) {
    // Finite-difference gradient over every weight the forward model
    // consumes. Full analytic grad is large; FD is fine for a lite optimizer.
    const eps = 1e-3;
    final base = _simulateCard(card, w).loss;
    var samples = 0;
    const indices = [
      0, 1, 2, 3, // initial stability (Again/Hard/Good/Easy)
      4, 5, 6, 7, // initial difficulty + damped mean-reversion update
      8, 9, 10, // recall stability
      11, 12, 13, 14, // lapse stability
      17, 18, // lapse short-term cap
      20, // decay
    ];
    for (final i in indices) {
      if (i >= w.length) continue;
      final w2 = List<double>.from(w);
      w2[i] = (w2[i] + eps).clamp(
        fsrs.lowerBoundsParameters[i],
        fsrs.upperBoundsParameters[i],
      );
      final loss2 = _simulateCard(card, w2).loss;
      grad[i] += (loss2 - base) / eps;
      samples++;
    }
    return samples > 0 ? 1 : 0;
  }

  /// Forward-simulate one card under weights [w], mirroring the fsrs 2.0.1
  /// scheduler: the first review only fixes initial S/D (no loss term —
  /// those weights are free parameters); every later review contributes one
  /// BCE term and updates S (with the PRE-update difficulty, matching the
  /// package's order) then D. The single implementation backs both the
  /// loss and the finite-difference gradient so they cannot drift apart.
  _SimResult _simulateCard(FsrsTrainCard card, List<double> w) {
    var loss = 0.0;
    var samples = 0;
    var s = 1.0;
    var d = 5.0;
    for (var i = 0; i < card.reviews.length; i++) {
      final rev = card.reviews[i];
      final g = rev.recalled ? _goodRating : _againRating;
      if (i == 0) {
        // FSRS-5 initial stability: S0(G) = w[G-1].
        s = w[g - 1];
        d = _initialDifficulty(g, w);
        continue;
      }
      final r = _retrievability(rev.deltaDays, s, w);
      loss += _bce(rev.recalled ? 1.0 : 0.0, r);
      samples++;
      s = _nextStability(d: d, s: s, r: r, recalled: rev.recalled, w: w);
      d = _nextDifficulty(d, g, w);
    }
    return _SimResult(loss, samples);
  }

  /// FSRS-5 initial difficulty (package `_initialDifficulty`):
  /// D0(G) = w[4] − e^{w[5]·(G−1)} + 1, clamped to [1, 10].
  double _initialDifficulty(int g, List<double> w) =>
      (w[4] - exp(w[5] * (g - 1)) + 1).clamp(1.0, 10.0);

  /// FSRS-5 difficulty update (package `_nextDifficulty`): linear damping
  /// of ΔD = −w[6]·(G−3), then mean reversion toward D0(Easy) with weight
  /// w[7]. This replaced the old hardcoded ±0.5 steps, which mismatched the
  /// scheduler the fitted weights feed back into.
  double _nextDifficulty(double d, int g, List<double> w) {
    final delta = -w[6] * (g - 3);
    final damped = (10.0 - d) * delta / 9.0;
    final target = d + damped;
    final easyInitial = _initialDifficulty(4, w);
    return (w[7] * easyInitial + (1.0 - w[7]) * target).clamp(1.0, 10.0);
  }

  /// FSRS-5 stability after recall / lapse (package `_nextStability`).
  /// Good carries no hard penalty / easy bonus; a lapse takes the min of
  /// the long-term recursion and the w[17]·w[18] short-term cap.
  double _nextStability({
    required double d,
    required double s,
    required double r,
    required bool recalled,
    required List<double> w,
  }) {
    double next;
    if (recalled) {
      next = s *
          (1 +
              exp(w[8]) *
                  (11.0 - d) *
                  pow(max(s, _stabilityMin), -w[9]) *
                  (exp(w[10] * (1.0 - r)) - 1.0));
    } else {
      final longTerm = w[11] *
          pow(d, -w[12]) *
          (pow(s + 1.0, w[13]) - 1.0) *
          exp(w[14] * (1.0 - r));
      final shortTermCap = s / exp(w[17] * w[18]);
      next = min(longTerm, shortTermCap);
    }
    return max(next, _stabilityMin);
  }

  /// Forgetting curve (package `getCardRetrievability`): the curve factor
  /// is anchored at 0.9 — the package computes it once in the Scheduler
  /// constructor with a literal 0.9 (desiredRetention only scales the
  /// CHOSEN interval, not the curve), so a configurable anchor here would
  /// diverge from the scheduler being fitted for.
  double _retrievability(double t, double s, List<double> w) {
    final decay = -w[20].clamp(0.1, 0.8);
    final factor = pow(0.9, 1.0 / decay) - 1.0;
    final ss = max(s, _stabilityMin);
    return pow(1.0 + factor * t / ss, decay).toDouble().clamp(1e-6, 1.0 - 1e-6);
  }

  double _bce(double y, double p) {
    final pp = p.clamp(1e-6, 1.0 - 1e-6);
    return -(y * log(pp) + (1.0 - y) * log(1.0 - pp));
  }
}

class _SimResult {
  const _SimResult(this.loss, this.samples);
  final double loss;
  final int samples;
}
