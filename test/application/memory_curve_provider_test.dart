// Tests for [MemoryCurveProvider]: retention estimate, due forecast, maturity
// breakdown, and the empirical retention-by-interval curve.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/memory_curve_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/data/review_history_dao.dart';
import 'package:varnamala/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SrsProvider srs;
  late GrammarReviewProvider grammar;
  late ReviewHistoryDao reviewDao;
  late MemoryCurveProvider memoryCurve;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    final link = LessonLinkStore(prefs);
    final srsDao = emptySrsStateDao();
    reviewDao = emptyReviewHistoryDao();
    srs = SrsProvider(prefs, link, srsDao);
    srs.setReviewHistoryDaoForTesting(reviewDao);
    grammar = GrammarReviewProvider(prefs, link, emptySrsStateDao());
    grammar.setReviewHistoryDaoForTesting(emptyReviewHistoryDao());
    memoryCurve = MemoryCurveProvider(reviewDao, srs, grammar);
  });

  group('MemoryCurveProvider.snapshot', () {
    test('empty queue yields full retention, zero forecast, empty curve',
        () async {
      final snap = await memoryCurve.snapshot();
      expect(snap.totalCards, 0);
      expect(snap.trackedCards, 0);
      expect(snap.currentRetention, 1.0);
      expect(snap.forecast.dueToday, 0);
      expect(snap.forecast.due7Days, 0);
      expect(snap.forecast.due30Days, 0);
      expect(snap.maturity.newCards, 0);
      expect(snap.retentionByInterval, isEmpty);
      expect(snap.totalReviews, 0);
    });

    test('forecast and maturity reflect registered/reviewed cards', () async {
      // w-1: reviewed once -> interval 1, due tomorrow (young).
      srs.registerWord('w-1');
      await srs.reviewWord('w-1', ReviewGrade.known.sm2);
      // w-2: never reviewed -> due now (new).
      srs.registerWord('w-2');
      // w-3: reviewed twice -> interval 4, due in 4 days (young).
      srs.registerWord('w-3');
      await srs.reviewWord('w-3', ReviewGrade.known.sm2);
      await srs.reviewWord('w-3', ReviewGrade.known.sm2);

      final snap = await memoryCurve.snapshot();
      expect(snap.totalCards, 3);
      expect(snap.trackedCards, 2); // w-1, w-3 reviewed
      // Reviewed just now -> retention ~1.0.
      expect(snap.currentRetention, greaterThan(0.99));
      // w-2 is due now.
      expect(snap.forecast.dueToday, 1);
      // w-1 (1d), w-2 (now), w-3 (4d) all within 7 days.
      expect(snap.forecast.due7Days, 3);
      expect(snap.forecast.due30Days, 3);
      // w-2 new, w-1 + w-3 young.
      expect(snap.maturity.newCards, 1);
      expect(snap.maturity.young, 2);
      expect(snap.maturity.mature, 0);
      expect(snap.maturity.leech, 0);
      // Three reviews recorded (w-1 x1, w-3 x2).
      expect(snap.totalReviews, 3);
    });

    test('retention-by-interval curve buckets recall rate by prev interval',
        () async {
      // Insert review events directly with controlled prevIntervalDays.
      await reviewDao.insertBatch([
        ReviewEventRecord(
            cardId: 'a', queue: 'srs', reviewedAt: DateTime(2026, 7, 1),
            quality: 4, prevIntervalDays: 1, nextIntervalDays: 4,
            prevEase: 2.5, nextEase: 2.5, reps: 1, lapses: 0),
        ReviewEventRecord(
            cardId: 'b', queue: 'srs', reviewedAt: DateTime(2026, 7, 2),
            quality: 1, prevIntervalDays: 1, nextIntervalDays: 1,
            prevEase: 2.5, nextEase: 2.3, reps: 0, lapses: 1),
        ReviewEventRecord(
            cardId: 'c', queue: 'srs', reviewedAt: DateTime(2026, 7, 3),
            quality: 4, prevIntervalDays: 4, nextIntervalDays: 10,
            prevEase: 2.5, nextEase: 2.5, reps: 3, lapses: 0),
        ReviewEventRecord(
            cardId: 'd', queue: 'srs', reviewedAt: DateTime(2026, 7, 4),
            quality: 4, prevIntervalDays: 30, nextIntervalDays: 60,
            prevEase: 2.5, nextEase: 2.5, reps: 5, lapses: 0),
        ReviewEventRecord(
            cardId: 'e', queue: 'srs', reviewedAt: DateTime(2026, 7, 5),
            quality: 1, prevIntervalDays: 30, nextIntervalDays: 1,
            prevEase: 2.5, nextEase: 2.3, reps: 0, lapses: 1),
      ]);

      final snap = await memoryCurve.snapshot();
      final byBucket = {
        for (final p in snap.retentionByInterval) p.intervalBucketDays: p,
      };
      // Bucket 1: 1 recalled of 2 -> 0.5
      expect(byBucket[1]?.retention, 0.5);
      expect(byBucket[1]?.sampleSize, 2);
      // Bucket 4: 1 recalled of 1 -> 1.0
      expect(byBucket[4]?.retention, 1.0);
      // Bucket 30: 1 recalled of 2 -> 0.5
      expect(byBucket[30]?.retention, 0.5);
      expect(snap.totalReviews, 5);
    });

    test('a stale card lowers the current retention estimate', () async {
      // FSRS power-curve R(t,S) with S=4 days, t=8 days is well below 1
      // (ADR 0028 — no longer uses exp(-Δt/interval)).
      srs.registerWord('w-stale');
      await srs.reviewWord('w-stale', ReviewGrade.known.sm2);
      final now = DateTime.now();
      srs.state['w-stale'] = srs.state['w-stale']!.copyWith(
        intervalDays: 4,
        stability: 4.0,
        difficulty: 5.0,
        fsrsState: 2,
        reps: 3,
        lastReviewedAt: now.subtract(const Duration(days: 8)),
        dueAt: now.subtract(const Duration(days: 4)),
      );

      final snap = await memoryCurve.snapshot();
      expect(snap.trackedCards, 1);
      // Just-reviewed cards stay near 1.0; 8 days past S=4 is clearly lower.
      expect(snap.currentRetention, lessThan(0.95));
      expect(snap.currentRetention, greaterThan(0.5));
      // Continuous mastery is also in (0,1], not a stage flag.
      expect(snap.meanMastery, inInclusiveRange(0.0, 1.0));
    });
  });
}
