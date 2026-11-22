// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/application/ai/practice/ai_practice_generator.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/application/ai/practice/ai_practice_quality.dart';
import 'package:turna/domain/ai/ai_course.dart';

AiEngineConfig _config() => const AiEngineConfig(
      preset: kCustomPreset,
      apiKey: 'k',
      modelChat: 'm',
      modelJson: 'm',
      customBaseUrl: 'https://example.test/v1',
      cacheEnabled: false,
    );

http.Response _jsonChatResponse(
  String content, {
  String finishReason = 'stop',
}) {
  final body = jsonEncode({
    'choices': [
      {
        'finish_reason': finishReason,
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

AiPracticeGenerator _generator(http.Client client) => AiPracticeGenerator(
      AiEngine(
        AiHttpClient.withClient(client),
        AiCache.forTest(maxEntries: 0, enabled: false),
      ),
      AiGroundedResourceProvider.detached(),
    );

AiPracticeRequest _request({
  int unitCount = 1,
  int lessonsPerUnit = 2,
  String template = 'mixed',
  Map<String, dynamic>? approvedOutline,
}) =>
    AiPracticeRequest(
      id: 'ai-sec-1',
      title: 'Coffee Shop',
      source: AiPracticeSource.custom,
      languageCode: 'tr',
      approvedOutline: approvedOutline,
      spec: AiCourseSpec(
        language: 'Turkish',
        sourceLanguage: 'Chinese',
        topic: 'Coffee Shop',
        level: 'A1',
        unitCount: unitCount,
        lessonsPerUnit: lessonsPerUnit,
        template: template,
        groundedMode: false,
      ),
    );

Map<String, dynamic> _validOutline() => {
      'id': 'ai-sec-1',
      'name': 'Coffee Shop',
      'description': 'Ordering drinks',
      'words': [
        {'id': 'w1', 'term': 'çay', 'translation': '茶'},
        {'id': 'w2', 'term': 'kahve', 'translation': '咖啡'},
      ],
      'expressions': const <dynamic>[],
      'grammarPoints': const <dynamic>[],
      'units': [
        {
          'id': 'u1',
          'name': 'Unit 1',
          'lessons': [
            {
              'id': 'l1',
              'name': 'Lesson 1',
              'template': 'intro',
              'targetWordIds': ['w1'],
            },
            {
              'id': 'l2',
              'name': 'Lesson 2',
              'template': 'mastery',
              'targetWordIds': ['w2'],
            },
          ],
        },
      ],
    };

Map<String, dynamic> _validLessonBody({
  required String id,
  required String template,
  required String term,
}) {
  final items = [
    {
      'runtimeType': 'multipleChoice',
      'id': '$id-q1',
      'prompt': 'What does $term mean?',
      'options': ['茶', '水', '面包', '咖啡'],
      'correctIndex': term == 'çay' ? 0 : 3,
    },
    {
      'runtimeType': 'fillBlank',
      'id': '$id-q2',
      'sentence': 'Bir ____ lütfen.',
      'answer': term,
    },
    {
      'runtimeType': 'multipleChoice',
      'id': '$id-q3',
      'prompt': 'Choose $term',
      'options': [term, 'su', 'ekmek', 'süt'],
      'correctIndex': 0,
    },
    {
      'runtimeType': 'translateSentence',
      'id': '$id-q4',
      'source': '请来一杯$term',
      'expected': 'Bir $term lütfen',
    },
  ];
  if (template == 'intro' || template == 'practice') {
    return {
      'id': id,
      'name': 'Lesson $id',
      'template': template,
      'content': {
        'subLessons': [
          {
            'id': '$id-sub1',
            'name': 'Part 1',
            'stages': [
              {'id': '$id-st1', 'name': 'Stage 1', 'items': items},
            ],
          },
        ],
      },
    };
  }
  return {
    'id': id,
    'name': 'Lesson $id',
    'template': template,
    'content': {
      'stages': [
        {'id': '$id-st1', 'name': 'Stage 1', 'items': items},
      ],
    },
  };
}

void main() {
  test('generateOutline recovers from malformed JSON on repair retry',
      () async {
    var calls = 0;
    final temperatures = <double>[];
    final client = MockClient((req) async {
      calls++;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (body['temperature'] is num) {
        temperatures.add((body['temperature'] as num).toDouble());
      }
      if (calls == 1) {
        // Malformed JSON triggers FormatException inside repair loop.
        return _jsonChatResponse('not valid json {{{');
      }
      return _jsonChatResponse(
        '<think>fixing syntax</think>\n${jsonEncode(_validOutline())}',
      );
    });

    final gen = _generator(client);
    final outline = await gen.generateOutline(
      config: _config(),
      request: _request(),
      cancelToken: AiCancelToken(),
    );

    expect(calls, 2);
    expect(temperatures.length, 2);
    expect(temperatures[1], lessThan(temperatures[0]));
    expect(outline['id'], 'ai-sec-1');
    expect((outline['units'] as List), hasLength(1));
  });

  test('generate resumes from checkpoint and skips already completed lessons',
      () async {
    final requestedLessons = <String>[];
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      final prompt = (messages.last as Map)['content'] as String;
      if (prompt.contains('"l2"') || prompt.contains('l2')) {
        requestedLessons.add('l2');
        return _jsonChatResponse(
          jsonEncode(
              _validLessonBody(id: 'l2', template: 'mastery', term: 'kahve')),
        );
      }
      requestedLessons.add('unexpected');
      return _jsonChatResponse(
        jsonEncode(_validLessonBody(id: 'l1', template: 'intro', term: 'çay')),
      );
    });

    // Pretend l1 was already filled and persisted in a checkpoint.
    final partialSection = {
      ..._validOutline(),
      'units': [
        {
          'id': 'u1',
          'name': 'Unit 1',
          'lessons': [
            _validLessonBody(id: 'l1', template: 'intro', term: 'çay'),
            {
              'id': 'l2',
              'name': 'Lesson 2',
              'template': 'mastery',
              'targetWordIds': ['w2'],
              'content': {'stages': <dynamic>[]},
            },
          ],
        },
      ],
    };

    final checkpoints = <Set<String>>[];
    final gen = _generator(client);
    final result = await gen.generate(
      config: _config(),
      request: _request(),
      cancelToken: AiCancelToken(),
      onProgress: (_) {},
      resumeSection: partialSection,
      completedLessonIds: const {'l1'},
      onCheckpoint: (_, completed) => checkpoints.add(Set.of(completed)),
    );

    // Only l2 should have been requested from the LLM; l1 came from checkpoint!
    expect(requestedLessons, ['l2']);
    expect(checkpoints, isNotEmpty);
    expect(checkpoints.last, containsAll(['l1', 'l2']));
    final resumeQuality = AiPracticeQualityReport.tryParse(result.qualityJson)!;
    expect(resumeQuality.passed, isTrue,
        reason: resumeQuality.blockingMessages.join(' | '));
  });

  test('generate recovers automatically from truncated lesson output',
      () async {
    var lessonCalls = 0;
    final client = MockClient((req) async {
      lessonCalls++;
      if (lessonCalls == 1) {
        return _jsonChatResponse('{"id":"l1","content":{"stages":[',
            finishReason: 'length');
      }
      return _jsonChatResponse(
        jsonEncode(
            _validLessonBody(id: 'l1', template: 'mastery', term: 'çay')),
      );
    });

    final singleOutline = {
      ..._validOutline(),
      'units': [
        {
          'id': 'u1',
          'name': 'Unit 1',
          'lessons': [
            {
              'id': 'l1',
              'name': 'Lesson 1',
              'template': 'mastery',
              'targetWordIds': ['w1'],
            },
          ],
        },
      ],
    };

    final gen = _generator(client);
    final result = await gen.generate(
      config: _config(),
      request: _request(unitCount: 1, lessonsPerUnit: 1, template: 'mastery'),
      cancelToken: AiCancelToken(),
      onProgress: (_) {},
      approvedOutline: singleOutline,
    );

    expect(lessonCalls, 2);
    final truncQuality = AiPracticeQualityReport.tryParse(result.qualityJson)!;
    expect(truncQuality.passed, isTrue);
  });

  test('regenerateLesson replaces only the targeted lesson', () async {
    final client = MockClient((req) async {
      final regenerated = _validLessonBody(
        id: 'l2',
        template: 'mastery',
        term: 'kahve',
      );
      regenerated['name'] = 'Lesson 2 Refreshed';
      return _jsonChatResponse(jsonEncode(regenerated));
    });

    final currentSection = {
      ..._validOutline(),
      'units': [
        {
          'id': 'u1',
          'name': 'Unit 1',
          'lessons': [
            _validLessonBody(id: 'l1', template: 'intro', term: 'çay'),
            _validLessonBody(id: 'l2', template: 'mastery', term: 'kahve'),
          ],
        },
      ],
    };

    final gen = _generator(client);
    final updated = await gen.regenerateLesson(
      config: _config(),
      request: _request(),
      currentSection: currentSection,
      lessonId: 'l2',
      cancelToken: AiCancelToken(),
    );

    final lessons =
        ((updated.section['units'] as List).first as Map)['lessons'] as List;
    expect((lessons[0] as Map)['name'], 'Lesson l1');
    expect((lessons[1] as Map)['name'], 'Lesson 2 Refreshed');
    final regenQuality = AiPracticeQualityReport.tryParse(updated.qualityJson)!;
    expect(regenQuality.passed, isTrue);
  });
}
