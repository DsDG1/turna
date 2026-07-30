// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/hint_genres.dart';
import 'package:varnamala/application/ai/engine/ai_cancel_token.dart';
import 'package:varnamala/application/ai/engine/ai_engine.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/di/injection.dart';

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
}

/// Provider backing the in-lesson AI hint assistant (the right-corner AI
/// button -> explanation sheet -> follow-up chat page).
///
/// Holds a single question's context plus the conversation history built on
/// top of it. The [AiEngineConfig] is sourced from [AiEngineConfigHolder]; all
/// LLM traffic routes through the shared [AiEngine] (the single choke point),
/// so hint replies are cacheable and an in-flight generation can be cancelled
/// mid-flight via [cancel].
class AiHintProvider extends ChangeNotifier {
  AiHintProvider({AiEngine? engine}) : _engine = engine ?? getIt<AiEngine>();
  AiHintProvider.withEngine(this._engine);

  final AiEngine _engine;

  /// Active cancel token for the in-flight generation, if any. Cancelled on
  /// [reset] / [cancel] / when a newer request supersedes it.
  AiCancelToken? _cancelToken;

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

  /// Monotonic token bumped on every [explainQuestion] / [reset]. Each
  /// request captures the token at start and refuses to mutate state if the
  /// token changed while it was awaiting the network - so a stale in-flight
  /// reply from a previous question can't be appended into the current
  /// conversation.
  int _generation = 0;

  /// Latest assistant explanation/reply, for the sheet to render without
  /// scanning the message list.
  String? get latestReply {
    for (final m in _messages.reversed) {
      if (m.role == 'assistant') return m.content;
    }
    return null;
  }

