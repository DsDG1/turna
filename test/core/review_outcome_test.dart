import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/fsrs_engine.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/srs_word.dart';

void main() {
  group('ReviewOutcome binary contract', () {
    test('fromCorrect maps exercise grades', () {
      expect(ReviewOutcome.fromCorrect(true), ReviewOutcome.pass);
      expect(ReviewOutcome.fromCorrect(false), ReviewOutcome.fail);
    });

    test('fromQuality collapses any stored grade to pass/fail', () {
      expect(ReviewOutcome.fromQuality(0), ReviewOutcome.fail);
      expect(ReviewOutcome.fromQuality(1), ReviewOutcome.fail);
      expect(ReviewOutcome.fromQuality(2), ReviewOutcome.fail);
      expect(ReviewOutcome.fromQuality(3), ReviewOutcome.pass); // Anki Hard
      expect(ReviewOutcome.fromQuality(4), ReviewOutcome.pass); // Good
      expect(ReviewOutcome.fromQuality(5), ReviewOutcome.pass); // Easy
    });

    test('ReviewGrade aliases outcome', () {
      expect(ReviewGrade.unknown.outcome, ReviewOutcome.fail);
      expect(ReviewGrade.known.outcome, ReviewOutcome.pass);
      expect(ReviewGrade.fromOutcome(ReviewOutcome.pass), ReviewGrade.known);
      expect(ReviewGrade.fromOutcome(ReviewOutcome.fail), ReviewGrade.unknown);
    });

    test('FsrsEngine maps pass/fail only (no Hard/Easy path)', () {
      final engine = FsrsEngine(enableFuzzing: false);
      final t0 = DateTime.utc(2026, 6, 1, 12);
      final word = SrsWord(
        wordId: 'bin',
        dueAt: t0.toLocal(),
        intervalDays: 0,
        reps: 0,
      );

      final pass = engine.review(word, ReviewOutcome.pass.quality, now: t0);
      expect(pass.reps, 1);
      expect(pass.lapses, 0);
      expect(pass.stability, isNotNull);

      final fail = engine.review(word, ReviewOutcome.fail.quality, now: t0);
      expect(fail.lapses, 1);
      expect(fail.reps, 0);
    });

    test('same-day fail ladder pushes due past today at streak 4', () {
      final engine = FsrsEngine(enableFuzzing: false, maxSameDayFails: 4);
      final t0 = DateTime.utc(2026, 6, 1, 8);
      final word = SrsWord(
        wordId: 'spam',
        dueAt: t0.toLocal(),
        intervalDays: 1,
        reps: 2,
        stability: 5,
        difficulty: 5,
        fsrsState: 2,
        lastReviewedAt: t0.toLocal().subtract(const Duration(days: 1)),
      );

      // fourth fail today (sameDayFailsBefore: 3) → next day
      final updated = engine.reviewWithFailContext(
        word,
        ReviewOutcome.fail.quality,
        now: t0,
        sameDayFailsBefore: 3,
      );

      final lastDue = updated.dueAt;
      final day0 =
          DateTime(t0.toLocal().year, t0.toLocal().month, t0.toLocal().day);
      final dueDay = DateTime(lastDue.year, lastDue.month, lastDue.day);
      expect(dueDay.isAfter(day0), isTrue);
    });
  });
}
