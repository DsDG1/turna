// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_grounded_resource_provider.dart';
import 'package:varnamala/application/ai/ai_prompt_builder.dart';
import 'package:varnamala/application/ai/engine/ai_cancel_token.dart';
import 'package:varnamala/application/ai/engine/ai_engine.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/routing/routing.gr.dart';

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
class AiWishProvider extends ChangeNotifier {
  AiWishProvider({AiEngine? engine, AiGroundedResourceProvider? groundedProvider})
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

  /// Active cancel token for the in-flight call, if any. Cancelled on
  /// [reset] / [cancel].
  AiCancelToken? _cancelToken;

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
    _cancelToken?.cancel();
    _cancelToken = null;
    _messages.clear();
    _state = AiWishState.idle;
    _error = null;
    _generatedJson = null;
    _explanation = null;
    _generatedSectionId = null;
    notifyListeners();
  }

  /// Cancel the in-flight call (if any) and return to idle, keeping the
  /// conversation history. A no-op when idle/generated.
  void cancel() {
    final active = _state == AiWishState.aligning ||
        _state == AiWishState.generating ||
        _state == AiWishState.explaining;
    if (!active) return;
    _cancelToken?.cancel();
    _cancelToken = null;
    _state = AiWishState.idle;
    notifyListeners();
  }

  /// Send a user alignment message and append the assistant reply.
  Future<void> sendAlignment({
    required AiEngineConfig config,
    required AiCourseSpec spec,
    required String userText,
  }) async {
    if (userText.trim().isEmpty) return;
    _cancelToken?.cancel();
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _state = AiWishState.aligning;
    _messages.add(AiChatMessage(role: 'user', content: userText));
    notifyListeners();
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
        cancelToken: token,
      );
      _messages.add(AiChatMessage(role: 'assistant', content: result.content));
      _state = AiWishState.idle;
    } on AiCancelled {
      _state = AiWishState.idle;
    } catch (e) {
      logger.w('AiWishProvider.sendAlignment failed: $e');
      _error = e.toString();
      _state = AiWishState.error;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    notifyListeners();
  }

  /// Finalize: generate the course JSON from the conversation, then ask the
  /// AI to explain it in plain language.
  Future<void> finalizeGeneration({
    required AiEngineConfig config,
    required AiCourseSpec spec,
  }) async {
    _cancelToken?.cancel();
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _state = AiWishState.generating;
    notifyListeners();
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
        cancelToken: token,
      );
      final course = _service.parseCompletion(result.body);
      _generatedJson = course.rawJson;
      _generatedSectionId = course.parsed['id'] as String?;
      _state = AiWishState.explaining;
      notifyListeners();
      try {
        _explanation = await _explainCourse(
          config: config,
          spec: spec,
          sectionJson: course.parsed,
          token: token,
        );
      } catch (e) {
        logger.w('AiWishProvider.explain failed: $e');
        _explanation = null;
      }
      _state = AiWishState.generated;
      _recordRecent(spec);
    } on AiCancelled {
      _state = AiWishState.idle;
    } catch (e) {
      logger.w('AiWishProvider.finalizeGeneration failed: $e');
      _error = e.toString();
      _state = AiWishState.error;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
    notifyListeners();
  }

  /// Plain-language explanation of a generated course (mirrors the former
  /// `AiCourseService.explainCourse` prompt, now routed through the engine).
  Future<String> _explainCourse({
    required AiEngineConfig config,
    required AiCourseSpec spec,
    required Map<String, dynamic> sectionJson,
    required AiCancelToken token,
  }) async {
    final prompt =
        'You just generated the following course for a teacher with no '
        'technical background. Please explain in plain, easy-to-understand '
        '${spec.sourceLanguage}: the course\'s learning objectives, how units '
        'are divided, the key vocabulary / sentence patterns, and why it is '
        'designed this way. Do not output JSON or code.\n\n'
        'Course language: ${spec.language}\n'
        'Prompt language: ${spec.sourceLanguage}\n'
        'Level: ${spec.level}\n'
        'Course name: ${sectionJson['name'] ?? ''}\n'
        'Course description: ${sectionJson['description'] ?? ''}\n';
    final result = await _engine.chat(
      config: config,
      messages: <Map<String, dynamic>>[
        {
          'role': 'system',
          'content':
              'You are a language-course design assistant who explains course '
              'content in plain ${spec.sourceLanguage}.',
        },
        {'role': 'user', 'content': prompt},
      ],
      temperature: 0.6,
      timeout: const Duration(seconds: 120),
      cancelToken: token,
    );
    final content = result.content;
    return content.isEmpty ? '(AI returned no explanation)' : content;
  }

  /// Loads existing resources when [spec.groundedMode] is enabled. Returns
  /// `null` when grounding is off or no resources are available.
  Future<String?> _loadGroundedContext(AiCourseSpec spec) async {
    if (!spec.groundedMode) return null;
    await _groundedProvider.load(scope: spec.resourceScope);
    if (_groundedProvider.error != null) {
      logger.w('AiWishProvider grounded load failed: ${_groundedProvider.error}');
      return null;
    }
    return _groundedProvider.formatContext(
      maxResources: spec.maxGroundedResources,
    );
  }

  /// Append a wish-generation task to the AI Hub's recent list. Called from
  /// the success branch of [finalizeGeneration].
  void _recordRecent(AiCourseSpec spec) {
    try {
      getIt<AiRecentTasksProvider>().record(
            AiRecentTask(
              kind: AiTaskKind.wish,
              summary: '${spec.topic} · ${spec.level}',
              timestamp: DateTime.now(),
              route: AiWishChatRoute.name,
            ),
          );
    } catch (_) {
      // Advisory only.
    }
  }
}
