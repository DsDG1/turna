// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_recent_task_log.dart';
import 'package:turna/application/ai/ai_streaming_session_base.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

/// State machine for the in-lesson AI hint conversation.
enum AiHintState { idle, loading, ready, error }

/// A snapshot of the question the user wants explained, handed to the
/// provider when the AI button is tapped. Fields are pre-extracted by the
/// caller (using the `interactionXxxLabel` helpers) so this class stays free
/// of the Interaction model.
class AiQuestionContext {
  const AiQuestionContext({
    required this.language,
    required this.typeLabel,
    required this.promptLabel,
    this.optionsLabel,
    this.correctLabel,
    this.userAnswer,
  });

  /// Target language being taught (e.g. "Turkish").
  final String language;

  /// Human-readable question type (e.g. "Multiple Choice").
  final String typeLabel;

  /// The prompt / question text shown to the learner.
  final String promptLabel;

  /// Selectable options joined for display, or `null` when the question has
  /// no options.
  final String? optionsLabel;

  /// Canonical correct-answer label. NOT sent to the model by default - kept
  /// here only so callers can decide per-type whether to reveal it.
  final String? correctLabel;

  /// What the learner answered, if they have already submitted.
  final String? userAnswer;

  bool get hasSubmittedAnswer =>
      userAnswer != null && userAnswer!.trim().isNotEmpty;
}

/// Provider backing the in-lesson AI hint assistant (the right-corner AI
/// button -> explanation sheet -> follow-up chat page).
///
/// Holds a single question's context plus the conversation history built on
/// top of it. Streams via [AiEngine.chat] `onChunk`; cancel keeps partial
/// text and generation tokens block superseded chunks.
class AiHintProvider extends AiStreamingSessionBase {
  AiHintProvider({
    AiEngine? engine,
    AiExplainPrefsStore? prefs,
  })  : _engine = engine ?? getIt<AiEngine>(),
        _prefs = AiExplainPrefsStore.resolve(
          prefs: prefs,
          allowEphemeral: true,
        );

  AiHintProvider.withEngine(
    this._engine, {
    AiExplainPrefsStore? prefs,
  }) : _prefs = AiExplainPrefsStore.resolve(
          prefs: prefs,
          allowEphemeral: true,
        );

  final AiEngine _engine;
  final AiExplainPrefsStore _prefs;

  final List<AiChatMessage> _messages = <AiChatMessage>[];
  List<AiChatMessage> get messages => List.unmodifiable(_messages);

  AiHintState _state = AiHintState.idle;
  AiHintState get state => _state;

  String? _error;
  String? get error => _error;

  /// The question this conversation is about. `null` until
  /// [explainQuestion] is called; cleared by [reset].
  AiQuestionContext? _context;
  AiQuestionContext? get context => _context;

  /// Optional learner snapshot injected into system prompts when prefs allow.
  LearnerAiContext? _learnerContext;
  LearnerAiContext? get learnerContext => _learnerContext;

  int _streamingAssistantIndex = -1;
  AiChatMessage? _activeFollowupUser;

  @override
  void applyStreamingBatch(String batch) {
    final index = _streamingAssistantIndex;
    if (index < 0 || index >= _messages.length) return;
    final current = _messages[index];
    if (current.role != 'assistant') return;
    _messages[index] = AiChatMessage(
      role: 'assistant',
      content: current.content + batch,
    );
  }

  /// Latest assistant explanation/reply, for the sheet to render without
  /// scanning the message list.
  String? get latestReply {
    for (final m in _messages.reversed) {
      if (m.role == 'assistant' && m.content.isNotEmpty) return m.content;
    }
    return null;
  }

  /// Inject (or clear) learner context for subsequent system prompts.
  void setLearnerContext(LearnerAiContext? ctx) {
    _learnerContext = ctx;
  }

  /// Cancel any in-flight generation, clear history/context/state, and return
  /// to idle.
  void reset() {
    if (isSessionDisposed) return;
    abandonStreamingSession();
    _messages.clear();
    _state = AiHintState.idle;
    _error = null;
    _context = null;
    notifySessionListeners();
  }

  /// Cancel the in-flight generation (if any) and return to idle, keeping the
  /// conversation history **including partial streamed assistant text**.
  void cancel() {
    if (isSessionDisposed || _state != AiHintState.loading) return;
    cancelStreamingSession();
    _state = AiHintState.idle;
    notifySessionListeners();
  }

