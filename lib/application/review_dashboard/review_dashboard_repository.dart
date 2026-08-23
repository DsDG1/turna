// Dart imports:
import 'dart:async';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';

/// Builds the single [ReviewDashboardSnapshot] for the review-overview home
/// (Plan 3 §16).
///
/// Cost contract (P3-1): one load performs
///   * ONE in-memory pass over the SRS + grammar states (cards classified
///     once into due/new/overdue and per-source buckets — the legacy
///     provider did this pass twice plus per-source re-filters);
///   * ONE bounded SQL query for today's events ([ReviewHistoryDao.eventsBetween]
///     — never `allEvents()`);
///   * ONE bounded 7-day GROUP BY query ([ReviewHistoryDao.dailyActivityBetween]);
///   * cheap prefs reads (streak, daily stats, goals).
///
/// Caching (§16.5): the last snapshot is kept with its (localDay, revision)
/// key. Reloading with the same key returns the cached snapshot; a revision
/// bump invalidates. In-flight loads carry a generation id so a slow older
/// load can never overwrite a newer one.
@lazySingleton
class ReviewDashboardRepository {
  ReviewDashboardRepository(
    this._reviewDao,
    this._srs,
    this._grammar,
    this._ankiImportDao,
    this._revision,
    this._studyLog,
    this._appPrefs,
    this._streak,
  );

  final ReviewHistoryDao _reviewDao;
  final SrsProvider _srs;
  final GrammarReviewProvider _grammar;
  final AnkiImportDao _ankiImportDao;
  final ReviewDataRevision _revision;
  final StudyLogRepository _studyLog;
  final AppPrefs _appPrefs;
  final StreakProvider _streak;

  ReviewDashboardSnapshot? _cached;
  DateTime? _cachedDay;
  int _cachedRevision = -1;
  int _generation = 0;

  /// The cache entry a page can show instantly while a fresh load runs
  /// (stale-while-revalidate). Null on first open.
  ReviewDashboardSnapshot? get cachedSnapshot => _cached;

  /// Discard the cache (e.g. after restore/import side effects).
  void invalidate() {
    _cached = null;
    _cachedDay = null;
    _cachedRevision = -1;
  }

  /// Loads the dashboard snapshot for [day] (defaults to now).
  ///
  /// When [forceRefresh] is false and the cache matches the current local
  /// day *and* data revision, the cached snapshot is returned immediately —
  /// the RefreshIndicator always passes [forceRefresh] so pull-to-refresh
  /// genuinely re-queries (Plan 3 §14.7).
  Future<ReviewDashboardSnapshot> loadDashboard({
    DateTime? day,
    bool forceRefresh = false,
  }) async {
    final trace = Stopwatch()..start();
    final now = day ?? DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final revision = _revision.value;

    if (!forceRefresh &&
        _cached != null &&
        _cachedDay == startOfToday &&
        _cachedRevision == revision) {
      trace.stop();
      PerformanceTrace.instance.record(
        feature: 'dashboard',
        operation: 'load',
        duration: trace.elapsed,
        resultSize: 1,
        cacheStatus: TraceCacheStatus.hit,
      );
      return _cached!;
    }

    final generation = ++_generation;

    // ── Single card pass: due/new/overdue + per-source buckets ──────────
    var due = 0, newCards = 0, overdue = 0;
    final dueBySource = <String, int>{};
    final totalBySource = <String, int>{};

    void account(String sourceKey, bool isNew, bool isDue, bool isOverdue) {
      totalBySource[sourceKey] = (totalBySource[sourceKey] ?? 0) + 1;
      if (isDue) {
        due++;
        dueBySource[sourceKey] = (dueBySource[sourceKey] ?? 0) + 1;
      }
      if (isOverdue) overdue++;
      if (isNew) newCards++;
    }

    for (final w in _srs.state.values) {
      final key = switch (w.sourceKind) {
        SrsSourceKind.course => 'course',
        SrsSourceKind.grammar => 'grammar',
        SrsSourceKind.ankiLegacy => 'anki:${w.sourceId}',
        SrsSourceKind.ankiOfficial => 'official:${w.sourceId}',
      };
      final isNew = w.reps == 0;
      final isDue = !isNew && !w.dueAt.isAfter(now);
      final isOverdue = !isNew && w.dueAt.isBefore(startOfToday);
      account(key, isNew, isDue, isOverdue);
    }
    for (final w in _grammar.state.values) {
      final isNew = w.reps == 0;
      final isDue = !isNew && !w.dueAt.isAfter(now);
      final isOverdue = !isNew && w.dueAt.isBefore(startOfToday);
      account('grammar', isNew, isDue, isOverdue);
    }

    // ── Today's events: bounded query, never allEvents() ────────────────
    final todayEvents = await _reviewDao.eventsBetween(startOfToday, now);
    final reviewedToday = todayEvents.length;
    final correctToday = todayEvents.where((e) => e.recalled).length;
    final completedCards = todayEvents.map((e) => e.cardId).toSet().length;

    // ── 7-day activity: fixed 7 aggregated points ───────────────────────
    final activity = await _reviewDao.dailyActivityBetween(
      startOfToday.subtract(const Duration(days: 6)),
      startOfToday.add(const Duration(days: 1)),
    );
    final reviewedByDay = <DateTime, int>{
      for (final row in activity) row.localDay: row.reviewedCount,
    };

    // ── Study-log daily stats: minutes / XP / accuracy / active days ────
    final dailyStats = await _studyLog.readAllDailyStats();
    final minutesByDay = <DateTime, int>{};
    DailyStudyStats? todayStats;
    for (final s in dailyStats.values) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      minutesByDay[d] = s.totalDurationSeconds ~/ 60;
      if (d == startOfToday) todayStats = s;
    }
    final studyMinutes = (todayStats?.totalDurationSeconds ?? 0) ~/ 60;
    final answered =
        (todayStats?.correctCount ?? 0) + (todayStats?.incorrectCount ?? 0);
    final double? accuracy =
        answered == 0 ? null : todayStats!.correctCount / answered;

