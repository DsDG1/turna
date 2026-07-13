// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:varnamala/core/logger.dart';

/// In-memory only configuration for an OpenAI-compatible chat completions
/// endpoint. The fields are deliberately **not persisted** — they live in the
/// [AiCourseProvider] for the current session and are discarded on app exit.
class AiApiConfig {
  const AiApiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// Base URL of an OpenAI-compatible endpoint, e.g.
  /// `https://api.openai.com/v1` or `http://localhost:11434/v1`.
  final String baseUrl;

  /// Secret API key. Never logged or persisted.
  final String apiKey;

  /// Model id, e.g. `gpt-4o-mini`, `deepseek-chat`, `moonshot-v1-8k`.
  final String model;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  /// Normalized chat-completions URL. Strips any trailing slash on [baseUrl]
  /// and appends `/chat/completions` if the user only provided the base.
  String get chatCompletionsUrl {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  AiApiConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      AiApiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

/// Parameters describing the course the user wants the AI to author.
class AiCourseRequestSpec {
  const AiCourseRequestSpec({
    required this.language,
    required this.topic,
    required this.learnerLevel,
    required this.unitCount,
    required this.lessonsPerUnit,
    this.extraInstructions = '',
  });

  /// Target language to teach (e.g. "Turkish").
  final String language;

  /// Free-form topic / theme (e.g. "Travel vocabulary", "Past tense").
  final String topic;

  /// CEFR level hint (e.g. "A1", "A2", "B1").
  final String learnerLevel;

  /// How many units to generate.
  final int unitCount;

  /// How many lessons per unit to generate.
  final int lessonsPerUnit;

  /// Optional extra instructions appended to the prompt.
  final String extraInstructions;
}

/// A course JSON payload produced by the AI, already decoded into a
/// `Map<String, dynamic>` matching the Varnamala section file schema:
/// `{ "id", "name", "description", "units": [ { "id", "name", "lessons": [...] } ] }`.
class AiGeneratedCourse {
  const AiGeneratedCourse({required this.rawJson, required this.parsed});

  final String rawJson;
  final Map<String, dynamic> parsed;
}

/// Calls an OpenAI-compatible `/chat/completions` endpoint and parses the
/// returned Varnamala course JSON. The prompt instructs the model to output
/// strict JSON conforming to the bundled section-file schema.
class AiCourseService {
  const AiCourseService();

  /// Sends the authoring prompt to the configured endpoint and returns the
  /// decoded course JSON. Throws [Exception] with a human-readable message on
  /// network / HTTP / parse errors so the UI can surface it directly.
  Future<AiGeneratedCourse> generateCourse({
    required AiApiConfig config,
    required AiCourseRequestSpec spec,
  }) async {
    if (!config.isComplete) {
      throw Exception('API configuration is incomplete.');
    }

    final prompt = _buildPrompt(spec);
    final uri = Uri.parse(config.chatCompletionsUrl);

    final http.Response res;
    try {
      res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode({
          'model': config.model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a language-course authoring assistant. You output '
                  'ONLY valid JSON, no prose, no markdown fences.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.4,
          'response_format': {'type': 'json_object'},
        }),
      ).timeout(const Duration(seconds: 120));
    } catch (e) {
      logger.w('AiCourseService network error: $e');
      throw Exception('Network error: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = res.body;
      logger.w('AiCourseService HTTP ${res.statusCode}: $body');
      throw Exception('HTTP ${res.statusCode}: ${_truncate(body)}');
    }

    return _parseCompletion(res.body);
  }

  String _buildPrompt(AiCourseRequestSpec spec) {
    final lessonsPerUnit = spec.lessonsPerUnit;
    final unitCount = spec.unitCount;
    return '''
Generate a language learning course section as JSON.

Target language: ${spec.language}
Topic / theme: ${spec.topic}
Learner level: ${spec.learnerLevel}
Units: $unitCount, each with $lessonsPerUnit lessons.
${spec.extraInstructions.isNotEmpty ? 'Extra instructions: ${spec.extraInstructions}\n' : ''}

Return STRICT JSON only (no markdown, no code fences) with EXACTLY this shape:

{
  "id": "<sectionId e.g. ai-travel>",
  "name": "<Section name>",
  "description": "<short description>",
  "units": [
    {
      "id": "<unitId e.g. ai-travel-u1>",
      "name": "<Unit name>",
      "description": "",
      "prerequisiteUnitIds": [],
      "lessons": [
        {
          "id": "<lessonId e.g. ai-travel-u1-l1>",
          "name": "<Lesson name>",
          "description": "",
          "type": "normal",
          "template": "legacy",
          "prerequisiteLessonIds": [],
          "content": {
            "stages": [
              {
                "id": "<stageId>",
                "name": "<stage name>",
                "items": [
                  { "runtimeType": "showWord", "id": "<id>", "wordId": "<wordId>" },
                  { "runtimeType": "multipleChoice", "id": "<id>", "prompt": "<prompt in ${spec.language}>", "options": ["<opt1>","<opt2>","<opt3>","<opt4>"], "correctIndex": 0 },
                  { "runtimeType": "fillBlank", "id": "<id>", "sentence": "<sentence with ____ blank, in ${spec.language}>", "answer": "<answer>", "hint": "<hint>" },
                  { "runtimeType": "translateSentence", "id": "<id>", "source": "<English sentence>", "expected": "<${spec.language} translation>", "hints": ["<hint>"] }
                ]
              }
            ]
          }
        }
      ]
    }
  ]
}

Rules:
1. Every id MUST be unique across the whole course and use a stable lowercase kebab-case string prefixed with "ai-".
2. Every lesson MUST have at least one stage with at least 3 items.
3. Multiple choice items: exactly 4 options, correctIndex in 0..3.
4. translateSentence: source in English, expected in ${spec.language}.
5. fillBlank: sentence in ${spec.language} with a single ____ blank; answer is the missing word.
6. Do NOT include "questions"; use "stages".
7. Output JSON object only — no surrounding text.
''';
  }

  AiGeneratedCourse _parseCompletion(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List;
      if (choices.isEmpty) {
        throw Exception('AI returned no choices.');
      }
      final msg =
          (choices.first as Map<String, dynamic>)['message'] as Map;
      final content = msg['content'] as String? ?? '';
      final cleaned = _stripCodeFences(content.trim());
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      if (parsed['units'] is! List) {
        throw Exception('AI JSON missing "units" array.');
      }
      return AiGeneratedCourse(rawJson: cleaned, parsed: parsed);
    } catch (e) {
      logger.w('AiCourseService parse error: $e');
      throw Exception('Failed to parse AI response: $e');
    }
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

  String _truncate(String s, [int n = 200]) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}