  /// Ask the AI to explain the current question. Streams assistant text via
  /// `onChunk`; seeds the conversation with a user turn + empty assistant.
  Future<void> explainQuestion({
    required AiEngineConfig config,
    required AiQuestionContext ctx,
  }) async {
    // No acquire-gate here: supersede / new-question must always start.
    // Debounce double-taps via cancel of the previous in-flight token.
    if (isSessionDisposed) return;
    final session = beginStreamingSession();
    _error = null;
    _context = ctx;
    _state = AiHintState.loading;
    _messages.clear();
    final userText = _buildExplainPrompt(ctx);
    _messages.add(AiChatMessage(role: 'user', content: userText));
    _messages.add(const AiChatMessage(role: 'assistant', content: ''));
    final assistantIndex = _messages.length - 1;
    _streamingAssistantIndex = assistantIndex;
    notifySessionListeners();
    try {
      final apiMessages = <Map<String, dynamic>>[
        {'role': 'system', 'content': buildSystemPrompt(ctx)},
        _messages[0].toApiDict(),
      ];
      final result = await _engine.chat(
        config: config,
        messages: apiMessages,
        cancelToken: session.cancelToken,
        onChunk: (delta) => addStreamingDelta(session, delta),
      );
      flushStreamingSession(session);
      if (!isCurrentSession(session)) return;
      if (_messages[assistantIndex].content.isEmpty &&
          result.content.isNotEmpty) {
        _messages[assistantIndex] =
            AiChatMessage(role: 'assistant', content: result.content);
      }
      _state = AiHintState.ready;
      _recordRecent(ctx.language);
    } on AiCancelled {
      if (!isCurrentSession(session)) return;
      flushStreamingSession(session);
      // Keep partial assistant text.
      _state = AiHintState.idle;
    } catch (e) {
      if (!isCurrentSession(session)) return;
      logger.w('AiHintProvider.explainQuestion failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiHintState.error;
      if (assistantIndex < _messages.length &&
          _messages[assistantIndex].content.isEmpty) {
        _messages.removeAt(assistantIndex);
      }
    } finally {
      finishStreamingSession(session);
    }
    if (!isSessionDisposed) notifySessionListeners();
  }

  /// Append a follow-up question and stream the assistant's reply. Returns
  /// `true` when the turn was actually started.
  Future<bool> ask({
    required AiEngineConfig config,
    required String text,
  }) async {
    if (text.trim().isEmpty || _context == null) return false;
    if (isSessionDisposed) return false;
    // Remove the prior in-flight follow-up before capturing indices for the
    // replacement. Its cancelled Future may settle later, but can then no
    // longer shift the new turn's slots.
    final supersededUser = _activeFollowupUser;
    if (supersededUser != null) {
      _removeOrphanTurn(supersededUser);
    }
    final session = beginStreamingSession();
    _error = null;
    _state = AiHintState.loading;
    final userMessage = AiChatMessage(role: 'user', content: text);
    _activeFollowupUser = userMessage;
    _messages.add(userMessage);
    _messages.add(const AiChatMessage(role: 'assistant', content: ''));
    final assistantIndex = _messages.length - 1;
    _streamingAssistantIndex = assistantIndex;
    notifySessionListeners();
    try {
      final apiMessages = <Map<String, dynamic>>[
        {'role': 'system', 'content': buildSystemPrompt(_context!)},
        for (var i = 0; i < _messages.length; i++)
          if (i != assistantIndex) _messages[i].toApiDict(),
      ];
      final result = await _engine.chat(
        config: config,
        messages: apiMessages,
        cancelToken: session.cancelToken,
        onChunk: (delta) => addStreamingDelta(session, delta),
      );
      flushStreamingSession(session);
      if (!isCurrentSession(session)) {
        _removeOrphanTurn(userMessage);
        return true;
      }
      if (assistantIndex < _messages.length &&
          _messages[assistantIndex].content.isEmpty &&
          result.content.isNotEmpty) {
        _messages[assistantIndex] =
            AiChatMessage(role: 'assistant', content: result.content);
      }
      _state = AiHintState.ready;
      _recordRecent(_context!.language);
    } on AiCancelled {
      if (!isCurrentSession(session)) {
        _removeOrphanTurn(userMessage);
        return true;
      }
      flushStreamingSession(session);
      // Keep partial text on user cancel.
      _state = AiHintState.idle;
    } catch (e) {
      if (!isCurrentSession(session)) {
        _removeOrphanTurn(userMessage);
        return true;
      }
      logger.w('AiHintProvider.ask failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiHintState.error;
      if (assistantIndex < _messages.length &&
          _messages[assistantIndex].role == 'assistant' &&
          _messages[assistantIndex].content.isEmpty) {
        _messages.removeAt(assistantIndex);
      }
    } finally {
      finishStreamingSession(session);
      if (identical(_activeFollowupUser, userMessage)) {
        _activeFollowupUser = null;
      }
    }
    if (!isSessionDisposed) notifySessionListeners();
    return true;
  }

  /// Drop a superseded turn's user + assistant only when those slots still
  /// belong to that turn (avoids clobbering a newer ask's messages).
  void _removeOrphanTurn(AiChatMessage userMessage) {
    final userIndex = _messages.indexWhere((m) => identical(m, userMessage));
    if (userIndex < 0) return;
    final assistantIndex = userIndex + 1;
    if (assistantIndex < _messages.length &&
        _messages[assistantIndex].role == 'assistant') {
      // Drop empty or partial assistant from the superseded stream.
      _messages.removeAt(assistantIndex);
    }
    if (userIndex < _messages.length &&
        identical(_messages[userIndex], userMessage)) {
      _messages.removeAt(userIndex);
    }
    if (identical(_activeFollowupUser, userMessage)) {
      _activeFollowupUser = null;
    }
  }

  /// Persona + rules for the hint assistant. Public for snapshot tests.
  @visibleForTesting
  String buildSystemPrompt(AiQuestionContext ctx) {
    final prefs = _prefs.snapshot;
    final hasAnswer = ctx.hasSubmittedAnswer;
    final reveal = prefs.allowRevealAnswer || hasAnswer;

    final buf = StringBuffer()
      ..writeln('You are a language-learning tutor. The learner is practicing '
          '${ctx.language}.')
      ..writeln(prefs.toSystemPromptRules())
      ..writeln('Requirements:')
      ..writeln(
          '- First state what this question is testing (grammar point, word '
          'meaning, sentence pattern, etc.).')
      ..writeln('- Then give the solving approach or related knowledge points, '
          'concisely as bullet points.');
    if (reveal) {
      buf.writeln(
          '- The learner has submitted or allow-reveal is on; you may compare '
          'their answer and clarify the correct form when helpful.');
    } else {
      buf.writeln(
          '- Do not directly restate the correct answer; guide the learner to '
          'reach it themselves.');
    }
    buf
      ..writeln(
          '- If the learner asks a follow-up, you may give more specific hints '
          'step by step, but keep it primarily heuristic.')
      ..writeln(buildQuestionTypeStrategy(ctx.typeLabel));

    if (prefs.injectLearnerContext &&
        _learnerContext != null &&
        !_learnerContext!.isEmpty) {
      buf.writeln(_learnerContext!.toPromptBlock());
    }
    return buf.toString();
  }

  /// The first user turn: describe the question for the model.
  String _buildExplainPrompt(AiQuestionContext ctx) {
    final buf = StringBuffer()
      ..writeln(
          'Please explain the following ${ctx.language} practice question '
          '(question type: ${ctx.typeLabel}):')
      ..writeln('Question: ${ctx.promptLabel}');
    if (ctx.optionsLabel != null && ctx.optionsLabel!.isNotEmpty) {
      buf.writeln('Options: ${ctx.optionsLabel}');
    }
    if (ctx.userAnswer != null && ctx.userAnswer!.isNotEmpty) {
      buf.writeln('My answer: ${ctx.userAnswer}');
    }
    if (!ctx.hasSubmittedAnswer && !_prefs.snapshot.allowRevealAnswer) {
      buf.writeln(
          'Explain according to your rules; do not give the answer directly.');
    } else {
      buf.writeln('Explain according to your rules.');
    }
    return buf.toString();
  }

  // ─── Depth-learning tutor genres ─────────────────────────────────────

  /// Shared hop for the genres: one `chat()` call whose reply is a JSON
  /// object, decoded and parsed into [T] by [parse].
  Future<T> _typedChat<T>({
    required AiEngineConfig config,
    required String systemPrompt,
    required String userPrompt,
    required T Function(Map<String, dynamic>) parse,
    AiCancelToken? cancelToken,
    double temperature = 0.4,
  }) async {
    final result = await _engine.chat(
      config: config,
      messages: <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: temperature,
      cancelToken: cancelToken,
    );
    return parse(decodeJsonObject(result.content));
  }

  /// Explain a grammar point illustrated by [sentence].
  Future<GrammarExplanation> explainGrammarPoint({
    required AiEngineConfig config,
    required String language,
    required String sentence,
    required String grammarPoint,
    AiCancelToken? cancelToken,
  }) {
    return _typedChat<GrammarExplanation>(
      config: config,
      cancelToken: cancelToken,
      systemPrompt: 'You are a language-learning tutor. The learner is '
          'practicing $language. Explain grammar points in plain Chinese. '
          'Respond with ONLY a JSON object (no markdown fences): '
          '{"explanation": string, "relatedExamples": [string], '
          '"contrastWith": [string]}.',
      userPrompt: 'Grammar point: $grammarPoint\n'
          'Sentence illustrating it: $sentence\n'
          'Explain the point. relatedExamples: 2-3 example sentences in '
          '$language. contrastWith: other points it is often confused with '
          '(may be empty).',
      parse: GrammarExplanation.fromJson,
    );
  }

  /// Compare near-synonymous [words].
  Future<SynonymComparison> compareSynonyms({
    required AiEngineConfig config,
    required String language,
    required List<String> words,
    AiCancelToken? cancelToken,
  }) {
    final wordList = words.map((w) => '- $w').join('\n');
    return _typedChat<SynonymComparison>(
      config: config,
      cancelToken: cancelToken,
      systemPrompt: 'You are a language-learning tutor. The learner is '
          'practicing $language. Compare near-synonymous words in plain '
          'Chinese. Respond with ONLY a JSON object (no markdown fences): '
          '{"pairs": [{"a": string, "b": string, "nuance": string, '
          '"whenToUseA": string, "whenToUseB": string, "examples": [string]}]}.',
      userPrompt: 'Compare these $language words and explain the nuances:\n'
          '$wordList\n'
          'Produce one pair entry per meaningful contrast; examples should be '
          'short sentences in $language.',
      parse: SynonymComparison.fromJson,
    );
  }

  /// Decompose [sentence] token-by-token.
  Future<SentenceBreakdown> decomposeSentence({
    required AiEngineConfig config,
    required String language,
    required String sentence,
    AiCancelToken? cancelToken,
  }) {
    return _typedChat<SentenceBreakdown>(
      config: config,
      cancelToken: cancelToken,
      systemPrompt: 'You are a language-learning tutor. The learner is '
          'practicing $language. Decompose sentences token by token. Respond '
          'with ONLY a JSON object (no markdown fences): {"tokens": [{"surface": '
          'string, "lemma": string|null, "gloss": string, "role": string}], '
          '"structure": string}. Glosses and roles in Chinese.',
      userPrompt: 'Decompose this $language sentence:\n$sentence\n'
          'One token per entry; "structure" is a one-line Chinese summary of '
          'the sentence pattern.',
      parse: SentenceBreakdown.fromJson,
    );
  }

  /// Explain why [userAnswer] was wrong.
  Future<WhyWrongExplanation> explainWhyWrong({
    required AiEngineConfig config,
    required String language,
    required String userAnswer,
    required String correctAnswer,
    required String questionContext,
    AiCancelToken? cancelToken,
  }) {
    return _typedChat<WhyWrongExplanation>(
      config: config,
      cancelToken: cancelToken,
      systemPrompt: 'You are a language-learning tutor. The learner is '
          'practicing $language. Help the learner understand a mistake. '
          'Respond with ONLY a JSON object (no markdown fences): {"whyWrong": '
          'string, "whatYouProbablyThought": string, "howToRemember": string}. '
          'All fields in Chinese.',
      userPrompt: 'Question: $questionContext\n'
          'My answer: $userAnswer\n'
          'Correct answer: $correctAnswer\n'
          'Explain why my answer is wrong, what I probably confused it with, '
          'and a mnemonic to remember the correct answer.',
      parse: WhyWrongExplanation.fromJson,
    );
  }

  void _recordRecent(String language) {
    final context = _context;
    if (context == null) return;
    recordAiRecentTask(
      kind: AiTaskKind.hintChat,
      summary: '${context.typeLabel} · $language',
      route: AiRecentTaskRoute.hintChat,
    );
  }
}
