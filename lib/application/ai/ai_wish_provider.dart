// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_grounded_resource_provider.dart';
import 'package:varnamala/core/logger.dart';

/// State machine for wish-mode conversation.
enum AiWishState { idle, aligning, generating, explaining, generated, error }

/// Provider backing the wish-mode chat page. Holds the conversation history
/// and orchestrates alignment → finalize-generation → explain.
///
/// The [AiApiConfig] is shared with [AiCourseProvider]; the chat page reads it
/// from the main provider and passes it here.
class AiWishProvider extends ChangeNotifier {
  AiWishProvider({http.Client? client, AiGroundedResourceProvider? groundedProvider})
      : _service = AiCourseService(client: client),
        _groundedProvider = groundedProvider ?? AiGroundedResourceProvider();
  AiWishProvider.withService(this._service, {AiGroundedResourceProvider? groundedProvider})
      : _groundedProvider = groundedProvider ?? AiGroundedResourceProvider();

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
    _messages.clear();
    _state = AiWishState.idle;
    _error = null;
    _generatedJson = null;
    _explanation = null;
    _generatedSectionId = null;
    notifyListeners();
  }

  /// Send a user alignment message and append the assistant reply.
  Future<void> sendAlignment({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required String userText,
  }) async {
    if (userText.trim().isEmpty) return;
    _error = null;
    _state = AiWishState.aligning;
    _messages.add(AiChatMessage(role: 'user', content: userText));
    notifyListeners();
    try {
      final groundedContext = await _loadGroundedContext(spec);
      final reply = await _service.requestAlignmentReply(
        config: config,
        spec: spec,
        messages: _messages,
        groundedContext: groundedContext,
      );
      _messages.add(AiChatMessage(role: 'assistant', content: reply));
      _state = AiWishState.idle;
    } catch (e) {
      logger.w('AiWishProvider.sendAlignment failed: $e');
      _error = e.toString();
      _state = AiWishState.error;
    }
    notifyListeners();
  }

  /// Finalize: generate the course JSON from the conversation, then ask the
  /// AI to explain it in plain language.
  Future<void> finalizeGeneration({
    required AiApiConfig config,
    required AiCourseSpec spec,
  }) async {
    _error = null;
    _state = AiWishState.generating;
    notifyListeners();
    try {
      final groundedContext = await _loadGroundedContext(spec);
      final result = await _service.generateFromChat(
        config: config,
        spec: _service.applyGenreToSpec(spec),
        messages: _messages,
        groundedContext: groundedContext,
      );
      _generatedJson = result.rawJson;
      _generatedSectionId = result.parsed['id'] as String?;
      _state = AiWishState.explaining;
      notifyListeners();
      try {
        _explanation = await _service.explainCourse(
          config: config,
          spec: spec,
          sectionJson: result.parsed,
        );
      } catch (e) {
        logger.w('AiWishProvider.explain failed: $e');
        _explanation = null;
      }
      _state = AiWishState.generated;
    } catch (e) {
      logger.w('AiWishProvider.finalizeGeneration failed: $e');
      _error = e.toString();
      _state = AiWishState.error;
    }
    notifyListeners();
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
}