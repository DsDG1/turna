// Flutter imports:
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/diagnostics/storage_write_telemetry.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/mistake_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/service/locator.dart';

/// Manages a FIFO log of recent wrong answers.
///
/// Only the most recent [maxEntries] mistakes are kept; older entries are
/// evicted automatically. Entries can be reviewed and removed when the user
/// rewrites them correctly.
///
/// Alongside the log, two lightweight aggregates are persisted for the
/// mistake dashboard: new-mistake counts per local day ([dailyCounts], pruned
/// to [dailyCountWindowDays]) and the cumulative mastered count
/// ([masteredTotal]).
@lazySingleton
class MistakeProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  MistakeProvider(this.appPrefs);

  MistakeRepository? _repository;

  @visibleForTesting
  void useRepository(MistakeRepository repository) {
    _repository = repository;
  }
  String _languageCode = LanguageCodes.turkish;
  bool _loaded = false;
  bool _prefsMigrated = false;

  static const int maxEntries = 200;

  /// Correct rewrites needed before an entry leaves the log.
  static const int rewriteGoal = 2;

  /// How many days of per-day counts are kept for the trend chart.
  static const int dailyCountWindowDays = 30;

  static const String _prefsKey = LocalStateKeys.mistakeLog;
  static const String _dailyCountsKey = LocalStateKeys.mistakeDailyCounts;
  static const String _masteredTotalKey = LocalStateKeys.mistakeMasteredTotal;

  List<MistakeEntry>? _cached;
  List<MistakeEntry>? _cachedView;
  Map<String, int>? _dailyCountsCache;
  int? _masteredTotalCache;

  String get languageCode => _languageCode;

  MistakeRepository? get _repo {
    if (_repository != null) return _repository;
    try {
      if (getIt.isRegistered<CourseDatabase>()) {
        _repository = MistakeRepository(getIt<CourseDatabase>());
      }
    } catch (_) {}
    return _repository;
  }

  Future<void> setLanguage(String code) async {
    final next = LanguageCodes.canonicalize(code);
    if (next == _languageCode && _loaded) return;
    _languageCode = next;
    _loaded = false;
    _cached = null;
    _cachedView = null;
    _dailyCountsCache = null;
    _masteredTotalCache = null;
    await ensureLoaded();
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _migratePrefsIfNeeded();
    final repo = _repo;
    if (repo != null) {
      _cached = await repo.load(_languageCode);
      _dailyCountsCache = await repo.loadDailyCounts(_languageCode);
      _masteredTotalCache = await repo.loadMasteredTotal(_languageCode);
      _cachedView = List.unmodifiable(_cached!);
      _loaded = true;
      return;
    }
    _readPrefsIntoCache();
    _loaded = true;
  }

  void _readPrefsIntoCache() {
    final raw = appPrefs.preferences
        .getString(_prefsKey, defaultValue: '[]')
        .getValue();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _cached = decoded
          .map((e) => MistakeEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _cached = <MistakeEntry>[];
    }
    _cachedView = List.unmodifiable(_cached!);
  }

  List<MistakeEntry> get entries {
    if (_cachedView != null) return _cachedView!;
    if (_repo != null && !_loaded) return const [];
    _readPrefsIntoCache();
    return _cachedView!;
  }

  /// New mistakes per local day (`yyyy-MM-dd` -> count), kept for the last
  /// [dailyCountWindowDays] days. Installs from before this aggregate existed
  /// decode an empty map and simply show no trend until new mistakes arrive.
  Map<String, int> get dailyCounts {
    if (_dailyCountsCache != null) return _dailyCountsCache!;
    final raw = appPrefs.preferences
        .getString(_dailyCountsKey, defaultValue: '{}')
        .getValue();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _dailyCountsCache = <String, int>{
        for (final e in decoded.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      };
    } catch (_) {
      _dailyCountsCache = <String, int>{};
    }
    return _dailyCountsCache!;
  }

  /// Cumulative number of mistakes mastered out of the log — either by
  /// reaching [rewriteGoal] rewrites or by being answered correctly in a
  /// mistake review session. Deck uninstalls do not count as mastered.
  int get masteredTotal => _masteredTotalCache ??=
      appPrefs.preferences
          .getInt(_masteredTotalKey, defaultValue: 0)
          .getValue();

  /// Number of mistakes currently stored.
  int get count => entries.length;

  /// Most recent [max] mistakes (FIFO tail — newest last). Used by the
  /// personalized tutor ([SrsTutorProvider]) to assemble context.
  List<MistakeEntry> recentMistakes({int max = 20}) {
    if (max <= 0) return const <MistakeEntry>[];
    final list = entries;
    if (list.length <= max) return list;
    return list.sublist(list.length - max);
  }

  /// Add a new mistake. If the log exceeds [maxEntries], the oldest entry is
  /// removed. The entry's local day is counted in [dailyCounts].
  Future<void> record(MistakeEntry entry) async {
    await ensureLoaded();
    final current = entries.toList();
    current.add(entry);
    if (current.length > maxEntries) {
      current.removeAt(0);
    }
    await _persist(current, dayBump: entry.timestamp);
  }

  /// Mark a mistake as rewritten correctly. If [rewriteCount] reaches
  /// [rewriteGoal], the entry is removed from the log and counted as
  /// mastered.
  Future<void> recordRewrite(String entryId) async {
    await ensureLoaded();
    final current = entries.toList();
    final index = current.indexWhere((e) => e.id == entryId);
    if (index == -1) return;

    final entry = current[index];
    final updated = entry.copyWith(rewriteCount: entry.rewriteCount + 1);
    if (updated.rewriteCount >= rewriteGoal) {
      current.removeAt(index);
      await _persist(current, masteredDelta: 1);
    } else {
      current[index] = updated;
      await _persist(current);
    }
  }

  /// Remove the mistakes answered correctly in a review session ("做完则掌握"
  /// — clear only correct ones). Each id in [ids] that matches a stored entry
  /// is removed in a single shot, regardless of its [MistakeEntry.rewriteCount],
  /// and counted as mastered.
  Future<void> removeByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    await ensureLoaded();
    final current = entries.toList();
    final before = current.length;
    current.removeWhere((e) => ids.contains(e.id));
    if (current.length == before) return;
    await _persist(current, masteredDelta: before - current.length);
  }

  /// Hard-delete bookkeeping for an Anki uninstall: drop every mistake that
  /// belongs to the removed deck/source.
  ///
  /// [idPrefixes] matches entries whose `wordId`, `lessonId`, or
  /// `interactionId` starts with the prefix — legacy decks own
  /// `anki-<importId>-…` ids and official sources own
  /// `official-anki-<sourceId>-…` tree/lesson ids. Official card-scoped
  /// word ids do not carry the sourceId (`official-anki-<profileHash>-c<id>`
  /// from projections, `official-anki-review-c<id>` from practice review), so
  /// [cardIds] matches those on the trailing `-c<cardId>` instead.
  Future<void> removeForAnkiDeletion({
    List<String> idPrefixes = const <String>[],
    Set<int> cardIds = const <int>{},
  }) async {
    if (idPrefixes.isEmpty && cardIds.isEmpty) return;
    await ensureLoaded();
    final current = entries.toList();
    final before = current.length;
    current.removeWhere((entry) {
      for (final prefix in idPrefixes) {
        if (entry.lessonId.startsWith(prefix) ||
            entry.interactionId.startsWith(prefix) ||
            (entry.wordId != null && entry.wordId!.startsWith(prefix))) {
          return true;
        }
      }
      if (cardIds.isNotEmpty) {
        final wordId = entry.wordId;
        if (wordId != null) {
          final match = _trailingAnkiCardId.firstMatch(wordId);
          final cardId = match == null ? null : int.tryParse(match.group(1)!);
          if (cardId != null && cardIds.contains(cardId)) return true;
        }
      }
      return false;
    });
    if (current.length == before) return;
    await _persist(current);
  }

  static final RegExp _trailingAnkiCardId = RegExp(r'-c(\d+)$');

  /// Clear all recorded mistakes and the dashboard aggregates.
  Future<void> clear() async {
    await _persist(<MistakeEntry>[], resetAggregates: true);
  }

  /// Drop decoded state after an external checkpoint restore.
  void reloadFromPrefs() {
    _loaded = false;
    _cached = null;
    _cachedView = null;
    _dailyCountsCache = null;
    _masteredTotalCache = null;
    notifyListeners();
  }

  /// Returns the stored interaction snapshot for [entry], or `null` if the
  /// mistake was recorded before snapshots were saved.
  Interaction? toInteraction(MistakeEntry entry) => entry.interactionSnapshot;

  Future<void> _migratePrefsIfNeeded() async {
    if (_prefsMigrated) return;
    _prefsMigrated = true;
    final repo = _repo;
    if (repo == null) return;
    final logJson = appPrefs.preferences
        .getString(_prefsKey, defaultValue: '[]')
        .getValue();
    final countsJson = appPrefs.preferences
        .getString(_dailyCountsKey, defaultValue: '{}')
        .getValue();
    final mastered = appPrefs.preferences
        .getInt(_masteredTotalKey, defaultValue: 0)
        .getValue();
    if (logJson.trim().isEmpty || logJson.trim() == '[]') {
      if (countsJson.trim().isEmpty || countsJson.trim() == '{}') {
        if (mastered == 0) return;
      }
    }
    try {
      final migrated = await repo.migrateFromPrefsJson(
        languageCode: LanguageCodes.turkish,
        logJson: logJson,
        dailyCountsJson: countsJson,
        masteredTotal: mastered,
      );
      if (migrated) {
        await appPrefs.preferences.setString(_prefsKey, '[]');
        await appPrefs.setString(_dailyCountsKey, '{}');
        await appPrefs.setInt(_masteredTotalKey, 0);
      }
    } catch (error, stackTrace) {
      // prefs stay untouched: the next launch retries (plan §6.2). The
      // in-memory flag keeps this session from hammering a broken path.
      logger.e(
        'MistakeProvider prefs→SQLite migration failed; will retry next boot',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _persist(
    List<MistakeEntry> list, {
    DateTime? dayBump,
    int masteredDelta = 0,
    bool resetAggregates = false,
  }) async {
    if (resetAggregates) {
      _dailyCountsCache = <String, int>{};
      _masteredTotalCache = 0;
    } else {
      if (dayBump != null) {
        _bumpDailyCount(dayBump);
      }
      if (masteredDelta != 0) {
        _masteredTotalCache = masteredTotal + masteredDelta;
      }
    }
    _cached = list;
    _cachedView = List.unmodifiable(list);
    final repo = _repo;
    if (repo != null) {
      await repo.replaceAll(
        languageCode: _languageCode,
        entries: list,
        dailyCounts: _dailyCountsCache ?? {},
        masteredTotal: _masteredTotalCache ?? 0,
        maxEntries: maxEntries,
      );
    } else {
      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      final stopwatch = Stopwatch()..start();
      await appPrefs.preferences.setString(_prefsKey, encoded);
      stopwatch.stop();
      StorageWriteTelemetry.instance.record(
        key: _prefsKey,
        estimatedBytes: utf8.encode(encoded).length,
        elapsed: stopwatch.elapsed,
      );
      await appPrefs.setString(
        _dailyCountsKey,
        jsonEncode(_dailyCountsCache ?? {}),
      );
      await appPrefs.setInt(_masteredTotalKey, _masteredTotalCache ?? 0);
    }
    notifyListeners();
  }

  /// Increment the count for [when]'s local day and prune entries older than
  /// [dailyCountWindowDays]. Returns the updated map (also cached).
  Map<String, int> _bumpDailyCount(DateTime when) {
    final counts = Map<String, int>.of(dailyCounts);
    final key = dayKey(when);
    counts[key] = (counts[key] ?? 0) + 1;

    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: dailyCountWindowDays - 1));
    counts.removeWhere((k, _) {
      final day = DateTime.tryParse(k);
      return day == null || day.isBefore(cutoff);
    });
    _dailyCountsCache = counts;
    return counts;
  }

  /// Local-day key (`yyyy-MM-dd`) used by [dailyCounts]. Public so tests and
  /// the dashboard build chart buckets with the same key format.
  static String dayKey(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
