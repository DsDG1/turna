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
    _completedSubLessonIds = _readStringList(
      LocalStateKeys.completedSubLessonIds,
      const <String>[],
    ).toSet();
  }

  final AppPrefs appPrefs;

  final StreamController<Set<String>> _completedLessonsController =
      StreamController<Set<String>>.broadcast();

  late Set<String> _completedLessonIds;
  late Set<String> _perfectLessonIds;
  late Set<String> _completedSubLessonIds;

  static String _subKey(String lessonId, String subLessonId) =>
      '$lessonId::$subLessonId';

  Set<String> get completedLessonIds => Set.unmodifiable(_completedLessonIds);
  Set<String> get perfectLessonIds => Set.unmodifiable(_perfectLessonIds);

  bool isLessonCompleted(String lessonId) =>
      _completedLessonIds.contains(lessonId);

  bool isLessonPerfect(String lessonId) => _perfectLessonIds.contains(lessonId);

  /// Whether [subLessonId] inside [lessonId] has been finished, regardless of
  /// whether the parent lesson is complete. The unit segmented lessons resume
  /// from: "walked sub-lesson 1, exited" must not replay sub-lesson 1.
  bool isSubLessonCompleted(String lessonId, String subLessonId) =>
      _completedSubLessonIds.contains(_subKey(lessonId, subLessonId));

  /// Records one sub-lesson as finished. Idempotent, and deliberately does
  /// not touch lesson-level completion: a lesson counts as complete only
  /// through [recordLessonCompletion], which the lesson walker fires when the
  /// last segment finishes.
  Future<void> recordSubLessonCompletion({
    required String lessonId,
    required String subLessonId,
  }) async {
    if (!_completedSubLessonIds.add(_subKey(lessonId, subLessonId))) return;
    await appPrefs.preferences.setStringList(
      LocalStateKeys.completedSubLessonIds,
      _completedSubLessonIds.toList(growable: false),
    );
  }

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
    _completedSubLessonIds.clear();

    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedSubLessonIds,
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
  /// provider (data import).
  void reloadFromPrefs() {
    _completedLessonIds = _readStringList(
      LocalStateKeys.completedLessonIds,
      const <String>[],
    ).toSet();
    _perfectLessonIds = _readStringList(
      LocalStateKeys.perfectLessonIds,
      const <String>[],
    ).toSet();
    _completedSubLessonIds = _readStringList(
      LocalStateKeys.completedSubLessonIds,
      const <String>[],
    ).toSet();
    notifyListeners();
    _completedLessonsController.add(Set.unmodifiable(_completedLessonIds));
  }

  /// Drop the given lessons from the completed / perfect sets (a language's
  /// uninstall cascade). Rewrites the persisted sets and the derived counters
  /// so totals stop counting lessons of a course that no longer exists.
  Future<void> removeLessonIds(Set<String> lessonIds) async {
    if (lessonIds.isEmpty) return;
    _completedLessonIds.removeAll(lessonIds);
    _perfectLessonIds.removeAll(lessonIds);
    _completedSubLessonIds.removeWhere(
      (key) => lessonIds.contains(key.split('::').first),
    );

    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        _completedLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        _perfectLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedSubLessonIds,
        _completedSubLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.lessonsCompleted,
        _completedLessonIds.length,
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.perfectLessons,
        _perfectLessonIds.length,
      ),
    ]);

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
