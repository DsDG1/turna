// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_normalizer.dart';

void main() {
  group('AiPracticeNormalizer.decodeObject', () {
    test('strips <think> reasoning tags, code fences, and trailing commas', () {
      const raw = '''
<think>
Let me plan the JSON carefully...
</think>
Here is the output:
```json
{
  "id": "sec-1",
  "units": [1, 2,],
}
```
Hope this helps!
''';
      final decoded = AiPracticeNormalizer.decodeObject(raw);
      expect(decoded['id'], 'sec-1');
      expect(decoded['units'], [1, 2]);
    });

    test('handles braces inside string literals when scanning balanced object',
        () {
      const raw = 'Prefix {"text": "use {braces} safely", "ok": true} suffix';
      final decoded = AiPracticeNormalizer.decodeObject(raw);
      expect(decoded['text'], 'use {braces} safely');
      expect(decoded['ok'], isTrue);
    });
  });

  group('AiPracticeNormalizer.normalizeOutline', () {
    test('resolves mixed and unknown templates, deduplicates ids, prunes words',
        () {
      final raw = <String, dynamic>{
        'words': [
          {'id': 'w1', 'term': 'merhaba', 'translation': '你好'},
        ],
        'units': [
          {
            'id': 'u1',
            'name': 'Unit 1',
            'lessons': [
              {
                'id': 'l1',
                'name': 'L1',
                'template': 'mixed',
                'targetWordIds': ['w1', 'w-nonexistent'],
              },
              {
                'id': 'l1',
                'name': 'L2',
                'template': 'listening',
                'targetWordIds': ['w1'],
              },
              {
                'id': 'l3',
                'name': 'L3',
                'template': 'dialogue',
                'targetWordIds': ['w1'],
              },
            ],
          },
        ],
      };

      final normalized = AiPracticeNormalizer.normalizeOutline(
        raw,
        fallbackSectionId: 'ai-sec-1',
        fallbackTitle: 'Fallback',
        requestedTemplate: 'mixed',
      );
      expect(normalized['id'], 'ai-sec-1');
      final lessons =
          ((normalized['units'] as List).first as Map)['lessons'] as List;
      expect(lessons, hasLength(3));
      // No lesson keeps "mixed" or forbidden "listening".
      for (final lesson in lessons) {
        final tpl = (lesson as Map)['template'] as String;
        expect(AiPracticeNormalizer.allowedTemplates, contains(tpl));
      }
      // Duplicate id l1 was deduplicated.
      final ids = lessons.map((l) => (l as Map)['id']).toSet();
      expect(ids, hasLength(3));
      // Unknown word id pruned.
      expect((lessons.first as Map)['targetWordIds'], ['w1']);
      // Valid dialogue template preserved.
      expect((lessons[2] as Map)['template'], 'dialogue');
    });
  });

  group('AiPracticeNormalizer.normalizeLessonJson', () {
    test('wraps intro/practice flat stages into canonical subLessons', () {
      final lesson = AiPracticeNormalizer.normalizeLessonJson(
        {
          'content': {
            'stages': [
              {
                'id': 'st1',
                'name': 'Stage 1',
                'items': [
                  {
                    'runtimeType': 'multipleChoice',
                    'prompt': 'Pick',
                    'options': ['a', 'b', 'c', 'd'],
                    'correctIndex': 1,
                  },
                ],
              },
            ],
          },
        },
        lessonId: 'l-intro',
        template: 'intro',
      );
      final content = lesson['content'] as Map<String, dynamic>;
      expect(content.containsKey('subLessons'), isTrue);
      expect(content.containsKey('stages'), isFalse);
      final subLessons = content['subLessons'] as List;
      expect(subLessons, hasLength(1));
      expect((subLessons.first as Map)['stages'], hasLength(1));
    });

    test('collapses multiple stages in mastery into a single stage', () {
      final lesson = AiPracticeNormalizer.normalizeLessonJson(
        {
          'content': {
            'stages': [
              {
                'id': 'st1',
                'items': [
                  {
                    'runtimeType': 'multipleChoice',
                    'prompt': 'P1',
                    'options': ['a', 'b', 'c', 'd'],
                    'correctIndex': 0,
                  }
                ],
              },
              {
                'id': 'st2',
                'items': [
                  {
                    'runtimeType': 'multipleChoice',
                    'prompt': 'P2',
                    'options': ['x', 'y', 'z', 'w'],
                    'correctIndex': 2,
                  }
                ],
              },
            ],
          },
        },
        lessonId: 'l-mastery',
        template: 'mastery',
      );
      final stages = (lesson['content'] as Map)['stages'] as List;
      expect(stages, hasLength(1));
      expect((stages.first as Map)['items'], hasLength(2));
    });

    test('deduplicates multipleChoice options and preserves correct answer',
        () {
      final lesson = AiPracticeNormalizer.normalizeLessonJson(
        {
          'content': {
            'stages': [
              {
                'id': 'st1',
                'items': [
                  {
                    'runtimeType': 'multipleChoice',
                    'prompt': 'Pick',
                    'options': ['dup', 'dup', 'target', 'other'],
                    'correctIndex': 2,
                  },
                ],
              },
            ],
          },
        },
        lessonId: 'l-mcq',
        template: 'mastery',
      );
      final item =
          (((lesson['content'] as Map)['stages'] as List).first as Map)['items']
              .first as Map;
      expect(item['options'], ['dup', 'target', 'other']);
      expect(item['correctIndex'], 1);
    });

    test('auto-shuffles unscrambled reorderSentence and normalizes fillBlank',
        () {
      final lesson = AiPracticeNormalizer.normalizeLessonJson(
        {
          'content': {
            'stages': [
              {
                'id': 'st1',
                'items': [
                  {
                    'runtimeType': 'reorderSentence',
                    'prompt': 'Order it',
                    'scrambled': ['Ben', 'okula', 'gidiyorum'],
                    'correct': ['Ben', 'okula', 'gidiyorum'],
                  },
                  {
                    'runtimeType': 'fillBlank',
                    'sentence': 'Ben ___ gidiyorum.',
                    'answer': 'okula',
                  },
                ],
              },
            ],
          },
        },
        lessonId: 'l-norm',
        template: 'mastery',
      );
      final items = (((lesson['content'] as Map)['stages'] as List).first
          as Map)['items'] as List;
      final reorder = items[0] as Map;
      expect(reorder['scrambled'], isNot(equals(reorder['correct'])));
      expect(
        (reorder['scrambled'] as List).toSet(),
        equals((reorder['correct'] as List).toSet()),
      );

      final blank = items[1] as Map;
      expect(blank['sentence'], contains('____'));
    });

    test('normalizes guide lesson to pages without stages', () {
      final lesson = AiPracticeNormalizer.normalizeLessonJson(
        {
          'content': {
            'pages': [
              {'title': '规则 1', 'body': '元音和谐说明'},
            ],
            'stages': [
              {'id': 'should-be-removed', 'items': <dynamic>[]},
            ],
          },
        },
        lessonId: 'l-guide',
        template: 'guide',
      );
      final content = lesson['content'] as Map;
      expect(content['pages'], hasLength(1));
      expect(content.containsKey('stages'), isFalse);
    });

    test('normalizes dialogue lesson scene and strips forbidden item types',
        () {
      final lesson = AiPracticeNormalizer.normalizeLessonJson(
        {
          'content': {
            'dialogueScene': {
              'setting': '在伊斯坦布尔咖啡馆',
              'speakers': [
                {'id': 'waiter', 'name': '服务员'},
                {'id': 'learner', 'name': '你'},
              ],
            },
            'stages': [
              {
                'id': 'st1',
                'items': [
                  {
                    'runtimeType': 'listenAndPick',
                    'prompt': 'should be stripped',
                  },
                  {
                    'runtimeType': 'multipleChoice',
                    'prompt': '你想点什么？',
                    'options': ['Bir çay lütfen', 'Güle güle', 'Evet', 'Hayır'],
                    'correctIndex': 0,
                  },
                ],
              },
            ],
          },
        },
        lessonId: 'l-dialogue',
        template: 'dialogue',
      );
      final content = lesson['content'] as Map;
      expect(content['dialogueScene'], isA<Map>());
      final stages = content['stages'] as List;
      expect(stages, hasLength(1));
      final items = (stages.first as Map)['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['runtimeType'], 'multipleChoice');
    });
  });
}
