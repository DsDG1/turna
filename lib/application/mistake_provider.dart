// Flutter imports:
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/service/locator.dart';

/// Manages a FIFO log of recent wrong answers.
///
/// Only the most recent [maxEntries] mistakes are kept; older entries are
/// evicted automatically. Entries can be reviewed and removed when the user
/// rewrites them correctly.
@lazySingleton
class MistakeProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  MistakeProvider(this.appPrefs);

  static const int maxEntries = 30;
  static const String _prefsKey = LocalStateKeys.mistakeLog;

  List<MistakeEntry>? _cached;
  List<MistakeEntry>? _cachedView;

  List<MistakeEntry> get entries {
    if (_cachedView != null) return _cachedView!;

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
    return _cachedView!;
  }

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
  /// removed.
  Future<void> record(MistakeEntry entry) async {
    final current = entries.toList();
    current.add(entry);
    if (current.length > maxEntries) {
      current.removeAt(0);
    }
    await _persist(current);
  }

  /// Mark a mistake as rewritten correctly. If [rewriteCount] reaches 2, the
  /// entry is removed from the log.
  Future<void> recordRewrite(String entryId) async {
    final current = entries.toList();
    final index = current.indexWhere((e) => e.id == entryId);
    if (index == -1) return;

    final entry = current[index];
    final updated = entry.copyWith(rewriteCount: entry.rewriteCount + 1);
    if (updated.rewriteCount >= 2) {
      current.removeAt(index);
    } else {
      current[index] = updated;
    }
    await _persist(current);
  }

  /// Remove the mistakes answered correctly in a review session ("做完则掌握"
  /// — clear only correct ones). Each id in [ids] that matches a stored entry
  /// is removed in a single shot, regardless of its [MistakeEntry.rewriteCount].
  Future<void> removeByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final current = entries.toList();
    current.removeWhere((e) => ids.contains(e.id));
    await _persist(current);
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

  /// Clear all recorded mistakes.
  Future<void> clear() async {
    await _persist(<MistakeEntry>[]);
  }

  /// Drop decoded state after an external checkpoint restore.
  void reloadFromPrefs() {
    _cached = null;
    _cachedView = null;
    notifyListeners();
  }

  /// Returns the stored interaction snapshot for [entry], or `null` if the
  /// mistake was recorded before snapshots were saved.
  Interaction? toInteraction(MistakeEntry entry) => entry.interactionSnapshot;

  Future<void> _persist(List<MistakeEntry> list) async {
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await appPrefs.preferences.setString(_prefsKey, encoded);
    _cached = list;
    _cachedView = null; // invalidate; next entries call rebuilds the view
    notifyListeners();
  }
}
