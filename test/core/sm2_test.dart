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

    test('first good review sets interval to 1 and reps to 1', () {
      final word = freshWord('w-1');
      final updated = engine.review(word, ReviewQuality.good.sm2);

      expect(updated.reps, 1);
      expect(updated.intervalDays, 1);
      expect(updated.lapses, 0);
      expect(updated.ease, closeTo(2.5, 0.001));
      expect(updated.dueAt.isAfter(DateTime.now().subtract(const Duration(seconds: 1))),
          isTrue);
    });

    test('second good review sets interval to 6 and reps to 2', () {
      final first = engine.review(freshWord('w-1'), ReviewQuality.good.sm2);
      final second = engine.review(first, ReviewQuality.good.sm2);

      expect(second.reps, 2);
      expect(second.intervalDays, 6);
      expect(second.ease, closeTo(2.5, 0.001));
    });

    test('third good review grows interval by ease factor', () {
      final first = engine.review(freshWord('w-1'), ReviewQuality.good.sm2);
      final second = engine.review(first, ReviewQuality.good.sm2);
      final third = engine.review(second, ReviewQuality.good.sm2);

      expect(third.reps, 3);
      expect(third.intervalDays, (6 * 2.5).round());
      expect(third.ease, closeTo(2.5, 0.001));
    });

    test('again quality resets reps, increments lapse, and interval becomes 1',
        () {
      final studied = engine.review(
        engine.review(freshWord('w-1'), ReviewQuality.good.sm2),
        ReviewQuality.good.sm2,
      );
      final failed = engine.review(studied, ReviewQuality.again.sm2);

      expect(failed.reps, 0);
      expect(failed.lapses, 1);
      expect(failed.intervalDays, 1);
      // ease drops: 2.5 + (0.1 - 4 * (0.08 + 4 * 0.02)) = 1.96
      expect(failed.ease, closeTo(1.96, 0.001));
    });

    test('hard quality reduces ease but still counts as success', () {
      final word = freshWord('w-1');
      final updated = engine.review(word, ReviewQuality.hard.sm2);

      expect(updated.reps, 1);
      expect(updated.intervalDays, 1);
      // ease: 2.5 + (0.1 - 2 * (0.08 + 2 * 0.02)) = 2.36
      expect(updated.ease, closeTo(2.36, 0.001));
    });

    test('easy quality boosts ease and counts as success', () {
      final word = freshWord('w-1');
      final updated = engine.review(word, ReviewQuality.easy.sm2);

      expect(updated.reps, 1);
      expect(updated.intervalDays, 1);
      // ease: 2.5 + (0.1 - 0) = 2.6
      expect(updated.ease, closeTo(2.6, 0.001));
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
        word = engine.review(word, ReviewQuality.again.sm2);
      }
      expect(word.ease, greaterThanOrEqualTo(Sm2Engine.minEase));
      expect(word.ease, closeTo(Sm2Engine.minEase, 0.001));
    });

    test('card becomes leech after 5 lapses with lapses > reps', () {
      var word = freshWord('w-1');
      // Five failures in a row: reps stays 0, lapses climbs to 5.
      for (var i = 0; i < 5; i++) {
        word = engine.review(word, ReviewQuality.again.sm2);
      }
      expect(word.lapses, 5);
      expect(word.reps, 0);
      expect(word.isLeech, isTrue);
    });

    test('card is not leech when lapses are offset by successful reps', () {
      var word = freshWord('w-1');
      // Success twice, then fail twice.
      word = engine.review(word, ReviewQuality.good.sm2);
      word = engine.review(word, ReviewQuality.good.sm2);
      word = engine.review(word, ReviewQuality.again.sm2);
      word = engine.review(word, ReviewQuality.again.sm2);

      expect(word.lapses, 2);
      expect(word.reps, 0);
      expect(word.isLeech, isFalse);
    });

    test('subsequent successful reviews recover interval after a lapse', () {
      var word = freshWord('w-1');
      word = engine.review(word, ReviewQuality.good.sm2); // reps=1, int=1
      word = engine.review(word, ReviewQuality.good.sm2); // reps=2, int=6
      word = engine.review(word, ReviewQuality.again.sm2); // reps=0, int=1
      word = engine.review(word, ReviewQuality.good.sm2); // reps=1, int=1
      word = engine.review(word, ReviewQuality.good.sm2); // reps=2, int=6

      expect(word.reps, 2);
      expect(word.intervalDays, 6);
    });
  });
}
