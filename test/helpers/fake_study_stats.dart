// Test helper: a minimal `StudyStatsProvider` stub. Concrete tests override
// the methods they need; defaults return empty / zero.

import 'package:flutter/foundation.dart';
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/domain/study/daily_stats.dart';
import 'package:varnamala/domain/study/study_log.dart';

class FakeStudyStatsProvider extends ChangeNotifier
    implements StudyStatsProvider {
  @override
  Future<DailyStudyStats> getTodayStats() async =>
      DailyStudyStats(date: DateTime.now());

  @override
  Future<List<DailyStudyStats>> getLastNDays(int n) async => List.generate(
        n,
        (_) => DailyStudyStats(date: DateTime.now()),
      );

  @override
  Future<int> getTotalStudyMinutes() async => 0;

  @override
  Future<double> getOverallAccuracy() async => 0.0;

  @override
  Future<int> getTotalRecordedXp() async => 0;

  @override
  Future<int> getTotalRecordedLessons() async => 0;

  @override
  Future<int> getTotalRecordedReviews() async => 0;

  @override
  Future<List<WeakWord>> getWeakWords({int limit = 10}) async => const [];

  @override
  Stream<List<DailyStudyStats>> getWeeklyStatsStream() =>
      const Stream.empty();

  @override
  Future<void> recordActivity({
    required StudyActivityType type,
    String? lessonId,
    int xpEarned = 0,
    int durationSeconds = 0,
    int correctCount = 0,
    int incorrectCount = 0,
    List<String> wordIds = const [],
  }) async {}

  // Unused in the LearningStats widget subtree — throw if ever reached.
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
