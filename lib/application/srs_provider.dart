// Flutter imports:
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/core/sm2.dart';
import 'package:varnamala/domain/course/lesson_word_link.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/service/locator.dart';

/// Manages the per-word spaced-repetition state, persisted to
/// [LocalStateKeys.srsState] via [StreamingSharedPreferences].
@lazySingleton
class SrsProvider extends ChangeNotifier {
  final AppPrefs appPrefs;
  final LessonLinkStore linkStore;
  final Sm2Engine _engine = const Sm2Engine();

  SrsProvider(this.appPrefs, this.linkStore);

  Map<String, SrsWord>? _cachedState;
  List<SrsWord>? _cachedDueWords;
  DateTime? _cachedDueAt;

  /// wordId → current [SrsWord] state. Words never seen are absent.
  Map<String, SrsWord> get state {
    if (_cachedState != null) return _cachedState!;

    final raw = appPrefs.preferences
        .getString(LocalStateKeys.srsState, defaultValue: '{}')
        .getValue();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cachedState = decoded.map((k, v) => MapEntry(k, _parse(v as Map<String, dynamic>)));
      return _cachedState!;
    } catch (e) {
      debugPrint('SrsProvider state decode failed: $e');
      _cachedState = <String, SrsWord>{};
      return _cachedState!;
    }
  }

  /// Register a new word as fresh (due immediately) if not yet seen.
  void registerWord(String wordId) {
    final current = state;
    if (current.containsKey(wordId)) return;
    current[wordId] = SrsWord.fresh(wordId);
    _persist(current);
  }

  /// Register multiple new words.
  void registerAll(Iterable<String> wordIds) {
    final current = state;
    var changed = false;
    for (final id in wordIds) {
      if (!current.containsKey(id)) {
        current[id] = SrsWord.fresh(id);
        changed = true;
      }
    }
    if (changed) _persist(current);
  }

  /// Register a new expression as fresh (due immediately) if not yet seen.
  void registerExpression(String expressionId) {
    final current = state;
    if (current.containsKey(expressionId)) return;
    current[expressionId] = SrsWord.fresh(expressionId).copyWith(
      type: SrsItemType.expression,
    );
    _persist(current);
  }

  /// Register multiple new expressions.
  void registerAllExpressions(Iterable<String> expressionIds) {
    final current = state;
    var changed = false;
    for (final id in expressionIds) {
      if (!current.containsKey(id)) {
        current[id] = SrsWord.fresh(id).copyWith(type: SrsItemType.expression);
        changed = true;
      }
    }
    if (changed) _persist(current);
  }

  /// Persist the lesson(s) where a set of word/expression/grammar ids were
  /// first encountered. Only the first recorded link for each id is kept.
  Future<void> recordLessonLinks({
    required Iterable<String> wordIds,
    required String lessonId,
    required String lessonName,
    LinkType type = LinkType.word,
  }) async {
    await linkStore.upsertFirstSeen(
      ids: wordIds,
      lessonId: lessonId,
      lessonName: lessonName,
      type: type,
    );
    notifyListeners();
  }

  /// The lesson name where [wordId] was first encountered, or `null` if
  /// unknown.
  String? getLessonNameForWord(String wordId) =>
      linkStore.lessonNameFor(wordId);

  /// The lesson name where [expressionId] was first encountered, or `null` if
  /// unknown.
  String? getLessonNameForExpression(String expressionId) =>
      linkStore.lessonNameFor(expressionId);

  /// Apply a SM-2 review for [wordId] with the given [quality].
  /// Returns the updated [SrsWord] (or null if [wordId] is unknown).
  Future<SrsWord?> reviewWord(String wordId, int quality) async {
    final current = state;
    final word = current[wordId];
    if (word == null) return null;
    final updated = _engine.review(word, quality);
    current[wordId] = updated;
    await _persist(current);
    return updated;
  }

  /// Apply a [ReviewQuality] review (4-button mapping).
  Future<SrsWord?> reviewWithQuality(String wordId, ReviewQuality quality) =>
      reviewWord(wordId, quality.sm2);

  /// Apply a SM-2 review for [expressionId] with the given [quality].
  /// Returns the updated [SrsWord] (or null if [expressionId] is unknown).
  Future<SrsWord?> reviewExpression(String expressionId, int quality) async {
    final current = state;
    final item = current[expressionId];
    if (item == null) return null;
    final updated = _engine.review(item, quality);
    current[expressionId] = updated;
    await _persist(current);
    return updated;
  }

  /// Apply a [ReviewQuality] review for an expression.
  Future<SrsWord?> reviewExpressionWithQuality(
    String expressionId,
    ReviewQuality quality,
  ) =>
      reviewExpression(expressionId, quality.sm2);

  /// Words whose `dueAt` is in the past or now.
  List<SrsWord> getDueWords([DateTime? now]) {
    final cutoff = now ?? DateTime.now();
    if (_cachedDueWords != null &&
        _cachedDueAt != null &&
        !_cachedDueAt!.isAfter(cutoff)) {
      return _cachedDueWords!;
    }
    final result = state.values
        .where((w) => w.type == SrsItemType.word && !w.dueAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    _cachedDueWords = result;
    _cachedDueAt = cutoff;
    return result;
  }

  /// Expressions whose `dueAt` is in the past or now.
  List<SrsWord> getDueExpressions([DateTime? now]) {
    final cutoff = now ?? DateTime.now();
    return state.values
        .where((w) =>
            w.type == SrsItemType.expression && !w.dueAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  /// Up to [n] random words that have been seen at least once.
  List<SrsWord> getMixedWords(int n) {
    final seen = state.values
        .where((w) => w.type == SrsItemType.word && w.reps >= 1)
        .toList();
    seen.shuffle();
    return seen.take(n).toList();
  }

  /// Up to [n] random expressions that have been seen at least once.
  List<SrsWord> getMixedExpressions(int n) {
    final seen = state.values
        .where((w) => w.type == SrsItemType.expression && w.reps >= 1)
        .toList();
    seen.shuffle();
    return seen.take(n).toList();
  }

  /// Words with at least one lapse (recurring mistakes).
  List<SrsWord> getLapseWords() {
    return state.values
        .where((w) => w.type == SrsItemType.word && w.lapses > 0)
        .toList()
      ..sort((a, b) => b.lapses.compareTo(a.lapses));
  }

  /// Expressions with at least one lapse.
  List<SrsWord> getLapseExpressions() {
    return state.values
        .where((w) => w.type == SrsItemType.expression && w.lapses > 0)
        .toList()
      ..sort((a, b) => b.lapses.compareTo(a.lapses));
  }

  int get dueCount => getDueWords().length;
  int get totalSeen =>
      state.values.where((w) => w.type == SrsItemType.word && w.reps >= 1).length;
  int get totalRegistered => state.values.where((w) => w.type == SrsItemType.word).length;

  int get expressionDueCount => getDueExpressions().length;
  int get expressionTotalSeen => state.values
      .where((w) => w.type == SrsItemType.expression && w.reps >= 1)
      .length;
  int get expressionTotalRegistered =>
      state.values.where((w) => w.type == SrsItemType.expression).length;

  Future<void> _persist(Map<String, SrsWord> map) async {
    // Update in-memory cache immediately so synchronous callers (and tests)
    // see the new state before the async write finishes.
    _cachedState = map;
    _cachedDueWords = null;
    _cachedDueAt = null;
    notifyListeners();

    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k, v.toJson())),
    );
    await appPrefs.preferences.setString(LocalStateKeys.srsState, encoded);
  }

  SrsWord _parse(Map<String, dynamic> json) {
    // SrsWord.fromJson handles DateTime conversion.
    return SrsWord.fromJson(json);
  }
}