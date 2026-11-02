// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/lesson_progress_provider.dart';

/// Read-only view onto the user's lesson-completion state.
///
/// Acts as the seam between UI (course tree, lesson list) and the
/// underlying [GameProvider] storage. Keeping the progress concerns here
/// means the course tree does not need to know about [GameProvider]'s
/// other responsibilities (XP, streak, gems, etc.).
///
/// Listening to [completedLessonsStream] lets a `StreamBuilder` rebuild
/// exactly when the user finishes a lesson — no manual invalidation
/// needed. Sub-lesson records fire no stream event, so this provider also
/// listens to [LessonProgressProvider] directly: a sub-lesson session that
/// finishes without settling the parent lesson must still refresh the
/// tree's per-node states.
@lazySingleton
class ProgressProvider extends ChangeNotifier {
  final GameProvider _gameProvider;
  final LessonProgressProvider? _lessonProgress;
  StreamSubscription<Set<String>>? _subscription;

  /// [lessonProgress] carries the sub-lesson node records the course tree
  /// reads ([isSubLessonCompleted] / [isSubLessonPerfect]) and the change
  /// signal for them — sub-lesson records fire no lesson-level stream event.
  /// Nullable so lightweight widget tests with a fake [GameProvider] can
  /// omit it (sub-lesson state then reads as unrecorded).
  ProgressProvider(this._gameProvider, {LessonProgressProvider? lessonProgress})
      : _lessonProgress = lessonProgress {
    _subscription = _gameProvider.completedLessonsStream.listen((_) {
      // Forward GameProvider's per-lesson-completion events so widgets
      // that `Provider.of` this can rebuild even though the underlying
      // record lives in [GameProvider].
      notifyListeners();
    });
    _lessonProgress?.addListener(notifyListeners);
  }

  /// True if the user has finished [lessonId] at least once.
  bool isLessonCompleted(String lessonId) =>
      _gameProvider.isLessonCompleted(lessonId);

  /// True if the user has finished [lessonId] with zero mistakes.
  bool isLessonPerfect(String lessonId) =>
      _gameProvider.isLessonPerfect(lessonId);

  /// True if sub-lesson [subLessonId] of [lessonId] has been finished.
  /// Callers must treat a completed parent lesson as "every sub-lesson
  /// completed" (legacy records predate per-node tracking) — this getter
  /// deliberately reports only the per-node record.
  bool isSubLessonCompleted(String lessonId, String subLessonId) =>
      _lessonProgress?.isSubLessonCompleted(lessonId, subLessonId) ?? false;

  /// True if sub-lesson [subLessonId] was finished with zero mistakes.
  bool isSubLessonPerfect(String lessonId, String subLessonId) =>
      _lessonProgress?.isSubLessonPerfect(lessonId, subLessonId) ?? false;

  /// Number of lessons the user has completed (any quality).
  int get lessonsCompleted => _gameProvider.completedLessonIds.length;

  /// Number of lessons completed without any mistakes.
  int get perfectLessons => _gameProvider.perfectLessonIds.length;

  /// Live stream of the completed-lesson-id set. Emits the current
  /// value on subscribe, then again on every lesson finish.
  Stream<Set<String>> get completedLessonsStream =>
      _gameProvider.completedLessonsStream;

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
