import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:turna/core/fsrs_optimizer.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/course/srs_word.dart';

void main() {
  group('FsrsLiteOptimizer', () {
    ReviewEventRecord ev(
      String id,
      DateTime at,
      int quality,
    ) =>
        ReviewEventRecord(
          cardId: id,
          queue: 'srs',
          reviewedAt: at,
          quality: quality,
          prevIntervalDays: 1,
          nextIntervalDays: 1,
          prevEase: 2.5,
          nextEase: 2.5,
          reps: 1,
          lapses: quality < 3 ? 1 : 0,
          type: SrsItemType.word,
        );

    test('rejects when below min review count', () {
      final t0 = DateTime(2026, 1, 1);
      final events = <ReviewEventRecord>[
        for (var i = 0; i < 10; i++) ev('c$i', t0.add(Duration(days: i)), 4),
        for (var i = 0; i < 10; i++)
          ev('c$i', t0.add(Duration(days: i + 1)), 4),
      ];
      final r = FsrsLiteOptimizer(minReviews: 300).optimize(events);
      expect(r.accepted, isFalse);
      expect(r.message, 'need_more_reviews');
    });

    test('runs and returns finite loss with enough reviews', () {
      final t0 = DateTime(2026, 1, 1);
      final events = <ReviewEventRecord>[];
      // 50 cards × 8 reviews = 400 events
      for (var c = 0; c < 50; c++) {
        for (var r = 0; r < 8; r++) {
          final pass = r % 3 != 0; // mix fails
          events.add(ev(
            'card-$c',
            t0.add(Duration(days: r * 3 + c % 3)),
            pass ? 4 : 1,
          ));
        }
      }
      final r = FsrsLiteOptimizer(
        minReviews: 300,
        epochs: 8,
      ).optimize(events);
      expect(r.reviewCount, greaterThanOrEqualTo(300));
      expect(r.baselineLoss.isFinite, isTrue);
      expect(r.optimizedLoss.isFinite, isTrue);
      expect(r.parameters, hasLength(21));
      // Accepted or no_improvement — both valid; never crash.
      expect(
        r.message == 'accepted' || r.message == 'no_improvement',
        isTrue,
      );
    });

    test('cardsFromEvents groups and requires 2+ reviews', () {
      final t0 = DateTime(2026, 1, 1);
      final events = [
        ev('a', t0, 4),
        ev('a', t0.add(const Duration(days: 2)), 1),
        ev('b', t0, 4), // single — dropped
      ];
      final cards = FsrsLiteOptimizer.cardsFromEvents(events);
      expect(cards, hasLength(1));
      expect(cards.single.reviews, hasLength(2));
    });

    group('quality', () {
      // Generative model = the optimizer's own forward model with PERTURBED
      // weights. Recovery then validates the loss/gradient machinery end to
      // end: if the fitter cannot recover parameters of its own model class
      // from clean data, it cannot be trusted on real (noisy) data.
      test('recovers known parameters from synthetic reviews', () {
        final truth = List<double>.from(fsrs.defaultParameters);
        // Perturb within package bounds: harder/easier initial stability and
        // a steeper decay — the weights the binary labels are most sensitive
        // to.
        truth[0] = 0.8; // S0(Again) — default ~0.4
        truth[2] = 4.5; // S0(Good) — default ~3.2
        truth[20] = truth[20].clamp(0.1, 0.75) + 0.05;

        final events = generateSyntheticReviews(truth, cards: 220, seed: 42);
        expect(events.length, greaterThan(1200));

        final optimizer = FsrsLiteOptimizer(
          minReviews: 300,
          epochs: 120,
          learningRate: 0.05,
        );
        final result = optimizer.optimize(events);

        expect(result.message, 'accepted');
        expect(result.optimizedLoss, lessThan(result.baselineLoss));

        // Recovery check: the fitted weights must sit measurably closer to
        // the generating weights than the defaults do.
        double dist(List<double> w) =>
            (w[0] - truth[0]) * (w[0] - truth[0]) +
            (w[2] - truth[2]) * (w[2] - truth[2]);
        expect(
          dist(result.parameters),
          lessThan(dist(fsrs.defaultParameters)),
          reason: 'fitted S0 weights must move toward the generating ones',
        );
      }, timeout: const Timeout(Duration(minutes: 4)));
    });
  });
}

/// Generate synthetic binary review history from weights [w] using the same
/// FSRS forward model the optimizer fits (initial S/D from the first grade,
/// then R-driven Bernoulli recall + stability/difficulty recursion).
List<ReviewEventRecord> generateSyntheticReviews(
  List<double> w, {
  required int cards,
  required int seed,
}) {
  final rng = Random(seed);
  final events = <ReviewEventRecord>[];
  const good = 3;
  const again = 1;

  double initialDifficulty(int g) =>
      (w[4] - exp(w[5] * (g - 1)) + 1).clamp(1.0, 10.0);
  double nextDifficulty(double d, int g) {
    final delta = -w[6] * (g - 3);
    final target = d + (10.0 - d) * delta / 9.0;
    return (w[7] * initialDifficulty(4) + (1.0 - w[7]) * target)
        .clamp(1.0, 10.0);
  }

  double retrievability(double t, double s) {
    final decay = -w[20].clamp(0.1, 0.8);
    final factor = pow(0.9, 1.0 / decay) - 1.0;
    return pow(1.0 + factor * t / max(s, 0.001), decay)
        .toDouble()
        .clamp(1e-6, 1.0 - 1e-6);
  }

  for (var c = 0; c < cards; c++) {
    var now = DateTime.utc(2026, 1, 1).add(Duration(hours: c));
    final firstRecalled = rng.nextBool();
    var s = firstRecalled ? w[2] : w[0];
    var d = initialDifficulty(firstRecalled ? good : again);
    events.add(_syntheticEvent('gen-$c', now, firstRecalled));
    final reviewCount = 4 + rng.nextInt(5);
    for (var i = 0; i < reviewCount; i++) {
      final gapDays = 1 + rng.nextInt(28);
      now = now.add(Duration(days: gapDays));
      final r = retrievability(gapDays.toDouble(), s);
      final recalled = rng.nextDouble() < r;
      events.add(_syntheticEvent('gen-$c', now, recalled));
      // Stability update with PRE-update difficulty, then difficulty —
      // the package's update order.
      if (recalled) {
        s = s *
            (1 +
                exp(w[8]) *
                    (11.0 - d) *
                    pow(max(s, 0.001), -w[9]) *
                    (exp(w[10] * (1.0 - r)) - 1.0));
      } else {
        final longTerm = w[11] *
            pow(d, -w[12]) *
            (pow(s + 1.0, w[13]) - 1.0) *
            exp(w[14] * (1.0 - r));
        s = min(longTerm, s / exp(w[17] * w[18]));
      }
      s = max(s, 0.001);
      d = nextDifficulty(d, recalled ? good : again);
    }
  }
  return events;
}

ReviewEventRecord _syntheticEvent(String cardId, DateTime at, bool recalled) {
  return ReviewEventRecord(
    cardId: cardId,
    queue: 'srs',
    reviewedAt: at,
    quality: recalled ? 4 : 1,
    prevIntervalDays: 0,
    nextIntervalDays: 0,
    prevEase: 2.5,
    nextEase: 2.5,
    reps: 1,
    lapses: 0,
  );
}
