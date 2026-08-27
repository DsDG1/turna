// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Typed destination a recorded AI task can resume to.
///
/// The persisted form is the auto_route route *name* (see [routeName]); a
/// stored name that no longer matches any value decodes to `null`, so a
/// renamed route degrades the row to informational instead of crashing.
enum AiRecentTaskRoute {
  wishChat('AiWishChatRoute'),
  textbookImport('TextbookImportRoute'),
  tutorChat('AiTutorChatRoute'),
  diagnosis('AiDiagnosisRoute'),
  hintChat('AiHintChatRoute');

  const AiRecentTaskRoute(this.routeName);

  /// The auto_route route name this destination is persisted as.
  final String routeName;

  /// Parse a persisted route name; unknown names return `null`.
  static AiRecentTaskRoute? tryParse(String? name) {
    if (name == null) return null;
    for (final value in AiRecentTaskRoute.values) {
      if (value.routeName == name) return value;
    }
    return null;
  }
}

/// A single completed AI task recorded by the engine's consumers.
///
/// [kind] is a short domain tag — one of the [AiTaskKind] constants or any
/// future surface the engine hosts. The Continue section of the AI Hub uses
/// it to pick an icon and label.
///
/// [summary] is a one-line human-readable hint, e.g. "By mistakes: 8
/// questions" or "Course · Turkish A1 → 4 units".
///
/// [route] is an optional typed resume destination. When non-null the AI Hub
/// renders the row as a navigation tile; when null the row is informational
/// only.
class AiRecentTask {
  const AiRecentTask({
    required this.kind,
    required this.summary,
    required this.timestamp,
    this.route,
  });

  final String kind;
  final String summary;
  final DateTime timestamp;
  final AiRecentTaskRoute? route;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'summary': summary,
        'timestamp': timestamp.toIso8601String(),
        'route': route?.routeName,
      };

  static AiRecentTask fromJson(Map<String, dynamic> m) => AiRecentTask(
        kind: (m['kind'] ?? AiTaskKind.generic).toString(),
        summary: (m['summary'] ?? '').toString(),
        timestamp: DateTime.tryParse((m['timestamp'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        route: AiRecentTaskRoute.tryParse(m['route']?.toString()),
      );

  @override
  String toString() =>
      'AiRecentTask(kind: $kind, summary: $summary, at: $timestamp)';
}

/// Built-in [AiRecentTask.kind] tags. Custom strings are accepted but the
/// Hub UI only recognises these for icon + label mapping.
class AiTaskKind {
  static const String generic = 'generic';
  static const String wish = 'wish';
  static const String textbook = 'textbook';
  static const String tutor = 'tutor';
  static const String tutorMistakes = 'tutor.mistakes';
  static const String tutorWeakWords = 'tutor.weak-words';
  static const String hintDepth = 'hint.depth';
  static const String hintChat = 'hint.chat';
  static const String lessonHelper = 'lesson-helper';
  static const String courseGenerate = 'course.generate';
  static const String tutorChat = 'tutor.chat';
  static const String diagnosis = 'tutor.diagnosis';
  static const String dictionary = 'dictionary.enrich';
  static const String saved = 'saved';

  /// Companion kinds that are persisted across restarts.
  static const Set<String> companionPersistKinds = {
    hintChat,
    hintDepth,
    tutorChat,
    diagnosis,
    dictionary,
    tutorMistakes,
    tutorWeakWords,
  };
}

/// Prefs key for companion recent tasks JSON array.
const kAiRecentCompanionTasksKey = 'ai.recentCompanionTasks';

/// In-memory ring of the most recent AI tasks completed by the engine.
///
/// Companion task kinds are also persisted to prefs so they survive process
/// restarts. Authoring kinds remain memory-only.
@lazySingleton
class AiRecentTasksProvider extends ChangeNotifier {
  static const int maxEntries = 20;

  final List<AiRecentTask> _items = <AiRecentTask>[];
  bool _loaded = false;

  /// Newest-first snapshot of all recorded tasks. Rebuilt only when [_items]
  /// changes, so its identity (and `==`) is stable across notifications —
  /// safe to use directly as a `Selector` value (a getter that allocates a
  /// fresh list there would rebuild on every notify).
  List<AiRecentTask> _snapshotNewestFirst = const <AiRecentTask>[];

  /// All recorded tasks, newest first. The same list instance is returned
  /// until the recorded set changes.
  List<AiRecentTask> get items => _snapshotNewestFirst;

  void _rebuildSnapshot() {
    _snapshotNewestFirst = _items.isEmpty
        ? const <AiRecentTask>[]
        : List<AiRecentTask>.unmodifiable(_items.reversed);
  }

  /// Most recent [limit] tasks (newest first). The returned list is
  /// unmodifiable; callers must not mutate it. Inside `Selector` values
  /// prefer [items] (stable identity); use this only outside rebuild-scope
  /// comparisons.
  List<AiRecentTask> recent({int limit = 3}) {
    if (limit <= 0) return const <AiRecentTask>[];
    final n = _snapshotNewestFirst.length;
    if (n == 0) return const <AiRecentTask>[];
    final take = n < limit ? n : limit;
    return List<AiRecentTask>.unmodifiable(_snapshotNewestFirst.take(take));
  }

  /// Number of recorded tasks. Exposed for the AI Hub header chip.
  int get count => _items.length;

  /// Hydrate companion tasks from prefs (call once at startup).
  Future<void> loadPersisted() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final raw = prefs.preferences
          .getString(kAiRecentCompanionTasksKey, defaultValue: '')
          .getValue();
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final e in decoded) {
        final map = e is Map<String, dynamic>
            ? e
            : e is Map
                ? Map<String, dynamic>.from(e)
                : null;
        if (map == null) continue;
        final task = AiRecentTask.fromJson(map);
        if (AiTaskKind.companionPersistKinds.contains(task.kind)) {
          _items.add(task);
        }
      }
      if (_items.length > maxEntries) {
        _items.removeRange(0, _items.length - maxEntries);
      }
      if (_items.isNotEmpty) {
        _rebuildSnapshot();
        notifyListeners();
      }
    } catch (_) {
      // Corrupt — keep empty.
    }
  }

  /// Append [task] to the ring, evicting the oldest entry if necessary.
  void record(AiRecentTask task) {
    _items.add(task);
    if (_items.length > maxEntries) {
      _items.removeAt(0);
    }
    _rebuildSnapshot();
    _persistCompanion();
    notifyListeners();
  }

  /// Drop every recorded task.
  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _rebuildSnapshot();
    _persistCompanion();
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

  void _persistCompanion() {
    final prefs = _prefs;
    if (prefs == null) return;
    final companion = [
      for (final t in _items)
        if (AiTaskKind.companionPersistKinds.contains(t.kind)) t.toJson(),
    ];
    // Fire-and-forget.
    prefs.preferences
        .setString(kAiRecentCompanionTasksKey, jsonEncode(companion));
  }
}
