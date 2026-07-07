// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/application/achievements_provider.dart';
import 'package:words625/application/audio_controller.dart';
import 'package:words625/application/course_provider.dart';
import 'package:words625/application/game_provider.dart';
import 'package:words625/application/gems_provider.dart';
import 'package:words625/application/srs_provider.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/lesson_content.dart';
import 'package:words625/domain/course/reading_question.dart';
import 'package:words625/domain/course/stage.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';

/// Describes the UI state after an answer is submitted.
enum AnswerState {
  none,
  selected,
  correct,
  incorrect,
  readyForNext,
}

extension AnswerStateX on AnswerState {
  bool get isCorrect =>
      this == AnswerState.correct || this == AnswerState.readyForNext;
  bool get isIncorrect => this == AnswerState.incorrect;
}

/// ViewModel for the new 5-layer lesson flow.
///
/// Owns progression through [Stage]s / [ReadingStage]s inside a [Lesson].
/// Renderers report correctness via `submitInteraction()`; the ViewModel
/// decides when to advance and when the lesson is complete.
@injectable
class LessonViewModel extends ChangeNotifier {
  final CourseProvider _courseProvider;
  final GameProvider _gameProvider;
  final GemsProvider _gemsProvider;
  final AchievementsProvider _achievementsProvider;
  final AudioController _audioController;
  final SrsProvider _srsProvider;

  LessonViewModel(
    this._courseProvider,
    this._gameProvider,
    this._gemsProvider,
    this._achievementsProvider,
    this._audioController,
    this._srsProvider,
  );

  // --- Lesson state ---
  Lesson? _lesson;
  int _currentStageIndex = 0;
  int _currentInteractionIndex = 0;
  int _mistakesInCurrentStage = 0;
  bool _isComplete = false;

  /// Per-item submission state, keyed by `interactionItemId(stageId, idx)`.
  final Map<String, InteractionState> _interactionStates = {};

  // --- Getters ---

  Lesson? get lesson => _lesson;
  LessonType get lessonType => _lesson?.type ?? LessonType.normal;
  bool get isComplete => _isComplete;

  bool get isReadingLesson =>
      _lesson?.content is ReadingContent;

  /// Current stage (for normal/listening/review/challenge).
  Stage? get currentStage {
    if (_lesson == null) return null;
    final content = _lesson!.content;
    if (content is NormalContent ||
        content is ListeningContent ||
        content is ReviewContent ||
        content is ChallengeContent) {
      final stages = _stagesFromContent(content);
      if (stages.isEmpty || _currentStageIndex >= stages.length) return null;
      return stages[_currentStageIndex] as Stage;
    }
    return null;
  }

  /// Current reading stage (for reading lessons).
  ReadingStage? get currentReadingStage {
    if (!isReadingLesson) return null;
    final content = _lesson!.content as ReadingContent;
    if (content.stages.isEmpty ||
        _currentStageIndex >= content.stages.length) {
      return null;
    }
    return content.stages[_currentStageIndex];
  }

  /// The current [Interaction] if this lesson uses normal stages.
  Interaction? get currentInteraction {
    final stage = currentStage;
    if (stage == null) return null;
    if (_currentInteractionIndex >= stage.items.length) return null;
    return stage.items[_currentInteractionIndex];
  }

  /// The current [ReadingQuestion] if this is a reading lesson.
  ReadingQuestion? get currentReadingQuestion {
    final stage = currentReadingStage;
    if (stage == null) return null;
    if (_currentInteractionIndex >= stage.items.length) return null;
    return stage.items[_currentInteractionIndex];
  }

  /// The ID for the current interaction item.
  String get currentInteractionId {
    final stageId = isReadingLesson
        ? currentReadingStage?.id
        : currentStage?.id;
    return interactionItemId(stageId ?? 'unknown', _currentInteractionIndex);
  }

  /// The [InteractionState] for the current item.
  InteractionState get currentInteractionState =>
      _interactionStates[currentInteractionId] ?? InteractionState.idle;

  /// Name of the current stage (e.g. "Vocabulary", "Practice").
  String? get currentStageName {
    if (isReadingLesson) return currentReadingStage?.name;
    return currentStage?.name;
  }

  /// 0.0 → 1.0 progress through the entire lesson.
  double get progress {
    if (_lesson == null) return 0.0;
    final total = _totalItemCount;
    if (total == 0) return 0.0;
    return (_completedItemCount) / total;
  }

  /// Progress within the current stage.
  double get currentStageProgress {
    final current = _stageItemCount;
    if (current == 0) return 0.0;
    return _currentInteractionIndex / current;
  }

  bool get isLastInteraction {
    if (_lesson == null) return true;
    final totalStages = _stageCount;
    if (_currentStageIndex >= totalStages - 1) {
      return _currentInteractionIndex >= _stageItemCount - 1;
    }
    return false;
  }

  bool get isLastStageItem =>
      _currentInteractionIndex >= _stageItemCount - 1;

  bool get hasSubmitted => currentInteractionState.submitted;
  bool get isAnswerCorrect => currentInteractionState.correct == true;

  // --- Methods ---

  /// Load a lesson by ID and reset all progress state.
  void loadLesson(String lessonId) {
    _lesson = _courseProvider.findLessonById(lessonId);
    if (_lesson == null) return;

    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _mistakesInCurrentStage = 0;
    _isComplete = false;
    _interactionStates.clear();

    // Register SRS words referenced by ShowWord interactions.
    _registerSrsWords();

    notifyListeners();
  }

