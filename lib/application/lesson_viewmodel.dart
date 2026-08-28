// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Dart imports:
import 'dart:async';

// Project imports:
import 'package:turna/application/study_session/anki_study_session_host.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_lesson_redo_flush.dart';
import 'package:turna/application/anki_official/engine/official_anki_lesson_unlock_quota.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/application/study_session/study_product_analytics.dart';
import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_completion_coordinator.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/mistake_review_assembler.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

/// Derive the SRS wordId from an Anki card interaction id.
///
/// Id conventions (retired Legacy assembler-era scheme, kept stable):
/// - Course lessons: `<wordId>-c<ord>` where wordId is
///   `anki-<importId>-c<cardId>`
/// - Review sessions: `anki-review-<wordId>`
///
/// Returns the wordId (`anki-<importId>-c<cardId>`) in both cases; ids that
/// match neither convention are returned unchanged.
String ankiWordIdFromInteractionId(String interactionId) {
  final id = interactionId.replaceFirst('anki-review-', '');
  final cIdx = id.lastIndexOf('-c');
  if (cIdx > 0 && int.tryParse(id.substring(cIdx + 2)) != null) {
    return id.substring(0, cIdx);
  }
  return id;
}

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

/// Snapshot of one submitted question for the lesson-completion summary.
class QuestionResult {
  final String prompt;
  final bool correct;
  final String? userAnswer;
  final String? correctAnswer;

  const QuestionResult({
    required this.prompt,
    required this.correct,
    this.userAnswer,
    this.correctAnswer,
  });
}

class _SubmittedInteraction {
  final int stageIndex;
  final int interactionIndex;
  final String itemId;
  final bool correct;

  const _SubmittedInteraction({
    required this.stageIndex,
    required this.interactionIndex,
    required this.itemId,
    required this.correct,
  });
}

/// SRS rollback entry captured before [LessonViewModel._applySrsOutcome]
/// fires a grade. [LessonViewModel.undoLastInteraction] walks the stack in
/// LIFO order so the most recent grade is rolled back first; entries for
/// expression / grammar-point grades are tracked alongside word entries so
/// a single undo restores all three when the lesson's interaction touched
/// more than one queue.
class _SrsUndoEntry {
  final String wordId;
  final SrsWord? previous;
  final bool isExpression;
  final bool isGrammarPoint;

  const _SrsUndoEntry({
    required this.wordId,
    required this.previous,
    this.isExpression = false,
    this.isGrammarPoint = false,
  });
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
  final AudioController _audioController;
  final SrsProvider _srsProvider;
  final MistakeProvider _mistakeProvider;
  final GrammarReviewProvider _grammarReviewProvider;
  final LessonCompletionCoordinator _completionCoordinator;

