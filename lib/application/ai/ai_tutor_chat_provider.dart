// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/application/ai/stream_delta_coalescer.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

/// Free companion chat modes (never generates course JSON).
enum AiTutorChatMode { qa, sentenceCheck, roleplay }

enum AiTutorChatState { idle, loading, ready, error }

/// Free companion chat: Q&A / sentence-check / role-play. Streams text only;
/// never parses or saves course section JSON.
class AiTutorChatProvider extends ChangeNotifier {
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

  String _language = 'Turkish';
  String get language => _language;

  LearnerAiContext? _learnerContext;
  int _generation = 0;
  AiCancelToken? _cancelToken;

  bool _disposed = false;

  /// Increments once per coalesced UI batch while an answer streams. Pages
  /// use it to rebuild ONLY the streaming bubble (Plan 3 §21.2), not the
  /// whole shell.
  int _streamingRevision = 0;
  int get streamingRevision => _streamingRevision;

  /// Batches network chunks to ≤1 notify per ~80 ms (Plan 3 §21.1). Created
  /// per ask() call so a finished stream's buffer can never leak into the
  /// next one.
  StreamDeltaCoalescer? _coalescer;

  StreamDeltaCoalescer _newCoalescer() => StreamDeltaCoalescer(
        interval: const Duration(milliseconds: 80),
        onBatch: (batch) {
          if (_disposed) return;
          final m = _messages;
          if (m.isEmpty || m.last.role != 'assistant') return;
          m[m.length - 1] = AiChatMessage(
            role: 'assistant',
            content: m.last.content + batch,
          );
          _streamingRevision++;
          notifyListeners();
        },
      );

  @override
  void dispose() {
    // Unified cancel contract (Plan 3 §18.7/§21.4): stop the in-flight
    // request, drop pending batches, and make any late callback inert.
    _disposed = true;
    _cancelToken?.cancel();
    _cancelToken = null;
    _coalescer?.cancel();
    super.dispose();
  }

  void setMode(AiTutorChatMode mode) {
    if (_mode == mode || _disposed) return;
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
    if (_disposed) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _generation++;
    _messages.clear();
    _state = AiTutorChatState.idle;
    _error = null;
    notifyListeners();
  }

  /// Stop generation; keep any partial assistant text already streamed.
  void cancel() {
    if (_disposed || _state != AiTutorChatState.loading) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiTutorChatState.idle;
    notifyListeners();
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
    _cancelToken?.cancel();
    _generation++;
    final gen = _generation;
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _state = AiTutorChatState.loading;
    _messages.add(AiChatMessage(role: 'user', content: text.trim()));
    _messages.add(const AiChatMessage(role: 'assistant', content: ''));
    final assistantIndex = _messages.length - 1;
    final coalescer = _newCoalescer();
    _coalescer?.cancel();
    _coalescer = coalescer;
    notifyListeners();

    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _buildSystemPrompt()},
      for (var i = 0; i < _messages.length; i++)
        if (i != assistantIndex) _messages[i].toApiDict(),
    ];

    try {
      final result = await _engine.chat(
        config: config,
        messages: apiMessages,
        cancelToken: token,
        onChunk: (delta) {
          if (gen != _generation || _disposed) return;
          coalescer.add(delta);
        },
      );
      coalescer.flush(); // stream finished: emit any pending tail batch
      if (gen != _generation || _disposed) return true;
      if (_messages[assistantIndex].content.isEmpty &&
          result.content.isNotEmpty) {
        _messages[assistantIndex] =
            AiChatMessage(role: 'assistant', content: result.content);
      }
      _state = AiTutorChatState.ready;
      _recordRecent();
    } on AiCancelled {
      if (gen != _generation || _disposed) return true;
      coalescer.flush(); // keep partial text already streamed (§26.3)
      _state = AiTutorChatState.idle;
    } catch (e) {
      if (gen != _generation || _disposed) return true;
      logger.w('AiTutorChatProvider.ask failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiTutorChatState.error;
      if (assistantIndex < _messages.length &&
          _messages[assistantIndex].content.isEmpty) {
        _messages.removeAt(assistantIndex);
      }
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    if (gen == _generation && !_disposed) notifyListeners();
    return true;
  }

  String _buildSystemPrompt() {
    final prefs = _prefs.snapshot;
    final buf = StringBuffer()
      ..writeln(
          'You are a language-learning companion for $_language. '
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
    try {
      getIt<AiRecentTasksProvider>().record(
        AiRecentTask(
          kind: AiTaskKind.tutorChat,
          summary: '自由问答 · $_language',
          timestamp: DateTime.now(),
          route: 'AiTutorChatRoute',
        ),
      );
    } catch (_) {}
  }
}
