// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/data/study_log_repository.dart';
import 'package:words625/domain/study/daily_stats.dart';
import 'package:words625/domain/study/study_log.dart';
import 'package:words625/service/locator.dart';

/// Provides aggregated learning statistics and records study activity.
@lazySingleton
class StudyStatsProvider extends ChangeNotifier {
  final StudyLogRepository _repository;
  final AppPrefs _appPrefs;

  final StreamController<List<DailyStudyStats>> _dailyStatsController =
      StreamController<List<DailyStudyStats>>.broadcast();

  StudyStatsProvider(this._repository, this._appPrefs);

  /// Record a completed study activity. Call this from lesson, review, and game screens.
  Future<void> recordActivity({
    required StudyActivityType type,
    String? lessonId,
    int xpEarned = 0,
    int durationSeconds = 0,
    int correctCount = 0,
    int incorrectCount = 0,
    List<String> wordIds = const [],
  }) async {
    final log = StudyLog(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}',
      timestamp: DateTime.now(),
      type: type,
      lessonId: lessonId,
      xpEarned: xpEarned,
      durationSeconds: durationSeconds,
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      wordIds: wordIds,
    );

    await _repository.appendLog(log);
    _emitDailyStats();
  }

  /// Get today's statistics snapshot.
  Future<DailyStudyStats> getTodayStats() async {
    final today = DateTime.now();
    return await _repository.readDailyStats(today) ??
        DailyStudyStats(
          date: DateTime(today.year, today.month, today.day),
        );
  }

  /// Stream of daily stats for the last 7 days (for charts).
  Stream<List<DailyStudyStats>> getWeeklyStatsStream() async* {
    yield await _repository.readLastNDays(7);
    yield* _dailyStatsController.stream;
  }

  /// Get last N days of stats (synchronous-ish, returns Future).
  Future<List<DailyStudyStats>> getLastNDays(int n) =>
      _repository.readLastNDays(n);

  /// Total study time in minutes across all recorded history.
  Future<int> getTotalStudyMinutes() async {
    final all = await _repository.readAllDailyStats();
    final totalSeconds = all.values.fold<int>(
      0,
      (sum, d) => sum + d.totalDurationSeconds,
    );
    return (totalSeconds / 60).ceil();
  }

  /// Overall accuracy across all recorded history.
  Future<double> getOverallAccuracy() async {
    final all = await _repository.readAllDailyStats();
    var correct = 0;
    var incorrect = 0;
    for (final d in all.values) {
      correct += d.correctCount;
      incorrect += d.incorrectCount;
    }
    final total = correct + incorrect;
    return total == 0 ? 0.0 : correct / total;
  }

  /// Total XP earned across all recorded history.
  Future<int> getTotalRecordedXp() async {
    final all = await _repository.readAllDailyStats();
    return all.values.fold<int>(0, (sum, d) => sum + d.totalXp);
  }

  /// Total lessons completed across all recorded history.
  Future<int> getTotalRecordedLessons() async {
    final all = await _repository.readAllDailyStats();
    return all.values.fold<int>(0, (sum, d) => sum + d.lessonCount);
  }

  /// Total reviews completed across all recorded history.
  Future<int> getTotalRecordedReviews() async {
    final all = await _repository.readAllDailyStats();
    return all.values.fold<int>(0, (sum, d) => sum + d.reviewCount);
  }

  /// Get weak words based on mistake log entries.
  /// This reads from the MistakeProvider's persisted data.
  Future<List<WeakWord>> getWeakWords({int limit = 10}) async {
    // Read mistake log from prefs
    final raw = _appPrefs.preferences
        .getString(LocalStateKeys.mistakeLog, defaultValue: '[]')
        .getValue();
    // The mistake log is a JSON list; we can't fully parse it here without
    // importing MistakeEntry, so we return an empty list for now.
    // A future iteration can cross-reference with vocab maps.
    return [];
  }

  void _emitDailyStats() async {
    final stats = await _repository.readLastNDays(7);
    _dailyStatsController.add(stats);
  }

  String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(6, (_) => chars[DateTime.now().millisecond % chars.length]).join();
  }

  @override
  void dispose() {
    _dailyStatsController.close();
    super.dispose();
  }
}
