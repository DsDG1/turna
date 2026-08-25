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
      var s = w[0]; // initial stability proxy for first grade
      var d = w[4];
      for (var i = 0; i < card.reviews.length; i++) {
        final rev = card.reviews[i];
        if (i == 0) {
          s = rev.recalled ? w[2] : w[0];
          d = rev.recalled ? w[4] : min(10.0, w[4] + 1.0);
        } else {
          final r = _retrievability(rev.deltaDays, s, w);
          final y = rev.recalled ? 1.0 : 0.0;
          loss += _bce(y, r);
          n++;
          if (rev.recalled) {
            // Stability increase (simplified FSRS-style).
            const hardPen = 1.0;
            final sInc = exp(w[8]) *
                pow(11.0 - d, w[9]) *
                pow(s, -w[10]) *
                (exp(w[11] * (1.0 - r)) - 1.0) *
                hardPen;
            s = max(0.001, s * max(1.0, sInc));
          } else {
            s = max(
              0.001,
              w[11] *
                  pow(d, -w[12]) *
                  (pow(s + 1.0, w[13]) - 1.0) *
                  exp(w[14] * (1.0 - r)),
            );
            d = min(10.0, d + 0.5);
          }
        }
      }
    }
    return n == 0 ? 0.0 : loss / n;
  }

  int _accumulateGrad(
    FsrsTrainCard card,
    List<double> w,
    List<double> grad,
  ) {
    // Finite-difference gradient on a subset of weights that dominate R.
    // Full analytic grad is large; FD is fine for lite mobile optimizer.
    const eps = 1e-3;
    final base = _cardLoss(card, w);
    var samples = 0;
    // Touch initial S and decay-related weights more than grade-specific Easy.
    final indices = <int>[0, 1, 2, 3, 4, 8, 9, 10, 11, 12, 13, 14, 20];
    for (final i in indices) {
      if (i >= w.length) continue;
      final w2 = List<double>.from(w);
      w2[i] = (w2[i] + eps).clamp(
        fsrs.lowerBoundsParameters[i],
        fsrs.upperBoundsParameters[i],
      );
      final loss2 = _cardLoss(card, w2);
      grad[i] += (loss2 - base) / eps;
      samples++;
    }
    return samples > 0 ? 1 : 0;
  }

  double _cardLoss(FsrsTrainCard card, List<double> w) {
    var loss = 0.0;
    var n = 0;
    var s = w[0];
    var d = w[4];
    for (var i = 0; i < card.reviews.length; i++) {
      final rev = card.reviews[i];
      if (i == 0) {
        s = rev.recalled ? w[2] : w[0];
        d = rev.recalled ? w[4] : min(10.0, w[4] + 1.0);
        continue;
      }
      final r = _retrievability(rev.deltaDays, s, w);
      loss += _bce(rev.recalled ? 1.0 : 0.0, r);
      n++;
      if (rev.recalled) {
        final sInc = exp(w[8]) *
            pow(11.0 - d, w[9]) *
            pow(max(s, 0.001), -w[10]) *
            (exp(w[11] * (1.0 - r)) - 1.0);
        s = max(0.001, s * max(1.0, sInc));
      } else {
        s = max(
          0.001,
          w[11] *
              pow(d, -w[12]) *
              (pow(s + 1.0, w[13]) - 1.0) *
              exp(w[14] * (1.0 - r)),
        );
        d = min(10.0, d + 0.5);
      }
    }
    return n == 0 ? 0.0 : loss / n;
  }

  double _retrievability(double t, double s, List<double> w) {
    // Power-curve style used by recent FSRS: R = (1 + factor * t / S)^decay
    final decay = -w[20].clamp(0.1, 0.8);
    final factor = pow(0.9, 1.0 / decay) - 1.0;
    final ss = max(s, 0.001);
    return pow(1.0 + factor * t / ss, decay).toDouble().clamp(1e-6, 1.0 - 1e-6);
  }

  double _bce(double y, double p) {
    final pp = p.clamp(1e-6, 1.0 - 1e-6);
    return -(y * log(pp) + (1.0 - y) * log(1.0 - pp));
  }
}
