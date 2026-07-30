import 'dart:math';

import 'package:varnamala/core/srs_scheduler.dart';
import 'package:varnamala/domain/course/srs_word.dart';

/// Legacy SM-2 spaced-repetition algorithm (kept for tests / opt-in).
///
/// Production queues default to [FsrsEngine] (ADR 0028). This class still
/// implements [SrsScheduler] so callers can swap implementations.
///
/// Tuned for binary 认识/不认识 grading.
///
/// Quality grades follow SuperMemo 2 conventions:
///   0..2 → recall failed (忘了); lapse handling
///   3..5 → recall succeeded (记住); grow interval
///
/// Binary-specific tuning over classic SM-2 (Anki-inspired):
/// - Failed recall costs a fixed [lapseEasePenalty] instead of the steep
///   SM-2 linear formula, and mature cards keep a fraction
///   ([lapseIntervalFactor]) of their old interval instead of resetting to
///   1 day. Failed cards reappear after [relearnDelayMinutes] (same-day
///   relearn) rather than tomorrow.
/// - Successful recall slowly raises ease ([knownEaseBonus], capped at
///   [maxEase]) so ease can recover from earlier lapses (no ease hell).
/// - Reviews done later than scheduled earn an overdue bonus: the interval
///   grows with the actually elapsed time, capped at [overdueBonusCap]×.
/// - Intervals are capped at [maxIntervalDays].
///
/// [ReviewGrade] aliases the 2-button mapping used by the review UI:
///   unknown = 1 (不认识, failed), known = 4 (认识, succeeded).
class Sm2Engine implements SrsScheduler {
  const Sm2Engine();

  /// Initial ease factor for any new card.
  static const double initialEase = 2.5;

  /// Floor for ease (cards with very poor recall do not fall below this).
  static const double minEase = 1.3;

  /// Ceiling for ease (binary grading lets successful cards recover ease).
  static const double maxEase = 3.0;

  /// Ease gained per successful mature review. Lets consistently-recalled
  /// cards recover from earlier lapse penalties.
  static const double knownEaseBonus = 0.02;

  /// Fixed ease penalty on a failed recall (Anki-style).
  static const double lapseEasePenalty = 0.2;

  /// Fraction of the old interval kept when a mature card lapses
  /// (Anki "new interval" for lapses). Young cards restart at 1 day.
  static const double lapseIntervalFactor = 0.2;

  /// Intervals at or above this many days count as mature for lapse handling.
  static const int matureThresholdDays = 21;

  /// Hard cap on any scheduled interval.
  static const int maxIntervalDays = 730;

  /// Failed cards reappear this many minutes later (same-day relearn).
  static const int relearnDelayMinutes = 10;

