// Flutter imports:
// Project imports:
import 'package:turna/application/ai/ai_card_context_resolver.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_streaming_session_base.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

enum AiCardExplainState { idle, loading, ready, error }

/// Secondary "explain this card" path for SRS / Anki review.
/// Does not alter scoring, notes, or Anki mapping.
class AiCardExplainProvider extends AiStreamingSessionBase {
  AiCardExplainProvider({
    AiEngine? engine,
    AiExplainPrefsStore? prefs,
  })  : _engine = engine ?? getIt<AiEngine>(),
        _prefs = AiExplainPrefsStore.resolve(
          prefs: prefs,
          allowEphemeral: true,
        );

  final AiEngine _engine;
  final AiExplainPrefsStore _prefs;

  AiCardExplainState _state = AiCardExplainState.idle;
  AiCardExplainState get state => _state;

  String? _error;
  String? get error => _error;

  String? _explanation;
  String? get explanation => _explanation;

  @override
  void applyStreamingBatch(String batch) {
    _explanation = (_explanation ?? '') + batch;
  }

  void clear() {
    if (isSessionDisposed) return;
    abandonStreamingSession();
    _explanation = null;
    _error = null;
    _state = AiCardExplainState.idle;
    notifySessionListeners();
  }

  void cancel() {
    if (isSessionDisposed || _state != AiCardExplainState.loading) return;
    cancelStreamingSession();
    _state = AiCardExplainState.idle;
    notifySessionListeners();
  }

  /// Explain a review card using the sole sanitized/reveal-gated context
  /// produced by [AiCardContextResolver].
  Future<String?> explain({
    required AiEngineConfig config,
    required AiCardContext context,
  }) async {
    if (isSessionDisposed || !context.supported) return null;
    final session = beginStreamingSession();
    _error = null;
    _explanation = null;
    _state = AiCardExplainState.loading;
    notifySessionListeners();

    final language = context.language ?? 'the target language';

    try {
      final result = await _engine.chat(
        config: config,
        messages: <Map<String, dynamic>>[
          {
            'role': 'system',
            'content': 'You are a language-learning companion for $language. '
                '${_prefs.snapshot.toSystemPromptRules()}\n'
                'Explain this flashcard briefly to help understanding. '
                'Do not change or "correct" the card answer keys. '
                'Note that explanations are for understanding only; the card answer is authoritative. '
                'Never output course section JSON.',
          },
          {
            'role': 'user',
            'content': 'Please explain this review card:\n'
                '${context.toPromptBlock()}',
          },
        ],
        cancelToken: session.cancelToken,
        onChunk: (delta) => addStreamingDelta(session, delta),
      );
      flushStreamingSession(session);
      if (!isCurrentSession(session)) return null;
      if ((_explanation == null || _explanation!.isEmpty) &&
          result.content.isNotEmpty) {
        _explanation = result.content;
      }
      _state = AiCardExplainState.ready;
      notifySessionListeners();
      return _explanation;
    } on AiCancelled {
      if (!isCurrentSession(session)) return null;
      flushStreamingSession(session);
      _state = AiCardExplainState.idle;
      notifySessionListeners();
      return _explanation;
    } catch (e) {
      if (!isCurrentSession(session)) return null;
      logger.w('AiCardExplainProvider.explain failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiCardExplainState.error;
      notifySessionListeners();
      return null;
    } finally {
      finishStreamingSession(session);
    }
  }
}
