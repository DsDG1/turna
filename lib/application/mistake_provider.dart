// Flutter imports:
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/mistake_entry.dart';
import 'package:words625/service/locator.dart';

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

  List<MistakeEntry> get entries {
    if (_cached != null) return List.unmodifiable(_cached!);

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
    return List.unmodifiable(_cached!);
  }

  /// Number of mistakes currently stored.
  int get count => entries.length;

  /// Add a new mistake. If the log exceeds [maxEntries], the oldest entry is
  /// removed.
  Future<void> record(MistakeEntry entry) async {
    final current = entries;
    current.add(entry);
    if (current.length > maxEntries) {
      current.removeAt(0);
    }
    await _persist(current);
  }

  /// Mark a mistake as rewritten correctly. If [rewriteCount] reaches 2, the
  /// entry is removed from the log.
  Future<void> recordRewrite(String entryId) async {
    final current = entries;
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

  /// Clear all recorded mistakes.
  Future<void> clear() async {
    await _persist(<MistakeEntry>[]);
  }

  /// Returns the stored interaction snapshot for [entry], or `null` if the
  /// mistake was recorded before snapshots were saved.
  Interaction? toInteraction(MistakeEntry entry) => entry.interactionSnapshot;

  Future<void> _persist(List<MistakeEntry> list) async {
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await appPrefs.preferences.setString(_prefsKey, encoded);
    _cached = list;
    notifyListeners();
  }
}
