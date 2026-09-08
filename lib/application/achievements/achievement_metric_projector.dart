// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_evaluator.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/application/score_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/service/locator.dart';

/// Persistent projection for metrics that cannot be cheaply rebuilt from
/// authoritative stores (study logs purge after 90 days, daily stats after
/// 365). Stored at `achievements.metric_projection.v1`.
///
/// - [totalReviewedCards]: monotonic counter of formally submitted card
///   answers (per-card, not per-session).
/// - [maxDailyXpEver]: highest single-day XP ever seen, survives the 365-day
///   daily-stats purge.
/// - [studiedWordIds]: unique word/expression ids from completed lessons and
///   formal reviews (feeds the deferred vocabulary series).
class AchievementMetricProjection {
  final int totalReviewedCards;
  final int maxDailyXpEver;
  final Set<String> studiedWordIds;
  final DateTime updatedAt;

  AchievementMetricProjection({
    this.totalReviewedCards = 0,
    this.maxDailyXpEver = 0,
    this.studiedWordIds = const {},
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? _epoch;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  AchievementMetricProjection copyWith({
    int? totalReviewedCards,
    int? maxDailyXpEver,
    Set<String>? studiedWordIds,
    DateTime? updatedAt,
  }) =>
      AchievementMetricProjection(
        totalReviewedCards: totalReviewedCards ?? this.totalReviewedCards,
        maxDailyXpEver: maxDailyXpEver ?? this.maxDailyXpEver,
        studiedWordIds: studiedWordIds ?? this.studiedWordIds,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'totalReviewedCards': totalReviewedCards,
        'maxDailyXpEver': maxDailyXpEver,
        'studiedWordIds': studiedWordIds.toList(growable: false),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static AchievementMetricProjection fromJson(Map<String, dynamic> json) =>
      AchievementMetricProjection(
        totalReviewedCards: (json['totalReviewedCards'] as num?)?.toInt() ?? 0,
        maxDailyXpEver: (json['maxDailyXpEver'] as num?)?.toInt() ?? 0,
        studiedWordIds: ((json['studiedWordIds'] as List?)
                    ?.map((e) => e.toString()) ??
                const Iterable<String>.empty())
            .toSet(),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
      );
}

/// Builds `AchievementMetricSnapshot` from the single authoritative source of
/// each metric, merging the persistent projection where history outlives the
/// raw stores:
///
/// | metric | authority |
/// | --- | --- |
/// | uniqueLessonsCompleted | LessonProgressProvider.completedLessonIds |
/// | uniquePerfectLessons | LessonProgressProvider.perfectLessonIds |
/// | currentStreakDays | StreakProvider |
/// | totalXp | ScoreProvider |
/// | maxDailyXp | max(daily stats, projection.maxDailyXpEver) |
/// | totalReviewedCards | max(per-card sum over logs, projection counter) |
/// | uniqueWordsStudied | projection.studiedWordIds ∪ log wordIds |
@lazySingleton
class AchievementMetricProjector {
  final AppPrefs _prefs;
  final LessonProgressProvider _lessonProgress;
  final StreakProvider _streakProvider;
  final ScoreProvider _scoreProvider;
  final StudyLogRepository _studyLogRepository;

  AchievementMetricProjection? _projectionCache;

  /// Serializes projection writes (read-modify-write on a JSON blob).
  Future<void> _writeChain = Future.value();

  AchievementMetricProjector(
    this._prefs,
    this._lessonProgress,
    this._streakProvider,
    this._scoreProvider,
    this._studyLogRepository,
  );

  static String? _srsLanguageCode() {
    try {
      if (getIt.isRegistered<SrsProvider>()) {
        return getIt<SrsProvider>().languageFilter;
      }
    } catch (_) {}
    return null;
  }

  /// In-memory projection (empty until first [readProjection]/[buildSnapshot]).
  AchievementMetricProjection get projection =>
      _projectionCache ?? AchievementMetricProjection();

  Future<AchievementMetricProjection> readProjection() async {
    final cached = _projectionCache;
    if (cached != null) return cached;
    final raw = _prefs.preferences
        .getString(LocalStateKeys.achievementsProjectionV1, defaultValue: '')
        .getValue();
    AchievementMetricProjection decoded;
    try {
      if (raw.isEmpty) {
        decoded = AchievementMetricProjection();
      } else {
        decoded =
            AchievementMetricProjection.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      logger.w('Achievement projection decode failed, resetting: $e');
      decoded = AchievementMetricProjection();
    }
    _projectionCache = decoded;
    return decoded;
  }

  /// Build a consistent snapshot. Daily stats / review logs are read through
  /// the repository's cache so repeated calls in one flow stay cheap.
  Future<AchievementMetricSnapshot> buildSnapshot() async {
    final persisted = await readProjection();

    var bestDailyXp = persisted.maxDailyXpEver;
    var reviewedFromLogs = 0;
    try {
      final languageCode = _srsLanguageCode();
      final dailyStats = await _studyLogRepository.readAllDailyStats(
        languageCode: languageCode,
      );
      for (final stats in dailyStats.values) {
        if (stats.totalXp > bestDailyXp) bestDailyXp = stats.totalXp;
      }
      final logs = await _studyLogRepository.readLogs(
        languageCode: languageCode,
      );
      for (final log in logs) {
        reviewedFromLogs += _reviewedCardsIn(log);
      }
    } catch (e) {
      // Fail closed for log-derived metrics: keep persisted projection only.
      logger.w('Achievement projector log read failed: $e');
    }

    final studiedWords = persisted.studiedWordIds.toSet();

    return AchievementMetricSnapshot(
      uniqueLessonsCompleted: _lessonProgress.completedLessonIds.length,
      uniquePerfectLessons: _lessonProgress.perfectLessonIds.length,
      // Voucher-protected days preserve the display streak but never satisfy
      // a real-learning streak achievement threshold.
      currentStreakDays: _streakProvider.realStreak,
      totalXp: _scoreProvider.score,
      maxDailyXp: bestDailyXp,
      totalReviewedCards:
          reviewedFromLogs > persisted.totalReviewedCards
              ? reviewedFromLogs
              : persisted.totalReviewedCards,
      uniqueWordsStudied: studiedWords.length,
    );
  }

  /// Persist a review-session delta. Study logs purge after 90 days, so the
  /// running counter is the only durable record of per-card totals.
  Future<void> applyReviewSessionDelta({required int cardsAnswered}) async {
    if (cardsAnswered <= 0) return;
    await _enqueueProjectionWrite((current) {
      return current.copyWith(
        totalReviewedCards: current.totalReviewedCards + cardsAnswered,
      );
    });
  }

  /// Fold new word ids into the studied-words projection (vocabulary series
  /// is unpublished until coverage is complete, but data accrues now).
  Future<void> applyStudiedWords(Iterable<String> wordIds) async {
    final ids = wordIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    await _enqueueProjectionWrite((current) {
      if (current.studiedWordIds.containsAll(ids)) return current;
      return current.copyWith(
        studiedWordIds: {...current.studiedWordIds, ...ids},
      );
    });
  }

  /// Reset projection (account reset). Chain-serialized.
  Future<void> reset() async {
    await _enqueueProjectionWrite((_) => AchievementMetricProjection());
  }

  /// Drop caches after an external restore (import / Fun Lab snapshot).
  Future<void> reloadFromPrefs() async {
    await _writeChain;
    _projectionCache = null;
    await readProjection();
  }

  Future<void> _enqueueProjectionWrite(
    AchievementMetricProjection Function(AchievementMetricProjection current) op,
  ) {
    _writeChain = _writeChain.then((_) async {
      final current = await readProjection();
      final next = op(current);
      if (identical(next, current)) return;
      _projectionCache = next;
      await _prefs.preferences.setString(
        LocalStateKeys.achievementsProjectionV1,
        jsonEncode(next.toJson()),
      );
    }).catchError((Object e) {
      logger.w('Achievement projection write failed: $e');
    });
    return _writeChain;
  }

  /// Per-card answer count inside one study log row. SRS reviews carry both
  /// remembered and forgotten counts; grammar reviews carry rated points.
  static int _reviewedCardsIn(StudyLog log) {
    switch (log.type) {
      case StudyActivityType.srsReview:
        return log.correctCount + log.incorrectCount;
      case StudyActivityType.grammarReview:
        return log.correctCount + log.incorrectCount;
      case StudyActivityType.lessonComplete:
      case StudyActivityType.matchGame:
      case StudyActivityType.characterPractice:
        return 0;
    }
  }
}
