import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/domain/course/srs_word.dart';

void main() {
  group('Sm2Engine.review', () {
    const engine = Sm2Engine();

    SrsWord freshWord(String id) => SrsWord(
          wordId: id,
          dueAt: DateTime.now(),
          intervalDays: 0,
          ease: Sm2Engine.initialEase,
          reps: 0,
          lapses: 0,
        );

    // A seeded RNG keeps mature-interval fuzz deterministic in tests.
    final seededRandom = Random(42);

    test('first known review sets interval to 1 and reps to 1', () {
      final word = freshWord('w-1');
      final updated = engine.review(word, ReviewGrade.known.sm2);

      expect(updated.reps, 1);
      expect(updated.intervalDays, 1);
      expect(updated.lapses, 0);
      expect(updated.ease, closeTo(2.5, 0.001));
      expect(
        updated.dueAt.isAfter(DateTime.now().subtract(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('second known review sets interval to 4 and reps to 2', () {
      final first = engine.review(freshWord('w-1'), ReviewGrade.known.sm2,
          random: seededRandom);
      final second =
          engine.review(first, ReviewGrade.known.sm2, random: seededRandom);

      expect(second.reps, 2);
      expect(second.intervalDays, 4);
      expect(second.ease, closeTo(2.5, 0.001));
    });

    test('third known review grows interval by ease factor (fuzzed)', () {
      final first = engine.review(freshWord('w-1'), ReviewGrade.known.sm2,
          random: seededRandom);
      final second =
          engine.review(first, ReviewGrade.known.sm2, random: seededRandom);
      final third =
          engine.review(second, ReviewGrade.known.sm2, random: seededRandom);

      // Base = 4 * (2.5 + 0.02) = 10.08 → 10, fuzzed ±2 → 8..12.
      expect(third.reps, 3);
      expect(third.intervalDays, inInclusiveRange(8, 12));
      expect(third.ease, closeTo(2.52, 0.001));
    });

    test('successful mature review slowly recovers ease, capped at maxEase',
        () {
      const engine = Sm2Engine();
      var word = freshWord('w-1')
          .copyWith(reps: 5, intervalDays: 30, ease: Sm2Engine.maxEase - 0.01);
      word = engine.review(word, ReviewGrade.known.sm2, random: Random(1));
      expect(word.ease, closeTo(Sm2Engine.maxEase, 0.001));
    });

    test('unknown review counts a lapse, applies fixed ease penalty, and '
        'relearns same-day', () {
      final studied = engine.review(
        engine.review(freshWord('w-1'), ReviewGrade.known.sm2,
            random: seededRandom),
        ReviewGrade.known.sm2,
        random: seededRandom,
      );
      final failed = engine.review(studied, ReviewGrade.unknown.sm2);

      // reps is NOT reset — it counts total successes.
      expect(failed.reps, 2);
      expect(failed.lapses, 1);
      // Young card (interval 4 < 21) restarts at 1 day.
      expect(failed.intervalDays, 1);
      // Fixed Anki-style penalty: 2.5 - 0.2.
      expect(failed.ease, closeTo(2.3, 0.001));
      // Same-day relearn: due again in ~10 minutes, not tomorrow.
      final now = DateTime.now();
      expect(
        failed.dueAt.isAfter(now.add(const Duration(minutes: 9))),
        isTrue,
      );
      expect(
        failed.dueAt.isBefore(now.add(const Duration(minutes: 11))),
        isTrue,
      );
    });

    test('mature lapse keeps a fraction of the old interval', () {
      final word = freshWord('w-1')
          .copyWith(reps: 5, intervalDays: 30, ease: 2.5);
      final failed = engine.review(word, ReviewGrade.unknown.sm2);

      expect(failed.intervalDays, (30 * Sm2Engine.lapseIntervalFactor).round());
      expect(failed.reps, 5); // preserved
      expect(failed.lapses, 1);
      expect(failed.ease, closeTo(2.3, 0.001));
    });

    test('relearnt mature card resumes growth from its lapse interval', () {
      var word = freshWord('w-1')
          .copyWith(reps: 5, intervalDays: 30, ease: 2.5);
      word = engine.review(word, ReviewGrade.unknown.sm2); // int 6, ease 2.3
      word = engine.review(word, ReviewGrade.known.sm2, random: Random(7));

      // reps 6 (>= 3) → mature branch from interval 6: 6 * 2.32 ≈ 14, fuzzed.
      expect(word.reps, 6);
      expect(word.intervalDays, inInclusiveRange(11, 17));
    });

    test('overdue successful review earns an elapsed-time bonus', () {
      // 10-day interval reviewed 10 days late: elapsed 20 → factor 2.
      final word = freshWord('w-1').copyWith(
        reps: 3,
        intervalDays: 10,
        ease: 2.5,
        dueAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      final updated = engine.review(word, ReviewGrade.known.sm2,
          random: Random(3));

      // Unfuzzed: 10 * 2.52 * 2 = 50.4 → 50; fuzz ±8 → 42..58.
      expect(updated.intervalDays, inInclusiveRange(42, 58));
    });

    test('overdue bonus is capped', () {
      // 100 days late on a 10-day interval: elapsed factor would be 11,
      // capped at overdueBonusCap (2) → same schedule as 10 days late.
      final word = freshWord('w-1').copyWith(
        reps: 3,
        intervalDays: 10,
        ease: 2.5,
        dueAt: DateTime.now().subtract(const Duration(days: 100)),
      );
      final updated = engine.review(word, ReviewGrade.known.sm2,
          random: Random(3));
      expect(updated.intervalDays, inInclusiveRange(42, 58));
    });

    test('interval is capped at maxIntervalDays (after fuzz)', () {
      final word = freshWord('w-1')
          .copyWith(reps: 10, intervalDays: 400, ease: 3.0);
      final updated = engine.review(word, ReviewGrade.known.sm2,
          random: Random(5));
      expect(updated.intervalDays, lessThanOrEqualTo(Sm2Engine.maxIntervalDays));
    });

    test('quality values are clamped to 0..5', () {
      final word = freshWord('w-1');

      final tooLow = engine.review(word, -1);
      expect(tooLow.reps, 0);
      expect(tooLow.lapses, 1);

      final tooHigh = engine.review(word, 10);
      expect(tooHigh.reps, 1);
      expect(tooHigh.intervalDays, 1);
    });

    test('ease does not drop below minEase even after many failures', () {
      var word = freshWord('w-1');
      for (var i = 0; i < 20; i++) {
        word = engine.review(word, ReviewGrade.unknown.sm2);
      }
      expect(word.ease, greaterThanOrEqualTo(Sm2Engine.minEase));
      expect(word.ease, closeTo(Sm2Engine.minEase, 0.001));
    });

    test('card becomes leech after 5 lapses with lapses > reps', () {
      var word = freshWord('w-1');
      // Five failures in a row: reps stays 0, lapses climbs to 5.
      for (var i = 0; i < 5; i++) {
        word = engine.review(word, ReviewGrade.unknown.sm2);
      }
      expect(word.lapses, 5);
      expect(word.reps, 0);
      expect(word.isLeech, isTrue);
    });

    test('card is not leech when lapses are offset by successful reps', () {
      var word = freshWord('w-1');
      // Success twice, then fail twice.
      word = engine.review(word, ReviewGrade.known.sm2, random: seededRandom);
      word = engine.review(word, ReviewGrade.known.sm2, random: seededRandom);
      word = engine.review(word, ReviewGrade.unknown.sm2);
      word = engine.review(word, ReviewGrade.unknown.sm2);

      expect(word.lapses, 2);
      expect(word.reps, 2); // successes are preserved across lapses
      expect(word.isLeech, isFalse);
    });
  });

  group('Sm2Engine.previewIntervalDays', () {
    const engine = Sm2Engine();

    SrsWord freshWord(String id) => SrsWord(
          wordId: id,
          dueAt: DateTime.now(),
          intervalDays: 0,
          ease: Sm2Engine.initialEase,
          reps: 0,
          lapses: 0,
        );

    test('failed recall previews 0 days (same-day relearn)', () {
      final word = freshWord('w-1').copyWith(reps: 5, intervalDays: 30);
      expect(engine.previewIntervalDays(word, ReviewGrade.unknown.sm2), 0);
    });

    test('first known review previews 1 day, second previews 4 days', () {
      var word = freshWord('w-1');
      expect(engine.previewIntervalDays(word, ReviewGrade.known.sm2), 1);
      word = engine.review(word, ReviewGrade.known.sm2); // reps 1, interval 1
      expect(engine.previewIntervalDays(word, ReviewGrade.known.sm2), 4);
    });

    test('mature preview is deterministic (no fuzz) and matches the unfuzzed interval', () {
      // reps >= 3: interval = intervalDays * (ease + bonus) (no fuzz).
      final word = freshWord('w-1').copyWith(reps: 2, intervalDays: 10, ease: 2.5);
      final a = engine.previewIntervalDays(word, ReviewGrade.known.sm2);
      final b = engine.previewIntervalDays(word, ReviewGrade.known.sm2);
      expect(a, b); // deterministic
      expect(a, (10 * 2.52).round()); // 25
    });

    test('mature preview includes the overdue bonus', () {
      final word = freshWord('w-1').copyWith(
        reps: 3,
        intervalDays: 10,
        ease: 2.5,
        dueAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      // elapsed 20 → factor 2 → 10 * 2.52 * 2 = 50.4 → 50.
      expect(engine.previewIntervalDays(word, ReviewGrade.known.sm2), 50);
    });

    test('preview is capped at maxIntervalDays', () {
      final word = freshWord('w-1')
          .copyWith(reps: 10, intervalDays: 400, ease: 3.0);
      expect(
        engine.previewIntervalDays(word, ReviewGrade.known.sm2),
        Sm2Engine.maxIntervalDays,
      );
    });

    test('preview does not mutate the input word', () {
      final word = freshWord('w-1').copyWith(reps: 2, intervalDays: 10);
      engine.previewIntervalDays(word, ReviewGrade.known.sm2);
      expect(word.reps, 2);
      expect(word.intervalDays, 10);
    });
  });
}
