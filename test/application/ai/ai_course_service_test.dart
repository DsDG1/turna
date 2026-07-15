// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';

http.Response _chatResponse(String content) {
  final body = jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content},
      },
    ],
  });
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Map<String, dynamic> _validSectionJson() {
  return {
    'id': 'ai-topic',
    'name': 'Topic',
    'description': '',
    'words': [
      {'id': 'w-merhaba', 'term': 'Merhaba', 'translation': '你好'},
    ],
    'expressions': [],
    'grammarPoints': [],
    'units': [
      {
        'id': 'ai-topic-u1',
        'name': 'U1',
        'lessons': [
          {
            'id': 'ai-topic-u1-l1',
            'name': 'L1',
            'type': 'normal',
            'template': 'legacy',
            'content': {
              'stages': [
                {
                  'id': 'st1',
                  'items': [
                    {'runtimeType': 'showWord', 'id': 'i1', 'wordId': 'w-merhaba'},
                  ],
                },
              ],
            },
          },
        ],
      },
    ],
  };
}

void main() {
  group('AiCourseService.parseCompletion', () {
    final service = const AiCourseService();

    test('parses valid JSON with code fences', () {
      final body = _chatResponse(
        '```json\n${jsonEncode(_validSectionJson())}\n```',
      );
      final result = service.parseCompletion(body.body);
      expect(result.parsed['id'], 'ai-topic');
      expect(result.parsed['words'], isA<List>());
    });

    test('autoFixResources fills missing word stub then passes', () {
      final section = _validSectionJson();
      (section['words'] as List).clear();
      final body = _chatResponse(jsonEncode(section));
      final result = service.parseCompletion(body.body);
      final words = result.parsed['words'] as List;
      expect(words.length, 1);
      expect(words.first['id'], 'w-merhaba');
    });

    test('throws when choices empty', () {
      final body =
          http.Response.bytes(utf8.encode(jsonEncode({'choices': []})), 200);
      expect(
        () => service.parseCompletion(body.body),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when units missing', () {
      final body = _chatResponse(jsonEncode({'id': 'x'}));
      expect(
        () => service.parseCompletion(body.body),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AiCourseService.extractAssistantText', () {
    final service = const AiCourseService();

    test('returns trimmed content for a well-formed response', () {
      final body = jsonDecode(_chatResponse('  hello  ').body)
          as Map<String, dynamic>;
      expect(service.extractAssistantText(body), 'hello');
    });

    test('throws a user-facing error when choices is empty', () {
      expect(
        () => service.extractAssistantText({'choices': []}),
        throwsA(isA<Exception>()),
      );
    });

    test('throws a user-facing error when message is null', () {
      expect(
        () => service
            .extractAssistantText({'choices': [{'message': null}]}),
        throwsA(isA<Exception>()),
      );
    });

    test('throws a user-facing error when content is not a string', () {
      // Multimodal-style content array — must not crash with a TypeError.
      expect(
        () => service.extractAssistantText({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': [
                  {'type': 'text', 'text': 'hi'},
                ],
              },
            },
          ],
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('throws a user-facing error when the first choice is not a Map', () {
      // A malformed/stub payload like {"choices":[42]} must surface the
      // friendly Exception, not a raw TypeError from an `as Map?` cast.
      expect(
        () => service.extractAssistantText({'choices': [42]}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('AiCourseService.requestCourseWithRetry', () {
    test('retries once when validator reports errors', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        final section = _validSectionJson();
        // First call: break a unit id to trigger validation error.
        if (callCount == 1) {
          (section['units'] as List).first['id'] = '';
        }
        return _chatResponse(jsonEncode(section));
      });

      final service = AiCourseService(client: client);
      final config = const AiApiConfig(
        baseUrl: 'https://example.com/v1',
        apiKey: 'key',
        model: 'm',
      );
      final spec = const AiCourseSpec(
        language: 'Turkish',
        topic: 'Travel',
        level: 'A1',
        unitCount: 1,
        lessonsPerUnit: 1,
      );
      // Validator: empty unit id -> 1 error.
      List<String> validator(Map<String, dynamic> s) {
        final units = s['units'] as List;
        if (units.first['id'] == '') return ['empty unit id'];
        return [];
      }

      final result = await service.requestCourseWithRetry(
        config: config,
        spec: spec,
        validator: validator,
        maxRetries: 1,
      );
      expect(callCount, 2);
      expect(result.parsed['units'].first['id'], 'ai-topic-u1');
    });

    test('does not retry when validator passes', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return _chatResponse(jsonEncode(_validSectionJson()));
      });
      final service = AiCourseService(client: client);
      final config = const AiApiConfig(
        baseUrl: 'https://example.com/v1',
        apiKey: 'key',
        model: 'm',
      );
      final spec = const AiCourseSpec(
        language: 'Turkish',
        topic: 'Travel',
        level: 'A1',
        unitCount: 1,
        lessonsPerUnit: 1,
      );
      final result = await service.requestCourseWithRetry(
        config: config,
        spec: spec,
        validator: (_) => [],
        maxRetries: 1,
      );
      expect(callCount, 1);
      expect(result.parsed['id'], 'ai-topic');
    });
  });

  group('AiCourseService.requestChat reasoning payload', () {
    test('omits reasoning_effort/thinking for a non-DeepSeek endpoint', () async {
      final config = const AiApiConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'key',
        model: 'gpt-4o',
      );
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('reasoning_effort'), isFalse);
        expect(body.containsKey('thinking'), isFalse);
        return _chatResponse('ok');
      });
      final service = AiCourseService(client: client);
      await service.requestTextReply(
        config: config,
        systemPrompt: 's',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
    });

    test('includes reasoning_effort/thinking for a DeepSeek endpoint', () async {
      final config = const AiApiConfig(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'key',
        model: 'deepseek-v4-pro',
      );
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reasoning_effort'], 'high');
        expect(body['thinking'], {'type': 'enabled'});
        return _chatResponse('ok');
      });
      final service = AiCourseService(client: client);
      await service.requestTextReply(
        config: config,
        systemPrompt: 's',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
    });

    test(
        'supportsReasoning=true sends reasoning fields even on a non-DeepSeek host',
        () async {
      // A reasoning-capable endpoint behind a non-DeepSeek host: the declared
      // capability overrides the host inference (the host check would say no).
      final config = const AiApiConfig(
        baseUrl: 'https://my-proxy.example.com/v1',
        apiKey: 'key',
        model: 'some-reasoning-model',
        supportsReasoning: true,
      );
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['reasoning_effort'], 'high');
        expect(body['thinking'], {'type': 'enabled'});
        return _chatResponse('ok');
      });
      final service = AiCourseService(client: client);
      await service.requestTextReply(
        config: config,
        systemPrompt: 's',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
    });

    test(
        'supportsReasoning=false suppresses reasoning fields even on a DeepSeek host',
        () async {
      // Explicit opt-out for a DeepSeek-host endpoint that should not use
      // reasoning — the host check would say yes, but the flag wins.
      final config = const AiApiConfig(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'key',
        model: 'deepseek-v4-pro',
        supportsReasoning: false,
      );
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('reasoning_effort'), isFalse);
        expect(body.containsKey('thinking'), isFalse);
        return _chatResponse('ok');
      });
      final service = AiCourseService(client: client);
      await service.requestTextReply(
        config: config,
        systemPrompt: 's',
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
    });
  });

  group('AiApiConfig reasoning capability', () {
    test('isDeepSeekHost detects deepseek hosts', () {
      expect(isDeepSeekHost('https://api.deepseek.com'), isTrue);
      expect(isDeepSeekHost('https://api-cn.deepseek.com/v1'), isTrue);
      expect(isDeepSeekHost('https://api.openai.com/v1'), isFalse);
      expect(isDeepSeekHost('http://localhost:11434/v1'), isFalse);
    });

    test('reasoningEnabled falls back to host check when flag is null', () {
      const deepseek = AiApiConfig(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'k',
        model: 'm',
      );
      const openai = AiApiConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'k',
        model: 'm',
      );
      expect(deepseek.reasoningEnabled, isTrue);
      expect(openai.reasoningEnabled, isFalse);
    });

    test('reasoningEnabled honors an explicit supportsReasoning flag', () {
      const forced = AiApiConfig(
        baseUrl: 'https://my-proxy.example.com/v1',
        apiKey: 'k',
        model: 'm',
        supportsReasoning: true,
      );
      const suppressed = AiApiConfig(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'k',
        model: 'm',
        supportsReasoning: false,
      );
      expect(forced.reasoningEnabled, isTrue);
      expect(suppressed.reasoningEnabled, isFalse);
    });
  });
}