// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:get_it/get_it.dart';

// Project imports:
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/core/fsrs_engine.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/core/srs_scheduler.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

/// Shared SRS queue machinery for [SrsProvider] and [GrammarReviewProvider].
///
/// Default scheduler is FSRS ([FsrsEngine], ADR 0028). SM-2 remains available
/// for tests via [setSchedulerForTesting]. Subclasses supply [statePrefsKey]
/// (legacy blob key, used only for the one-time v7 migration) / [queueId] /
/// [logTag] and thin public API wrappers. See ADR 0013 and ADR 0021.
///
/// State is persisted in SQLite (`srs_states`, via [SrsStateDao]); an in-memory
/// `Map<String, SrsWord>` cache (`_cachedState`) is the synchronous read source
/// so the many synchronous consumers (`dueCount`, `getDueWords()`,
/// `context.select`) are untouched. Call [ensureLoaded] once at startup (before
/// the UI reads state) to hydrate the cache; writes are write-through.
abstract class SrsQueueProvider extends ChangeNotifier {
  SrsQueueProvider(this.appPrefs, this.linkStore, this.srsDao) {
    engine = _buildFsrsEngine();
  }

  final AppPrefs appPrefs;
  final LessonLinkStore linkStore;
  final SrsStateDao srsDao;

  /// Production default: continuous FSRS memory model (ADR 0028).
  late SrsScheduler engine;

  /// Legacy SM-2 engine kept for callers that need the concrete type.
  @protected
  final Sm2Engine sm2Engine = const Sm2Engine();

  /// Override scheduler in unit tests (e.g. deterministic SM-2).
  @visibleForTesting
  void setSchedulerForTesting(SrsScheduler scheduler) {
    engine = scheduler;
  }

  double _readDesiredRetention() {
    final raw = appPrefs.preferences
        .getDouble(LocalStateKeys.srsDesiredRetention, defaultValue: 0.9)
        .getValue();
    return raw.clamp(0.8, 0.95);
  }

