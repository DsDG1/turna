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
      throw Exception('API 配置不完整，请填写 Base URL / API Key / Model。');
    }

    final uri = Uri.parse(config.chatCompletionsUrl);
    final payloadObj = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': temperature,
    };
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
      throw Exception('网络错误: $e');
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
      throw Exception('无法解析 API 响应: $e');
    }
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
        throw Exception('无法解析 API 响应 JSON: $e');
      }
    } else {
      throw Exception('无法解析 API 响应: 非预期类型');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('API 返回的 choices 为空。');
    }
    final message = (choices.first as Map)['message'] as Map;
    final content = (message['content'] as String?) ?? '';
    final cleaned = _stripCodeFences(content.trim());
    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('无法解析模型输出的 JSON: $e\n原始内容前 200 字: ${cleaned.substring(0, cleaned.length < 200 ? cleaned.length : 200)}');
    }
    if (parsed['units'] is! List) {
      throw Exception("模型输出缺少顶层 'units' 数组。");
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
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences.',
      },
      {'role': 'user', 'content': buildPrompt(spec)},
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
    Duration timeout = const Duration(seconds: 120),
    int maxRetries = 1,
  }) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a language-course authoring assistant. You output ONLY valid JSON, no prose, no markdown fences.',
      },
      {'role': 'user', 'content': buildPrompt(spec)},
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
          '上一版有以下校验错误，请修正后只输出完整的修正 JSON：\n- ${errors.join('\n- ')}';
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

  /// Get a plain-language alignment reply from the AI (wish mode).
  Future<String> requestAlignmentReply({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required List<AiChatMessage> messages,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': buildAlignmentPrompt(spec)},
      for (final m in messages) m.toApiDict(),
    ];
    final body = await requestChat(
      config: config,
      messages: apiMessages,
      temperature: 0.7,
      timeout: timeout,
    );
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('API 返回的 choices 为空。');
    }
    final content = ((choices.first as Map)['message'] as Map)['content'];
    return (content as String? ?? '').trim();
  }

  /// Generate the final course section JSON from wish-mode conversation
  /// history. If [draftJson] is provided, it is included as context.
  Future<AiGeneratedCourse> generateFromChat({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required List<AiChatMessage> messages,
    Map<String, dynamic>? draftJson,
    Duration timeout = const Duration(seconds: 180),
  }) async {
    var generationPrompt = buildPrompt(spec);
    if (draftJson != null) {
      generationPrompt +=
          '\n\n以下是目前已生成的课程草稿，请根据对话中的修改意见进行调整，'
          '返回完整的新的课程 JSON（不要只返回 diff）。\n\n'
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

  /// Ask the AI to explain the generated course in plain language.
  Future<String> explainCourse({
    required AiApiConfig config,
    required AiCourseSpec spec,
    required Map<String, dynamic> sectionJson,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final prompt =
        '你刚刚为一位没有技术背景的教师生成了以下课程。'
        '请用通俗易懂的中文简要解释这门课的教学目标、单元划分、重点词汇/句型，'
        '以及为什么这样设计。不要输出 JSON 或代码。\n\n'
        '课程语言：${spec.language}\n'
        '提示语言：${spec.sourceLanguage}\n'
        '等级：${spec.level}\n'
        '课程名称：${sectionJson['name'] ?? ''}\n'
        '课程描述：${sectionJson['description'] ?? ''}\n';
    final apiMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '你是语言课程设计助手，用中文通俗解释课程内容。',
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
    if (choices is! List || choices.isEmpty) return '（AI 未返回解释）';
    final content = ((choices.first as Map)['message'] as Map)['content'];
    return (content as String? ?? '').trim();
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