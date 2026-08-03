import 'package:flutter_test/flutter_test.dart';
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
  });
}
