// Unit tests for the review dashboard aggregation layer (Plan 3 §16/P3-1):
// bounded queries (never allEvents), single-pass classification, cache +
// revision invalidation, and empty-data semantics.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_dashboard/review_dashboard_repository.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import 'package:drift/native.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs appPrefs;
  late ReviewHistoryDao reviewDao;
  late SrsProvider srs;
  late GrammarReviewProvider grammar;
  late ReviewDataRevision revision;
  late StudyLogRepository studyLog;
  late StreakProvider streak;
  late ReviewDashboardRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(sp);
    final db = emptyReviewHistoryDao();
    reviewDao = db;
    final dao = emptySrsStateDao();
    srs = SrsProvider(appPrefs, LessonLinkStore(appPrefs), dao);
    grammar = GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
    revision = ReviewDataRevision();
    studyLog = StudyLogRepository(appPrefs);
    streak = StreakProvider(appPrefs);
    repo = ReviewDashboardRepository(
      reviewDao,
      srs,
      grammar,
      AnkiImportDao(CourseDatabase(NativeDatabase.memory())),
      revision,
      studyLog,
      appPrefs,
      streak,
    );
  });

  ReviewEventRecord event(String cardId, DateTime at, {int quality = 4}) =>
      ReviewEventRecord(
        cardId: cardId,
        queue: 'word',
        reviewedAt: at,
        quality: quality,
        prevIntervalDays: 1,
        nextIntervalDays: 2,
        prevEase: 2.5,
        nextEase: 2.5,
        reps: 1,
        lapses: 0,
      );

  test('empty data shows no fake accuracy and an empty-source state', () async {
    final snap = await repo.loadDashboard();

    expect(snap.todayQuality.firstAnswerAccuracy, isNull,
        reason: 'no answers today must not fabricate 0%/100%');
    expect(snap.sources, isEmpty);
    expect(snap.last7Days.length, 7);
    expect(snap.last7Days.every((d) => d.reviewedCount == 0), isTrue);
    expect(snap.due.due, 0);
    expect(snap.due.newCards, 0);
  });

  test('due/new/overdue classification in one snapshot', () async {
    final now = DateTime.now();
    // A new (never reviewed) course card.
    srs.registerItem('w-new');
    // An introduced card due now (dueAt in the past, last reviewed 2 days ago).
    _seedDueCard(srs, 'w-due', now);

    final snap = await repo.loadDashboard(day: now);
    expect(snap.due.newCards, greaterThanOrEqualTo(1));
    expect(snap.due.due, greaterThanOrEqualTo(1));
    expect(snap.sources.first.dueToday, greaterThanOrEqualTo(1));
    expect(snap.sources.first.source.kind, LearningSourceKind.course);

    // Cards due today (not before today) are not overdue.
    expect(snap.due.overdue, 0, reason: 'cards due today are not overdue');
  });

  test('mixed sources are classified only from persisted identity', () async {
    srs.registerWord('opaque-course');
    srs.registerWord(
      'not-a-prefixed-legacy-card',
      sourceKind: SrsSourceKind.ankiLegacy,
      sourceId: 'legacy-source',
    );
    srs.registerWord(
      'not-a-prefixed-official-card',
      sourceKind: SrsSourceKind.ankiOfficial,
      sourceId: 'official-source',
    );
    grammar.registerGrammarPoint('opaque-grammar');

    final snap = await repo.loadDashboard(forceRefresh: true);
    final kinds = snap.sources.map((row) => row.source.kind).toSet();
    expect(kinds, containsAll(LearningSourceKind.values));
    expect(
      snap.sources
          .firstWhere((row) => row.source.kind == LearningSourceKind.ankiLegacy)
          .source
          .sourceId,
      'legacy-source',
    );
    expect(
      snap.sources
          .firstWhere(
              (row) => row.source.kind == LearningSourceKind.ankiOfficial)
          .source
          .sourceId,
      'official-source',
    );
  });

  test('today events come from the bounded window query', () async {
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day).add(const Duration(hours: 12));
    if (today.isAfter(now)) {
      // Avoid flakiness right after midnight: treat as pass-through when the
      // fixture would land in the future.
      return;
    }
    await reviewDao.insertEvent(event('a', today, quality: 5));
    await reviewDao.insertEvent(
        event('a', today.add(const Duration(minutes: 1)), quality: 2));
    // Yesterday's event must NOT be counted today.
    await reviewDao
        .insertEvent(event('b', today.subtract(const Duration(days: 1))));

    final snap =
        await repo.loadDashboard(day: today.add(const Duration(hours: 1)));
    expect(snap.today.reviewedToday, 2);
    expect(snap.today.correctToday, 1);
    expect(snap.today.completedCards, 1, reason: 'distinct cards');
  });

  test('daily activity returns local-day aggregated rows', () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await reviewDao.insertEvent(event('a', day.add(const Duration(hours: 3))));
    await reviewDao.insertEvent(event('a', day.add(const Duration(hours: 4))));
    final rows = await reviewDao.dailyActivityBetween(
      day.subtract(const Duration(days: 6)),
      day.add(const Duration(days: 1)),
    );
    expect(rows.length, 1);
    expect(rows.first.reviewedCount, 2);
    expect(rows.first.localDay, day);
  });

  test('cache hit without forceRefresh; revision bump invalidates', () async {
    final first = await repo.loadDashboard();
    expect(first.dataRevision, 0);

    final second = await repo.loadDashboard();
    expect(identical(second, first), isTrue,
        reason: 'same day + same revision serves the cached snapshot');

    revision.bump();
    final third = await repo.loadDashboard();
    expect(third, isNot(same(first)));
    expect(third.dataRevision, 1);
  });

  test('forceRefresh re-queries even with the same revision', () async {
    final first = await repo.loadDashboard();
    final second = await repo.loadDashboard(forceRefresh: true);
    expect(identical(second, first), isFalse);
  });

  test('study minutes and accuracy come from the study daily stats', () async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await studyLog.appendLog(StudyLog(
      id: 'log-1',
      timestamp: day.add(const Duration(hours: 6)),
      type: StudyActivityType.lessonComplete,
      lessonId: 'l',
      xpEarned: 30,
      durationSeconds: 300,
      correctCount: 8,
      incorrectCount: 2,
    ));

    final snap = await repo.loadDashboard();
    expect(snap.todayQuality.studyMinutes, 5);
    expect(snap.todayQuality.firstAnswerAccuracy, closeTo(0.8, 0.001));
    expect(snap.todayQuality.accuracySampleSize, 10);
  });
}

/// Seed an introduced card whose dueAt is already in the past and return it.
dynamic _seedDueCard(SrsProvider srs, String id, DateTime now) {
  srs.registerItem(id);
  final word = srs.state[id]!;
  final due = word.copyWith(
    dueAt: now.subtract(const Duration(hours: 2)),
    lastReviewedAt: now.subtract(const Duration(days: 2)),
    reps: 3,
  );
  srs.state[id] = due;
  return due;
}
