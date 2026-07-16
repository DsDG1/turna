// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/core/logger.dart';

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

  /// Canonical correct-answer label. NOT sent to the model by default — kept
  /// here only so callers can decide per-type whether to reveal it.
  final String? correctLabel;

  /// What the learner answered, if they have already submitted.
  final String? userAnswer;
}

/// Provider backing the in-lesson AI hint assistant (the right-corner AI
/// button → explanation sheet → follow-up chat page).
///
/// Holds a single question's context plus the conversation history built on
/// top of it. The [AiApiConfig] is shared with [AiCourseProvider]; the sheet
/// / chat page read it from there and pass it in.
class AiHintProvider extends ChangeNotifier {
  AiHintProvider({http.Client? client})
      : _service = AiCourseService(client: client);
  AiHintProvider.withService(this._service);

  final AiCourseService _service;

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
  /// token changed while it was awaiting the network — so a stale in-flight
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

  void reset() {
    _generation++;
    _messages.clear();
    _state = AiHintState.idle;
    _error = null;
    _context = null;
    notifyListeners();
  }

  /// Ask the AI to explain the current question. Builds the system prompt
  /// from [ctx], seeds the conversation with a "explain this" user turn, and
  /// appends the assistant's reply.
  Future<void> explainQuestion({
    required AiApiConfig config,
    required AiQuestionContext ctx,
  }) async {
    _generation++;
    final gen = _generation;
    _error = null;
    _context = ctx;
    _state = AiHintState.loading;
    _messages.clear();
    notifyListeners();
    try {
      final userText = _buildExplainPrompt(ctx);
      _messages.add(AiChatMessage(role: 'user', content: userText));
      notifyListeners();
      final reply = await _service.requestTextReply(
        config: config,
        systemPrompt: _buildSystemPrompt(ctx),
        messages: _messages.map((m) => m.toApiDict()).toList(),
      );
      if (gen != _generation) return; // superseded by a newer request/reset
      _messages.add(AiChatMessage(role: 'assistant', content: reply));
      _state = AiHintState.ready;
    } catch (e) {
      if (gen != _generation) return; // superseded — drop the stale error
      logger.w('AiHintProvider.explainQuestion failed: $e');
      _error = e.toString();
      _state = AiHintState.error;
    }
    notifyListeners();
  }

  /// Append a follow-up question and the assistant's reply. Returns `true`
  /// when the turn was actually started (context present, text non-empty),
  /// `false` when it was a no-op — callers can use the return value to avoid
  /// clearing the input field on a no-op so the user's text isn't lost.
  Future<bool> ask({
    required AiApiConfig config,
    required String text,
  }) async {
    if (text.trim().isEmpty || _context == null) return false;
    _generation++;
    final gen = _generation;
    final userIndex = _messages.length; // for orphan cleanup if superseded
    _error = null;
    _state = AiHintState.loading;
    _messages.add(AiChatMessage(role: 'user', content: text));
    notifyListeners();
    try {
      final reply = await _service.requestTextReply(
        config: config,
        systemPrompt: _buildSystemPrompt(_context!),
        messages: _messages.map((m) => m.toApiDict()).toList(),
      );
      if (gen != _generation) {
        // Superseded — remove this turn's orphan user message so the stale
        // question doesn't linger in the transcript or the newer request's
        // history. Only do this if it's still ours at that index (a newer
        // ask that already cleaned up would have shifted indices).
        if (userIndex < _messages.length) {
          _messages.removeAt(userIndex);
        }
        return true;
      }
      _messages.add(AiChatMessage(role: 'assistant', content: reply));
      _state = AiHintState.ready;
    } catch (e) {
      if (gen != _generation) {
        if (userIndex < _messages.length) {
          _messages.removeAt(userIndex);
        }
        return true; // superseded — drop the stale error
      }
      logger.w('AiHintProvider.ask failed: $e');
      _error = e.toString();
      _state = AiHintState.error;
    }
    notifyListeners();
    return true;
  }

  /// Persona + rules for the hint assistant. The correct answer is NOT
  /// included — the assistant explains the knowledge point and reasoning
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
}