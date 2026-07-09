// Flutter imports:
import 'dart:convert';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/application/lesson_link_store.dart';
import 'package:words625/core/sm2.dart';
import 'package:words625/domain/course/lesson_word_link.dart';
import 'package:words625/domain/course/srs_word.dart';
import 'package:words625/service/locator.dart';

/// Manages the per-grammar-point spaced-repetition state, persisted to
/// [LocalStateKeys.grammarReviewState] via [StreamingSharedPreferences].
///
/// This is a parallel SRS queue to [SrsProvider], keyed by `grammarPointId`
/// instead of `wordId`. It reuses [SrsWord] / [Sm2Engine] / [ReviewQuality]
/// unchanged. Lesson links go through [LessonLinkStore] (shared with SRS).
@lazySingleton
class GrammarReviewProvider extends ChangeNotifier {
  final AppPrefs appPrefs;
  final LessonLinkStore linkStore;
  final Sm2Engine _engine = const Sm2Engine();

  GrammarReviewProvider(this.appPrefs, this.linkStore);

  Map<String, SrsWord>? _cachedState;
  List<SrsWord>? _cachedDueWords;
  DateTime? _cachedDueAt;

  /// grammarPointId → current [SrsWord] state. Points never seen are absent.
  Map<String, SrsWord> get state {
    if (_cachedState != null) return _cachedState!;

    final raw = appPrefs.preferences
        .getString(LocalStateKeys.grammarReviewState, defaultValue: '{}')
        .getValue();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cachedState = decoded.map(
          (k, v) => MapEntry(k, SrsWord.fromJson(v as Map<String, dynamic>)));
      return _cachedState!;
    } catch (e) {
      debugPrint('GrammarReviewProvider state decode failed: $e');
      _cachedState = <String, SrsWord>{};
      return _cachedState!;
    }
  }

  /// Register a new grammar point as fresh (due immediately) if unseen.
  void registerGrammarPoint(String id) {
    final current = state;
    if (current.containsKey(id)) return;
    current[id] = SrsWord.fresh(id);
    _persist(current);
  }

  /// Force [id] into the due queue immediately (mistake → grammar cross-route).
  ///
  /// Registers the point if unseen. Does not change SM-2 ease/reps — only
  /// sets [SrsWord.dueAt] to now so the next review session includes it.
  Future<void> markDueNow(String id) async {
    final current = state;
    final existing = current[id];
    if (existing == null) {
      current[id] = SrsWord.fresh(id);
    } else {
      current[id] = existing.copyWith(dueAt: DateTime.now());
    }
    await _persist(current);
  }

  /// Register multiple new grammar points.
  void registerAll(Iterable<String> ids) {
    final current = state;
    var changed = false;
    for (final id in ids) {
      if (!current.containsKey(id)) {
        current[id] = SrsWord.fresh(id);
        changed = true;
      }
    }
    if (changed) _persist(current);
  }

  /// Persist the lesson(s) where a set of grammar points was first
  /// encountered. Only the first recorded link for each id is kept.
  Future<void> recordLessonLinks({
    required Iterable<String> ids,
    required String lessonId,
    required String lessonName,
  }) async {
    await linkStore.upsertFirstSeen(
      ids: ids,
      lessonId: lessonId,
      lessonName: lessonName,
      type: LinkType.grammarPoint,
    );
    notifyListeners();
  }

  /// The lesson name where [id] was first encountered, or `null` if unknown.
  String? getLessonNameForGrammarPoint(String id) =>
      linkStore.lessonNameFor(id);

  /// Apply a SM-2 review for [id] with the given [quality].
  /// Returns the updated [SrsWord] (or null if [id] is unknown).
  Future<SrsWord?> reviewGrammarPoint(String id, int quality) async {
    final current = state;
    final word = current[id];
    if (word == null) return null;
    final updated = _engine.review(word, quality);
    current[id] = updated;
    await _persist(current);
    return updated;
  }

  /// Apply a [ReviewQuality] review (4-button mapping).
  Future<SrsWord?> reviewWithQuality(String id, ReviewQuality quality) =>
      reviewGrammarPoint(id, quality.sm2);

  /// Grammar points whose `dueAt` is in the past or now.
  List<SrsWord> getDueGrammarPoints([DateTime? now]) {
    final cutoff = now ?? DateTime.now();
    if (_cachedDueWords != null &&
        _cachedDueAt != null &&
        !_cachedDueAt!.isAfter(cutoff)) {
      return _cachedDueWords!;
    }
    final result = state.values.where((w) => !w.dueAt.isAfter(cutoff)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    _cachedDueWords = result;
    _cachedDueAt = cutoff;
    return result;
  }

  int get dueCount => getDueGrammarPoints().length;
  int get totalSeen => state.values.where((w) => w.reps >= 1).length;
  int get totalRegistered => state.length;

  Future<void> _persist(Map<String, SrsWord> map) async {
    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k, v.toJson())),
    );
    await appPrefs.preferences
        .setString(LocalStateKeys.grammarReviewState, encoded);
    _cachedState = map;
    _cachedDueWords = null;
    _cachedDueAt = null;
    notifyListeners();
  }

}