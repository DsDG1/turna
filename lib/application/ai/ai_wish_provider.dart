// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_explainer.dart';
import 'package:turna/application/ai/ai_course_service.dart';
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/ai_prompt_builder.dart';
import 'package:turna/application/ai/ai_recent_task_log.dart';
import 'package:turna/application/ai/ai_streaming_session_base.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';

/// State machine for wish-mode conversation.
enum AiWishState { idle, aligning, generating, explaining, generated, error }

/// Provider backing the wish-mode chat page. Holds the conversation history
/// and orchestrates alignment -> finalize-generation -> explain.
///
/// The [AiEngineConfig] is sourced from [AiEngineConfigHolder]; all LLM traffic
/// routes through the shared [AiEngine] (the single choke point), so a long
/// generation can be cancelled mid-flight via [cancel]. Pure helpers
/// ([AiCourseService.parseCompletion], [AiCourseService.applyGenreToSpec]) are
/// reused from a helper [AiCourseService] instance - no network hop there.
@lazySingleton
class AiWishProvider extends AiRequestSessionBase {
  AiWishProvider(
      {AiEngine? engine, AiGroundedResourceProvider? groundedProvider})
      : _engine = engine ?? getIt<AiEngine>(),
        _service = AiCourseService(),
        _groundedProvider = groundedProvider ?? AiGroundedResourceProvider();
  AiWishProvider.withEngine(this._engine,
      {AiGroundedResourceProvider? groundedProvider})
      : _service = AiCourseService(),
        _groundedProvider = groundedProvider ?? AiGroundedResourceProvider();

  final AiEngine _engine;
  final AiCourseService _service;
  final AiGroundedResourceProvider _groundedProvider;

  final List<AiChatMessage> _messages = <AiChatMessage>[];
  List<AiChatMessage> get messages => List.unmodifiable(_messages);

  AiWishState _state = AiWishState.idle;
  AiWishState get state => _state;

  String? _error;
  String? get error => _error;

  /// Generated course raw JSON after finalize.
  String? _generatedJson;
  String? get generatedJson => _generatedJson;

  /// Plain-language explanation of the generated course.
  String? _explanation;
  String? get explanation => _explanation;

  /// Parsed section id of the generated course.
  String? _generatedSectionId;
  String? get generatedSectionId => _generatedSectionId;

  void reset() {
    abandonStreamingSession();
    _messages.clear();
    _state = AiWishState.idle;
    _error = null;
    _generatedJson = null;
    _explanation = null;
    _generatedSectionId = null;
    notifySessionListeners();
  }

  /// Cancel the in-flight call (if any) and return to idle, keeping the
  /// conversation history. A no-op when idle/generated.
  void cancel() {
    final active = _state == AiWishState.aligning ||
        _state == AiWishState.generating ||
        _state == AiWishState.explaining;
    if (!active) return;
    cancelStreamingSession();
    _state = AiWishState.idle;
    notifySessionListeners();
  }

  /// Send a user alignment message and append the assistant reply.
  Future<void> sendAlignment({
    required AiEngineConfig config,
    required AiCourseSpec spec,
    required String userText,
  }) async {
    if (userText.trim().isEmpty) return;
    final session = beginStreamingSession();
    _error = null;
    _state = AiWishState.aligning;
    _messages.add(AiChatMessage(role: 'user', content: userText));
    notifySessionListeners();
    try {
      final groundedContext = await _loadGroundedContext(spec);
      final result = await _engine.chat(
        config: config,
        messages: <Map<String, dynamic>>[
          {
            'role': 'system',
            'content':
                buildAlignmentPrompt(spec, groundedContext: groundedContext),
          },
          ..._messages.map((m) => m.toApiDict()),
        ],
        temperature: 0.7,
        timeout: const Duration(seconds: 120),
        cancelToken: session.cancelToken,
      );
      if (!isCurrentSession(session)) return;
      _messages.add(AiChatMessage(role: 'assistant', content: result.content));
      _state = AiWishState.idle;
    } on AiCancelled {
      if (!isCurrentSession(session)) return;
      _state = AiWishState.idle;
    } catch (e) {
      if (!isCurrentSession(session)) return;
      logger.w('AiWishProvider.sendAlignment failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiWishState.error;
    } finally {
      finishStreamingSession(session);
    }
    notifySessionListeners();
  }

  /// Finalize: generate the course JSON from the conversation, then ask the
  /// AI to explain it in plain language.
  Future<void> finalizeGeneration({
    required AiEngineConfig config,
    required AiCourseSpec spec,
  }) async {
    final session = beginStreamingSession();
    _error = null;
    _state = AiWishState.generating;
    notifySessionListeners();
    try {
      final groundedContext = await _loadGroundedContext(spec);
      final applied = _service.applyGenreToSpec(spec);
      final generationPrompt =
          buildPrompt(applied, groundedContext: groundedContext);
      final result = await _engine.requestJson(
        config: config,
        messages: <Map<String, dynamic>>[
          {
            'role': 'system',
            'content':
                'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences. '
                    'The conversation history below captures the teacher\'s requirements. '
                    'Generate the final course JSON based on those requirements.',
          },
          ..._messages.map((m) => m.toApiDict()),
          {'role': 'user', 'content': generationPrompt},
        ],
        temperature: 0.4,
        timeout: const Duration(seconds: 180),
        cancelToken: session.cancelToken,
      );
      if (!isCurrentSession(session)) return;
      final course = _service.parseCompletion(result.body);
      _generatedJson = course.rawJson;
      _generatedSectionId = course.parsed['id'] as String?;
      _state = AiWishState.explaining;
      notifySessionListeners();
      try {
        final explanation = await explainGeneratedCourse(
          engine: _engine,
          config: config,
          spec: spec,
          sectionJson: course.parsed,
          cancelToken: session.cancelToken,
        );
        if (isCurrentSession(session)) _explanation = explanation;
      } catch (e) {
        logger.w('AiWishProvider.explain failed: $e');
        if (isCurrentSession(session)) _explanation = null;
      }
      if (!isCurrentSession(session)) return;
      _state = AiWishState.generated;
      recordAiRecentTask(
        kind: AiTaskKind.wish,
        summary: '${spec.topic} · ${spec.level}',
        route: AiRecentTaskRoute.wishChat,
      );
    } on AiCancelled {
      if (!isCurrentSession(session)) return;
      _state = AiWishState.idle;
    } catch (e) {
      if (!isCurrentSession(session)) return;
      logger.w('AiWishProvider.finalizeGeneration failed: $e');
      _error = AiErrorMapper.map(e).message;
      _state = AiWishState.error;
    } finally {
      finishStreamingSession(session);
    }
    notifySessionListeners();
  }

  /// Loads existing resources when [spec.groundedMode] is enabled. Returns
  /// `null` when grounding is off or no resources are available.
  Future<String?> _loadGroundedContext(AiCourseSpec spec) async {
    if (!spec.groundedMode) return null;
    await _groundedProvider.load(scope: spec.resourceScope);
    if (_groundedProvider.error != null) {
      logger
          .w('AiWishProvider grounded load failed: ${_groundedProvider.error}');
      return null;
    }
    return _groundedProvider.formatContext(
      maxResources: spec.maxGroundedResources,
    );
  }
}
