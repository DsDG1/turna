// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/domain/study/daily_stats.dart';
import 'package:words625/domain/study/study_log.dart';
import 'package:words625/service/locator.dart';

/// Stores study logs and daily aggregates in [StreamingSharedPreferences].
/// Keeps the last 90 days of raw logs; older logs are purged during write.
@lazySingleton
class StudyLogRepository {
  final AppPrefs appPrefs;

  static const String _logsKey = 'study.logs';
  static const String _dailyStatsKey = 'study.dailyStats';
  static const int _maxLogDays = 90;

  /// Serializes mutating writes (appendLog / clearAll) so concurrent callers
  /// don't race on the read-modify-write cycle for [_dailyStatsKey]. Inspired
  /// by [LessonLinkStore._writeChain].
  Future<void> _writeChain = Future.value();

  StudyLogRepository(this.appPrefs);

  Future<void> appendLog(StudyLog log) async {
    await _enqueueWrite(() async {
      final logs = await _readLogs();
      logs.add(log);
      _purgeOldLogs(logs);
      await _writeLogs(logs);
      await _updateDailyStats(log);
    });
  }

  Future<List<StudyLog>> readLogs({
    DateTime? since,
    DateTime? until,
    StudyActivityType? type,
  }) async {
    var logs = await _readLogs();
    if (since != null) {
      logs = logs.where((l) => l.timestamp.isAfter(since)).toList();
    }
    if (until != null) {
      logs =
          logs.where((l) => l.timestamp.isBefore(until.add(const Duration(days: 1)))).toList();
    }
    if (type != null) {
      logs = logs.where((l) => l.type == type).toList();
    }
    return logs;
  }

  Future<Map<String, DailyStudyStats>> readAllDailyStats() async {
    final raw = appPrefs.preferences
        .getString(_dailyStatsKey, defaultValue: '{}')
        .getValue();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((key, value) =>
        MapEntry(key, DailyStudyStats.fromJson(value as Map<String, dynamic>)));
  }

  Future<DailyStudyStats?> readDailyStats(DateTime date) async {
    final all = await readAllDailyStats();
    return all[_dateKey(date)];
  }

  Future<List<DailyStudyStats>> readLastNDays(int n) async {
    final all = await readAllDailyStats();
    final today = DateTime.now();
    final result = <DailyStudyStats>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = DateTime(today.year, today.month, today.day - i);
      final key = _dateKey(d);
      result.add(all[key] ?? DailyStudyStats(date: d));
    }
    return result;
  }

  Future<void> clearAll() async {
    await _enqueueWrite(() async {
      await appPrefs.preferences.setString(_logsKey, '[]');
      await appPrefs.preferences.setString(_dailyStatsKey, '{}');
    });
  }

  // --- internal ---

  /// Chain a mutating write so they execute in submission order. Errors in
  /// one op don't break subsequent writes — they just get logged.
  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).catchError((Object e) {
      // Ignore: error here means a subsequent read will see stale stats,
      // but the next appendLog will repaint from the latest prefs read.
      assert(() {
        // ignore: avoid_print
        print('StudyLogRepository write failed: $e');
        return true;
      }());
    });
    return _writeChain;
  }

  Future<List<StudyLog>> _readLogs() async {
    final raw = appPrefs.preferences
        .getString(_logsKey, defaultValue: '[]')
        .getValue();
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => StudyLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeLogs(List<StudyLog> logs) async {
    final encoded = jsonEncode(logs.map((l) => l.toJson()).toList());
    await appPrefs.preferences.setString(_logsKey, encoded);
  }

  void _purgeOldLogs(List<StudyLog> logs) {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxLogDays));
    logs.removeWhere((l) => l.timestamp.isBefore(cutoff));
  }

  Future<void> _updateDailyStats(StudyLog log) async {
    final all = await readAllDailyStats();
    final key = _dateKey(log.timestamp);
    final existing = all[key] ??
        DailyStudyStats(
          date: DateTime(
            log.timestamp.year,
            log.timestamp.month,
            log.timestamp.day,
          ),
        );

    final updated = DailyStudyStats(
      date: existing.date,
      totalXp: existing.totalXp + log.xpEarned,
      totalDurationSeconds: existing.totalDurationSeconds + log.durationSeconds,
      correctCount: existing.correctCount + log.correctCount,
      incorrectCount: existing.incorrectCount + log.incorrectCount,
      lessonCount: existing.lessonCount +
          (log.type == StudyActivityType.lessonComplete ? 1 : 0),
      reviewCount: existing.reviewCount +
          (log.type == StudyActivityType.srsReview ||
                  log.type == StudyActivityType.grammarReview
              ? 1
              : 0),
    );

    all[key] = updated;

    // Purge stats older than 365 days
    final yearCutoff = DateTime.now().subtract(const Duration(days: 365));
    all.removeWhere((k, v) => v.date.isBefore(yearCutoff));

    final encoded = jsonEncode(
      all.map((k, v) => MapEntry(k, v.toJson())),
    );
    await appPrefs.preferences.setString(_dailyStatsKey, encoded);
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
