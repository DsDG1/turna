import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/core/fsrs_engine.dart';
import 'package:varnamala/core/fsrs_relearn.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/domain/course/srs_word.dart';

void main() {
  group('relearnDelayForFailStreak', () {
    test('ladder 10m → 30m → 2h → next day', () {
      expect(relearnDelayForFailStreak(1)!.inMinutes, 10);
      expect(relearnDelayForFailStreak(2)!.inMinutes, 30);
      expect(relearnDelayForFailStreak(3)!.inHours, 2);
      expect(relearnDelayForFailStreak(4), isNull);
    });

    test('mature first fail is 30 minutes', () {
      expect(relearnDelayForFailStreak(1, mature: true)!.inMinutes, 30);
    });
  });

  group('FsrsEngine relearn ladder', () {
    final engine = FsrsEngine(enableFuzzing: false, maxSameDayFails: 4);
    final t0 = DateTime.utc(2026, 8, 1, 10);

    SrsWord card() => SrsWord(
          wordId: 'ladder',
          dueAt: t0.toLocal(),
          intervalDays: 5,
          reps: 3,
          stability: 5,
          difficulty: 5,
          fsrsState: 2,
          lastReviewedAt: t0.toLocal().subtract(const Duration(days: 2)),
        );

    test('first fail today → ~10 minutes', () {
      final u = engine.reviewWithFailContext(
        card(),
        ReviewOutcome.fail.quality,
        now: t0,
        sameDayFailsBefore: 0,
      );
      final delta = u.dueAt.difference(t0.toLocal());
      expect(delta.inMinutes, inInclusiveRange(9, 11));
    });

    test('second fail today → ~30 minutes', () {
      final u = engine.reviewWithFailContext(
        card(),
        ReviewOutcome.fail.quality,
        now: t0,
        sameDayFailsBefore: 1,
      );
      final delta = u.dueAt.difference(t0.toLocal());
      expect(delta.inMinutes, inInclusiveRange(29, 31));
    });

    test('third fail today → ~2 hours', () {
      final u = engine.reviewWithFailContext(
        card(),
        ReviewOutcome.fail.quality,
        now: t0,
        sameDayFailsBefore: 2,
      );
      final delta = u.dueAt.difference(t0.toLocal());
      expect(delta.inHours, inInclusiveRange(1, 2));
    });

    test('fourth fail today → next calendar day', () {
      final u = engine.reviewWithFailContext(
        card(),
        ReviewOutcome.fail.quality,
        now: t0,
        sameDayFailsBefore: 3,
      );
      final local = t0.toLocal();
      final dueDay = DateTime(u.dueAt.year, u.dueAt.month, u.dueAt.day);
      final day0 = DateTime(local.year, local.month, local.day);
      expect(dueDay.isAfter(day0), isTrue);
    });

    test('mature first fail uses 30 min', () {
      final mature = card().copyWith(stability: 40, intervalDays: 40);
      final u = engine.reviewWithFailContext(
        mature,
        ReviewOutcome.fail.quality,
        now: t0,
        sameDayFailsBefore: 0,
      );
      final delta = u.dueAt.difference(t0.toLocal());
      expect(delta.inMinutes, inInclusiveRange(29, 31));
    });
  });
}
