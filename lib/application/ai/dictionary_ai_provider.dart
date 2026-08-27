// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_recent_task_log.dart';
import 'package:turna/application/ai/ai_streaming_session_base.dart';
import 'package:turna/application/ai/companion_rate_limiter.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

enum DictionaryAiState { idle, loading, ready, error }

/// Dictionary entry AI enrichment via [AiEngine] (cache-friendly fixed prompts).
class DictionaryAiProvider extends AiRequestSessionBase {
  DictionaryAiProvider({
    AiEngine? engine,
    AiExplainPrefsStore? prefs,
    CompanionRateLimiter? rateLimiter,
  })  : _engine = engine ?? getIt<AiEngine>(),
        _prefs = AiExplainPrefsStore.resolve(
          prefs: prefs,
          allowEphemeral: true,
        ),
        _rateLimiter = rateLimiter ?? CompanionRateLimiter();

  final AiEngine _engine;
  final AiExplainPrefsStore _prefs;
  final CompanionRateLimiter _rateLimiter;

  DictionaryAiState _state = DictionaryAiState.idle;
  DictionaryAiState get state => _state;

  String? _error;
  String? get error => _error;

  DictionaryEnrichment? _enrichment;
  DictionaryEnrichment? get enrichment => _enrichment;

  String? _lastTerm;
  String? get lastTerm => _lastTerm;

  void clear() {
    abandonStreamingSession();
    _enrichment = null;
    _error = null;
    _lastTerm = null;
    _state = DictionaryAiState.idle;
    notifySessionListeners();
  }

  void cancel() {
    if (_state != DictionaryAiState.loading) return;
    cancelStreamingSession();
    _state = DictionaryAiState.idle;
    notifySessionListeners();
  }

  Future<DictionaryEnrichment?> enrich({
    required AiEngineConfig config,
    required String language,
    required String term,
    String? translation,
  }) async {
    final t = term.trim();
    if (t.isEmpty) return null;

    if (!_rateLimiter.tryAcquire(CompanionRateLimiter.dictionary)) {
      _error = AiErrorMapper.map(
        Exception('HTTP 429: rate'),
      ).message;
      _state = DictionaryAiState.error;
      notifyListeners();
      return null;
    }

    final session = beginStreamingSession();
    _error = null;
    _lastTerm = t;
    _state = DictionaryAiState.loading;
    notifySessionListeners();

    try {
      // Prefs rules are part of system prompt so cache keys shift with language/depth.
      final result = await _engine.requestJson(
        config: config,
        messages: <Map<String, dynamic>>[
          {
            'role': 'system',
            'content': 'You are a language-learning tutor for $language. '
                '${_prefs.snapshot.toSystemPromptRules()}\n'
                'Respond with ONLY a JSON object (no markdown fences): '
                '{"expandedGloss":string,"examples":[string],"pairs":'
                '[{"a":string,"b":string,"nuance":string,"whenToUseA":string,'
                '"whenToUseB":string,"examples":[string]}],"mnemonic":string}. '
                'examples: prefer 3 example sentences in $language. '
                'mnemonic: one short memory hook in the reply language.',
          },
          {
            'role': 'user',
            'content': 'Term: $t\n'
                '${translation != null && translation.isNotEmpty ? 'Known gloss: $translation\n' : ''}'
                'Provide enrichment JSON.',
          },
        ],
        cancelToken: session.cancelToken,
      );
      if (!isCurrentSession(session)) return null;
      final enrichment = DictionaryEnrichment.fromJson(
          decodeJsonObject(result.content),
          term: t);
      _enrichment = enrichment;
      _state = DictionaryAiState.ready;
      recordAiRecentTask(
        kind: AiTaskKind.dictionary,
        summary: '词典 · $t',
      );
      notifySessionListeners();
      return enrichment;
    } on AiCancelled {
      if (!isCurrentSession(session)) return null;
      _state = DictionaryAiState.idle;
      notifySessionListeners();
      return null;
    } catch (e) {
      if (!isCurrentSession(session)) return null;
      logger.w('DictionaryAiProvider.enrich failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = DictionaryAiState.error;
      notifySessionListeners();
      return null;
    } finally {
      finishStreamingSession(session);
    }
  }
}
