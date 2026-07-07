import 'package:words625/domain/course/srs_word.dart';

/// SM-2 spaced-repetition algorithm.
///
/// Quality grades follow SuperMemo 2 conventions:
///   0..2 → recall failed; reset interval
///   3..5 → recall succeeded; grow interval
///
/// [ReviewQuality] aliases the canonical 4-button mapping:
///   Again=1, Hard=3, Good=4, Easy=5
class Sm2Engine {
  const Sm2Engine();

  /// Initial ease factor for any new card.
  static const double initialEase = 2.5;

  /// Floor for ease (cards with very poor recall do not fall below this).
  static const double minEase = 1.3;

  /// Compute the next [SrsWord] state given the current [word] and the
  /// recall quality [quality] (clamped to 0..5).
  SrsWord review(SrsWord word, int quality) {
    final q = quality.clamp(0, 5);

    // Update ease factor.
    var ease = word.ease +
        (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (ease < minEase) ease = minEase;

    var reps = word.reps;
    var lapses = word.lapses;
    int interval;

    if (q < 3) {
      // Failed recall: reset repetitions, count as lapse.
      reps = 0;
      lapses += 1;
      interval = 1;
    } else {
      reps += 1;
      if (reps == 1) {
        interval = 1;
      } else if (reps == 2) {
        interval = 6;
      } else {
        interval = (word.intervalDays * ease).round();
      }
    }

    final dueAt = DateTime.now().add(Duration(days: interval));
    // A leech is a card with many lapses relative to reps.
    final isLeech = lapses >= 5 && lapses > reps;

    return word.copyWith(
      dueAt: dueAt,
      intervalDays: interval,
      ease: ease,
      reps: reps,
      lapses: lapses,
      isLeech: isLeech,
    );
  }
}

/// 4-button mapping used by the review UI. Each maps to a SM-2 quality grade.
enum ReviewQuality {
  again(1),
  hard(3),
  good(4),
  easy(5);

  final int sm2;
  const ReviewQuality(this.sm2);
}