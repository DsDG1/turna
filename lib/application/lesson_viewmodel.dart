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
import 'package:words625/application/grammar_review_provider.dart';
import 'package:words625/application/mistake_provider.dart';
import 'package:words625/application/srs_provider.dart';
import 'package:words625/application/study_stats_provider.dart';
import 'package:words625/courses/course_loader.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/lesson_word_link.dart';
import 'package:words625/domain/course/mistake_entry.dart';
import 'package:words625/domain/course/stage.dart';
import 'package:words625/domain/study/study_log.dart';
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

/// ViewModel for the lesson flow.
///
/// Owns progression through [Stage]s inside a [Lesson]. Every lesson —
/// normal, listening, reading, review, challenge, or a flat list of
/// questions — is modelled as `lesson.content.stages`, each holding a
/// `List<Interaction>`. The viewmodel walks that single list; it never
/// branches on content type, so adding a new [LessonType] or a new
/// [Interaction] variant needs no changes here.
///
/// Renderers report correctness via [submitInteraction]; the ViewModel
/// decides when to advance and when the lesson is complete.
@lazySingleton
class LessonViewModel extends ChangeNotifier {
  final CourseProvider _courseProvider;
  final GameProvider _gameProvider;
  final GemsProvider _gemsProvider;
  final AchievementsProvider _achievementsProvider;
  final AudioController _audioController;
  final SrsProvider _srsProvider;
  final MistakeProvider _mistakeProvider;
  final GrammarReviewProvider _grammarReviewProvider;
  final StudyStatsProvider _studyStatsProvider;

  LessonViewModel(
    this._courseProvider,
    this._gameProvider,
    this._gemsProvider,
    this._achievementsProvider,
    this._audioController,
    this._srsProvider,
    this._mistakeProvider,
    this._grammarReviewProvider,
    this._studyStatsProvider,
  );

  // --- Lesson state ---
  Lesson? _lesson;
  List<Stage> _cachedStages = const [];
  int _currentStageIndex = 0;
  int _currentInteractionIndex = 0;
  int _totalMistakes = 0;
  bool _isComplete = false;
  DateTime? _lessonStartTime;
  int _correctAnswers = 0;
  int _incorrectAnswers = 0;

  // Mastery-specific state
  int _masteryAttempts = 0;
  bool _masteryPassed = false;

  /// Per-item submission state, keyed by [interactionItemId] — uses the
  /// item's stable `id` field when present, falling back to `legacy-$idx`.
  final Map<String, InteractionState> _interactionStates = {};

  // --- Getters ---

  Lesson? get lesson => _lesson;
  LessonType get lessonType => _lesson?.type ?? LessonType.normal;
  bool get isComplete => _isComplete;
  bool get isMastery => _lesson?.isMastery ?? false;
  bool get masteryPassed => _masteryPassed;
  int get masteryAttempts => _masteryAttempts;
  int get correctAnswers => _correctAnswers;
  int get totalInteractionCount => _totalItemCount;

  /// The stages of the current lesson (empty before [loadLesson] completes).
  List<Stage> get _stages => _cachedStages;

  /// Current stage, or `null` if out of range.
  Stage? get currentStage {
    if (_lesson == null) return null;
    if (_currentStageIndex < 0 || _currentStageIndex >= _stages.length) {
      return null;
    }
    return _stages[_currentStageIndex];
  }

  /// The current [Interaction] if there is one at the current index.
  Interaction? get currentInteraction {
    final stage = currentStage;
    if (stage == null) return null;
    if (_currentInteractionIndex < 0 ||
        _currentInteractionIndex >= stage.items.length) {
      return null;
    }
    return stage.items[_currentInteractionIndex];
  }

  /// The ID for the current interaction item. Composed from the parent
  /// stage's id and the interaction's own [id] field; items without an
  /// explicit id get a `legacy-$index` key so the synthetic id remains
  /// stable across reorderings of the parent stage.
  String get currentInteractionId {
    final stageId = currentStage?.id ?? 'unknown';
    final itemId = currentInteraction?.id ?? '';
    return interactionItemId(stageId, itemId, _currentInteractionIndex);
  }

  /// The [InteractionState] for the current item.
  InteractionState get currentInteractionState =>
      _interactionStates[currentInteractionId] ?? InteractionState.idle;

  /// Name of the current stage (e.g. "Vocabulary", "Practice").
  String? get currentStageName => currentStage?.name;

  /// 0.0 → 1.0 progress through the entire lesson.
  double get progress {
    if (_lesson == null) return 0.0;
    final total = _totalItemCount;
    if (total == 0) return 0.0;
    return _completedItemCount / total;
  }

  /// Progress within the current stage.
  double get currentStageProgress {
    final current = _stageItemCount;
    if (current == 0) return 0.0;
    return _currentInteractionIndex / current;
  }

