// Dart imports:

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/engine/ai_cancel_token.dart';
import 'package:varnamala/application/ai/engine/ai_engine.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/data/srs_state_dao.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/domain/study/daily_stats.dart';

/// Plan-driven generator that synthesizes a personalized remediation
/// section (ADR 0026 / floofy-hugging-hopper Phase 2.2).
///
/// The provider gathers three slices of recent learner state (mistakes, weak
/// words, recent SRS reviews), asks the AI engine to emit a single section
/// JSON targeting the highest-frequency gaps, then persists it via the
/// existing [AiCourseProvider.saveSectionJson] pipeline. The caller can push
/// the resulting [lessonId] into [NewLessonRoute] for the learner to play.
///
/// State machine: [SrsTutorState]. Every transition calls
/// [notifyListeners]. Cancel returns to [SrsTutorState.idle]; other failures
/// land in [SrsTutorState.error] with [errorMessage] populated.
enum SrsTutorState { idle, gathering, planning, ready, saving, saved, error }

/// Source hint for which context buckets the planner should emphasize.
enum SrsTutorFocus { mistakes, weakWords }

@lazySingleton
class SrsTutorProvider extends ChangeNotifier {
  SrsTutorProvider({
    AiEngine? engine,
    AiCourseProvider? courseProvider,
    MistakeProvider? mistakeProvider,
    SrsStateDao? srsDao,
  })  : _engine = engine ?? getIt<AiEngine>(),
        _courseProvider = courseProvider ?? getIt<AiCourseProvider>(),
        _mistakes = mistakeProvider ?? getIt<MistakeProvider>(),
        _srsDao = srsDao ?? getIt<SrsStateDao>();

  final AiEngine _engine;
  final AiCourseProvider _courseProvider;
  final MistakeProvider _mistakes;
  final SrsStateDao _srsDao;
  // Pure-helper shim used for parseCompletion (no network, no DI needed).
  static final AiCourseService _parseHelper = AiCourseService();

  /// In-memory cancel token for the current generation, if any. Used by the
  /// UI's "cancel" affordance to abort a long-running plan call.
  AiCancelToken? _cancelToken;

  SrsTutorState _state = SrsTutorState.idle;
  String? _errorMessage;
  String? _generatedSectionId;
  String? _generatedSectionName;
  Map<String, dynamic>? _lastPlan;

  SrsTutorState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get generatedSectionId => _generatedSectionId;
  String? get generatedSectionName => _generatedSectionName;
  Map<String, dynamic>? get lastPlan => _lastPlan;

  bool get isBusy =>
      _state == SrsTutorState.gathering ||
      _state == SrsTutorState.planning ||
      _state == SrsTutorState.saving;

  /// Cancel any in-flight generation. Returns to [SrsTutorState.idle] on the
  /// next notify cycle (the engine raises [AiCancelled]).
  void cancel() {
    final token = _cancelToken;
    if (token == null) return;
    token.cancel();
  }

  /// Reset the provider to idle and clear any cached plan. Used by callers
  /// when the user dismisses the preview card without acting on it.
  void reset() {
    _state = SrsTutorState.idle;
    _errorMessage = null;
    _generatedSectionId = null;
    _generatedSectionName = null;
    _lastPlan = null;
    _cancelToken = null;
    notifyListeners();
  }

  /// Build a personalized lesson focused on the chosen [focus].
  ///
  /// [language] is the learner's target language label (e.g. "Turkish") used
  /// to scope the system prompt. [sectionName] (optional) seeds the title of
  /// the generated section. The provider does not touch any state outside
  /// its own fields and the lesson DB write happens via
  /// [AiCourseProvider.saveSectionJson].
  Future<String?> tutorPlan({
    required AiEngineConfig config,
    required String language,
    SrsTutorFocus focus = SrsTutorFocus.mistakes,
    String? sectionName,
    int mistakeLimit = 20,
    int weakLimit = 20,
    int srsLimit = 20,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (config.apiKey.trim().isEmpty) {
      _errorMessage = 'AI engine config missing API key.';
      _state = SrsTutorState.error;
      notifyListeners();
      return null;
    }

    // Cancel any previous generation before starting a new one.
    _cancelToken?.cancel();
    final token = AiCancelToken();
    _cancelToken = token;
    _errorMessage = null;
    _generatedSectionId = null;
    _generatedSectionName = null;
    _lastPlan = null;
    _state = SrsTutorState.gathering;
    notifyListeners();

    final List<MistakeEntry> mistakes;
    final List<WeakWord> weakWords;
    final List<SrsWord> recentReviews;
    try {
      mistakes = _mistakes.recentMistakes(max: mistakeLimit);
      weakWords = WeakWordQuizAssembler.aggregateWeakWords(
        _mistakes.entries,
        limit: weakLimit,
      );
      recentReviews = await _srsDao.recentReviews(limit: srsLimit);
    } on AiCancelled {
      _state = SrsTutorState.idle;
      _cancelToken = null;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to gather learner context: $e';
      _state = SrsTutorState.error;
      _cancelToken = null;
      notifyListeners();
      return null;
    }

    if (token.isCanceled) {
      _state = SrsTutorState.idle;
      _cancelToken = null;
      notifyListeners();
      return null;
    }

    _state = SrsTutorState.planning;
    notifyListeners();

    final userPrompt = _buildUserPrompt(
      language: language,
      focus: focus,
      sectionName: sectionName,
      mistakes: mistakes,
      weakWords: weakWords,
      recentReviews: recentReviews,
    );

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(language)},
      {'role': 'user', 'content': userPrompt},
    ];

