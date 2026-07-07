// Flutter imports:
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/core/sm2.dart';
import 'package:words625/domain/course/srs_word.dart';
import 'package:words625/service/locator.dart';

/// Manages the per-word spaced-repetition state, persisted to
/// [LocalStateKeys.srsState] via [StreamingSharedPreferences].
@injectable
class SrsProvider extends ChangeNotifier {
  final AppPrefs appPrefs;
  final Sm2Engine _engine = const Sm2Engine();

  SrsProvider(this.appPrefs);

  Map<String, SrsWord>? _cachedState;

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
    } catch (_) {
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

  /// Words whose `dueAt` is in the past or now.
  List<SrsWord> getDueWords([DateTime? now]) {
    final cutoff = now ?? DateTime.now();
    return state.values.where((w) => !w.dueAt.isAfter(cutoff)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  /// Up to [n] random words that have been seen at least once.
  List<SrsWord> getMixedWords(int n) {
    final seen = state.values.where((w) => w.reps >= 1).toList();
    seen.shuffle();
    return seen.take(n).toList();
  }

  /// Words with at least one lapse (recurring mistakes).
  List<SrsWord> getLapseWords() {
    return state.values.where((w) => w.lapses > 0).toList()
      ..sort((a, b) => b.lapses.compareTo(a.lapses));
  }

  int get dueCount => getDueWords().length;
  int get totalSeen => state.values.where((w) => w.reps >= 1).length;
  int get totalRegistered => state.length;

  Future<void> _persist(Map<String, SrsWord> map) async {
    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k, v.toJson())),
    );
    await appPrefs.preferences.setString(LocalStateKeys.srsState, encoded);
    _cachedState = map;
    notifyListeners();
  }

  SrsWord _parse(Map<String, dynamic> json) {
    // SrsWord.fromJson handles DateTime conversion.
    return SrsWord.fromJson(json);
  }
}