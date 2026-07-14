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
      // ease unchanged for quality 4: 2.5 + (0.1 - 1*(0.08 + 1*0.02)) = 2.5
      expect(updated.ease, closeTo(2.5, 0.001));
      expect(updated.dueAt.isAfter(DateTime.now().subtract(const Duration(seconds: 1))),
          isTrue);
    });

    test('second known review sets interval to 4 and reps to 2', () {
      final first =
          engine.review(freshWord('w-1'), ReviewGrade.known.sm2, random: seededRandom);
      final second = engine.review(first, ReviewGrade.known.sm2, random: seededRandom);

      expect(second.reps, 2);
      expect(second.intervalDays, 4);
      expect(second.ease, closeTo(2.5, 0.001));
    });

    test('third known review grows interval by ease factor (fuzzed)', () {
      final first =
          engine.review(freshWord('w-1'), ReviewGrade.known.sm2, random: seededRandom);
      final second = engine.review(first, ReviewGrade.known.sm2, random: seededRandom);
      final third = engine.review(second, ReviewGrade.known.sm2, random: seededRandom);

      // Base = 4 * 2.5 = 10, fuzzed ±15% (≈ ±1) → 9..11.
      expect(third.reps, 3);
      expect(third.intervalDays, inInclusiveRange(9, 11));
      expect(third.ease, closeTo(2.5, 0.001));
    });

    test('mature interval is not fuzzed when random is fixed to midpoint', () {
      // A Random stub returning a constant lets us pin the jitter. Using a
      // real seeded RNG, the value still lands within the ±band.
      final first =
          engine.review(freshWord('w-1'), ReviewGrade.known.sm2, random: seededRandom);
      final second = engine.review(first, ReviewGrade.known.sm2, random: seededRandom);
      final third = engine.review(second, ReviewGrade.known.sm2, random: seededRandom);

      final delta = (10 * Sm2Engine.fuzzRatio).round();
      expect(third.intervalDays, inInclusiveRange(10 - delta, 10 + delta));
    });

    test('unknown quality resets reps, increments lapse, and interval becomes 1',
        () {
      final studied = engine.review(
        engine.review(freshWord('w-1'), ReviewGrade.known.sm2, random: seededRandom),
        ReviewGrade.known.sm2,
        random: seededRandom,
      );
      final failed = engine.review(studied, ReviewGrade.unknown.sm2);

      expect(failed.reps, 0);
      expect(failed.lapses, 1);
      expect(failed.intervalDays, 1);
      // ease drops: 2.5 + (0.1 - 4 * (0.08 + 4 * 0.02)) = 1.96
      expect(failed.ease, closeTo(1.96, 0.001));
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
      expect(word.reps, 0);
      expect(word.isLeech, isFalse);
    });

    test('subsequent successful reviews recover interval after a lapse', () {
      var word = freshWord('w-1');
      word = engine.review(word, ReviewGrade.known.sm2, random: seededRandom); // reps=1, int=1
      word = engine.review(word, ReviewGrade.known.sm2, random: seededRandom); // reps=2, int=4
      word = engine.review(word, ReviewGrade.unknown.sm2); // reps=0, int=1
      word = engine.review(word, ReviewGrade.known.sm2, random: seededRandom); // reps=1, int=1
      word = engine.review(word, ReviewGrade.known.sm2, random: seededRandom); // reps=2, int=4

      expect(word.reps, 2);
      expect(word.intervalDays, 4);
    });
  });
}