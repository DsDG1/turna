// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/hint_genres.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

enum AiDiagnosisState { idle, loading, ready, error }

/// Text-only learning diagnosis from mistakes/weak words (not a course tree).
class AiDiagnosisProvider extends ChangeNotifier {
  AiDiagnosisProvider({
    AiEngine? engine,
    AiExplainPrefsStore? prefs,
    this.minInterval = const Duration(seconds: 60),
  })  : _engine = engine ?? getIt<AiEngine>(),
        _prefs = AiExplainPrefsStore.resolve(
          prefs: prefs,
          allowEphemeral: true,
        );

  final AiEngine _engine;
  final AiExplainPrefsStore _prefs;
  final Duration minInterval;

  AiDiagnosisState _state = AiDiagnosisState.idle;
  AiDiagnosisState get state => _state;

  String? _error;
  String? get error => _error;

  DiagnosisReport? _report;
  DiagnosisReport? get report => _report;

  DateTime? _lastGeneratedAt;
  DateTime? get lastGeneratedAt => _lastGeneratedAt;

  AiCancelToken? _cancelToken;
  int _generation = 0;

  void clear() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _generation++;
    _report = null;
    _error = null;
    _state = AiDiagnosisState.idle;
    notifyListeners();
  }

  void cancel() {
    if (_state != AiDiagnosisState.loading) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiDiagnosisState.idle;
    notifyListeners();
  }

  /// Whether [generate] would be rejected by the local rate limit.
  bool get isRateLimited {
    final last = _lastGeneratedAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < minInterval;
  }

  /// Generate a diagnosis report. Returns `false` when rate-limited without
  /// calling the engine. Never produces course section JSON.
  Future<bool> generate({
    required AiEngineConfig config,
    required LearnerAiContext learnerContext,
    bool force = false,
  }) async {
    if (!force && isRateLimited) {
      _error = 'rate_limited';
      _state = AiDiagnosisState.error;
      notifyListeners();
      return false;
    }

    _cancelToken?.cancel();
    _generation++;
    final gen = _generation;
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _state = AiDiagnosisState.loading;
    notifyListeners();

    try {
      final result = await _engine.requestJson(
        config: config,
        messages: <Map<String, dynamic>>[
          {'role': 'system', 'content': _systemPrompt(learnerContext)},
          {
            'role': 'user',
            'content':
                'Based on the learner context, produce a diagnosis JSON only. '
                    'No course section/unit/lesson schema.',
          },
        ],
        cancelToken: token,
      );
      if (gen != _generation) return true;
      final report = DiagnosisReport.fromJson(decodeJsonObject(result.content));
      _report = report;
      _lastGeneratedAt = DateTime.now();
      _state = AiDiagnosisState.ready;
      _recordRecent();
    } on AiCancelled {
      if (gen != _generation) return true;
      _state = AiDiagnosisState.idle;
    } catch (e) {
      if (gen != _generation) return true;
      logger.w('AiDiagnosisProvider.generate failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiDiagnosisState.error;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    if (gen == _generation) notifyListeners();
    return true;
  }

  String _systemPrompt(LearnerAiContext ctx) {
    final prefs = _prefs.snapshot;
    final buf = StringBuffer()
      ..writeln(
          'You are a language-learning coach for ${ctx.languageName}. '
          'Produce a TEXT diagnosis of weak areas only. '
          'Never output course section/unit/lesson JSON.')
      ..writeln(prefs.toSystemPromptRules())
      ..writeln(
          'Respond with ONLY a JSON object (no markdown fences): '
          '{"weakAreas":[{"title":string,"severity":"high|medium|low","evidence":[string]}],'
          '"priorityTips":[string],"exampleDrillIdeas":[string]}.')
      ..writeln('priorityTips: 3-7 items. exampleDrillIdeas: short text ideas, not lessons.');
    if (!ctx.isEmpty) {
      buf.writeln(ctx.toPromptBlock(maxChars: 1200));
    }
    return buf.toString();
  }

  @visibleForTesting
  String systemPromptForTest(LearnerAiContext ctx) => _systemPrompt(ctx);

  void _recordRecent() {
    try {
      getIt<AiRecentTasksProvider>().record(
        AiRecentTask(
          kind: AiTaskKind.diagnosis,
          summary: '学习诊断',
          timestamp: DateTime.now(),
          route: 'AiDiagnosisRoute',
        ),
      );
    } catch (_) {}
  }
}
