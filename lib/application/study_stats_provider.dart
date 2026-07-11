// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/courses/languages/grammar_points.dart';
import 'package:varnamala/courses/languages/swahili_vocab.dart';
import 'package:varnamala/data/study_log_repository.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/domain/study/daily_stats.dart';
import 'package:varnamala/domain/study/study_log.dart';
import 'package:varnamala/service/locator.dart';

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
    unawaited(_emitDailyStats());
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

  /// Get weak words based on the persisted mistake log. Aggregates by
  /// wordId (or grammarPointId when no word is available), looking up the
  /// display term/translation from the in-memory vocab tables. Sorted by
  /// mistake count descending; truncated to [limit].
  Future<List<WeakWord>> getWeakWords({int limit = 10}) async {
    final raw = _appPrefs.preferences
        .getString(LocalStateKeys.mistakeLog, defaultValue: '[]')
        .getValue();

    final List<MistakeEntry> entries;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      entries = decoded
          .map((e) => MistakeEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const <WeakWord>[];
    }

    // Aggregate by primary key (wordId, falling back to grammarPointId).
    final aggregates = <String, _WeakAggregate>{};
    for (final entry in entries) {
      final key = entry.wordId;
      if (key == null || key.isEmpty) {
        if (entry.grammarPointId == null) continue;
        // Grammar-only entries — skip word slot but still tracked via wordId
        // replacement. We keep them under their grammarPointId so the UI can
        // show grammar-targeted weak points.
        final gKey = 'grammar:${entry.grammarPointId}';
        final existing = aggregates[gKey];
        if (existing == null) {
          aggregates[gKey] = _WeakAggregate(
            key: gKey,
            mistakeCount: 1,
            lastMistakeAt: entry.timestamp,
          );
        } else {
          existing
            ..mistakeCount += 1
            ..lastMistakeAt = entry.timestamp.isAfter(existing.lastMistakeAt)
                ? entry.timestamp
                : existing.lastMistakeAt;
        }
        continue;
      }
      final existing = aggregates[key];
      if (existing == null) {
        aggregates[key] = _WeakAggregate(
          key: key,
          mistakeCount: 1,
          lastMistakeAt: entry.timestamp,
        );
      } else {
        existing
          ..mistakeCount += 1
          ..lastMistakeAt = entry.timestamp.isAfter(existing.lastMistakeAt)
              ? entry.timestamp
              : existing.lastMistakeAt;
      }
    }

    final sorted = aggregates.values.toList()
      ..sort((a, b) {
        final byCount = b.mistakeCount.compareTo(a.mistakeCount);
        if (byCount != 0) return byCount;
        return b.lastMistakeAt.compareTo(a.lastMistakeAt);
      });

    final result = <WeakWord>[];
    for (final agg in sorted) {
      if (result.length >= limit) break;
      WeakWord? word;
      if (agg.key.startsWith('grammar:')) {
        final gpId = agg.key.substring('grammar:'.length);
        final gp = swahiliGrammarPointById[gpId];
        word = WeakWord(
          wordId: gpId,
          displayText: gp?.title ?? gpId,
          translation: gp?.explanation,
          mistakeCount: agg.mistakeCount,
          lastMistakeAt: agg.lastMistakeAt,
        );
      } else {
        final entry = swahiliVocabById[agg.key];
        word = WeakWord(
          wordId: agg.key,
          displayText: entry?.term ?? agg.key,
          translation: entry?.translation,
          mistakeCount: agg.mistakeCount,
          lastMistakeAt: agg.lastMistakeAt,
        );
      }
      result.add(word);
    }
    return result;
  }

  Future<void> _emitDailyStats() async {
    try {
      final stats = await _repository.readLastNDays(7);
      if (!_dailyStatsController.isClosed) {
        _dailyStatsController.add(stats);
      }
    } catch (e) {
      // Don't let a stats-emit failure escape as an unhandled async-void
      // exception; the stream subscribers just won't get this update.
      debugPrint('StudyStatsProvider _emitDailyStats failed: $e');
    }
  }

  final Random _rand = Random();

  String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(6, (_) => chars[_rand.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _dailyStatsController.close();
    super.dispose();
  }
}

/// Internal aggregation record for [getWeakWords].
class _WeakAggregate {
  final String key;
  int mistakeCount;
  DateTime lastMistakeAt;

  _WeakAggregate({
    required this.key,
    required this.mistakeCount,
    required this.lastMistakeAt,
  });
}