  /// Submit the current interaction with a correctness verdict.
  void submitInteraction(bool correct, {String? userAnswerText}) {
    if (_lesson == null) return;

    if (!correct) {
      _mistakesInCurrentStage++;
      _audioController.playRandomErrorSound();
    } else {
      _audioController.playRandomLevelUpSound();
    }

    _interactionStates[currentInteractionId] = InteractionState(
      submitted: true,
      correct: correct,
      userAnswerText: userAnswerText,
    );

    notifyListeners();
  }

  /// Advance to the next interaction (or stage). Called after the user
  /// acknowledges the current result (tap "Continue" / "Got It").
  void advance() {
    if (_lesson == null || _isComplete) return;

    _currentInteractionIndex++;

    // Check if we've exhausted the current stage.
    if (_currentInteractionIndex >= _stageItemCount) {
      _currentInteractionIndex = 0;
      _currentStageIndex++;
      _mistakesInCurrentStage = 0;

      // Check if all stages are done.
      if (_currentStageIndex >= _stageCount) {
        _isComplete = true;
        _onLessonCompleted();
        notifyListeners();
        return;
      }
    }

    notifyListeners();
  }

  /// Reset to beginning of lesson (for retry).
  void reset() {
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _mistakesInCurrentStage = 0;
    _isComplete = false;
    _interactionStates.clear();
    notifyListeners();
  }

  // --- Private helpers ---

  int get _stageCount {
    if (_lesson == null) return 0;
    final content = _lesson!.content;
    return switch (content) {
      NormalContent(stages: final s) => s.length,
      ListeningContent(stages: final s) => s.length,
      ReviewContent(stages: final s) => s.length,
      ChallengeContent(stages: final s) => s.length,
      ReadingContent(stages: final s) => s.length,
    };
  }

  int get _stageItemCount {
    if (_lesson == null) return 0;
    final content = _lesson!.content;
    if (_currentStageIndex < 0) return 0;
    return switch (content) {
      NormalContent(stages: final s) =>
        _currentStageIndex < s.length
            ? s[_currentStageIndex].items.length
            : 0,
      ListeningContent(stages: final s) =>
        _currentStageIndex < s.length
            ? s[_currentStageIndex].items.length
            : 0,
      ReviewContent(stages: final s) =>
        _currentStageIndex < s.length
            ? s[_currentStageIndex].items.length
            : 0,
      ChallengeContent(stages: final s) =>
        _currentStageIndex < s.length
            ? s[_currentStageIndex].items.length
            : 0,
      ReadingContent(stages: final s) =>
        _currentStageIndex < s.length
            ? s[_currentStageIndex].items.length
            : 0,
    };
  }

  int get _totalItemCount {
    if (_lesson == null) return 0;
    final content = _lesson!.content;
    return switch (content) {
      NormalContent(stages: final s) =>
        s.fold<int>(0, (sum, st) => sum + st.items.length),
      ListeningContent(stages: final s) =>
        s.fold<int>(0, (sum, st) => sum + st.items.length),
      ReviewContent(stages: final s) =>
        s.fold<int>(0, (sum, st) => sum + st.items.length),
      ChallengeContent(stages: final s) =>
        s.fold<int>(0, (sum, st) => sum + st.items.length),
      ReadingContent(stages: final s) =>
        s.fold<int>(0, (sum, st) => sum + st.items.length),
    };
  }

  /// Count of items already submitted (completed).
  int get _completedItemCount =>
      _interactionStates.values.where((s) => s.submitted).length;

  List _stagesFromContent(LessonContent content) {
    return switch (content) {
      NormalContent(stages: final s) => s,
      ListeningContent(stages: final s) => s,
      ReviewContent(stages: final s) => s,
      ChallengeContent(stages: final s) => s,
      ReadingContent() => <Stage>[],
    };
  }

  /// Find all ShowWord interactions and register their wordIds in SRS.
  void _registerSrsWords() {
    if (_lesson == null) return;
    final wordIds = <String>{};
    final content = _lesson!.content;
    if (content is! ReadingContent) {
      for (final stage in _stagesFromContent(content)) {
        if (stage is Stage) {
          for (final item in stage.items) {
            if (item is ShowWord) wordIds.add(item.wordId);
          }
        }
      }
    }
    if (wordIds.isNotEmpty) {
      _srsProvider.registerAll(wordIds);
    }
  }

  // --- Completion hooks (ported from old LessonProvider) ---

  Future<void> _onLessonCompleted() async {
    final wasPerfect = _mistakesInCurrentStage == 0;

    await _gameProvider.awardXP(XPEvent.lessonComplete);
    await _gemsProvider.earnGems(GemEvent.lessonComplete);

    if (wasPerfect) {
      await _gameProvider.awardXP(XPEvent.perfectLesson);
      await _gemsProvider.earnGems(GemEvent.perfectLesson);
    }

    await _gameProvider.recordLessonCompletion(wasPerfect: wasPerfect);

    final userData = await _gameProvider.getUserGameStateOnce();
    final lessonsCompleted =
        (userData['lessonsCompleted'] as num? ?? 0).toInt();
    final perfectLessons =
        (userData['perfectLessons'] as num? ?? 0).toInt();
    await _achievementsProvider.checkLessonMilestones(
      lessonsCompleted: lessonsCompleted,
      perfectLessons: perfectLessons,
    );
  }
}
