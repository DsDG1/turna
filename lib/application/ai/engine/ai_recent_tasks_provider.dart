// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

/// A single completed AI task recorded by the engine's consumers.
///
/// [kind] is a short domain tag — one of the [AiTaskKind] constants or any
/// future surface the engine hosts. The Continue section of the AI Hub uses
/// it to pick an icon and label.
///
/// [summary] is a one-line human-readable hint, e.g. "By mistakes: 8
/// questions" or "Course · Turkish A1 → 4 units".
///
/// [route] is an optional `auto_route` route **name** (e.g.
/// `AiWishChatRoute.name`). When non-null the AI Hub renders the row as a
/// navigation tile; when null the row is informational only.
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
  final String? route;

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
}

/// In-memory ring of the most recent AI tasks completed by the engine.
///
/// The engine facade itself stays domain-agnostic: every provider / feature
/// that calls into [AiEngine] is responsible for [record]ing its outcome
/// here. Cache hits are intentionally NOT recorded — the AI Hub's Continue
/// section is a list of things the user actually generated, not a list of
/// requests served from cache.
///
/// Lifetime is process-bound (no persistence). Resetting the engine config
/// does NOT clear this list; only [clear] does.
@lazySingleton
class AiRecentTasksProvider extends ChangeNotifier {
  static const int maxEntries = 20;

  final List<AiRecentTask> _items = <AiRecentTask>[];

  /// Most recent [limit] tasks (newest first). The returned list is
  /// unmodifiable; callers must not mutate it.
  List<AiRecentTask> recent({int limit = 3}) {
    if (limit <= 0) return const <AiRecentTask>[];
    final n = _items.length;
    if (n == 0) return const <AiRecentTask>[];
    final take = n < limit ? n : limit;
    return List<AiRecentTask>.unmodifiable(_items.reversed.take(take));
  }

  /// Number of recorded tasks. Exposed for the AI Hub header chip.
  int get count => _items.length;

  /// Append [task] to the ring, evicting the oldest entry if necessary.
  void record(AiRecentTask task) {
    _items.add(task);
    if (_items.length > maxEntries) {
      _items.removeAt(0);
    }
    notifyListeners();
  }

  /// Drop every recorded task. Used by the AI Hub Tools section's
  /// "clear history" affordance if/when it ships.
  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