  /// Cancel any in-flight generation, clear history/context/state, and return
  /// to idle.
  void reset() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _generation++;
    _messages.clear();
    _state = AiHintState.idle;
    _error = null;
    _context = null;
    notifyListeners();
  }

  /// Cancel the in-flight generation (if any) and return to idle, keeping the
  /// conversation history. A no-op when nothing is loading.
  void cancel() {
    if (_state != AiHintState.loading) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiHintState.idle;
    notifyListeners();
  }

  /// Ask the AI to explain the current question. Builds the system prompt
  /// from [ctx], seeds the conversation with a "explain this" user turn, and
  /// appends the assistant's reply.
  Future<void> explainQuestion({
    required AiEngineConfig config,
    required AiQuestionContext ctx,
  }) async {
    _cancelToken?.cancel();
    _generation++;
    final gen = _generation;
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _context = ctx;
    _state = AiHintState.loading;
    _messages.clear();
    notifyListeners();
    try {
      final userText = _buildExplainPrompt(ctx);
      _messages.add(AiChatMessage(role: 'user', content: userText));
      notifyListeners();
      final result = await _engine.chat(
        config: config,
        messages: <Map<String, dynamic>>[
          {'role': 'system', 'content': _buildSystemPrompt(ctx)},
          ..._messages.map((m) => m.toApiDict()),
        ],
        cancelToken: token,
      );
      if (gen != _generation) return; // superseded by a newer request/reset
      _messages.add(AiChatMessage(role: 'assistant', content: result.content));
      _state = AiHintState.ready;
      _recordRecent(ctx.language);
    } on AiCancelled {
      if (gen != _generation) return; // superseded - expected
      _state = AiHintState.idle; // user-cancelled
    } catch (e) {
      if (gen != _generation) return; // superseded - drop the stale error
      logger.w('AiHintProvider.explainQuestion failed: $e');
      _error = e.toString();
      _state = AiHintState.error;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    if (gen == _generation) notifyListeners();
  }

  /// Append a follow-up question and the assistant's reply. Returns `true`
  /// when the turn was actually started (context present, text non-empty),
  /// `false` when it was a no-op - callers can use the return value to avoid
  /// clearing the input field on a no-op so the user's text isn't lost.
  Future<bool> ask({
    required AiEngineConfig config,
    required String text,
  }) async {
    if (text.trim().isEmpty || _context == null) return false;
    _cancelToken?.cancel();
    _generation++;
    final gen = _generation;
    final token = AiCancelToken();
    _cancelToken = token;
    final userIndex = _messages.length; // for orphan cleanup if superseded
    _error = null;
    _state = AiHintState.loading;
    _messages.add(AiChatMessage(role: 'user', content: text));
    notifyListeners();
    try {
      final result = await _engine.chat(
        config: config,
        messages: <Map<String, dynamic>>[
          {'role': 'system', 'content': _buildSystemPrompt(_context!)},
          ..._messages.map((m) => m.toApiDict()),
        ],
        cancelToken: token,
      );
      if (gen != _generation) {
        // Superseded - remove this turn's orphan user message so the stale
        // question doesn't linger in the transcript or the newer request's
        // history. Only do this if it's still ours at that index (a newer
        // ask that already cleaned up would have shifted indices).
        if (userIndex < _messages.length) {
          _messages.removeAt(userIndex);
        }
        return true;
      }
      _messages.add(AiChatMessage(role: 'assistant', content: result.content));
      _state = AiHintState.ready;
      _recordRecent(_context!.language);
    } on AiCancelled {
      if (gen != _generation) {
        if (userIndex < _messages.length) {
          _messages.removeAt(userIndex);
        }
        return true; // superseded - expected
      }
      _state = AiHintState.idle; // user-cancelled
    } catch (e) {
      if (gen != _generation) {
        if (userIndex < _messages.length) {
          _messages.removeAt(userIndex);
        }
        return true; // superseded - drop the stale error
      }
      logger.w('AiHintProvider.ask failed: $e');
      _error = e.toString();
      _state = AiHintState.error;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    if (gen == _generation) notifyListeners();
    return true;
  }

  /// Persona + rules for the hint assistant. The correct answer is NOT
  /// included - the assistant explains the knowledge point and reasoning
  /// rather than revealing the answer, to keep it a learning aid.
  String _buildSystemPrompt(AiQuestionContext ctx) {
    return 'You are a ${ctx.language} language-learning tutor who explains '
        'practice questions to the learner in plain Chinese.\n'
        'Requirements:\n'
        '- First state what this question is testing (grammar point, word '
        'meaning, sentence pattern, etc.).\n'
        '- Then give the solving approach or related knowledge points, '
        'concisely as bullet points.\n'
        '- Do not directly restate the correct answer; guide the learner to '
        'reach it themselves.\n'
        '- If the learner asks a follow-up, you may give more specific hints '
        'step by step, but keep it primarily heuristic.\n'
        '- Reply in Chinese throughout.';
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
    buf.writeln('Explain according to your rules; do not give the answer '
        'directly.');
    return buf.toString();
  }

  // ─── Depth-learning tutor genres ─────────────────────────────────────
  //
  // Each genre is a one-shot `chat()` round-trip whose reply is a small JSON
  // object, decoded and parsed into a typed result. They do NOT touch the
  // conversation state machine above (no `_messages` / `_state` mutation) -
  // they are stateless helpers the depth-tutor sheet calls directly. Errors
  // (network or JSON parse) propagate to the caller; the sheet surfaces them.

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

  /// Explain a grammar point illustrated by [sentence]. Returns a structured
  /// explanation with related examples and points it contrasts with.
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
      systemPrompt: 'You are a $language grammar tutor. Explain grammar '
          'points in plain Chinese. Respond with ONLY a JSON object (no '
          'markdown fences): {"explanation": string, "relatedExamples": '
          '[string], "contrastWith": [string]}.',
      userPrompt: 'Grammar point: $grammarPoint\n'
          'Sentence illustrating it: $sentence\n'
          'Explain the point. relatedExamples: 2-3 example sentences in '
          '$language. contrastWith: other points it is often confused with '
          '(may be empty).',
      parse: GrammarExplanation.fromJson,
    );
  }

  /// Compare near-synonymous [words], returning pairwise nuance and usage.
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
      systemPrompt: 'You are a $language vocabulary tutor. Compare '
          'near-synonymous words in plain Chinese. Respond with ONLY a JSON '
          'object (no markdown fences): {"pairs": [{"a": string, "b": string, '
          '"nuance": string, "whenToUseA": string, "whenToUseB": string, '
          '"examples": [string]}]}.',
      userPrompt: 'Compare these $language words and explain the nuances:\n'
          '$wordList\n'
          'Produce one pair entry per meaningful contrast; examples should be '
          'short sentences in $language.',
      parse: SynonymComparison.fromJson,
    );
  }

  /// Decompose [sentence] token-by-token with glosses and roles, plus a
  /// one-line structure summary.
  Future<SentenceBreakdown> decomposeSentence({
    required AiEngineConfig config,
    required String language,
    required String sentence,
    AiCancelToken? cancelToken,
  }) {
    return _typedChat<SentenceBreakdown>(
      config: config,
      cancelToken: cancelToken,
      systemPrompt: 'You are a $language syntax tutor. Decompose sentences '
          'token by token. Respond with ONLY a JSON object (no markdown '
          'fences): {"tokens": [{"surface": string, "lemma": string|null, '
          '"gloss": string, "role": string}], "structure": string}. Glosses '
          'and roles in Chinese.',
      userPrompt: 'Decompose this $language sentence:\n$sentence\n'
          'One token per entry; "structure" is a one-line Chinese summary of '
          'the sentence pattern.',
      parse: SentenceBreakdown.fromJson,
    );
  }

  /// Explain why [userAnswer] was wrong for [questionContext], what the
  /// learner likely confused it with, and how to remember [correctAnswer].
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
      systemPrompt: 'You are a $language tutor. Help a learner understand a '
          'mistake. Respond with ONLY a JSON object (no markdown fences): '
          '{"whyWrong": string, "whatYouProbablyThought": string, '
          '"howToRemember": string}. All fields in Chinese.',
      userPrompt: 'Question: $questionContext\n'
          'My answer: $userAnswer\n'
          'Correct answer: $correctAnswer\n'
          'Explain why my answer is wrong, what I probably confused it with, '
          'and a mnemonic to remember the correct answer.',
      parse: WhyWrongExplanation.fromJson,
    );
  }

  /// Append a hint task to the AI Hub's recent list. Called from the success
  /// branches of [explainQuestion] / [ask] so Continue shows hint flows.
  void _recordRecent(String language) {
    final context = _context;
    if (context == null) return;
    try {
      getIt<AiRecentTasksProvider>().record(
            AiRecentTask(
              kind: AiTaskKind.hintChat,
              summary: '${context.typeLabel} · $language',
              timestamp: DateTime.now(),
            ),
          );
    } catch (_) {
      // Recent tasks are advisory; never let a record failure break the flow.
    }
  }
}

/// Build a self-contained Chinese prompt handed to HarmonyOS 小艺 when the
/// learner taps the AI button with "用小艺解答" enabled. Unlike
/// [AiHintProvider._buildExplainPrompt] (which tells the tutor model not to
/// reveal the answer), this asks 小艺 to directly explain and answer the
/// question, because 小艺 is a general assistant outside the app's learning
/// flow and the learner chose it precisely to get the answer.
String buildXiaoyiPrompt(AiQuestionContext ctx) {
  final buf = StringBuffer()
    ..writeln('这是一道${ctx.language}语言学习练习题，请帮我解答并讲解：')
    ..writeln('题型：${ctx.typeLabel}')
    ..writeln('题目：${ctx.promptLabel}');
  if (ctx.optionsLabel != null && ctx.optionsLabel!.isNotEmpty) {
    buf.writeln('选项：${ctx.optionsLabel}');
  }
  if (ctx.userAnswer != null && ctx.userAnswer!.isNotEmpty) {
    buf.writeln('我的答案：${ctx.userAnswer}');
  }
  buf.writeln('请给出正确答案并简要讲解相关知识点。');
  return buf.toString();
}