  LessonViewModel(
    this._courseProvider,
    this._audioController,
    this._srsProvider,
    this._mistakeProvider,
    this._grammarReviewProvider,
    this._completionCoordinator,
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

  /// Total interaction count across all stages, cached at lesson load. A
  /// lesson pass never changes its stage/item structure, so recomputing the
  /// fold on every [progress] / [currentQuestionNumber] read is wasteful —
  /// especially as several widgets read these getters per VM notify.
  int _cachedTotalItemCount = 0;

  /// Idempotency guard for [_onLessonCompleted]. `advance()` calls it
  /// fire-and-forget (the Future keeps running after the widget unmounts —
  /// Flutter doesn't tear down pending Futures on dispose — so the XP/gems/
  /// progress/study-stats side effects are not lost on fast back-out). This
  /// guard prevents a double completion if `advance()` is invoked twice or a
  /// mastery retry re-passes after a prior completion already started.
  bool _completionStarted = false;

  // Mastery-specific state
  int _masteryAttempts = 0;
  bool _masteryPassed = false;

  /// When false, wrong answers are NOT recorded to [MistakeProvider]. Used by
  /// synthetic review sessions (e.g. mistake review) whose own completion
  /// prunes the log — recording fresh entries there would create a feedback
  /// loop. Set by [loadLessonInstance] and reset to `true` by [loadLesson].
  bool _recordsMistakes = true;

  /// Per-item submission state, keyed by [interactionItemId] — uses the
  /// item's stable `id` field when present, falling back to `legacy-$idx`.
  final Map<String, InteractionState> _interactionStates = {};

  /// Cached [QuestionResult]s in submission order. Appended once per
  /// [submitInteraction] (an item is submitted at most once per lesson pass —
  /// re-submits only happen via [retryMastery]/[reset], which clear this list)
  /// so the completion-summary dialog doesn't re-walk every stage/item and
  /// re-allocate the whole list on every build.
  final List<QuestionResult> _questionResults = [];
  final List<_SubmittedInteraction> _submittedInteractions = [];

  /// Per-queue captured `previous` snapshots for [undoLastInteraction].
  /// Populated in [_applySrsOutcome] before the grade fires; one entry per
  /// queue (word / expression / grammar-point) that the interaction touched,
  /// so a single undo restores all three when the same item id referred to
  /// multiple queues. Drained in [retryMastery] / [_resetToLesson].
  final List<_SrsUndoEntry> _srsUndoStack = [];

  // --- Getters ---

  Lesson? get lesson => _lesson;
  LessonType get lessonType => _lesson?.type ?? LessonType.normal;
  bool get isComplete => _isComplete;

  /// Set after a redo flush that did not write every not-yet-rated card.
  /// The completion dialog shows [AppStrings.lessonAnkiRedoFlushFailed].
  bool get officialRedoFlushFailed => _officialRedoFlushFailed;
  bool _officialRedoFlushFailed = false;

  bool get isMastery => _lesson?.isMastery ?? false;
  bool get masteryPassed => _masteryPassed;
  int get masteryAttempts => _masteryAttempts;

  /// True only when the user has finished every interaction of a mastery
  /// lesson but failed to reach the 80% pass threshold. Distinguishes the
  /// "walked off the end" state from the freshly-loaded "not started" state
  /// (both have [_masteryPassed] == false) by requiring that there is no
  /// current interaction left to render.
  bool get masteryFailed =>
      _lesson != null &&
      _lesson!.isMastery &&
      !_isComplete &&
      !_masteryPassed &&
      currentInteraction == null;

  int get correctAnswers => _correctAnswers;
  int get incorrectAnswers => _incorrectAnswers;
  int get totalInteractionCount => _totalItemCount;

  /// Seconds elapsed since the lesson started. Returns 0 when no lesson is
  /// loaded or the clock has not been set.
  int get durationSeconds {
    final start = _lessonStartTime;
    if (start == null) return 0;
    return DateTime.now().difference(start).inSeconds;
  }

  /// A per-question snapshot of the user's performance, in submission order.
  /// Backed by the incrementally-maintained [_questionResults] cache so the
  /// completion dialog's build path is O(1) instead of re-walking every
  /// stage/item. Also serves as the single source of truth for the submitted-
  /// item count ([progress] reads [_questionResults.length]), so there is no
  /// separate completed-count counter to keep in lockstep across resets.
  List<QuestionResult> get questionResults =>
      List.unmodifiable(_questionResults);

  /// 1-based index of the question the user is currently answering, clamped
  /// to [totalInteractionCount] when the lesson is complete. Returns 0 when
  /// there is no lesson.
  int get currentQuestionNumber {
    if (_lesson == null || _totalItemCount == 0) return 0;
    if (_isComplete) return _totalItemCount;
    final flat = _flatItemIndex();
    return flat < _totalItemCount ? flat + 1 : _totalItemCount;
  }

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
    return _questionResults.length / total;
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

  bool get isLastStageItem => _currentInteractionIndex >= _stageItemCount - 1;

  bool get hasSubmitted => currentInteractionState.submitted;
  bool get isAnswerCorrect => currentInteractionState.correct == true;

  // --- Methods ---

  /// Load a lesson by ID and reset all progress state.
  ///
  /// Uses [CourseProvider] only when the cached [Lesson] already has body
  /// content (tests / preloaded full lessons). The course tree holds L1
  /// metadata with empty [Lesson.content], so those fall through to
  /// [CourseLoader.loadLessonById] (L2).
  ///
  /// Returns `true` if the lesson was found and loaded.
  Future<bool> loadLesson(String lessonId) async {
    Lesson? lesson = _courseProvider.findLessonById(lessonId);
    if (lesson != null && !_lessonHasBody(lesson)) {
      lesson = null;
    }
    if (lesson == null) {
      try {
        lesson = await CourseLoader.loadLessonById(lessonId);
      } catch (e) {
        debugPrint('loadLesson($lessonId) failed: $e');
        lesson = null;
      }
    }
    if (lesson == null) {
      _lesson = null;
      _cachedStages = const [];
      _cachedTotalItemCount = 0;
      _questionResults.clear();
      notifyListeners();
      return false;
    }

    final fresh = lesson;
    _lesson = fresh;
    _recordsMistakes = true; // real lessons always record wrong answers
    _resetToLesson(fresh);

    notifyListeners();
    return true;
  }

  /// True when [lesson] carries playable content (not L1 tree metadata).
  static bool _lessonHasBody(Lesson lesson) {
    final c = lesson.content;
    return c.stages.isNotEmpty ||
        c.subLessons.isNotEmpty ||
        c.listeningPhases.isNotEmpty ||
        c.readingPassage != null ||
        c.passage.isNotEmpty;
  }

  /// Load an in-memory [Lesson] directly, bypassing the by-id lookup. Used
  /// for synthesized lessons that are not registered in the course tree
  /// (e.g. the Daily Challenge deck assembled at runtime). Resets all
  /// progress state exactly like [loadLesson].
  ///
  /// Pass [recordMistakes] `false` for synthetic review sessions that manage
  /// their own mistake-log pruning (e.g. mistake review) so wrong answers do
  /// not create new entries — avoiding a feedback loop. The flag is reset to
  /// `true` on the next load.
  void loadLessonInstance(Lesson lesson, {bool recordMistakes = true}) {
    _lesson = lesson;
    _recordsMistakes = recordMistakes;
    _resetToLesson(lesson);
    notifyListeners();
  }

  /// Apply [lesson] as the current lesson and reset all progression state.
  /// Shared by [loadLesson] and [loadLessonInstance] so the two entry points
  /// can never drift apart.
  void _resetToLesson(Lesson lesson) {
    _cachedStages = lesson.flattenedStages;
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _totalMistakes = 0;
    _isComplete = false;
    _completionStarted = false;
    _officialRedoFlushFailed = false;
    _lessonStartTime = DateTime.now();
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _interactionStates.clear();
    _questionResults.clear();
    _submittedInteractions.clear();
    _srsUndoStack.clear();
    _masteryAttempts = 0;
    _masteryPassed = !lesson.isMastery; // default true for non-mastery lessons
    _cachedTotalItemCount = _cachedStages.fold<int>(
      0,
      (sum, stage) => sum + stage.items.length,
    );

    // Register SRS words referenced by ShowWord interactions.
    _registerSrsWords();
    // Register grammar points this lesson teaches.
    _registerGrammarPoints();
  }

  /// Submit the current interaction with a correctness verdict.
  ///
  /// [recordMistake] overrides the lesson-level `recordMistakes` flag for
  /// this one submission — sessions that load with `recordMistakes: false`
  /// (e.g. Anki review) can still opt objectively-graded items into the
  /// mistake log while keeping self-graded flip cards out of it.
  /// [mistakeWordId] attaches a word id to the mistake entry when the
  /// interaction itself does not carry one (Anki cards are not ShowWords).
  void submitInteraction(
    bool correct, {
    String? userAnswerText,
    int? reviewQuality,
    bool? recordMistake,
    String? mistakeWordId,
  }) {
    if (_lesson == null) return;
    final interaction = currentInteraction;
    if (interaction != null &&
        _isAnkiOwnedInteraction(interaction, mistakeWordId)) {
      unawaited(
        _submitAnkiOwned(
          correct: correct,
          userAnswerText: userAnswerText,
          recordMistake: recordMistake,
          mistakeWordId: mistakeWordId,
        ),
      );
      return;
    }

    _submitStandardInteraction(
      correct,
      userAnswerText: userAnswerText,
      reviewQuality: reviewQuality,
      recordMistake: recordMistake,
      mistakeWordId: mistakeWordId,
    );
  }

  void _submitStandardInteraction(
    bool correct, {
    String? userAnswerText,
    int? reviewQuality,
    bool? recordMistake,
    String? mistakeWordId,
  }) {
    final interaction = currentInteraction;
    if (!correct) {
      _totalMistakes++;
      _incorrectAnswers++;
      _audioController.playRandomErrorSound();
      if (recordMistake ?? _recordsMistakes) {
        _recordMistake(userAnswerText, wordId: mistakeWordId);
      }
    } else {
      _correctAnswers++;
      _audioController.playRandomLevelUpSound();
    }

    // Count this item as completed exactly once per pass — guard against a
    // double-submit of the same item inflating the progress counter (which is
    // [_questionResults.length]). retry/reset clear the list, so re-submits
    // after a reset start from zero again.
    final wasAlreadySubmitted =
        _interactionStates[currentInteractionId]?.submitted ?? false;

    _interactionStates[currentInteractionId] = InteractionState(
      submitted: true,
      correct: correct,
      userAnswerText: userAnswerText,
    );

    // Incrementally cache the completion-summary snapshot so the dialog's
    // build path is O(1), and so [progress] (which reads
    // [_questionResults].length) advances by exactly one per submitted item.
    // Guarded by wasAlreadySubmitted so a double-submit of one item doesn't
    // append a duplicate row — the completion summary and the mistake-review
    // zip (which pairs results with entryIds by index) rely on one row per
    // item. retry/reset clear _questionResults, so re-submits after a reset
    // start fresh.
    if (interaction != null && !wasAlreadySubmitted) {
      _questionResults.add(
        QuestionResult(
          prompt: interactionPromptLabel(interaction),
          correct: correct,
          userAnswer: userAnswerText,
          correctAnswer: interactionCorrectAnswerLabel(interaction),
        ),
      );
      // Binary SRS signal: 做对/做错 → pass/fail (same pipeline as flashcards).
      _applySrsOutcome(
        correct: correct,
        reviewQuality: reviewQuality,
        wordId: mistakeWordId,
        interaction: interaction,
      );
      _submittedInteractions.add(_SubmittedInteraction(
        stageIndex: _currentStageIndex,
        interactionIndex: _currentInteractionIndex,
        itemId: currentInteractionId,
        correct: correct,
      ));
    }

    notifyListeners();
  }

  /// Feed lesson exercise grades into FSRS as binary pass/fail (ADR 0028).
  /// Only runs when a concrete word/expression id is known; skips intro-only
  /// ShowWord sentinel ids and unregistered phantoms.
  void _applySrsOutcome({
    required bool correct,
    int? reviewQuality,
    String? wordId,
    required Interaction interaction,
  }) {
    final outcome = ReviewOutcome.fromCorrect(correct);

    String? effectiveWordId = wordId;
    String? expressionId;
    String? grammarPointId;
    if (interaction is ShowWord) {
      if (effectiveWordId == null || effectiveWordId.isEmpty) {
        effectiveWordId = interaction.wordId;
      }
      expressionId = interaction.expressionId;
    } else if (interaction is AnkiCard || interaction is AnkiHtmlCard) {
      // Flip cards studied through the standard lesson path: the assembler
      // ids the interaction '<wordId>-c<ord>' (review sessions re-id them
      // 'anki-review-<wordId>'), so the SRS wordId is recoverable from the
      // interaction id. Without this branch a course-path flip card would
      // never reach the FSRS queue.
      if (effectiveWordId == null || effectiveWordId.isEmpty) {
        effectiveWordId = ankiWordIdFromInteractionId(interaction.id);
      }
    }

    // Capture pre-grade `previous` snapshots so [undoLastInteraction] can
    // roll back the SRS state when the user taps Undo. Captured AFTER
    // registerWord so a never-before-seen word's `previous` reflects the
    // fresh state that registerWord just inserted (the rollback then
    // restores that same fresh state — restoring the new-card "never
    // seen" condition the user expected before this lesson attempt).
    if (effectiveWordId != null &&
        effectiveWordId.isNotEmpty &&
        !effectiveWordId.startsWith(unknownInteractionWordIdPrefix) &&
        !effectiveWordId.startsWith('mistake-review-') &&
        !_isAnkiOwnedInteraction(interaction, effectiveWordId)) {
      _srsProvider.registerWord(effectiveWordId);
      _srsUndoStack.add(_SrsUndoEntry(
        wordId: effectiveWordId,
        previous: _srsProvider.state[effectiveWordId],
      ));
      unawaited(
        reviewQuality == null
            ? _srsProvider.reviewWordOutcome(effectiveWordId, outcome)
            : _srsProvider.reviewWord(effectiveWordId, reviewQuality),
      );
    }

    if (expressionId != null &&
        expressionId.isNotEmpty &&
        !_isAnkiOwnedId(expressionId)) {
      _srsProvider.registerExpression(expressionId);
      _srsUndoStack.add(_SrsUndoEntry(
        wordId: expressionId,
        previous: _srsProvider.state[expressionId],
        isExpression: true,
      ));
      unawaited(_srsProvider.reviewExpressionOutcome(expressionId, outcome));
    }

    // Grammar points use the same binary pass/fail FSRS path.
    grammarPointId = interactionGrammarPointId(interaction);
    if (grammarPointId != null && grammarPointId.isNotEmpty) {
      _grammarReviewProvider.registerGrammarPoint(grammarPointId);
      _srsUndoStack.add(_SrsUndoEntry(
        wordId: grammarPointId,
        previous: _grammarReviewProvider.state[grammarPointId],
        isGrammarPoint: true,
      ));
      unawaited(
          _grammarReviewProvider.reviewWithOutcome(grammarPointId, outcome));
    }
  }

  CanonicalCardKey? _canonicalKeyForAnkiInteraction(Interaction interaction) {
    const profileId = 'profile-default-01';
    final rawId = ankiWordIdFromInteractionId(interaction.id);
    final lessonId = _lesson?.id ?? '';
    return CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: profileId,
          rawId: rawId,
        ) ??
        CardIntroductionEligibility.keyFromLessonAndWordId(
          lessonId: lessonId,
          wordId: rawId,
        ) ??
        CardIntroductionEligibility.keyFromLessonAndWordId(
          lessonId: lessonId,
          wordId: interaction.id,
        ) ??
        _keyFromLooseAnkiId(rawId) ??
        _keyFromLooseAnkiId(interaction.id);
  }

