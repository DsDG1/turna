// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// A bookmarked AI explanation (prefs-backed FIFO list, max [maxEntries]).
@immutable
class SavedExplanation {
  const SavedExplanation({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.createdAt,
    this.language,
    this.genre,
  });

  final String id;
  final String title;
  final String body;
  final String source; // hint | depth | dictionary | diagnosis | review
  final String? language;
  final String? genre;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'source': source,
        'language': language,
        'genre': genre,
        'createdAt': createdAt.toIso8601String(),
      };

  static SavedExplanation fromJson(Map<String, dynamic> m) => SavedExplanation(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        source: (m['source'] ?? 'hint').toString(),
        language: m['language']?.toString(),
        genre: m['genre']?.toString(),
        createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Prefs key for the JSON array of saved explanations.
const kSavedExplanationsKey = 'ai.savedExplanations';

/// List/search/save/delete companion explanations. Survives process restart
/// when [AppPrefs] is registered.
class AiSavedExplanationsStore extends ChangeNotifier {
  static const int maxEntries = 100;

  final List<SavedExplanation> _items = <SavedExplanation>[];

  List<SavedExplanation> get items => List.unmodifiable(_items);

  /// Newest-first list filtered by [query] over title/body (case-insensitive).
  List<SavedExplanation> search(String query) {
    final q = query.trim().toLowerCase();
    final ordered = _items.reversed.toList();
    if (q.isEmpty) return ordered;
    return ordered
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.body.toLowerCase().contains(q))
        .toList();
  }

  Future<void> load() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final raw = prefs.preferences
          .getString(kSavedExplanationsKey, defaultValue: '')
          .getValue();
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _items
        ..clear()
        ..addAll([
          for (final e in decoded)
            if (e is Map<String, dynamic>) SavedExplanation.fromJson(e)
            else if (e is Map) SavedExplanation.fromJson(Map<String, dynamic>.from(e)),
        ]);
      notifyListeners();
    } catch (_) {
      // Corrupt JSON — keep empty.
    }
  }

  /// Save [item]; FIFO-evict oldest when over [maxEntries]. Returns the id.
  Future<String> save(SavedExplanation item) async {
    // Replace same id if re-saving.
    _items.removeWhere((e) => e.id == item.id);
    _items.add(item);
    while (_items.length > maxEntries) {
      _items.removeAt(0);
    }
    await _persist();
    notifyListeners();
    return item.id;
  }

  Future<void> delete(String id) async {
    final before = _items.length;
    _items.removeWhere((e) => e.id == id);
    if (_items.length == before) return;
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items.clear();
    await _persist();
    notifyListeners();
  }

  AppPrefs? get _prefs {
    if (!getIt.isRegistered<AppPrefs>()) return null;
    try {
      return getIt<AppPrefs>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.preferences.setString(kSavedExplanationsKey, raw);
  }

  /// Create a new id (time-based; fine for local MVP).
  static String newId() =>
      'se_${DateTime.now().microsecondsSinceEpoch}';
}
