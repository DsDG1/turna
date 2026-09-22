// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/service/locator.dart';

/// Prefs key for the last AI lesson rewrite, kept so undo survives leaving
/// the helper sheet.
const kAiLessonUndoKey = 'ai.lessonHelper.lastUndo';

/// One-step local snapshot of the lesson JSON from before the last apply.
class AiLessonUndoStore extends ChangeNotifier {
  AiLessonUndoStore({AppPrefs? prefs}) : _prefs = prefs;

  static final AiLessonUndoStore instance = AiLessonUndoStore();

  final AppPrefs? _prefs;

  AppPrefs? get _resolved {
    if (_prefs != null) return _prefs;
    if (getIt.isRegistered<AppPrefs>()) return getIt<AppPrefs>();
    return null;
  }

  Lesson? peek() {
    final prefs = _resolved;
    if (prefs == null) return null;
    try {
      final raw = prefs.preferences
          .getString(kAiLessonUndoKey, defaultValue: '')
          .getValue();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Lesson.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Corrupt JSON — nothing to undo.
      return null;
    }
  }

  Future<void> save(Lesson lesson) async {
    final prefs = _resolved;
    if (prefs == null) return;
    await prefs.preferences
        .setString(kAiLessonUndoKey, jsonEncode(lesson.toJson()));
    notifyListeners();
  }

  Future<Lesson?> take() async {
    final lesson = peek();
    await clear();
    return lesson;
  }

  Future<void> clear() async {
    final prefs = _resolved;
    if (prefs == null) return;
    await prefs.preferences.remove(kAiLessonUndoKey);
    notifyListeners();
  }
}
