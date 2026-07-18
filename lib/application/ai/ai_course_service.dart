// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_genre.dart';
import 'package:varnamala/application/ai/ai_prompt_builder.dart';
import 'package:varnamala/application/ai/ai_resource_consistency.dart';
import 'package:varnamala/core/logger.dart';

/// Signature of a section validator used by [AiCourseService.requestCourseWithRetry].
/// Returns a list of human-readable error strings (empty == valid).
typedef AiSectionValidator = List<String> Function(Map<String, dynamic> section);

/// Calls an OpenAI-compatible `/chat/completions` endpoint and parses the
/// returned Varnamala course JSON. Mirrors
/// `tool/gui/src/backend/ai_generator.py`.
class AiCourseService {
  const AiCourseService({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// Sends a chat completion request and returns the parsed JSON body.
  ///
  /// [messages] must already include the system prompt if needed.
  Future<Map<String, dynamic>> requestChat({
    required AiApiConfig config,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.7,
    Map<String, String>? responseFormat,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!config.isComplete) {
      throw Exception(
          'AI config incomplete: please fill in Base URL / API Key / Model.');
    }

    final uri = Uri.parse(config.chatCompletionsUrl);
    final payloadObj = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': temperature,
    };
    // Reasoning controls, gated on the endpoint's declared capability
    // (config.supportsReasoning, defaulting to the DeepSeek host check — see
    // AiApiConfig.reasoningEnabled). Other OpenAI-compatible endpoints (OpenAI,
    // Ollama, Moonshot) reject or ignore `reasoning_effort`/`thinking`, and
    // some return an error for unknown fields. For reasoning-capable
    // endpoints, reasoning output is returned in a separate
    // `reasoning_content` field and never leaks into `message.content`, so
    // JSON-course-generation parsing is unaffected.
    if (config.reasoningEnabled) {
      payloadObj['reasoning_effort'] = 'high';
      payloadObj['thinking'] = const {'type': 'enabled'};
    }
    if (responseFormat != null) {
      payloadObj['response_format'] = responseFormat;
    }
    final body = jsonEncode(payloadObj);

    final http.Response res;
    try {
      if (_client != null) {
        res = await _client
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${config.apiKey}',
              },
              body: body,
            )
            .timeout(timeout);
      } else {
        res = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${config.apiKey}',
              },
              body: body,
            )
            .timeout(timeout);
      }
    } catch (e) {
      logger.w('AiCourseService network error: $e');
      throw Exception('Network error: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final detail = _truncate(res.body);
      logger.w('AiCourseService HTTP ${res.statusCode}: $detail');
      throw Exception('HTTP ${res.statusCode}: $detail');
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      logger.w('AiCourseService parse error: $e');
      throw Exception('Could not parse AI response: $e');
    }
  }

  /// Extract the assistant's reply text from an OpenAI-compatible chat
  /// completion response body. Guards against malformed shapes (missing
  /// `choices`, a null `message`, or `content` that is not a plain string
  /// — e.g. a multimodal array or a rate-limit payload) by throwing a
  /// user-facing error instead of a raw `TypeError`.
  ///
  /// Shared by [requestTextReply] and [requestAlignmentReply] so the two
  /// paths can't drift apart on a response-format change.
  String extractAssistantText(Map<String, dynamic> body) {
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('AI response choices is empty.');
    }
    // Check `is Map` rather than `as Map?` so a malformed first element that
    // is neither null nor a Map (e.g. `{"choices":[42]}`) throws the friendly
    // error below instead of a raw `TypeError` at the cast.
    final first = choices.first;
    if (first is! Map) {
      throw Exception('AI response message is empty or malformed.');
    }
    final message = first['message'];
    if (message is! Map) {
      throw Exception('AI response message is empty or malformed.');
    }
    final content = message['content'];
    if (content is! String) {
      throw Exception('AI response content is empty or malformed.');
    }
    return content.trim();
  }

  /// Parse an OpenAI-compatible chat completion response body into the
  /// decoded course JSON dict. Runs resource normalization, auto-fix and
  /// self-consistency checks.
  AiGeneratedCourse parseCompletion(dynamic body) {
    Map<String, dynamic> decoded;
    if (body is Map<String, dynamic>) {
      decoded = body;
    } else if (body is String) {
      try {
        decoded = jsonDecode(body) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Could not parse AI response JSON: $e');
      }
    } else {
      throw Exception('Could not parse AI response: unexpected type');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('AI response choices is empty.');
    }
    final message = (choices.first as Map)['message'] as Map;
    final content = (message['content'] as String?) ?? '';
    final cleaned = _stripCodeFences(content.trim());
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Could not parse model JSON output: $e\nFirst 200 chars: ${cleaned.substring(0, cleaned.length < 200 ? cleaned.length : 200)}');
    }
    if (parsed['units'] is! List) {
      throw Exception("Model output is missing the top-level 'units' array.");
    }
    normalizeResources(parsed);
    autoFixResources(parsed);
    checkResourceSelfConsistency(parsed);
    return AiGeneratedCourse(rawJson: cleaned, parsed: parsed);
  }

  /// Single-shot course generation (normal mode).
  Future<AiGeneratedCourse> requestCourse({
    required AiApiConfig config,
    required AiCourseSpec spec,
    String? groundedContext,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences.',
      },
      {'role': 'user', 'content': buildPrompt(spec, groundedContext: groundedContext)},
    ];
    final body = await requestChat(
      config: config,
      messages: messages,
      temperature: 0.4,
      responseFormat: {'type': 'json_object'},
      timeout: timeout,
    );
    return parseCompletion(body);
  }

  /// Generate a course and, if [validator] returns error strings, re-prompt
  /// the model with those errors once (C3 self-heal). Mirrors
  /// `request_course_with_retry`.
  Future<AiGeneratedCourse> requestCourseWithRetry({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required AiSectionValidator validator,
    String? groundedContext,
    Duration timeout = const Duration(seconds: 120),
    int maxRetries = 1,
  }) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences.',
      },
      {'role': 'user', 'content': buildPrompt(spec, groundedContext: groundedContext)},
    ];
    var result = parseCompletion(
      await requestChat(
        config: config,
        messages: messages,
        temperature: 0.4,
        responseFormat: {'type': 'json_object'},
        timeout: timeout,
      ),
    );
    for (var i = 0; i < maxRetries; i++) {
      final errors = validator(result.parsed);
      if (errors.isEmpty) break;
      final correction =
          'The previous version has the following validation errors. Fix them and output only the complete corrected JSON:\n- ${errors.join('\n- ')}';
      messages.add({
        'role': 'assistant',
        'content': jsonEncode(result.parsed),
      });
      messages.add({'role': 'user', 'content': correction});
      result = parseCompletion(
        await requestChat(
          config: config,
          messages: messages,
          temperature: 0.2,
          responseFormat: {'type': 'json_object'},
          timeout: timeout,
        ),
      );
    }
    return result;
  }

  /// Generic plain-text chat. [systemPrompt] sets the assistant persona;
  /// [messages] is the conversation history (role/content dicts). Returns the
  /// assistant's reply text (trimmed). Used by the in-lesson AI hint assistant
  /// which has no [AiCourseSpec] to bind to.
  Future<String> requestTextReply({
    required AiApiConfig config,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    double temperature = 0.5,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = await requestChat(
      config: config,
      messages: <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
      temperature: temperature,
      timeout: timeout,
    );
    return extractAssistantText(body);
  }

  /// Get a plain-language alignment reply from the AI (wish mode).
  Future<String> requestAlignmentReply({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required List<AiChatMessage> messages,
    String? groundedContext,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': buildAlignmentPrompt(spec, groundedContext: groundedContext)},
      for (final m in messages) m.toApiDict(),
    ];
    final body = await requestChat(
      config: config,
      messages: apiMessages,
      temperature: 0.7,
      timeout: timeout,
    );
    return extractAssistantText(body);
  }

  /// Generate the final course section JSON from wish-mode conversation
  /// history. If [draftJson] is provided, it is included as context.
  Future<AiGeneratedCourse> generateFromChat({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required List<AiChatMessage> messages,
    Map<String, dynamic>? draftJson,
    String? groundedContext,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    var generationPrompt = buildPrompt(spec, groundedContext: groundedContext);
    if (draftJson != null) {
      generationPrompt +=
          '\n\nBelow is the current course draft. Adjust it according to the '
          'changes discussed in the conversation and return the complete new '
          'course JSON (do not return only a diff).\n\n'
          '```json\n${jsonEncode(draftJson)}\n```';
    }
    final apiMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences. '
            'The conversation history below captures the teacher\'s requirements. '
            'Generate the final course JSON based on those requirements.',
      },
      for (final m in messages) m.toApiDict(),
      {'role': 'user', 'content': generationPrompt},
    ];
    final body = await requestChat(
      config: config,
      messages: apiMessages,
      temperature: 0.4,
      responseFormat: {'type': 'json_object'},
      timeout: timeout,
    );
    return parseCompletion(body);
  }

  /// Ask the AI to transform a single lesson according to [instruction].
  /// Returns the parsed lesson JSON. The caller is responsible for validating
  /// and persisting it.
  Future<AiGeneratedCourse> requestLessonTransform({
    required AiApiConfig config,
    required Map<String, dynamic> lessonJson,
    required String instruction,
    required Set<String> resourceIds,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences. '
            'You modify lesson content according to the teacher\'s instruction. '
            'Preserve all existing IDs. Only create new IDs for genuinely new content.',
      },
      {
        'role': 'user',
        'content': buildLessonTransformPrompt(
          lessonJson: lessonJson,
          instruction: instruction,
          resourceIds: resourceIds,
        ),
      },
    ];
    final body = await requestChat(
      config: config,
      messages: messages,
      temperature: 0.4,
      responseFormat: {'type': 'json_object'},
      timeout: timeout,
    );
    return parseCompletion(body);
  }

  /// Extract teachable knowledge points from a textbook chapter. Returns the
  /// parsed JSON body; callers coerce it into [KnowledgePoints].
  Future<Map<String, dynamic>> requestKnowledgeExtraction({
    required AiApiConfig config,
    required List<Map<String, String>> messages,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final body = await requestChat(
      config: config,
      messages: messages,
      temperature: 0.4,
      responseFormat: {'type': 'json_object'},
      timeout: timeout,
    );
    return parseCompletion(body).parsed;
  }

  Future<String> explainCourse({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required Map<String, dynamic> sectionJson,
    Duration timeout = const Duration(seconds: 120),
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
    final apiMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course design assistant who explains course '
            'content in plain ${spec.sourceLanguage}.',
      },
      {'role': 'user', 'content': prompt},
    ];
    final body = await requestChat(
      config: config,
      messages: apiMessages,
      temperature: 0.6,
      timeout: timeout,
    );
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return '(AI returned no explanation)';
    return extractAssistantText(body);
  }

  /// If a genre tag is present and batch mode is on, update the spec template.
  AiCourseSpec applyGenreToSpec(AiCourseSpec spec) {
    if (!spec.useGenreBatch) return spec;
    final tag = detectGenreFromSpec(
      topic: spec.topic,
      extraInstructions: spec.extraInstructions,
    );
    if (tag != null) {
      return spec.copyWith(template: genreToTemplate(tag));
    }
    return spec;
  }

  String _stripCodeFences(String s) {
    if (s.startsWith('```')) {
      final firstNewline = s.indexOf('\n');
      if (firstNewline >= 0) s = s.substring(firstNewline + 1);
      if (s.endsWith('```')) {
        s = s.substring(0, s.length - 3);
      }
    }
    return s.trim();
  }

  String _truncate(String s, [int n = 300]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}