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
}