  bool get isLastInteraction {
    if (_lesson == null) return true;
    if (_currentStageIndex < _stageCount - 1) return false;
    return _currentInteractionIndex >= _stageItemCount - 1;
  }

  bool get isLastStageItem =>
      _currentInteractionIndex >= _stageItemCount - 1;

  bool get hasSubmitted => currentInteractionState.submitted;
  bool get isAnswerCorrect => currentInteractionState.correct == true;

  // --- Methods ---

  /// Load a lesson by ID and reset all progress state.
  ///
  /// Prefers [CourseProvider] when the section body is already in memory;
  /// otherwise falls back to [SwahiliCourse.loadLessonById] so deep links /
  /// tests work without pre-loading the whole section tree.
  ///
  /// Returns `true` if the lesson was found and loaded.
  Future<bool> loadLesson(String lessonId) async {
    Lesson? lesson = _courseProvider.findLessonById(lessonId);
    if (lesson == null) {
      try {
        lesson = await SwahiliCourse.loadLessonById(lessonId);
      } catch (e) {
        debugPrint('loadLesson($lessonId) failed: $e');
        lesson = null;
      }
    }
    if (lesson == null) {
      _lesson = null;
      _cachedStages = const [];
      notifyListeners();
      return false;
    }

    _lesson = lesson;
    _cachedStages = lesson.flattenedStages;
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _totalMistakes = 0;
    _isComplete = false;
    _lessonStartTime = DateTime.now();
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _interactionStates.clear();
    _masteryAttempts = 0;
    _masteryPassed = !lesson.isMastery; // default true for non-mastery lessons

    // Register SRS words referenced by ShowWord interactions.
    _registerSrsWords();
    // Register grammar points this lesson teaches.
    _registerGrammarPoints();

    notifyListeners();
    return true;
  }

  /// Submit the current interaction with a correctness verdict.
  void submitInteraction(bool correct, {String? userAnswerText}) {
    if (_lesson == null) return;

    if (!correct) {
      _totalMistakes++;
      _incorrectAnswers++;
      _audioController.playRandomErrorSound();
      _recordMistake(userAnswerText);
    } else {
      _correctAnswers++;
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

      // Check if all stages are done.
      if (_currentStageIndex >= _stageCount) {
        // Mastery lesson: require 80% accuracy
        if (_lesson!.isMastery) {
          final accuracy = _totalItemCount == 0
              ? 0.0
              : _correctAnswers / _totalItemCount;
          if (accuracy >= 0.8) {
            _masteryPassed = true;
            _isComplete = true;
            _onLessonCompleted();
          } else {
            _masteryPassed = false;
            // Don't mark complete; UI will show "Try Again" dialog
          }
          notifyListeners();
          return;
        }

        _isComplete = true;
        _onLessonCompleted();
        notifyListeners();
        return;
      }
    }

    notifyListeners();
  }

  /// Retry a mastery lesson after failing.
  void retryMastery() {
    if (_lesson == null || !_lesson!.isMastery) return;
    _masteryAttempts++;
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _totalMistakes = 0;
    _isComplete = false;
    _masteryPassed = false;
    _lessonStartTime = DateTime.now();
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _interactionStates.clear();
    notifyListeners();
  }

  /// Reset to beginning of lesson (for retry).
  void reset() {
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _totalMistakes = 0;
    _isComplete = false;
    _lessonStartTime = DateTime.now();
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _interactionStates.clear();
    notifyListeners();
  }

  // --- Private helpers ---

  int get _stageCount => _stages.length;

  int get _stageItemCount {
    if (_currentStageIndex < 0 || _currentStageIndex >= _stages.length) {
      return 0;
    }
    return _stages[_currentStageIndex].items.length;
  }

  int get _totalItemCount =>
      _stages.fold<int>(0, (sum, stage) => sum + stage.items.length);

  /// Count of items already submitted (completed).
  int get _completedItemCount =>
      _interactionStates.values.where((s) => s.submitted).length;

  /// Register all ShowWord interactions and register their wordIds in SRS.
  void _registerSrsWords() {
    if (_lesson == null) return;
    final wordIds = <String>{};
    final expressionIds = <String>{};
    for (final stage in _stages) {
      for (final item in stage.items) {
        if (item is ShowWord) {
          if (item.wordId.isNotEmpty) wordIds.add(item.wordId);
          if (item.expressionId != null && item.expressionId!.isNotEmpty) {
            expressionIds.add(item.expressionId!);
          }
        }
      }
    }
    if (wordIds.isNotEmpty) {
      _srsProvider.registerAll(wordIds);
      _srsProvider.recordLessonLinks(
        wordIds: wordIds,
        lessonId: _lesson!.id,
        lessonName: _lesson!.name,
        type: LinkType.word,
      );
    }
    if (expressionIds.isNotEmpty) {
      _srsProvider.registerAllExpressions(expressionIds);
      _srsProvider.recordLessonLinks(
        wordIds: expressionIds,
        lessonId: _lesson!.id,
        lessonName: _lesson!.name,
        type: LinkType.expression,
      );
    }
  }

