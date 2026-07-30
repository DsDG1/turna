// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Project imports:
import 'package:varnamala/application/ai/ai_course_service.dart';

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
    final service = AiCourseService();

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
    final service = AiCourseService();

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
}