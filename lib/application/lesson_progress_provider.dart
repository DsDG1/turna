// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/service/locator.dart';

/// Owns per-lesson completed / perfect sets.
@lazySingleton
class LessonProgressProvider extends ChangeNotifier {
  LessonProgressProvider(this.appPrefs) {
    _completedLessonIds = _readStringList(
      LocalStateKeys.completedLessonIds,
      const <String>[],
    ).toSet();
    _perfectLessonIds = _readStringList(
      LocalStateKeys.perfectLessonIds,
      const <String>[],
    ).toSet();
  }

  final AppPrefs appPrefs;

  final StreamController<Set<String>> _completedLessonsController =
      StreamController<Set<String>>.broadcast();

  late Set<String> _completedLessonIds;
  late Set<String> _perfectLessonIds;

  Set<String> get completedLessonIds => Set.unmodifiable(_completedLessonIds);
  Set<String> get perfectLessonIds => Set.unmodifiable(_perfectLessonIds);

  bool isLessonCompleted(String lessonId) =>
      _completedLessonIds.contains(lessonId);

  bool isLessonPerfect(String lessonId) => _perfectLessonIds.contains(lessonId);

  Stream<Set<String>> get completedLessonsStream async* {
    yield Set.unmodifiable(_completedLessonIds);
    yield* _completedLessonsController.stream;
  }

  Future<void> recordLessonCompletion({
    required String lessonId,
    required bool wasPerfect,
  }) async {
    _completedLessonIds.add(lessonId);
    if (wasPerfect) {
      _perfectLessonIds.add(lessonId);
    }

    final lessonsCompleted = _completedLessonIds.length;
    final perfectLessons = _perfectLessonIds.length;

    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        _completedLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        _perfectLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.lessonsCompleted,
        lessonsCompleted,
      ),
      appPrefs.preferences
          .setInt(LocalStateKeys.perfectLessons, perfectLessons),
    ]);

    notifyListeners();
    _completedLessonsController.add(Set.unmodifiable(_completedLessonIds));
  }

  Future<void> resetLessonProgress() async {
    _completedLessonIds.clear();
    _perfectLessonIds.clear();

    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setInt(LocalStateKeys.lessonsCompleted, 0),
      appPrefs.preferences.setInt(LocalStateKeys.perfectLessons, 0),
      appPrefs.preferences.setInt(LocalStateKeys.wordsLearned, 0),
    ]);

    notifyListeners();
    _completedLessonsController.add(const <String>{});
  }

  /// Refresh cached lesson-id sets after progress is restored outside this
  /// provider (Fun Lab checkpoint / data import).
  void reloadFromPrefs() {
    _completedLessonIds = _readStringList(
      LocalStateKeys.completedLessonIds,
      const <String>[],
    ).toSet();
    _perfectLessonIds = _readStringList(
      LocalStateKeys.perfectLessonIds,
      const <String>[],
    ).toSet();
    notifyListeners();
    _completedLessonsController.add(Set.unmodifiable(_completedLessonIds));
  }

  List<String> _readStringList(String key, List<String> fallback) =>
      appPrefs.preferences
          .getStringList(key, defaultValue: fallback)
          .getValue();

  @override
  void dispose() {
    _completedLessonsController.close();
    super.dispose();
  }
}
