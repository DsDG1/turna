// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';

/// Read-only view onto the user's lesson-completion state.
///
/// Acts as the seam between UI (course tree, lesson list) and the
/// underlying [GameProvider] storage. Keeping the progress concerns here
/// means the course tree does not need to know about [GameProvider]'s
/// other responsibilities (XP, streak, gems, etc.).
///
/// Listening to [completedLessonsStream] lets a `StreamBuilder` rebuild
/// exactly when the user finishes a lesson — no manual invalidation
/// needed.
@lazySingleton
class ProgressProvider extends ChangeNotifier {
  final GameProvider _gameProvider;
  StreamSubscription<Set<String>>? _subscription;

  ProgressProvider(this._gameProvider) {
    _subscription = _gameProvider.completedLessonsStream.listen((_) {
      // Forward GameProvider's per-lesson-completion events so widgets
      // that `Provider.of` this can rebuild even though the underlying
      // record lives in [GameProvider].
      notifyListeners();
    });
  }

  /// True if the user has finished [lessonId] at least once.
  bool isLessonCompleted(String lessonId) =>
      _gameProvider.isLessonCompleted(lessonId);

  /// True if the user has finished [lessonId] with zero mistakes.
  bool isLessonPerfect(String lessonId) =>
      _gameProvider.isLessonPerfect(lessonId);

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