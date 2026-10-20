// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/application/ai/practice/ai_practice_pipeline.dart';
import 'package:turna/application/ai/practice/ai_practice_prompts.dart';
import 'package:turna/domain/ai/ai_course.dart';

Map<String, dynamic> _outline() => {
      'id': 'ai-practice-1',
      'name': 'Practice',
      'description': 'drill',
      'words': [
        {
          'id': 'w-ai-merhaba',
          'term': 'Merhaba',
          'translation': 'hello',
        }
      ],
      'expressions': <dynamic>[],
      'grammarPoints': <dynamic>[],
      'units': [
        {
          'id': 'ai-practice-1-u1',
          'name': 'Unit',
          'lessons': [
            {
              'id': 'ai-practice-1-u1-l1',
              'name': 'Lesson',
              'template': 'mastery',
              'targetWordIds': ['w-ai-merhaba'],
            }
          ],
        }
      ],
    };

Map<String, dynamic> _section() => {
      'id': 'ai-practice-1',
      'name': 'Practice',
      'description': 'drill',
      'words': <dynamic>[],
      'expressions': <dynamic>[],
      'grammarPoints': <dynamic>[],
      'units': [
        {
          'id': 'ai-practice-1-u1',
          'name': 'Unit',
          'lessons': [
            {
              'id': 'ai-practice-1-u1-l1',
              'name': 'Lesson',
              'type': 'normal',
              'template': 'mastery',
              'content': {
                'stages': [
                  {
                    'id': 'st1',
                    'name': 'Practice',
                    'items': [
                      {
                        'runtimeType': 'multipleChoice',
                        'id': 'q1',
                        'prompt': 'Pick one',
                        'options': ['a', 'b', 'c', 'd'],
                        'correctIndex': 0,
                      }
                    ],
                  }
                ],
              },
            }
          ],
        }
      ],
    };

void main() {
  group('decodeObject', () {
    test('strips fences and surrounding prose', () {
      expect(AiPracticePipeline.decodeObject('```json\n{"a":1}\n```')['a'], 1);
      expect(
        AiPracticePipeline.decodeObject(
            'Here is the JSON:\n{"a":2}\nDone')['a'],
        2,
      );
    });
  });

  group('validateOutline', () {
    test('accepts a 1x1 mastery outline', () {
      expect(
        AiPracticePipeline.validateOutline(
          _outline(),
          expectedUnits: 1,
          expectedLessonsPerUnit: 1,
        ),
        isEmpty,
      );
    });

    test('rejects wrong unit/lesson counts', () {
      final errors = AiPracticePipeline.validateOutline(
        _outline(),
        expectedUnits: 2,
        expectedLessonsPerUnit: 3,
      );
      expect(errors, isNotEmpty);
      expect(errors.join(' '), contains('unit'));
    });

    test('rejects a lesson referencing an unknown word id', () {
      final outline = _outline();
      (outline['units'] as List).first['lessons'].first['targetWordIds'] = [
        'w-missing'
      ];
      final errors = AiPracticePipeline.validateOutline(
        outline,
        expectedUnits: 1,
        expectedLessonsPerUnit: 1,
      );
      expect(errors.join(' '), contains('w-missing'));
    });
  });

  group('sectionShell', () {
    test('locks section/unit/lesson ids and templates', () {
      final shell = AiPracticePipeline.sectionShell(
        _outline(),
        sectionId: 'ai-practice-1',
        sectionName: 'Practice',
      );
      expect(shell['id'], 'ai-practice-1');
      final unit = (shell['units'] as List).first as Map<String, dynamic>;
      expect(unit['id'], 'ai-practice-1-u1');
      final lesson = (unit['lessons'] as List).first as Map<String, dynamic>;
      expect(lesson['id'], 'ai-practice-1-u1-l1');
      expect(lesson['template'], 'mastery');
      expect(lesson['content'], contains('stages'));
    });
  });

  group('normalizeLessonJson', () {
    test('wraps flat questions into one canonical stage', () {
      final lesson = AiPracticePipeline.normalizeLessonJson(
        {
          'content': {
            'questions': [
              {'runtimeType': 'multipleChoice', 'id': 'q1'}
            ]
          }
        },
        lessonId: 'l1',
        template: 'mastery',
      );
      expect(lesson['id'], 'l1');
      expect(lesson['template'], 'mastery');
      final content = lesson['content'] as Map<String, dynamic>;
      expect(content.containsKey('questions'), isFalse);
      final stages = content['stages'] as List;
      expect(stages, hasLength(1));
      expect((stages.first as Map)['items'], hasLength(1));
    });
  });

  group('validateSectionJson', () {
    test('accepts a minimal valid mastery section', () {
      expect(AiPracticePipeline.validateSectionJson(_section()), isEmpty);
    });

    test('rejects a showWord whose wordId is not defined', () {
      final section = _section();
      final lesson =
          ((section['units'] as List).first as Map)['lessons'].first as Map;
      final content = lesson['content'] as Map;
      final stage = (content['stages'] as List).first as Map;
      (stage['items'] as List).add({
        'runtimeType': 'showWord',
        'id': 'q2',
        'wordId': 'w-missing',
      });
      final errors = AiPracticePipeline.validateSectionJson(section);
      expect(errors.join(' '), contains('w-missing'));
    });
  });

  group('prompts', () {
    AiPracticeRequest request() => AiPracticeRequest(
          id: 'ai-practice-1',
          title: 'Practice',
          source: AiPracticeSource.mistakes,
          languageCode: 'tr',
          sourceContext: '- [w-a] user="a" correct="A"',
          spec: const AiCourseSpec(
            language: 'Turkish',
            topic: 'Mistakes',
            level: 'A1',
            unitCount: 1,
            lessonsPerUnit: 1,
            template: 'practice',
            designBrief: 'Keep prompts short.',
          ),
        );

    test('outline prompt carries counts, template and learner evidence', () {
      final prompt = AiPracticePrompts.outlinePrompt(request());
      expect(prompt, contains('Units: 1'));
      expect(prompt, contains('Template for every lesson: practice'));
      expect(prompt, contains('Learner evidence'));
      expect(prompt, contains('"units"'));
    });

    test('mixed template asks for per-lesson choice, never listening', () {
      final mixed = request().spec.copyWith(template: 'mixed');
      final prompt = AiPracticePrompts.outlinePrompt(
        AiPracticeRequest(
          id: 'ai-practice-1',
          title: 'Practice',
          source: AiPracticeSource.custom,
          languageCode: 'tr',
          spec: mixed,
        ),
      );
      expect(prompt, contains('never listening'));
      expect(prompt, contains('intro / practice / review / reading / mastery'));
    });

    test('lesson prompt locks id/template and lists text-only types', () {
      final prompt = AiPracticePrompts.lessonPrompt(
        request: request(),
        outline: _outline(),
        lessonOutline: (_outline()['units'] as List).first['lessons'].first
            as Map<String, dynamic>,
        unitId: 'ai-practice-1-u1',
      );
      expect(prompt, contains('ai-practice-1-u1-l1'));
      expect(prompt, contains('TEXT ONLY'));
      expect(prompt, contains('multipleChoice'));
      expect(prompt, contains('never emit listenAndPick'));
    });

    test('adjust prompt keeps the instruction and current section id', () {
      final prompt = AiPracticePrompts.adjustPrompt(
        section: _section(),
        instruction: 'make prompts shorter',
      );
      expect(prompt, contains('make prompts shorter'));
      expect(prompt, contains('ai-practice-1'));
      expect(prompt, contains('Keep the section id'));
    });
  });
}