    final user = _appPrefs.authUser.getValue();
    final xpGoal = user.dailyXpGoal;

    var activeDaysThisWeek = 0;
    for (var i = 0; i < 7; i++) {
      final day_ = startOfToday.subtract(Duration(days: i));
      final s = dailyStats[_dayKey(day_)];
      if (s != null && (s.totalQuestions > 0 || s.totalDurationSeconds > 0)) {
        activeDaysThisWeek++;
      }
    }

    // ── Source summaries (single list, sorted by dueToday desc) ─────────
    final sources = <ReviewSourceSummary>[];
    final ankiKeys =
        totalBySource.keys.where((k) => k.startsWith('anki:')).toList();
    final officialKeys =
        totalBySource.keys.where((k) => k.startsWith('official:')).toList();
    final nameByImport = <String, String>{};
    if (ankiKeys.isNotEmpty) {
      final imports = await _ankiImportDao.getAll();
      for (final r in imports) {
        final name = r.sourcePath
            .split(RegExp(r'[/\\]'))
            .last
            .replaceAll(RegExp(r'\.(apkg|colpkg)$', caseSensitive: false), '');
        nameByImport[r.importId] = name.isEmpty
            ? AppStrings.reviewProgressSourceAnki(r.importId)
            : name;
      }
    }

    void addSource(
      LearningSourceKind kind,
      String key,
      String sourceId,
      String name, {
      bool active = true,
    }) {
      final total = totalBySource[key] ?? 0;
      if (total == 0) return;
      sources.add(ReviewSourceSummary(
        source: LearningSourceRef(
          kind: kind,
          sourceId: sourceId,
          displayName: name,
          active: active,
        ),
        totalCards: total,
        dueToday: dueBySource[key] ?? 0,
      ));
    }

    addSource(LearningSourceKind.course, 'course', 'course',
        AppStrings.reviewProgressSourceCourse);
    addSource(LearningSourceKind.grammar, 'grammar', 'grammar',
        AppStrings.reviewProgressSourceGrammar);
    for (final key in ankiKeys) {
      final importId = key.substring(5);
      addSource(
        LearningSourceKind.ankiLegacy,
        key,
        importId,
        nameByImport[importId] ?? AppStrings.reviewProgressSourceAnki(importId),
        active: nameByImport.containsKey(importId),
      );
    }
    for (final key in officialKeys) {
      final sourceId = key.substring('official:'.length);
      addSource(
        LearningSourceKind.ankiOfficial,
        key,
        sourceId,
        AppStrings.reviewProgressSourceAnki(sourceId),
      );
    }
    sources.sort((a, b) {
      final byDue = b.dueToday.compareTo(a.dueToday);
      if (byDue != 0) return byDue;
      return a.source.displayName.compareTo(b.source.displayName);
    });

    final snapshot = ReviewDashboardSnapshot(
      generatedAt: now,
      dataRevision: revision,
      today: TodayProgress(
        reviewedToday: reviewedToday,
        correctToday: correctToday,
        completedCards: completedCards,
        todayXp: todayStats?.totalXp,
        xpGoal: xpGoal,
      ),
      due: DueSummary(due: due, newCards: newCards, overdue: overdue),
      streak: StreakSummary(
        currentStreakDays: _streak.streak,
        activeDaysThisWeek: activeDaysThisWeek,
        protectedByVoucher: _streak.currentChainProtected,
      ),
      last7Days: [
        for (var i = 6; i >= 0; i--)
          DailyActivityPoint(
            localDay: startOfToday.subtract(Duration(days: i)),
            reviewedCount:
                reviewedByDay[startOfToday.subtract(Duration(days: i))] ?? 0,
            activeMinutes:
                minutesByDay[startOfToday.subtract(Duration(days: i))] ?? 0,
          ),
      ],
      todayQuality: StudyQuality(
        studyMinutes: studyMinutes,
        firstAnswerAccuracy: accuracy,
        accuracySampleSize: answered,
      ),
      sources: sources,
    );

    // Late loads from a previous generation must not overwrite newer data.
    if (generation != _generation) {
      return snapshot;
    }
    _cached = snapshot;
    _cachedDay = startOfToday;
    _cachedRevision = revision;
    trace.stop();
    PerformanceTrace.instance.record(
      feature: 'dashboard',
      operation: 'load',
      duration: trace.elapsed,
      resultSize: snapshot.sources.length + snapshot.last7Days.length,
      cacheStatus: TraceCacheStatus.miss,
    );
    return snapshot;
  }

  /// Date key matching DailyStudyStats serialization (yyyy-MM-dd local).
  static String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
