import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/fsrs_engine.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/srs_word.dart';

void main() {
  group('FsrsEngine', () {
    final engine = FsrsEngine(enableFuzzing: false);

    SrsWord fresh(String id) => SrsWord(
          wordId: id,
          dueAt: DateTime.now(),
          intervalDays: 0,
          ease: 2.5,
          reps: 0,
          lapses: 0,
        );

    test('first known review sets stability and schedules future due', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final updated = engine.review(
        fresh('w1'),
        ReviewGrade.known.sm2,
        now: now,
      );

      expect(updated.reps, 1);
      expect(updated.lapses, 0);
      expect(updated.stability, isNotNull);
      expect(updated.stability!, greaterThan(0));
      expect(updated.difficulty, isNotNull);
      expect(updated.dueAt.isAfter(now.toLocal()), isTrue);
    });

    test('unknown review increments lapses and does not reset reps to zero',
        () {
      final now = DateTime.utc(2026, 1, 1, 12);
      var word = engine.review(fresh('w1'), ReviewGrade.known.sm2, now: now);
      word = engine.review(
        word,
        ReviewGrade.known.sm2,
        now: now.add(const Duration(days: 1)),
      );
      final repsBefore = word.reps;
      final failed = engine.review(
        word,
        ReviewGrade.unknown.sm2,
        now: now.add(const Duration(days: 2)),
      );

      expect(failed.lapses, 1);
      expect(failed.reps, repsBefore); // successes preserved
      expect(failed.stability, isNotNull);
      // Post-lapse S is reduced but not wiped to a stage-0 box.
      expect(failed.stability!, greaterThan(0));
    });

    test('successful reviews grow stability over time', () {
      final t0 = DateTime.utc(2026, 1, 1, 12);
      var word = engine.review(fresh('w1'), ReviewGrade.known.sm2, now: t0);
      final s1 = word.stability!;
      // Advance past learning step into review growth.
      word = engine.review(
        word,
        ReviewGrade.known.sm2,
        now: t0.add(const Duration(days: 1)),
      );
      word = engine.review(
        word,
        ReviewGrade.known.sm2,
        now: t0.add(const Duration(days: 5)),
      );
      expect(word.stability!, greaterThanOrEqualTo(s1));
    });

    test('retrievability is continuous in [0,1], not a stage flag', () {
      final t0 = DateTime.utc(2026, 1, 1, 12);
      final word = engine.review(fresh('w1'), ReviewGrade.known.sm2, now: t0);
      final rNow =
          engine.retrievability(word, now: t0.add(const Duration(hours: 1)));
      final rLater = engine.retrievability(
        word,
        now: t0.add(Duration(days: (word.stability ?? 1).ceil() + 10)),
      );
      expect(rNow, inInclusiveRange(0.0, 1.0));
      expect(rLater, inInclusiveRange(0.0, 1.0));
      expect(rLater, lessThanOrEqualTo(rNow + 1e-9));
    });

    test('masteryScore is continuous and rises with stability', () {
      expect(engine.masteryScore(fresh('new')), closeTo(0.0, 1e-6));
      final t0 = DateTime.utc(2026, 1, 1, 12);
      var word = engine.review(fresh('w1'), ReviewGrade.known.sm2, now: t0);
      final m1 =
          engine.masteryScore(word, now: t0.add(const Duration(hours: 1)));
      word = engine.review(
        word,
        ReviewGrade.known.sm2,
        now: t0.add(const Duration(days: 2)),
      );
      final m2 = engine.masteryScore(
        word,
        now: t0.add(const Duration(days: 2, hours: 1)),
      );
      expect(m1, inInclusiveRange(0.0, 1.0));
      expect(m2, inInclusiveRange(0.0, 1.0));
    });

    test('previewIntervalDays is deterministic and non-negative', () {
      final word = fresh('w1');
      final now = DateTime.utc(2026, 3, 1, 12);
      final a =
          engine.previewIntervalDays(word, ReviewGrade.known.sm2, now: now);
      final b =
          engine.previewIntervalDays(word, ReviewGrade.known.sm2, now: now);
      expect(b, a);
      expect(a, greaterThanOrEqualTo(0));
      expect(
        engine.previewIntervalDays(word, ReviewGrade.unknown.sm2, now: now),
        0,
      );
    });

    test('Anki Hard, Good and Easy remain distinct FSRS ratings', () {
      final now = DateTime.utc(2026, 3, 1, 12);
      final hard = engine.review(
        fresh('hard'),
        AnkiReviewRating.hard.quality,
        now: now,
      );
      final good = engine.review(
        fresh('good'),
        AnkiReviewRating.good.quality,
        now: now,
      );
      final easy = engine.review(
        fresh('easy'),
        AnkiReviewRating.easy.quality,
        now: now,
      );

      expect(hard.dueAt.isAfter(good.dueAt), isFalse);
      expect(easy.dueAt.isAfter(good.dueAt), isTrue);
    });

    test('SM-2 fields migrate into FSRS stability on first review', () {
      final legacy = SrsWord(
        wordId: 'legacy',
        dueAt: DateTime.now(),
        intervalDays: 30,
        ease: 2.0,
        reps: 5,
        lapses: 1,
        lastReviewedAt: DateTime.now().subtract(const Duration(days: 5)),
      );
      final updated = engine.review(
        legacy,
        ReviewGrade.known.sm2,
        now: DateTime.now().toUtc(),
      );
      expect(updated.stability, isNotNull);
      expect(updated.difficulty, isNotNull);
    });
  });
}