  /// Upper bound on the overdue bonus multiplier (elapsed / scheduled).
  static const double overdueBonusCap = 2.0;

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
  @override
  SrsWord review(SrsWord word, int quality, {DateTime? now, Random? random}) {
    final q = quality.clamp(0, 5);
    final reviewNow = now ?? DateTime.now();

    var reps = word.reps;
    var lapses = word.lapses;
    var ease = word.ease;
    int interval;
    DateTime dueAt;

    if (q < 3) {
      // Failed recall: count a lapse, fixed ease penalty, and re-show the
      // card soon (same-day relearn). Mature cards keep a fraction of their
      // interval; young ones restart at 1 day. reps is NOT reset — it counts
      // total successes, so a relearnt mature card resumes interval growth
      // from its lapse interval instead of the new-card ladder.
      lapses += 1;
      ease = word.ease - lapseEasePenalty;
      if (ease < minEase) ease = minEase;
      interval = word.intervalDays >= matureThresholdDays
          ? max(1, (word.intervalDays * lapseIntervalFactor).round())
          : 1;
      dueAt = reviewNow.add(const Duration(minutes: relearnDelayMinutes));
    } else {
      reps += 1;
      if (reps == 1) {
        interval = 1;
      } else if (reps == 2) {
        // Gentler early growth under binary grading (was 6).
        interval = 4;
      } else {
        // Successful recall slowly recovers ease (binary grading gives no
        // Easy button, so success carries a small bonus).
        ease = word.ease + knownEaseBonus;
        if (ease > maxEase) ease = maxEase;

        // Overdue bonus: recalling later than scheduled is stronger evidence
        // of retention, so grow with the actually elapsed time (capped).
        final overdueDays = max(0, reviewNow.difference(word.dueAt).inDays);
        final elapsedDays = word.intervalDays + overdueDays;
        final overdueFactor = word.intervalDays > 0
            ? min(elapsedDays / word.intervalDays, overdueBonusCap)
            : 1.0;

        interval = (word.intervalDays * ease * overdueFactor).round();
        // Fuzz mature intervals so reviews don't cluster on the same day,
        // then clamp to the hard cap so jitter can't push past it.
        interval = _maybeFuzz(interval, random ?? _sharedRandom);
        if (interval > maxIntervalDays) interval = maxIntervalDays;
      }
      dueAt = reviewNow.add(Duration(days: interval));
    }

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

  /// Preview the interval (days) that would result from grading [quality]
  /// on [word], WITHOUT mutating state or applying fuzz. Used by the review
  /// UI to show "Know it -> ~N days" before the user commits. Deterministic
  /// (no jitter) so the preview is stable across rebuilds. Returns 0 for a
  /// failed grade, meaning same-day relearn (< 1 day).
  @override
  int previewIntervalDays(SrsWord word, int quality, {DateTime? now}) {
    final q = quality.clamp(0, 5);
    if (q < 3) return 0; // failed recall -> relearn in minutes
    final reps = word.reps + 1;
    if (reps == 1) return 1;
    if (reps == 2) return 4;
    var ease = word.ease + knownEaseBonus;
    if (ease > maxEase) ease = maxEase;
    final clock = now ?? DateTime.now();
    final overdueDays = max(0, clock.difference(word.dueAt).inDays);
    final elapsedDays = word.intervalDays + overdueDays;
    final overdueFactor = word.intervalDays > 0
        ? min(elapsedDays / word.intervalDays, overdueBonusCap)
        : 1.0;
    final interval = (word.intervalDays * ease * overdueFactor).round();
    return interval > maxIntervalDays ? maxIntervalDays : interval;
  }

  /// Exponential forgetting proxy for legacy SM-2 (S ≈ intervalDays).
  @override
  double retrievability(SrsWord word, {DateTime? now}) {
    if (word.lastReviewedAt == null || word.intervalDays <= 0) {
      return word.reps == 0 ? 0.0 : 1.0;
    }
    final clock = now ?? DateTime.now();
    final dtDays = clock.difference(word.lastReviewedAt!).inMinutes / 1440.0;
    return exp(-dtDays / word.intervalDays).clamp(0.0, 1.0);
  }

  @override
  double masteryScore(SrsWord word, {DateTime? now}) {
    final r = retrievability(word, now: now);
    final s = max(0.0, word.intervalDays.toDouble());
    const ref = 30.0;
    final stabilityFactor = 1.0 - exp(-s / ref);
    return (r * stabilityFactor).clamp(0.0, 1.0);
  }

  /// Apply ±[fuzzRatio] jitter to [interval] only when it is mature
  /// (>= [fuzzThresholdDays] days). Always rounds to at least 1 day and at
  /// least ±1 day of jitter once in the fuzz range.
  int _maybeFuzz(int interval, Random random) {
    if (interval < fuzzThresholdDays) return interval;
    var delta = (interval * fuzzRatio).round();
    if (delta < 1) delta = 1;
    final jittered = interval + random.nextInt(2 * delta + 1) - delta;
    return jittered < 1 ? 1 : jittered;
  }
}

/// Sole user-facing review outcome for the whole app (ADR 0028 binary lock).
///
/// Flashcards: 没记住 / 记住 · Exercises: 做错 / 做对.
/// Never expose Hard/Easy or 0–5 SM-2 grades in the UI.
enum ReviewOutcome {
  /// Forgot / incorrect → FSRS Again.
  fail,

  /// Remembered / correct → FSRS Good.
  pass;

  /// Legacy SM-2 quality int still stored on [ReviewEvents.quality].
  int get quality {
    switch (this) {
      case ReviewOutcome.fail:
        return 1;
      case ReviewOutcome.pass:
        return 4;
    }
  }

  static ReviewOutcome fromCorrect(bool correct) =>
      correct ? ReviewOutcome.pass : ReviewOutcome.fail;

  static ReviewOutcome fromQuality(int quality) =>
      quality < 3 ? ReviewOutcome.fail : ReviewOutcome.pass;
}

/// 2-button flashcard labels — aliases of [ReviewOutcome].
///   unknown = fail (不认识)
///   known   = pass (认识)
enum ReviewGrade {
  unknown(1),
  known(4);

  final int sm2;
  const ReviewGrade(this.sm2);

  ReviewOutcome get outcome =>
      this == ReviewGrade.known ? ReviewOutcome.pass : ReviewOutcome.fail;

  static ReviewGrade fromOutcome(ReviewOutcome o) =>
      o == ReviewOutcome.pass ? ReviewGrade.known : ReviewGrade.unknown;
}