  List<double>? _readFsrsParameters() {
    final raw = appPrefs.preferences
        .getString(LocalStateKeys.srsFsrsParameters, defaultValue: '')
        .getValue();
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final list = decoded.map((e) => (e as num).toDouble()).toList();
      if (list.length != 21) return null;
      return list;
    } catch (_) {
      return null;
    }
  }

  FsrsEngine _buildFsrsEngine() => FsrsEngine(
        desiredRetention: _readDesiredRetention(),
        parameters: _readFsrsParameters(),
      );

  /// Rebuild the FSRS engine when the user changes target retention.
  /// No-op when tests have injected [Sm2Engine] (or another non-FSRS engine).
  void setDesiredRetention(double value) {
    if (engine is Sm2Engine) return;
    final clamped = value.clamp(0.8, 0.95);
    engine = FsrsEngine(
      desiredRetention: clamped,
      parameters: _readFsrsParameters(),
    );
  }

  /// Apply optimized FSRS weights (or null to restore defaults).
  Future<void> setFsrsParameters(List<double>? parameters) async {
    if (parameters == null || parameters.isEmpty) {
      await appPrefs.setString(LocalStateKeys.srsFsrsParameters, '');
    } else {
      await appPrefs.setString(
        LocalStateKeys.srsFsrsParameters,
        jsonEncode(parameters),
      );
    }
    if (engine is Sm2Engine) return;
    engine = _buildFsrsEngine();
  }

  /// Whether personalized weights are stored.
  bool get hasCustomFsrsParameters {
    final raw = appPrefs.preferences
        .getString(LocalStateKeys.srsFsrsParameters, defaultValue: '')
        .getValue();
    return raw.isNotEmpty;
  }

  /// Preview next interval days for [outcome] without mutating state.
  int previewOutcomeDays(SrsWord word, ReviewOutcome outcome) =>
      engine.previewIntervalDays(word, outcome.quality);

  /// Binary review API (ADR 0028). Prefer this over raw quality ints.
  Future<SrsWord?> reviewWithOutcome(String id, ReviewOutcome outcome) =>
      reviewItem(id, outcome.quality);

  /// Legacy prefs key for the JSON state blob. Used only as the migration
  /// source when hydrating from an empty SQLite table for the first time.
  @protected
  String get statePrefsKey;

  /// Discriminator stored on each `srs_states` row (`'srs'` / `'grammar'`).
  @protected
  String get queueId;

  /// Tag used in logger messages.
  @protected
  String get logTag;

  Map<String, SrsWord>? _cachedState;
  List<SrsWord>? _cachedDueItems;
  DateTime? _cachedDueAt;
  int? _cachedDueCount;
  bool _loaded = false;

  /// Ids with a grade currently in flight (between [reviewItem] start and the
  /// completion of its DB persists). [undoReview] refuses while a grade is in
  /// flight so the grade can't overwrite an undo restored mid-grade.
  final Set<String> _gradesInFlight = {};

  ReviewHistoryDao? _reviewDao;
  bool _reviewDaoResolved = false;

  /// The review-history DAO, lazily resolved from the DI container so the base
  /// class doesn't force every test to inject it. Null when unavailable (tests
  /// without DI) - review-event logging is then silently skipped. Resolved once
  /// and cached; [ReviewHistoryDao] transitively needs `CourseDatabase`, so it
  /// only resolves in production (where [setupLocator] has opened the DB).
  ReviewHistoryDao? get _effectiveReviewDao {
    if (_reviewDaoResolved) return _reviewDao;
    _reviewDaoResolved = true;
    try {
      _reviewDao = GetIt.instance<ReviewHistoryDao>();
    } catch (_) {
      _reviewDao = null;
    }
    return _reviewDao;
  }

  /// Inject a [ReviewHistoryDao] directly for tests that assert on events.
  @visibleForTesting
  void setReviewHistoryDaoForTesting(ReviewHistoryDao dao) {
    _reviewDao = dao;
    _reviewDaoResolved = true;
  }

  String get _migratedFlag => 'srs.migratedToSqlite.$queueId';

  /// id -> current [SrsWord]. Never-seen ids are absent. Returns an empty map
  /// until [ensureLoaded] hydrates from SQLite; callers must await
  /// [ensureLoaded] before reading pre-existing state.
  Map<String, SrsWord> get state {
    _cachedState ??= <String, SrsWord>{};
    return _cachedState!;
  }

  /// Hydrate the in-memory cache from SQLite. On the first hydrate of an empty
  /// table, transparently migrates the legacy prefs blob (if any) and backfills
  /// the DB. Idempotent; safe to call multiple times.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      var loaded = await srsDao.loadQueue(queueId);
      if (loaded.isEmpty && !_migrationDone()) {
        loaded = await _migrateFromPrefs();
      }
      final current = _cachedState ?? <String, SrsWord>{};
      // Merge: don't clobber in-memory mutations made before load completed.
      for (final e in loaded.entries) {
        current.putIfAbsent(e.key, () => e.value);
      }
      _cachedState = current;
      invalidateDueCaches();
      notifyListeners();
    } catch (e, st) {
      logger.w('$logTag ensureLoaded failed: $e', stackTrace: st);
      _cachedState ??= <String, SrsWord>{};
    }
  }

  bool _migrationDone() => appPrefs.preferences
      .getBool(_migratedFlag, defaultValue: false)
      .getValue();

  /// One-time migration of the legacy prefs blob into SQLite. Returns the
  /// parsed map (empty on parse failure). Always marks the migration done so a
  /// corrupt blob is not retried.
  Future<Map<String, SrsWord>> _migrateFromPrefs() async {
    final raw = appPrefs.preferences
        .getString(statePrefsKey, defaultValue: '{}')
        .getValue();
    Map<String, SrsWord> migrated = {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      migrated = decoded.map(
        (k, v) => MapEntry(k, SrsWord.fromJson(v as Map<String, dynamic>)),
      );
      if (migrated.isNotEmpty) {
        await srsDao.upsertBatch(queueId, migrated.values);
      }
    } catch (e) {
      logger.w('$logTag legacy blob parse failed; starting empty: $e');
    }
    await appPrefs.preferences.setBool(_migratedFlag, true);
    return migrated;
  }

  /// Register [id] as fresh if unseen.
  @protected
  void registerItem(String id, {SrsItemType type = SrsItemType.word}) {
    final current = state;
    if (current.containsKey(id)) return;
    current[id] = type == SrsItemType.word
        ? SrsWord.fresh(id)
        : SrsWord.fresh(id).copyWith(type: type);
    _commitAndPersist(current);
  }

  /// Register many ids as fresh.
  @protected
  void registerAllItems(
    Iterable<String> ids, {
    SrsItemType type = SrsItemType.word,
  }) {
    final current = state;
    var changed = false;
    for (final id in ids) {
      if (!current.containsKey(id)) {
        current[id] = type == SrsItemType.word
            ? SrsWord.fresh(id)
            : SrsWord.fresh(id).copyWith(type: type);
        changed = true;
      }
    }
    if (changed) _commitAndPersist(current);
  }

  /// Merge externally-migrated states (e.g. an Anki deck import) into the
  /// queue. Existing ids are left untouched so re-imports stay idempotent -
  /// the caller's per-id skip and this check together make double imports
  /// harmless.
  @protected
  Future<void> importStates(Map<String, SrsWord> incoming) async {
    final current = state;
    final newlyAdded = <SrsWord>[];
    for (final entry in incoming.entries) {
      if (!current.containsKey(entry.key)) {
        current[entry.key] = entry.value;
        newlyAdded.add(entry.value);
      }
    }
    if (newlyAdded.isEmpty) return;
    _commit(current);
    await _writeBatch(newlyAdded);
  }

  /// Remove every entry whose id starts with [prefix] (e.g. uninstalling an
  /// imported Anki deck removes its `anki-<importId>-` entries).
  @protected
  Future<void> removeItemsByPrefix(String prefix) async {
    final current = state;
    final keys = current.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      current.remove(key);
    }
    if (keys.isNotEmpty) _commit(current);
    try {
      await srsDao.deleteByPrefix(prefix);
    } catch (e, st) {
      logger.w('$logTag removeItemsByPrefix failed: $e', stackTrace: st);
    }
  }

  /// Schedule a review for [id], gated against concurrent undo. The UI enables
  /// Undo as soon as a grade is submitted (before this writes); without the
  /// gate, an undo fired during the fail-path await would be overwritten when
  /// this resumes. See [_gradesInFlight].
  @protected
  Future<SrsWord?> reviewItem(String id, int quality) async {
    _gradesInFlight.add(id);
    try {
      return await _doReviewItem(id, quality);
    } finally {
      _gradesInFlight.remove(id);
    }
  }

  /// Returns null if unknown. Records [lastReviewedAt] and appends a row to
  /// `review_events` (when a [ReviewHistoryDao] is available) so the
  /// memory-curve features have per-card history. Uses [engine] (FSRS by
  /// default).
  Future<SrsWord?> _doReviewItem(String id, int quality) async {
    final current = state;
    final word = current[id];
    if (word == null) return null;
    final reviewedAt = DateTime.now();

    // Same-day fail ladder needs how many fails already logged today.
    var sameDayFails = 0;
    final reviewDao = _effectiveReviewDao;
    if (quality < 3 && reviewDao != null) {
      try {
        sameDayFails = await reviewDao.countFailsOnLocalDay(id, reviewedAt);
      } catch (_) {
        sameDayFails = 0;
      }
    }

    final SrsWord graded;
    final eng = engine;
    if (eng is FsrsEngine) {
      graded = eng.reviewWithFailContext(
        word,
        quality,
        now: reviewedAt,
        sameDayFailsBefore: sameDayFails,
      );
    } else {
      graded = eng.review(word, quality, now: reviewedAt);
    }
    final updated = graded.copyWith(lastReviewedAt: reviewedAt);
    current[id] = updated;
    _commit(current);
    try {
      await srsDao.upsert(queueId, updated);
    } catch (e, st) {
      logger.w('$logTag reviewItem persist failed: $e', stackTrace: st);
    }
    if (reviewDao != null) {
      try {
        await reviewDao.insertEvent(ReviewEventRecord(
          cardId: id,
          queue: queueId,
          reviewedAt: reviewedAt,
          quality: quality.clamp(0, 5),
          prevIntervalDays: word.intervalDays,
          nextIntervalDays: updated.intervalDays,
          prevEase: word.ease,
          nextEase: updated.ease,
          reps: updated.reps,
          lapses: updated.lapses,
          type: updated.type,
        ));
      } catch (e, st) {
        logger.w('$logTag reviewEvent record failed: $e', stackTrace: st);
      }
    }
    return updated;
  }

  /// Roll back a known set of newly imported ids without touching older
  /// states that share the same import prefix.
  @protected
  Future<void> removeImportedItems(Iterable<String> ids) async {
    final uniqueIds = ids.toSet();
    if (uniqueIds.isEmpty) return;
    final current = state;
    var changed = false;
    for (final id in uniqueIds) {
      changed = current.remove(id) != null || changed;
    }
    if (changed) _commit(current);
    for (final id in uniqueIds) {
      await srsDao.delete(id);
    }
  }

  /// Restore the state captured immediately before the latest review of [id]
  /// and remove that review event. The caller owns the one-step undo stack.
  ///
  /// Returns false (without restoring) if a grade for [id] is still in flight
  /// - the UI enables Undo before [reviewItem] writes, so refusing here
  /// prevents the in-flight grade from overwriting the restored state when it
  /// resumes. The caller leaves the undo entry in place and retries once the
  /// grade completes.
  @protected
  Future<bool> undoReview(String id, SrsWord previous) async {
    if (_gradesInFlight.contains(id)) return false;
    final reviewDao = _effectiveReviewDao;
    // The review write and its history event are persisted independently, so
    // the user can reach Undo before the event insert finishes. Restoring the
    // captured state is still safe; deleting the event is best-effort.
    if (reviewDao != null) await reviewDao.deleteLatestForCard(id);
    state[id] = previous;
    _commit(state);
    try {
      await srsDao.upsert(queueId, previous);
    } catch (e, st) {
      logger.w('$logTag undo persist failed: $e', stackTrace: st);
    }
    return true;
  }

  /// Update imported Anki flags while preserving all scheduling fields.
  @protected
  Future<void> setItemFlags(
    String id, {
    bool? suspended,
    bool? buried,
  }) async {
    final current = state[id];
    if (current == null) return;
    final updated = current.copyWith(
      isSuspended: suspended ?? current.isSuspended,
      isBuried: buried ?? current.isBuried,
    );
    state[id] = updated;
    _commit(state);
    try {
      await srsDao.upsert(queueId, updated);
    } catch (e, st) {
      logger.w('$logTag flag persist failed: $e', stackTrace: st);
    }
  }

  /// Due items, optionally filtered by [typeFilter]. Uses the primary due
  /// cache when [typeFilter] is null or when the subclass reuses this cache
  /// for a single type (grammar / words).
  @protected
  List<SrsWord> getDueItems({
    SrsItemType? typeFilter,
    DateTime? now,
    bool usePrimaryCache = true,
  }) {
    final cutoff = now ?? DateTime.now();
    if (usePrimaryCache &&
        _cachedDueItems != null &&
        _cachedDueAt != null &&
        !_cachedDueAt!.isAfter(cutoff)) {
      return _cachedDueItems!;
    }
    final result = state.values
        .where(
          (w) =>
              (typeFilter == null || w.type == typeFilter) &&
              !w.isSuspended &&
              !w.isBuried &&
              !w.dueAt.isAfter(cutoff),
        )
        .toList()
      // Leeches (chronically failed cards) are deprioritized to the end of
      // the queue so they don't crowd out ordinary due cards.
      ..sort((a, b) {
        if (a.isLeech != b.isLeech) return a.isLeech ? 1 : -1;
        return a.dueAt.compareTo(b.dueAt);
      });
    if (usePrimaryCache) {
      _cachedDueItems = result;
      _cachedDueAt = cutoff;
      _cachedDueCount = result.length;
    }
    return result;
  }

  /// Cached due count for the primary due cache (see [getDueItems]).
  @protected
  int get primaryDueCount => _cachedDueCount ?? getDueItems().length;

  @protected
  int? get primaryCachedDueCount => _cachedDueCount;

  /// First-seen lesson links; notifies only when at least one id is new.
  @protected
  Future<void> recordLinks({
    required Iterable<String> ids,
    required String lessonId,
    required String lessonName,
    required LinkType type,
  }) async {
    final anyNew = ids.any((id) => !linkStore.containsId(id));
    await linkStore.upsertFirstSeen(
      ids: ids,
      lessonId: lessonId,
      lessonName: lessonName,
      type: type,
    );
    if (anyNew) notifyListeners();
  }

  /// Encode state the same way the legacy prefs blob did (ADR 0011
  /// benchmarks). Kept for tests that assert on the JSON shape.
  @visibleForTesting
  static String encodeStateForPersist(Map<String, SrsWord> map) =>
      jsonEncode(map.map((k, v) => MapEntry(k, v.toJson())));

  /// Invalidate primary due caches. Subclasses with extra caches must override
  /// and call `super.invalidateDueCaches()`.
  @protected
  @mustCallSuper
  void invalidateDueCaches() {
    _cachedDueItems = null;
    _cachedDueAt = null;
    _cachedDueCount = null;
  }

  /// Update in-memory cache, invalidate due caches, and notify listeners
  /// synchronously. The DB write is deferred to the caller ([_writeBatch] /
  /// [_writeOne]) so the per-card hot path can persist a single row.
  void _commit(Map<String, SrsWord> map) {
    _cachedState = map;
    invalidateDueCaches();
    notifyListeners();
  }

  /// [persist] for subclasses that mutate a single item then hand back the full
  /// map (e.g. [GrammarReviewProvider.markDueNow]). Commits synchronously then
  /// writes the whole map through (acceptable for the rare single-item paths;
  /// the hot review path uses [_writeOne] via [reviewItem]).
  @protected
  Future<void> persist(Map<String, SrsWord> map) async {
    _commit(map);
    await _writeBatch(map.values);
  }

  /// Synchronous commit + fire-and-forget batch write (for the `void` register
  /// methods, which cannot await).
  void _commitAndPersist(Map<String, SrsWord> map) {
    _commit(map);
    _writeBatch(map.values);
  }

  Future<void> _writeBatch(Iterable<SrsWord> words) async {
    try {
      await srsDao.upsertBatch(queueId, words);
    } catch (e, st) {
      logger.w('$logTag writeBatch failed: $e', stackTrace: st);
    }
  }

  /// Clear queue state (content-update reset).
  Future<void> clear() async {
    _cachedState = <String, SrsWord>{};
    invalidateDueCaches();
    notifyListeners();
    try {
      await srsDao.clearQueue(queueId);
    } catch (e, st) {
      logger.w('$logTag clear failed: $e', stackTrace: st);
    }
  }
}