    AiGeneratedCourse parsed;
    try {
      final result = await _engine.requestJson(
        config: config,
        messages: messages,
        temperature: 0.4,
        timeout: timeout,
        cancelToken: token,
      );
      parsed = _service.parseCompletion(result.body);
    } on AiCancelled {
      _state = SrsTutorState.idle;
      _cancelToken = null;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'AI planning failed: $e';
      _state = SrsTutorState.error;
      _cancelToken = null;
      notifyListeners();
      return null;
    }

    _lastPlan = parsed.parsed;
    _generatedSectionId = parsed.parsed['id'] as String?;
    _generatedSectionName =
        (parsed.parsed['name'] as String?) ?? sectionName ?? 'Personalized Review';
    _state = SrsTutorState.ready;
    notifyListeners();

    _state = SrsTutorState.saving;
    notifyListeners();
    try {
      await _courseProvider.saveSectionJson(parsed.parsed);
      // The AI assigns the section id; if it forgot, synthesize a stable id
      // derived from the current timestamp so the lesson player can still
      // navigate to it.
      _generatedSectionId ??=
          'tutor-${DateTime.now().millisecondsSinceEpoch}';
      _state = SrsTutorState.saved;
      _recordRecent(focus);
    } on AiCancelled {
      _state = SrsTutorState.idle;
      _cancelToken = null;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Failed to save section: $e';
      _state = SrsTutorState.error;
      _cancelToken = null;
      notifyListeners();
      return null;
    }

    if (identical(_cancelToken, token)) _cancelToken = null;
    notifyListeners();
    return _generatedSectionId;
  }

  /// The parseCompletion shim - one source of truth for the section schema
  /// normalization (strip fences, normalizeResources, autoFixResources,
  /// checkResourceSelfConsistency). The shared static [_parseHelper] avoids a
  /// DI registration for this pure helper class.
  AiCourseService get _service => _parseHelper;

  /// Append a tutor-generated task to the AI Hub's recent list.
  void _recordRecent(SrsTutorFocus focus) {
    try {
      final kind = switch (focus) {
        SrsTutorFocus.mistakes => AiTaskKind.tutorMistakes,
        SrsTutorFocus.weakWords => AiTaskKind.tutorWeakWords,
      };
      getIt<AiRecentTasksProvider>().record(
            AiRecentTask(
              kind: kind,
              summary: _generatedSectionName ?? 'Tutor',
              timestamp: DateTime.now(),
            ),
          );
    } catch (_) {
      // Advisory only.
    }
  }

  String _systemPrompt(String language) {
    return 'You are a language-course authoring assistant for $language. '
        'Generate ONE personalized remediation section whose primary goal is '
        'to drill the learner on the words, expressions, and grammar points '
        'they keep missing. '
        'Output ONLY valid JSON matching the Varnamala section schema '
        '(see AiCourseService). No prose, no markdown fences. The section '
        'must be self-contained: include its own words/expressions/grammar '
        'points and at least 4 practice interactions (mix of multipleChoice, '
        'translate, fillBlank where the prompt supports it). Cap the section '
        'at 8 interactions total to keep it short. Use the CEFR level of '
        'the user\'s most recent mistakes as the difficulty target.';
  }

  String _buildUserPrompt({
    required String language,
    required SrsTutorFocus focus,
    required String? sectionName,
    required List<MistakeEntry> mistakes,
    required List<WeakWord> weakWords,
    required List<SrsWord> recentReviews,
  }) {
    final focusLine = switch (focus) {
      SrsTutorFocus.mistakes =>
        'Focus on the recent mistakes below; weak words and SRS reviews '
            'provide additional context.',
      SrsTutorFocus.weakWords =>
        'Focus on the weak-word list below; recent mistakes and SRS reviews '
            'provide additional context.',
    };

    final buf = StringBuffer()
      ..writeln('Language: $language')
      ..writeln('Section name: ${sectionName ?? "Personalized Review"}')
      ..writeln('Focus: $focusLine')
      ..writeln()
      ..writeln('## Recent mistakes (newest last; up to ${mistakes.length})');
    if (mistakes.isEmpty) {
      buf.writeln('- (none recorded)');
    } else {
      for (final m in mistakes) {
        final id = m.wordId ?? m.expressionId ?? m.grammarPointId ?? m.id;
        buf.writeln(
            '- [$id] lesson=${m.lessonId} stage=${m.stageId} '
            'user="${m.userAnswer}" correct="${m.correctAnswer}" '
            'at=${m.timestamp.toIso8601String()}');
      }
    }

    buf
      ..writeln()
      ..writeln('## Weak words (${weakWords.length})');
    if (weakWords.isEmpty) {
      buf.writeln('- (none)');
    } else {
      for (final w in weakWords) {
        buf.writeln(
            '- [${w.wordId}] "${w.displayText}" -> "${w.translation ?? ""}" '
            '(${w.mistakeCount}x)');
      }
    }

    buf
      ..writeln()
      ..writeln('## Recent SRS reviews (newest first; ${recentReviews.length})');
    if (recentReviews.isEmpty) {
      buf.writeln('- (none)');
    } else {
      for (final r in recentReviews.take(10)) {
        final when = r.lastReviewedAt?.toIso8601String() ?? 'never';
        buf.writeln(
            '- [${r.wordId}] type=${r.type.name} reps=${r.reps} '
            'ease=${r.ease.toStringAsFixed(2)} lapses=${r.lapses} '
            'leech=${r.isLeech} lastReviewed=$when');
      }
    }

    buf
      ..writeln()
      ..writeln('Generate the section JSON now.');
    return buf.toString();
  }
}