  CanonicalCardKey? _keyFromLooseAnkiId(String id) {
    final cardId = CardIntroductionEligibility.cardIdFromWordId(id);
    if (cardId == null) return null;
    final official = RegExp(r'^official-anki-(.+)-c\d+').firstMatch(id);
    if (official != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: 'profile-default-01',
        sourceId: official.group(1)!,
        cardId: cardId,
      );
    }
    final legacy = RegExp(r'^anki-(.+)-c\d+').firstMatch(id);
    if (legacy != null) {
      return CanonicalCardKey(
        backend: AnkiBackendKind.legacyTurna,
        profileId: 'profile-default-01',
        sourceId: legacy.group(1)!,
        cardId: cardId,
      );
    }
    return null;
  }

  bool _isAnkiOwnedId(String id) {
    return CanonicalCardKeyAdapter.tryParseStoredWordId(
          profileId: 'profile-default-01',
          rawId: id,
        ) !=
        null;
  }

  bool _isAnkiOwnedInteraction(Interaction interaction, String? wordId) {
    if (_lesson?.id == MistakeReviewAssembler.lessonId ||
        _lesson?.id == WeakWordQuizAssembler.lessonId) {
      return false;
    }
    if (_canonicalKeyForAnkiInteraction(interaction) != null) return true;
    if (wordId != null && _isAnkiOwnedId(wordId)) return true;
    return false;
  }

  AnkiStudySessionHost? _ankiHost;

  AnkiStudySessionHost _ankiSessionHost() {
    final override = AnkiStudySessionHost.debugOverride;
    if (override != null) return override;
    // Doc 35 L2: course-lesson Anki items are practice-only (no ledger
    // write), so the resolver carries no Turna leg anymore.
    return _ankiHost ??= AnkiStudySessionHost(
      resolver: const StudyLedgerResolver(),
    );
  }

  Future<void> _submitAnkiOwned({
    required bool correct,
    String? userAnswerText,
    bool? recordMistake,
    String? mistakeWordId,
  }) async {
    final interaction = currentInteraction;
    if (interaction == null) return;
    final key = _canonicalKeyForAnkiInteraction(interaction);
    // Official course cards are practice + explicit introduction — never
    // attempt Official ledger learn then fall back on recoverableError.
    if (key?.backend == AnkiBackendKind.official) {
      final controller = await _commitAnkiCourse(interaction, correct, key!);
      _applyAnkiCourseSubmit(
        interaction: interaction,
        correct: correct,
        userAnswerText: userAnswerText,
        recordMistake: recordMistake,
        mistakeWordId: mistakeWordId,
        receipt: controller?.lastReceipt,
      );
      return;
    }

    final controller = await _commitAnkiCourse(interaction, correct, key);
    if (controller == null ||
        controller.phase == StudyCardPhase.recoverableError ||
        controller.lastReceipt == null) {
      _submitStandardInteraction(
        correct,
        userAnswerText: userAnswerText,
        recordMistake: recordMistake,
        mistakeWordId: mistakeWordId,
      );
      return;
    }
    _applyAnkiCourseSubmit(
      interaction: interaction,
      correct: correct,
      userAnswerText: userAnswerText,
      recordMistake: recordMistake,
      mistakeWordId: mistakeWordId,
      receipt: controller.lastReceipt,
    );
  }

  void _applyAnkiCourseSubmit({
    required Interaction interaction,
    required bool correct,
    String? userAnswerText,
    bool? recordMistake,
    String? mistakeWordId,
    StudyEventReceipt? receipt,
  }) {
    if (receipt != null) {
      StudyProductAnalytics.instance.record(receipt);
    }

    if (!correct) {
      _totalMistakes++;
      _incorrectAnswers++;
      _audioController.playRandomErrorSound();
      // ADR 0037: imported Anki cards never write the language mistake book.
    } else {
      _correctAnswers++;
      _audioController.playRandomLevelUpSound();
    }
    final wasAlreadySubmitted =
        _interactionStates[currentInteractionId]?.submitted ?? false;
    _interactionStates[currentInteractionId] = InteractionState(
      submitted: true,
      correct: correct,
      userAnswerText: userAnswerText,
    );
    if (!wasAlreadySubmitted) {
      _questionResults.add(
        QuestionResult(
          prompt: interactionPromptLabel(interaction),
          correct: correct,
          userAnswer: userAnswerText,
          correctAnswer: interactionCorrectAnswerLabel(interaction),
        ),
      );
      _submittedInteractions.add(_SubmittedInteraction(
        stageIndex: _currentStageIndex,
        interactionIndex: _currentInteractionIndex,
        itemId: currentInteractionId,
        correct: correct,
      ));
    }
    notifyListeners();
  }

  Future<StudySessionController?> _commitAnkiCourse(
    Interaction interaction,
    bool correct,
    CanonicalCardKey? key,
  ) async {
    final resolved = key ?? _canonicalKeyForAnkiInteraction(interaction);
    if (resolved == null) return null;
    final front = interaction is AnkiCard ? interaction.front : '';
    final back = interaction is AnkiCard ? interaction.back : '';
    final item = AnkiStudySessionHost.itemForCourse(
      key: resolved,
      presentation: FlipCardPresentation(
        cardKey: resolved,
        frontText: front,
        backText: back,
        sourceFingerprint: 'lesson',
      ),
      courseId: _lesson?.id ?? '',
      placementId: _lesson?.id ?? '',
    );
    try {
      return await _ankiSessionHost().driveFlip(
        item: item,
        outcome: correct ? RecallOutcome.remembered : RecallOutcome.forgotten,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isAnkiLessonRedo(String lessonId) {
    if (!getIt.isRegistered<GameProvider>()) return false;
    return getIt<GameProvider>().isLessonCompleted(lessonId);
  }

  List<OfficialAheadAnswer> _officialRatingsForCompletedPass() {
    final lesson = _lesson;
    if (lesson == null) return const [];
    final anyWrong = <int, bool>{};
    for (final submitted in _submittedInteractions) {
      if (submitted.stageIndex < 0 ||
          submitted.stageIndex >= _stages.length) {
        continue;
      }
      final items = _stages[submitted.stageIndex].items;
      if (submitted.interactionIndex < 0 ||
          submitted.interactionIndex >= items.length) {
        continue;
      }
      final key = _canonicalKeyForAnkiInteraction(
        items[submitted.interactionIndex],
      );
      if (key == null) continue;
      anyWrong[key.cardId] =
          (anyWrong[key.cardId] ?? false) || !submitted.correct;
    }
    return [
      for (final entry in anyWrong.entries)
        OfficialAheadAnswer(
          cardId: entry.key,
          rating: entry.value ? 'again' : 'good',
        ),
    ];
  }

  /// ADR 0037: unlock every Official card in this Lesson after the lesson
  /// completes. Mid-lesson exit leaves cards unintroduced.
  Future<void> _unlockAnkiCardsOnComplete() async {
    final lesson = _lesson;
    if (lesson == null) return;
    if (lesson.id == MistakeReviewAssembler.lessonId ||
        lesson.id == WeakWordQuizAssembler.lessonId) {
      return;
    }
    final store = CardIntroductionStore.resolve();
    final unlocked = <int>{};
    for (final stage in _stages) {
      for (final item in stage.items) {
        final candidates = <String>[
          if (item is ShowWord && item.wordId.isNotEmpty) item.wordId,
          ankiWordIdFromInteractionId(item.id),
          item.id,
        ];
        for (final candidate in candidates) {
          final key = CardIntroductionEligibility.keyFromLessonAndWordId(
            lessonId: lesson.id,
            wordId: candidate,
          );
          if (key == null || !unlocked.add(key.cardId)) continue;
          await store.markFromLesson(
            wordId: candidate,
            lessonId: lesson.id,
          );
          break;
        }
      }
    }
  }

  /// Advance to the next interaction (or stage). Called after the user
  /// acknowledges the current result (tap "Continue" / "Got It").
  void advance() {
    if (_lesson == null || _isComplete) return;
    final interaction = currentInteraction;
    if (interaction != null &&
        _isAnkiOwnedInteraction(interaction, null) &&
        !(_interactionStates[currentInteractionId]?.submitted ?? false)) {
      return;
    }

    _currentInteractionIndex++;

    // Check if we've exhausted the current stage.
    if (_currentInteractionIndex >= _stageItemCount) {
      _currentInteractionIndex = 0;
      _currentStageIndex++;

      // Check if all stages are done.
      if (_currentStageIndex >= _stageCount) {
        // Mastery lesson: require 80% accuracy
        if (_lesson!.isMastery) {
          final accuracy =
              _totalItemCount == 0 ? 0.0 : _correctAnswers / _totalItemCount;
          if (accuracy >= 0.8) {
            _masteryPassed = true;
            unawaited(_onLessonCompleted());
          } else {
            _masteryPassed = false;
            // Don't mark complete; UI will show "Try Again" dialog
            notifyListeners();
          }
          return;
        }

        unawaited(_onLessonCompleted());
        return;
      }
    }

    notifyListeners();
  }

  /// Rewind the most recently submitted interaction. The SRS layer owns the
  /// durable state rollback; this method restores the visible card and lesson
  /// counters to the same point, then awaits the SRS rollback for every
  /// queue (word / expression / grammar-point) the interaction touched.
  ///
  /// Returns a [Future] that completes with `true` when the UI counters and
  /// the SRS state are both restored; `false` when the SRS rollback gate is
  /// still held by an in-flight grade (the caller should leave the undo
  /// entry in place and re-tap once the gate releases — see
  /// [SrsQueueProvider.undoReview]).
  Future<bool> undoLastInteraction() async {
    if (_submittedInteractions.isEmpty) return false;
    final last = _submittedInteractions.removeLast();
    _currentStageIndex = last.stageIndex;
    _currentInteractionIndex = last.interactionIndex;
    _interactionStates.remove(last.itemId);
    if (last.correct) {
      if (_correctAnswers > 0) _correctAnswers--;
    } else {
      if (_incorrectAnswers > 0) _incorrectAnswers--;
      if (_totalMistakes > 0) _totalMistakes--;
    }
    if (_questionResults.isNotEmpty) _questionResults.removeLast();
    _isComplete = false;
    _completionStarted = false;
    _officialRedoFlushFailed = false;
    notifyListeners();

    // Walk the SRS undo stack: drain every entry added by the interaction
    // we just rewound (one word + zero or one expression + zero or one
    // grammar point). Roll them all back in LIFO order.
    while (_srsUndoStack.isNotEmpty) {
      final entry = _srsUndoStack.removeLast();
      final ok = entry.isGrammarPoint
          ? await _grammarReviewProvider.rollbackGrammarPoint(
              entry.wordId,
              entry.previous,
            )
          : entry.isExpression
              ? await _srsProvider.rollbackExpression(
                  entry.wordId,
                  entry.previous,
                )
              : await _srsProvider.rollbackWord(entry.wordId, entry.previous);
      if (!ok) {
        // Gate held by an in-flight grade — push the entry back so the
        // user's next undo attempt can retry it. Returning false tells
        // the UI to leave the snackbar visible / re-enable the button.
        _srsUndoStack.add(entry);
        return false;
      }
    }
    return true;
  }

  /// Retry a mastery lesson after failing.
  void retryMastery() {
    if (_lesson == null || !_lesson!.isMastery) return;
    _masteryAttempts++;
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _totalMistakes = 0;
    _isComplete = false;
    _completionStarted = false;
    _officialRedoFlushFailed = false;
    _masteryPassed = false;
    _lessonStartTime = DateTime.now();
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _interactionStates.clear();
    _questionResults.clear();
    _submittedInteractions.clear();
    _srsUndoStack.clear();
    notifyListeners();
  }

  /// Reset to beginning of lesson (for retry).
  void reset() {
    _currentStageIndex = 0;
    _currentInteractionIndex = 0;
    _totalMistakes = 0;
    _isComplete = false;
    _completionStarted = false;
    _officialRedoFlushFailed = false;
    _lessonStartTime = DateTime.now();
    _correctAnswers = 0;
    _incorrectAnswers = 0;
    _interactionStates.clear();
    _questionResults.clear();
    _submittedInteractions.clear();
    _srsUndoStack.clear();
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

  int get _totalItemCount => _cachedTotalItemCount;

  /// Flat (across all stages) 0-based index of the current item.
  int _flatItemIndex() {
    var index = 0;
    for (var s = 0; s < _currentStageIndex && s < _stages.length; s++) {
      index += _stages[s].items.length;
    }
    return index + _currentInteractionIndex;
  }

  /// Register all ShowWord interactions and register their wordIds in SRS.
  void _registerSrsWords() {
    if (_lesson == null) return;
    final wordIds = <String>{};
    final expressionIds = <String>{};
    for (final stage in _stages) {
      for (final item in stage.items) {
        if (item is ShowWord) {
          // Skip the synthetic fallback ShowWord that Interaction.fromJson
          // emits for an unknown/corrupted runtimeType — its wordId is a
          // diagnostic sentinel (unknownInteractionWordIdPrefix + rt), not a
          // real vocab id. Registering it would pollute the SRS queue with a
          // phantom, unanswerable card and record a bogus lesson link.
          if (item.wordId.isNotEmpty &&
              !item.wordId.startsWith(unknownInteractionWordIdPrefix) &&
              !_isAnkiOwnedId(item.wordId)) {
            wordIds.add(item.wordId);
          }
          if (item.expressionId != null &&
              item.expressionId!.isNotEmpty &&
              !_isAnkiOwnedId(item.expressionId!)) {
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
  ///
  /// [wordId] overrides the id derived from the interaction — Anki review
  /// sessions pass the card's SRS word id so weak-word aggregation can see
  /// the mistake (their interactions are not ShowWords).
  void _recordMistake(String? userAnswerText, {String? wordId}) {
    final lesson = _lesson;
    final stage = currentStage;
    final interaction = currentInteraction;
    if (lesson == null || stage == null || interaction == null) return;

    final correctAnswer = interactionCorrectAnswerLabel(interaction);

    var effectiveWordId = wordId;
    if (interaction is ShowWord) effectiveWordId ??= interaction.wordId;

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
      wordId: effectiveWordId,
      grammarPointId: grammarPointId,
      interactionSnapshot: interaction,
      userAnswer: userAnswerText ?? '',
      correctAnswer: correctAnswer ?? '',
      timestamp: DateTime.now(),
    );

    _mistakeProvider.record(entry);

    // Grammar due-now on mistake is handled in [_applySrsOutcome] when the
    // interaction carries a grammar link; keep markDue for ambiguous
    // lesson-level single grammar fallback above.
    if (grammarPointId != null &&
        grammarPointId.isNotEmpty &&
        interactionGrammarPointId(interaction) == null) {
      unawaited(_grammarReviewProvider.markDueNow(grammarPointId));
    }
  }

  /// Word / expression ids taught by the current lesson, for the study log
  /// and the unique-words achievement projection. Applies the same filters
  /// as [_registerSrsWords]: skip unknown-interaction sentinels and Anki-owned
  /// ids.
  List<String> lessonWordIds() {
    if (_lesson == null) return const [];
    final ids = <String>{};
    for (final stage in _stages) {
      for (final item in stage.items) {
        if (item is ShowWord) {
          if (item.wordId.isNotEmpty &&
              !item.wordId.startsWith(unknownInteractionWordIdPrefix) &&
              !_isAnkiOwnedId(item.wordId)) {
            ids.add(item.wordId);
          }
          final expressionId = item.expressionId;
          if (expressionId != null &&
              expressionId.isNotEmpty &&
              !_isAnkiOwnedId(expressionId)) {
            ids.add(expressionId);
          }
        }
      }
    }
    return ids.toList(growable: false);
  }

  Future<void> _onLessonCompleted() async {
    if (_completionStarted) return;
    _completionStarted = true;
    final lesson = _lesson;
    if (lesson == null) return;
    try {
      final isRedo = _isAnkiLessonRedo(lesson.id);
      await _unlockAnkiCardsOnComplete();
      if (isRedo) {
        final result = await OfficialAnkiLessonRedoFlush.resolve()
            .flush(_officialRatingsForCompletedPass());
        _officialRedoFlushFailed = result.userShouldBeNotified;
      } else {
        await OfficialAnkiLessonUnlockQuota.resolve()
            .ensureForCardIds(_ankiCardIdsInLesson());
      }
    } catch (e, st) {
      debugPrint('Official Anki lesson complete side-effect failed: $e\n$st');
    }
    _isComplete = true;
    notifyListeners();
    try {
      await _completionCoordinator.complete(
        lessonId: lesson.id,
        wasPerfect: _totalMistakes == 0,
        correctAnswers: _correctAnswers,
        incorrectAnswers: _incorrectAnswers,
        lessonStartTime: _lessonStartTime,
        wordIds: lessonWordIds(),
      );
    } catch (e, st) {
      // Fire-and-forget: an unhandled exception here would surface as a
      // framework error after the widget unmounts. Log and swallow so a
      // side-effect failure (XP/gems/stats) doesn't crash the app. The
      // side effects in [LessonCompletionCoordinator] are already
      // individually guarded, this is the outer backstop.
      debugPrint('LessonCompletionCoordinator failed: $e\n$st');
    }
  }

  Iterable<int> _ankiCardIdsInLesson() sync* {
    for (final stage in _stages) {
      for (final item in stage.items) {
        final key = _canonicalKeyForAnkiInteraction(item);
        if (key != null) yield key.cardId;
      }
    }
  }
}
