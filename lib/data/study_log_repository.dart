// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/domain/repositories/i_study_log_repository.dart';
import 'package:varnamala/domain/study/daily_stats.dart';
import 'package:varnamala/domain/study/study_log.dart';
import 'package:varnamala/service/locator.dart';

/// Stores study logs and daily aggregates in [StreamingSharedPreferences].
///
/// **Append strategy (ADR 0012)**: each [appendLog] writes to a small recent
/// queue (`study.logs.recent`, cap [_recentCap]) instead of rewriting the full
/// 90-day main blob every time. When the queue reaches the cap (or [flushRecent]
/// is forced), recent entries are merged into `study.logs` and purged.
/// [readLogs] always merges main + recent so callers never miss in-flight rows.
@lazySingleton
class StudyLogRepository implements IStudyLogRepository {
  final AppPrefs appPrefs;

  static const String _logsKey = 'study.logs';
  static const String _recentKey = 'study.logs.recent';
  static const String _dailyStatsKey = 'study.dailyStats';
  static const int _maxLogDays = 90;

  /// Cap for the incremental recent queue before merge into the main log.
  @visibleForTesting
  static const int recentCap = 200;

  /// Serializes mutating writes (appendLog / clearAll) so concurrent callers
  /// don't race on the read-modify-write cycle for [_dailyStatsKey]. Inspired
  /// by [LessonLinkStore._writeChain].
  Future<void> _writeChain = Future.value();

  /// Decoded daily-stats cache. The profile page fires multiple FutureBuilders
  /// that each used to re-`jsonDecode` the whole blob; this cache makes repeat
  /// reads free. Invalidated by every write ([_updateDailyStats]/[clearAll]).
  Map<String, DailyStudyStats>? _dailyStatsCache;

  StudyLogRepository(this.appPrefs);

  @override
  Future<void> appendLog(StudyLog log) async {
    await _enqueueWrite(() async {
      final recent = await _readRecentLogs();
      recent.add(log);
      // Drop stale recent rows so a 90-day-old append never lingers in the
      // queue until a full merge (matches prior purge-on-every-write semantics).
      _purgeOldLogs(recent);
      if (recent.length >= recentCap) {
        await _mergeRecentIntoMain(recent);
      } else {
        await _writeRecentLogs(recent);
      }
      await _updateDailyStats(log);
    });
  }

  /// Force-merge any pending recent entries into the main log.
  /// Useful for tests and for future background flush hooks.
  Future<void> flushRecent() async {
    await _enqueueWrite(() async {
      final recent = await _readRecentLogs();
      if (recent.isEmpty) return;
      await _mergeRecentIntoMain(recent);
    });
  }

  @override
  Future<List<StudyLog>> readLogs({
    DateTime? since,
    DateTime? until,
    StudyActivityType? type,
  }) async {
    var logs = await _readAllLogsMerged();
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

  @override
  Future<Map<String, DailyStudyStats>> readAllDailyStats() async {
    final cached = _dailyStatsCache;
    if (cached != null) return cached;

    final raw = appPrefs.preferences
        .getString(_dailyStatsKey, defaultValue: '{}')
        .getValue();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _dailyStatsCache = map.map((key, value) =>
          MapEntry(key, DailyStudyStats.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      // Corrupted prefs (partial write / migration glitch): return empty
      // instead of crashing the profile page. Mirrors SrsProvider.state guard.
      logger.w('StudyLogRepository dailyStats decode failed: $e');
      return _dailyStatsCache = <String, DailyStudyStats>{};
    }
  }

  Future<DailyStudyStats?> readDailyStats(DateTime date) async {
    final all = await readAllDailyStats();
    return all[_dateKey(date)];
  }

  @override
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

  @override
  Future<void> clearAll() async {
    await _enqueueWrite(() async {
      await appPrefs.preferences.setString(_logsKey, '[]');
      await appPrefs.preferences.setString(_recentKey, '[]');
      await appPrefs.preferences.setString(_dailyStatsKey, '{}');
      _dailyStatsCache = <String, DailyStudyStats>{};
    });
  }

  // --- internal ---

  /// Chain a mutating write so they execute in submission order. Errors in
  /// one op don't break subsequent writes — they just get logged.
  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).catchError((Object e) {
      // Ignore: error here means a subsequent read will see stale stats,
      // but the next appendLog will repaint from the latest prefs read.
      logger.w('StudyLogRepository write failed: $e');
    });
    return _writeChain;
  }

  Future<List<StudyLog>> _readMainLogs() async {
    final raw = appPrefs.preferences
        .getString(_logsKey, defaultValue: '[]')
        .getValue();
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => StudyLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.w('StudyLogRepository logs decode failed, treating as empty: $e');
      return <StudyLog>[];
    }
  }

  Future<List<StudyLog>> _readRecentLogs() async {
    final raw = appPrefs.preferences
        .getString(_recentKey, defaultValue: '[]')
        .getValue();
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => StudyLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.w(
        'StudyLogRepository recent logs decode failed, treating as empty: $e',
      );
      return <StudyLog>[];
    }
  }

  /// Merge main + recent by id (recent wins on collision), sorted by timestamp.
  Future<List<StudyLog>> _readAllLogsMerged() async {
    final main = await _readMainLogs();
    final recent = await _readRecentLogs();
    if (recent.isEmpty) return main;
    if (main.isEmpty) return recent;

    final byId = <String, StudyLog>{};
    for (final log in main) {
      byId[log.id] = log;
    }
    for (final log in recent) {
      byId[log.id] = log;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  Future<void> _writeMainLogs(List<StudyLog> logs) async {
    final encoded = jsonEncode(logs.map((l) => l.toJson()).toList());
    await appPrefs.preferences.setString(_logsKey, encoded);
  }

  Future<void> _writeRecentLogs(List<StudyLog> logs) async {
    final encoded = jsonEncode(logs.map((l) => l.toJson()).toList());
    await appPrefs.preferences.setString(_recentKey, encoded);
  }

  Future<void> _mergeRecentIntoMain(List<StudyLog> recent) async {
    final main = await _readMainLogs();
    final byId = <String, StudyLog>{};
    for (final log in main) {
      byId[log.id] = log;
    }
    for (final log in recent) {
      byId[log.id] = log;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _purgeOldLogs(merged);
    await _writeMainLogs(merged);
    await appPrefs.preferences.setString(_recentKey, '[]');
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
    // `all` was the cached object; keep it as the fresh cache so back-to-back
    // reads after a write don't re-decode.
    _dailyStatsCache = all;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