  /// Register grammar points this lesson teaches into the grammar-review SRS
  /// queue (keyed by grammarPointId).
  void _registerGrammarPoints() {
    if (_lesson == null) return;
    final ids = _lesson!.content.linkedGrammarPointIds;
    if (ids.isEmpty) return;
    _grammarReviewProvider.registerAll(ids);
    _grammarReviewProvider.recordLessonLinks(
      ids: ids,
      lessonId: _lesson!.id,
      lessonName: _lesson!.name,
    );
  }

  /// Record a wrong answer in the mistake log.
  void _recordMistake(String? userAnswerText) {
    final lesson = _lesson;
    final stage = currentStage;
    final interaction = currentInteraction;
    if (lesson == null || stage == null || interaction == null) return;

    final correctAnswer = interactionCorrectAnswerLabel(interaction);

    String? wordId;
    if (interaction is ShowWord) wordId = interaction.wordId;

    // Prefer an explicit link on the interaction; fall back to a single
    // lesson-level linked grammar point when unambiguous.
    String? grammarPointId = interactionGrammarPointId(interaction);
    if (grammarPointId == null || grammarPointId.isEmpty) {
      final linked = lesson.content.linkedGrammarPointIds;
      if (linked.length == 1) grammarPointId = linked.first;
    }

    final entry = MistakeEntry(
      id: '${lesson.id}#${stage.id}#${interaction.id}#${DateTime.now().millisecondsSinceEpoch}',
      lessonId: lesson.id,
      stageId: stage.id,
      interactionId: interaction.id,
      wordId: wordId,
      grammarPointId: grammarPointId,
      interactionSnapshot: interaction,
      userAnswer: userAnswerText ?? '',
      correctAnswer: correctAnswer ?? '',
      timestamp: DateTime.now(),
    );

    _mistakeProvider.record(entry);

    if (grammarPointId != null && grammarPointId.isNotEmpty) {
      _grammarReviewProvider.markDueNow(grammarPointId);
    }
  }

  // --- Completion hooks (ported from old LessonProvider) ---

  Future<void> _onLessonCompleted() async {
    final wasPerfect = _totalMistakes == 0;

    await Future.wait([
      _gameProvider.awardXP(XPEvent.lessonComplete).catchError((e) {
        debugPrint('Error awarding lesson-complete XP: $e');
        return Future<int>.value(0);
      }),
      _gemsProvider.earnGems(GemEvent.lessonComplete).catchError((e) {
        debugPrint('Error earning lesson-complete gems: $e');
        return null;
      }),
    ]);

    if (wasPerfect) {
      await Future.wait([
        _gameProvider.awardXP(XPEvent.perfectLesson).catchError((e) {
          debugPrint('Error awarding perfect-lesson XP: $e');
          return Future<int>.value(0);
        }),
        _gemsProvider.earnGems(GemEvent.perfectLesson).catchError((e) {
          debugPrint('Error earning perfect-lesson gems: $e');
          return null;
        }),
      ]);
    }

    try {
      await _gameProvider.recordLessonCompletion(
        lessonId: _lesson!.id,
        wasPerfect: wasPerfect,
      );
    } catch (e) {
      debugPrint('Error recording lesson completion: $e');
    }

    try {
      final userData = await _gameProvider.getUserGameStateOnce();
      final lessonsCompleted =
          (userData['lessonsCompleted'] as num? ?? 0).toInt();
      final perfectLessons =
          (userData['perfectLessons'] as num? ?? 0).toInt();
      await _achievementsProvider.checkLessonMilestones(
        lessonsCompleted: lessonsCompleted,
        perfectLessons: perfectLessons,
      );
    } catch (e) {
      debugPrint('Error checking lesson milestones: $e');
    }

    // Record study activity for statistics dashboard
    try {
      final duration = _lessonStartTime != null
          ? DateTime.now().difference(_lessonStartTime!).inSeconds
          : 0;
      final xpEarned = wasPerfect
          ? XPEvent.lessonComplete.base + XPEvent.perfectLesson.base
          : XPEvent.lessonComplete.base;
      await _studyStatsProvider.recordActivity(
        type: StudyActivityType.lessonComplete,
        lessonId: _lesson?.id,
        xpEarned: xpEarned,
        durationSeconds: duration,
        correctCount: _correctAnswers,
        incorrectCount: _incorrectAnswers,
      );
    } catch (e) {
      debugPrint('Error recording study stats: $e');
    }
  }
}