// Dart imports:
import 'dart:math';

// Package imports:
import 'package:fsrs/fsrs.dart' as fsrs;

// Project imports:
import 'package:varnamala/core/fsrs_relearn.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/core/srs_scheduler.dart';
import 'package:varnamala/domain/course/srs_word.dart';

/// FSRS-backed [SrsScheduler] (ADR 0028 / 0029).
///
/// Exercises use binary pass→Good / fail→Again, while imported Anki cards may
/// pass the four distinct Again/Hard/Good/Easy qualities. Optional
/// personalized [parameters]. Fail path applies a same-day relearn ladder.
class FsrsEngine implements SrsScheduler {
  FsrsEngine({
    this.desiredRetention = 0.9,
    this.maximumIntervalDays = 730,
    this.enableFuzzing = true,
    this.maxSameDayFails = 4,
    List<double>? parameters,
  })  : parameters = parameters == null
            ? List<double>.from(fsrs.defaultParameters)
            : List<double>.from(parameters),
        _scheduler = fsrs.Scheduler(
          parameters: parameters ?? fsrs.defaultParameters,
          desiredRetention: desiredRetention.clamp(0.8, 0.95),
          maximumInterval: maximumIntervalDays,
          enableFuzzing: enableFuzzing,
          learningSteps: const [Duration(minutes: 10)],
          relearningSteps: const [Duration(minutes: 10)],
        );

  /// Target recall probability used when computing the next interval.
  final double desiredRetention;

  /// Hard cap on scheduled interval (days).
  final int maximumIntervalDays;

  /// Whether FSRS applies interval fuzz (disabled for deterministic preview).
  final bool enableFuzzing;

  /// Fail streak (1-based, including current) at which due is pushed to tomorrow.
  final int maxSameDayFails;

  /// FSRS model weights (length 21). Defaults to package defaults.
  final List<double> parameters;

  final fsrs.Scheduler _scheduler;

  /// Reference stability (days) for the continuous mastery curve.
  static const double masteryStabilityRefDays = 30.0;

  @override
  SrsWord review(SrsWord word, int quality, {DateTime? now, Random? random}) {
    return reviewWithFailContext(
      word,
      quality,
      now: now,
      sameDayFailsBefore: 0,
    );
  }

  /// Like [review], but [sameDayFailsBefore] is the number of fail events
  /// already logged today for this card (from [ReviewHistoryDao]).
  SrsWord reviewWithFailContext(
    SrsWord word,
    int quality, {
    DateTime? now,
    int sameDayFailsBefore = 0,
  }) {
    final reviewAt = (now ?? DateTime.now()).toUtc();
    final nowLocal = reviewAt.toLocal();
    final card = _toFsrsCard(word);
    final rating = _toRating(quality);
    final result = _scheduler.reviewCard(
      card,
      rating,
      reviewDateTime: reviewAt,
    );
    var updated = _fromFsrsCard(word, result.card, quality: quality);

    if (rating == fsrs.Rating.again) {
      final streak = sameDayFailsBefore + 1;
      final mature = isMatureStability(word.stability, word.intervalDays);
      updated = _applyRelearnLadder(
        updated,
        nowLocal: nowLocal,
        failStreak: streak,
        mature: mature,
      );
    }
    return updated;
  }

  SrsWord _applyRelearnLadder(
    SrsWord word, {
    required DateTime nowLocal,
    required int failStreak,
    required bool mature,
  }) {
    if (failStreak >= maxSameDayFails) {
      return word.copyWith(
        dueAt: nextLocalMidnight(nowLocal),
        intervalDays: 1,
      );
    }
    final delay = relearnDelayForFailStreak(failStreak, mature: mature);
    if (delay == null) {
      return word.copyWith(
        dueAt: nextLocalMidnight(nowLocal),
        intervalDays: 1,
      );
    }
    return word.copyWith(
      dueAt: nowLocal.add(delay),
      intervalDays: 1,
    );
  }

  @override
  int previewIntervalDays(SrsWord word, int quality, {DateTime? now}) {
    final engine = FsrsEngine(
      desiredRetention: desiredRetention,
      maximumIntervalDays: maximumIntervalDays,
      enableFuzzing: false,
      maxSameDayFails: maxSameDayFails,
      parameters: parameters,
    );
    final updated = engine.reviewWithFailContext(
      word,
      quality,
      now: now,
      sameDayFailsBefore: 0,
    );
    final reviewAt = now ?? DateTime.now();
    final delta = updated.dueAt.difference(reviewAt);
    if (delta.inMinutes < 12 * 60) return 0;
    final days = delta.inDays;
    return days < 1 ? 1 : days;
  }

