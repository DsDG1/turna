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

  /// Decoded merged-log cache (main + recent, sorted). [readLogs] previously
  /// re-decoded both blobs and merged by id on every call; this cache makes
  /// repeat reads free. Invalidated by every mutating write (appendLog /
  /// flushRecent / clearAll) since any of them can change the merged set.
  List<StudyLog>? _mergedLogsCache;

  /// Count of write ops that failed (SharedPreferences I/O error, encode
  /// failure, …) since this repository was constructed. Writes are still
  /// best-effort (a failure degrades to stale-but-readable state rather than
  /// crashing the caller), but this counter surfaces the otherwise-silent
  /// data-loss risk for diagnostics / crash reporting.
  int _writeFailures = 0;

  /// Number of mutating writes that failed since construction. Exposed for
  /// diagnostics; not user-facing. See [_enqueueWrite].
  int get writeFailures => _writeFailures;

  StudyLogRepository(this.appPrefs);

  @override
  Future<void> appendLog(StudyLog log) async {
    await _enqueueWrite(() async {
      _invalidateMergedLogs();
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
      _invalidateMergedLogs();
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
    final all = await _readAllLogsMerged();
    var logs = all;
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
    // Defensive copy so callers can't mutate the shared [_mergedLogsCache].
    // When a filter ran, `logs` is already a fresh list; only copy when it's
    // still the cached reference (no filter, or all filters were no-ops).
    if (identical(logs, all)) {
      logs = List.of(logs);
    }
    return logs;
  }

  @override
  Future<Map<String, DailyStudyStats>> readAllDailyStats() async {
    final cached = _dailyStatsCache;
    if (cached != null) {
      // Defensive copy: _updateDailyStats mutates the cached map instance in
      // place (all[key] = ...; all.removeWhere(...)) and reassigns it as the
      // cache. A caller iterating a returned reference concurrently with a
      // queued write would throw ConcurrentModificationException. Hand back a
      // fresh map so callers can't mutate or race the cache.
      return Map.of(cached);
    }

    final raw = appPrefs.preferences
        .getString(_dailyStatsKey, defaultValue: '{}')
        .getValue();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final decoded = map.map((key, value) =>
          MapEntry(key, DailyStudyStats.fromJson(value as Map<String, dynamic>)));
      _dailyStatsCache = decoded;
      return Map.of(decoded);
    } catch (e) {
      // Corrupted prefs (partial write / migration glitch): return empty
      // instead of crashing the profile page. Mirrors SrsProvider.state guard.
      logger.w('StudyLogRepository dailyStats decode failed: $e');
      _dailyStatsCache = <String, DailyStudyStats>{};
      return <String, DailyStudyStats>{};
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
      _invalidateMergedLogs();
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
      // Don't rethrow: a failed write degrades to stale-but-readable state and
      // the next appendLog repaints from the latest prefs read. Count it so
      // the otherwise-silent data-loss risk stays observable (writeFailures).
      _writeFailures++;
      logger.w('StudyLogRepository write failed (#$_writeFailures): $e');
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
  /// Results are cached in [_mergedLogsCache]; invalidated by any mutating
  /// write (see [_invalidateMergedLogs]).
  ///
  /// Cache hits return directly WITHOUT chaining onto [_writeChain] — the
  /// cache is invalidated synchronously at the start of every mutating write,
  /// so a populated cache is always a consistent snapshot and there is no
  /// value in stalling a hot read behind in-flight writes. Only a cache MISS
  /// (re-merge from prefs) serializes on the write chain: without that, a
  /// [readLogs] queued while a write is suspended at an await (after the write
  /// nulled the cache but before it persisted) would re-merge from the
  /// still-old prefs and pin a stale cache that the completed write never
  /// re-invalidates.
  Future<List<StudyLog>> _readAllLogsMerged() async {
    final cached = _mergedLogsCache;
    if (cached != null) return cached;

    List<StudyLog> merged = const [];
    await _enqueueRead(() async {
      // Re-check inside the chain: another read ahead of us may have already
      // repopulated the cache, or a write may have invalidated it.
      final recached = _mergedLogsCache;
      if (recached != null) {
        merged = recached;
        return;
      }

      final main = await _readMainLogs();
      final recent = await _readRecentLogs();
      if (recent.isEmpty) {
        merged = main;
      } else if (main.isEmpty) {
        merged = recent;
      } else {
        final byId = <String, StudyLog>{};
        for (final log in main) {
          byId[log.id] = log;
        }
        for (final log in recent) {
          byId[log.id] = log;
        }
        merged = byId.values.toList();
      }
      merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _mergedLogsCache = merged;
    });
    return merged;
  }

  /// Chain a read op onto [_writeChain] so reads are serialized with writes
  /// (and with each other). A read never counts as a write failure and never
  /// rethrows — a decode error here degrades to an empty result, logged.
  Future<void> _enqueueRead(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).catchError((Object e) {
      logger.w('StudyLogRepository read failed: $e');
    });
    return _writeChain;
  }

  /// Drop the merged-log cache. Called at the start of every mutating write so
  /// a subsequent read re-merges from the updated prefs.
  void _invalidateMergedLogs() => _mergedLogsCache = null;

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
