import 'dart:math';

import 'package:varnamala/domain/course/srs_word.dart';

/// SM-2 spaced-repetition algorithm, tuned for binary 认识/不认识 grading.
///
/// Quality grades follow SuperMemo 2 conventions:
///   0..2 → recall failed; reset interval
///   3..5 → recall succeeded; grow interval
///
/// [ReviewGrade] aliases the 2-button mapping used by the review UI:
///   unknown = 1 (不认识, failed), known = 4 (认识, succeeded).
class Sm2Engine {
  const Sm2Engine();

  /// Initial ease factor for any new card.
  static const double initialEase = 2.5;

  /// Floor for ease (cards with very poor recall do not fall below this).
  static const double minEase = 1.3;

  /// Intervals at or above this many days get ±[fuzzRatio] jitter so mature
  /// cards do not all land on the same day. Early intervals (reps==1 → 1d,
  /// reps==2 → 4d) stay exact for deterministic testing.
  static const int fuzzThresholdDays = 7;

  /// Jitter band applied to mature intervals (±15%).
  static const double fuzzRatio = 0.15;

  /// Shared RNG used when no [random] is injected. Module-level so every
  /// review shares one source of jitter.
  static final Random _sharedRandom = Random();

  /// Compute the next [SrsWord] state given the current [word] and the
  /// recall quality [quality] (clamped to 0..5).
  ///
  /// [random] is used only to fuzz mature intervals (>= 7 days); pass one in
  /// tests to make the jitter deterministic.
  SrsWord review(SrsWord word, int quality, {Random? random}) {
    final q = quality.clamp(0, 5);

    // Update ease factor.
    var ease = word.ease +
        (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (ease < minEase) ease = minEase;

    var reps = word.reps;
    var lapses = word.lapses;
    int interval;

    if (q < 3) {
      // Failed recall: reset repetitions, count as lapse. No fuzz — failed
      // cards always come back tomorrow.
      reps = 0;
      lapses += 1;
      interval = 1;
    } else {
      reps += 1;
      if (reps == 1) {
        interval = 1;
      } else if (reps == 2) {
        // Gentler early growth under binary grading (was 6).
        interval = 4;
      } else {
        interval = (word.intervalDays * ease).round();
        // Fuzz mature intervals so reviews don't cluster on the same day.
        interval = _maybeFuzz(interval, random ?? _sharedRandom);
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

  /// Apply ±[fuzzRatio] jitter to [interval] only when it is mature
  /// (>= [fuzzThresholdDays] days). Always rounds to at least 1 day.
  int _maybeFuzz(int interval, Random random) {
    if (interval < fuzzThresholdDays) return interval;
    final delta = (interval * fuzzRatio).round();
    if (delta <= 0) return interval;
    final jittered = interval + random.nextInt(2 * delta + 1) - delta;
    return jittered < 1 ? 1 : jittered;
  }
}

/// 2-button mapping used by the review UI. Each maps to a SM-2 quality grade.
///   unknown = 1 → recall failed (不认识)
///   known   = 4 → recall succeeded (认识)
enum ReviewGrade {
  unknown(1),
  known(4);

  final int sm2;
  const ReviewGrade(this.sm2);
}