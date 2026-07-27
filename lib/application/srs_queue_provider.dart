// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/domain/course/lesson_word_link.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/service/locator.dart';

/// Shared SM-2 queue machinery for [SrsProvider] and [GrammarReviewProvider].
///
/// Subclasses supply [statePrefsKey] / [logTag] and thin public API wrappers.
/// See ADR 0013.
abstract class SrsQueueProvider extends ChangeNotifier {
  SrsQueueProvider(this.appPrefs, this.linkStore);

  final AppPrefs appPrefs;
  final LessonLinkStore linkStore;

  @protected
  final Sm2Engine engine = const Sm2Engine();

  /// Prefs key for the JSON state blob.
  @protected
  String get statePrefsKey;

  /// Tag used in logger messages.
  @protected
  String get logTag;

  Map<String, SrsWord>? _cachedState;
  List<SrsWord>? _cachedDueItems;
  DateTime? _cachedDueAt;
  int? _cachedDueCount;

  /// id → current [SrsWord]. Never-seen ids are absent.
  Map<String, SrsWord> get state {
    if (_cachedState != null) return _cachedState!;

    final raw = appPrefs.preferences
        .getString(statePrefsKey, defaultValue: '{}')
        .getValue();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cachedState = decoded.map(
        (k, v) => MapEntry(k, SrsWord.fromJson(v as Map<String, dynamic>)),
      );
      return _cachedState!;
    } catch (e) {
      logger.w('$logTag state decode failed: $e');
      _cachedState = <String, SrsWord>{};
      return _cachedState!;
    }
  }

  /// Register [id] as fresh if unseen.
  @protected
  void registerItem(String id, {SrsItemType type = SrsItemType.word}) {
    final current = state;
    if (current.containsKey(id)) return;
    current[id] = type == SrsItemType.word
        ? SrsWord.fresh(id)
        : SrsWord.fresh(id).copyWith(type: type);
    persist(current);
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
    if (changed) persist(current);
  }

  /// Merge externally-migrated states (e.g. an Anki deck import) into the
  /// queue. Existing ids are left untouched so re-imports stay idempotent —
  /// the caller's per-id skip and this check together make double imports
  /// harmless. Single persist for the whole batch.
  @protected
  Future<void> importStates(Map<String, SrsWord> incoming) async {
    final current = state;
    var changed = false;
    for (final entry in incoming.entries) {
      if (!current.containsKey(entry.key)) {
        current[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) await persist(current);
  }

  /// Remove every entry whose id starts with [prefix] (e.g. uninstalling an
  /// imported Anki deck removes its `anki-<importId>-` entries).
  @protected
  Future<void> removeItemsByPrefix(String prefix) async {
    final current = state;
    final keys =
        current.keys.where((k) => k.startsWith(prefix)).toList();
    if (keys.isEmpty) return;
    for (final key in keys) {
      current.remove(key);
    }
    await persist(current);
  }

  /// SM-2 review for [id]. Returns null if unknown.
  @protected
  Future<SrsWord?> reviewItem(String id, int quality) async {
    final current = state;
    final word = current[id];
    if (word == null) return null;
    final updated = engine.review(word, quality);
    current[id] = updated;
    await persist(current);
    return updated;
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
              !w.dueAt.isAfter(cutoff),
        )
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
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

  /// Encode state the same way [persist] does (benchmarks / ADR 0011).
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

  /// Persist [map]: update in-memory cache, notify synchronously, then write
  /// prefs.
  ///
  /// Listeners are notified BEFORE the prefs write completes: the in-memory
  /// cache is already updated to [map] (so session state is consistent), and
  /// delaying the notify until after the disk write would gate every UI
  /// repaint on the SharedPreferences platform-channel round-trip — a latency
  /// hit on the per-card SRS review hot path. A failed write degrades to
  /// "unsaved but current for the session", not "stale UI": the cache already
  /// holds [map] and the failure is logged. (notify here is unconditional,
  /// matching the old pre-`try` placement that always fired regardless of
  /// write outcome.)
  @protected
  Future<void> persist(Map<String, SrsWord> map) async {
    _cachedState = map;
    invalidateDueCaches();
    notifyListeners();
    await _writeState(encodeStateForPersist(map), tag: 'persist');
  }

  /// Clear queue state (content-update reset).
  Future<void> clear() async {
    _cachedState = <String, SrsWord>{};
    invalidateDueCaches();
    notifyListeners();
    await _writeState('{}', tag: 'clear');
  }

  /// Write the encoded state blob to prefs, logging (never rethrowing) on
  /// failure. The in-memory cache and notify have already happened in the
  /// caller, so a failure here degrades to "unsaved but current for the
  /// session" — see [persist]. Shared by [persist] and [clear] so the
  /// notify-then-write invariant lives in one place.
  Future<void> _writeState(String encoded, {required String tag}) async {
    try {
      await appPrefs.preferences.setString(statePrefsKey, encoded);
    } catch (e, st) {
      logger.w('$logTag $tag failed: $e', stackTrace: st);
    }
  }
}
