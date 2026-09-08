// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_recent_task_log.dart';
import 'package:turna/application/ai/ai_streaming_session_base.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

/// Free companion chat modes (never generates course JSON).
enum AiTutorChatMode { qa, sentenceCheck, roleplay }

enum AiTutorChatState { idle, loading, ready, error }

/// Free companion chat: Q&A / sentence-check / role-play. Streams text only;
/// never parses or saves course section JSON.
class AiTutorChatProvider extends AiStreamingSessionBase {
  AiTutorChatProvider({
    AiEngine? engine,
    AiExplainPrefsStore? prefs,
  })  : _engine = engine ?? getIt<AiEngine>(),
        _prefs = AiExplainPrefsStore.resolve(
          prefs: prefs,
          allowEphemeral: true,
        );

  final AiEngine _engine;
  final AiExplainPrefsStore _prefs;

  final List<AiChatMessage> _messages = <AiChatMessage>[];
  List<AiChatMessage> get messages => List.unmodifiable(_messages);

  AiTutorChatState _state = AiTutorChatState.idle;
  AiTutorChatState get state => _state;

  String? _error;
  String? get error => _error;

  AiTutorChatMode _mode = AiTutorChatMode.qa;
  AiTutorChatMode get mode => _mode;

  // Target language for prompts; the page sets the learner's current
  // language right after construction — this default covers DI-less tests.
  String _language = LanguageRegistry.instance.defaultLanguage.displayName;
  String get language => _language;

  LearnerAiContext? _learnerContext;
  int _streamingAssistantIndex = -1;

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

  void setMode(AiTutorChatMode mode) {
    if (_mode == mode || isSessionDisposed) return;
    _mode = mode;
    notifyListeners();
  }

  void setLanguage(String language) {
    _language = language;
  }

  void setLearnerContext(LearnerAiContext? ctx) {
    _learnerContext = ctx;
  }

  void reset() {
    if (isSessionDisposed) return;
    abandonStreamingSession();
    _messages.clear();
    _state = AiTutorChatState.idle;
    _error = null;
    notifySessionListeners();
  }

  /// Stop generation; keep any partial assistant text already streamed.
  void cancel() {
    if (isSessionDisposed || _state != AiTutorChatState.loading) return;
    cancelStreamingSession();
    _state = AiTutorChatState.idle;
    notifySessionListeners();
  }

  Future<bool> startRoleplayScene({
    required AiEngineConfig config,
    required String sceneLabel,
  }) {
    return ask(
      config: config,
      text: '请用$_language开始「$sceneLabel」情景对话。你扮演对方，'
          '我是学习者；必要时用简短中文旁注纠错。先开场。',
    );
  }

  Future<bool> ask({
    required AiEngineConfig config,
    required String text,
  }) async {
    if (text.trim().isEmpty) return false;
    if (isSessionDisposed) return false;
    final session = beginStreamingSession();
    _error = null;
    _state = AiTutorChatState.loading;
    _messages.add(AiChatMessage(role: 'user', content: text.trim()));
    _messages.add(const AiChatMessage(role: 'assistant', content: ''));
    final assistantIndex = _messages.length - 1;
    _streamingAssistantIndex = assistantIndex;
    notifySessionListeners();

    final apiMessages = _buildApiMessages(assistantIndex);

    try {
      final result = await _engine.chat(
        config: config,
        messages: apiMessages,
        cancelToken: session.cancelToken,
        onChunk: (delta) {
          addStreamingDelta(session, delta);
        },
      );
      flushStreamingSession(session);
      if (!isCurrentSession(session)) return true;
      if (_messages[assistantIndex].content.isEmpty &&
          result.content.isNotEmpty) {
        _messages[assistantIndex] =
            AiChatMessage(role: 'assistant', content: result.content);
      }
      _state = AiTutorChatState.ready;
      _recordRecent();
    } on AiCancelled {
      if (!isCurrentSession(session)) return true;
      flushStreamingSession(session);
      _state = AiTutorChatState.idle;
    } catch (e) {
      if (!isCurrentSession(session)) return true;
      logger.w('AiTutorChatProvider.ask failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiTutorChatState.error;
      if (assistantIndex < _messages.length &&
          _messages[assistantIndex].content.isEmpty) {
        _messages.removeAt(assistantIndex);
      }
    } finally {
      finishStreamingSession(session);
    }
    if (!isSessionDisposed) notifySessionListeners();
    return true;
  }

  static const int _recentMessageLimit = 16;

  List<Map<String, dynamic>> _buildApiMessages(int assistantIndex) {
    final history = <AiChatMessage>[
      for (var i = 0; i < _messages.length; i++)
        if (i != assistantIndex) _messages[i],
    ];
    final split = history.length > _recentMessageLimit
        ? history.length - _recentMessageLimit
        : 0;
    final older = history.take(split).toList(growable: false);
    final recent = history.skip(split);
    return <Map<String, dynamic>>[
      {'role': 'system', 'content': _buildSystemPrompt()},
      if (older.isNotEmpty)
        {
          'role': 'system',
          'content': _summarizeOlderTurns(older),
        },
      for (final message in recent) message.toApiDict(),
    ];
  }

  String _summarizeOlderTurns(List<AiChatMessage> messages) {
    final out = StringBuffer('Earlier conversation summary:\n');
    for (final message in messages) {
      final normalized = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final clipped = normalized.length > 160
          ? '${normalized.substring(0, 160)}…'
          : normalized;
      out.writeln('${message.role}: $clipped');
      if (out.length > 1200) break;
    }
    return out.toString();
  }

  String _buildSystemPrompt() {
    final prefs = _prefs.snapshot;
    final buf = StringBuffer()
      ..writeln('You are a language-learning companion for $_language. '
          'You help with questions, sentence correction, and role-play. '
          'Never output course section/unit/lesson JSON or any importable course schema.')
      ..writeln(prefs.toSystemPromptRules());

    switch (_mode) {
      case AiTutorChatMode.qa:
        buf.writeln(
            'Mode: Q&A. Answer grammar and usage questions clearly with examples.');
        break;
      case AiTutorChatMode.sentenceCheck:
        buf.writeln(
            'Mode: sentence check. Correct the learner sentence; note errors '
            '(span/issue/fix) in plain text; offer a more natural version and one tip.');
        break;
      case AiTutorChatMode.roleplay:
        buf.writeln(
            'Mode: role-play. Stay in character as the interlocutor in $_language; '
            'add brief Chinese correction notes when the learner errs.');
        break;
    }

    if (prefs.injectLearnerContext &&
        _learnerContext != null &&
        !_learnerContext!.isEmpty) {
      buf.writeln(_learnerContext!.toPromptBlock());
    }
    return buf.toString();
  }

  /// Exposed for prompt snapshot tests.
  @visibleForTesting
  String buildSystemPromptForTest() => _buildSystemPrompt();

  void _recordRecent() {
    recordAiRecentTask(
      kind: AiTaskKind.tutorChat,
      summary: '自由问答 · $_language',
      route: AiRecentTaskRoute.tutorChat,
    );
  }
}