  /// Minutes until next due for a fail preview (0 = next day / unknown).
  int previewFailMinutes(SrsWord word, {int sameDayFailsBefore = 0}) {
    final mature = isMatureStability(word.stability, word.intervalDays);
    final streak = sameDayFailsBefore + 1;
    if (streak >= maxSameDayFails) return 0;
    final d = relearnDelayForFailStreak(streak, mature: mature);
    if (d == null) return 0;
    return d.inMinutes;
  }

  @override
  double retrievability(SrsWord word, {DateTime? now}) {
    final card = _toFsrsCard(word);
    if (card.stability == null || card.lastReview == null) {
      return word.reps == 0 ? 0.0 : 1.0;
    }
    return _scheduler
        .getCardRetrievability(
          card,
          currentDateTime: (now ?? DateTime.now()).toUtc(),
        )
        .clamp(0.0, 1.0);
  }

  @override
  double masteryScore(SrsWord word, {DateTime? now}) {
    final r = retrievability(word, now: now);
    final s = word.stability ??
        (word.reps > 0 ? max(0.001, word.intervalDays.toDouble()) : 0.0);
    final stabilityFactor = 1.0 - exp(-s / masteryStabilityRefDays);
    return (r * stabilityFactor).clamp(0.0, 1.0);
  }

  static fsrs.Rating _toRating(int quality) {
    if (quality <= 2) return fsrs.Rating.again;
    if (quality == 3) return fsrs.Rating.hard;
    if (quality >= 5) return fsrs.Rating.easy;
    return fsrs.Rating.good;
  }

  static fsrs.Rating ratingForOutcome(ReviewOutcome outcome) =>
      outcome == ReviewOutcome.pass ? fsrs.Rating.good : fsrs.Rating.again;

  fsrs.Card _toFsrsCard(SrsWord word) {
    final migrated = _ensureFsrsFields(word);
    final state = fsrs.State.fromValue(migrated.fsrsState.clamp(1, 3));
    return fsrs.Card(
      cardId: word.wordId.hashCode,
      state: state,
      step: migrated.learningStep,
      stability: migrated.stability,
      difficulty: migrated.difficulty,
      due: word.dueAt.toUtc(),
      lastReview: word.lastReviewedAt?.toUtc(),
    );
  }

  SrsWord _ensureFsrsFields(SrsWord word) {
    if (word.stability != null && word.difficulty != null) return word;
    if (word.reps <= 0 && word.lastReviewedAt == null) {
      return word.copyWith(
        stability: null,
        difficulty: null,
        fsrsState: 1,
        learningStep: 0,
      );
    }
    final s = max(0.001, word.intervalDays.toDouble());
    final ease = word.ease.clamp(1.3, 3.0);
    final d = (10.0 - (ease - 1.3) / (3.0 - 1.3) * 9.0).clamp(1.0, 10.0);
    final dLapse = min(10.0, d + word.lapses * 0.3);
    return word.copyWith(
      stability: word.stability ?? s,
      difficulty: word.difficulty ?? dLapse,
      fsrsState: word.reps > 0 ? 2 : 1,
      learningStep: word.learningStep,
    );
  }

  SrsWord _fromFsrsCard(SrsWord original, fsrs.Card card,
      {required int quality}) {
    final now = DateTime.now();
    final dueLocal = card.due.toLocal();
    final lastLocal = card.lastReview?.toLocal();
    final intervalDays = _intervalDaysFromDue(dueLocal, lastLocal ?? now);

    var reps = original.reps;
    var lapses = original.lapses;
    final q = quality.clamp(0, 5);
    if (q < 3) {
      lapses += 1;
    } else {
      reps += 1;
    }
    final isLeech = lapses >= 5 && lapses > reps;
    final ease = _easeFromDifficulty(card.difficulty);

    return original.copyWith(
      dueAt: dueLocal,
      intervalDays: intervalDays,
      ease: ease,
      reps: reps,
      lapses: lapses,
      isLeech: isLeech,
      lastReviewedAt: lastLocal ?? now,
      stability: card.stability,
      difficulty: card.difficulty,
      fsrsState: card.state.value,
      learningStep: card.step,
    );
  }

  int _intervalDaysFromDue(DateTime due, DateTime from) {
    final delta = due.difference(from);
    if (delta.inMinutes < 12 * 60) return 1;
    final days = delta.inDays;
    if (days < 1) return 1;
    return days > maximumIntervalDays ? maximumIntervalDays : days;
  }

  double _easeFromDifficulty(double? difficulty) {
    if (difficulty == null) return 2.5;
    final d = difficulty.clamp(1.0, 10.0);
    return (3.0 - (d - 1.0) / 9.0 * 1.7).clamp(1.3, 3.0);
  }
}
