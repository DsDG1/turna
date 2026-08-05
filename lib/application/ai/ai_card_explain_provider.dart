// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

enum AiCardExplainState { idle, loading, ready, error }

/// Secondary "explain this card" path for SRS / Anki review.
/// Does not alter scoring, notes, or Anki mapping.
class AiCardExplainProvider extends ChangeNotifier {
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

  AiCancelToken? _cancelToken;
  int _generation = 0;

  void clear() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _generation++;
    _explanation = null;
    _error = null;
    _state = AiCardExplainState.idle;
    notifyListeners();
  }

  void cancel() {
    if (_state != AiCardExplainState.loading) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiCardExplainState.idle;
    notifyListeners();
  }

  /// Explain a review card. [front] / [back] are already-mapped display fields.
  Future<String?> explain({
    required AiEngineConfig config,
    required String language,
    required String front,
    String? back,
    String source = 'review',
  }) async {
    _cancelToken?.cancel();
    _generation++;
    final gen = _generation;
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _explanation = null;
    _state = AiCardExplainState.loading;
    notifyListeners();

    final buf = StringBuffer()
      ..writeln('Front: $front');
    if (back != null && back.trim().isNotEmpty) {
      buf.writeln('Back: $back');
    }

    try {
      final result = await _engine.chat(
        config: config,
        messages: <Map<String, dynamic>>[
          {
            'role': 'system',
            'content':
                'You are a language-learning companion for $language. '
                '${_prefs.snapshot.toSystemPromptRules()}\n'
                'Explain this flashcard briefly to help understanding. '
                'Do not change or "correct" the card answer keys. '
                'Note that explanations are for understanding only; the card answer is authoritative. '
                'Never output course section JSON.',
          },
          {
            'role': 'user',
            'content': 'Please explain this review card:\n$buf',
          },
        ],
        cancelToken: token,
        onChunk: (delta) {
          if (gen != _generation) return;
          if (delta.isEmpty) return;
          _explanation = (_explanation ?? '') + delta;
          notifyListeners();
        },
      );
      if (gen != _generation) return null;
      if ((_explanation == null || _explanation!.isEmpty) &&
          result.content.isNotEmpty) {
        _explanation = result.content;
      }
      _state = AiCardExplainState.ready;
      notifyListeners();
      return _explanation;
    } on AiCancelled {
      if (gen != _generation) return null;
      _state = AiCardExplainState.idle;
      notifyListeners();
      return _explanation;
    } catch (e) {
      if (gen != _generation) return null;
      logger.w('AiCardExplainProvider.explain failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiCardExplainState.error;
      notifyListeners();
      return null;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
  }
}
