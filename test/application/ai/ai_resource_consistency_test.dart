// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/ai_resource_consistency.dart';

void main() {
  group('ai_resource_consistency', () {
    test('normalizeResources fills missing arrays', () {
      final parsed = <String, dynamic>{'units': []};
      normalizeResources(parsed);
      expect(parsed['words'], isA<List>());
      expect(parsed['expressions'], isA<List>());
      expect(parsed['grammarPoints'], isA<List>());
      expect((parsed['words'] as List).isEmpty, isTrue);
    });

    test('normalizeResources throws when not a list', () {
      final parsed = <String, dynamic>{'words': 'not a list'};
      expect(() => normalizeResources(parsed), throwsA(isA<FormatException>()));
    });

    test('autoFixResources synthesizes stub word from context', () {
      final parsed = <String, dynamic>{
        'words': <Map<String, dynamic>>[],
        'expressions': <Map<String, dynamic>>[],
        'grammarPoints': <Map<String, dynamic>>[],
        'units': [
          {
            'id': 'u1',
            'lessons': [
              {
                'id': 'l1',
                'content': {
                  'stages': [
                    {
                      'id': 's1',
                      'items': [
                        {
                          'runtimeType': 'showWord',
                          'wordId': 'w-new',
                          'context': 'Merhaba — 你好',
                        },
                      ],
                    },
                  ],
                },
              },
            ],
          },
        ],
      };
      normalizeResources(parsed);
      autoFixResources(parsed);
      final words = parsed['words'] as List;
      expect(words.length, 1);
      expect(words.first['id'], 'w-new');
      expect(words.first['term'], 'Merhaba');
      expect(words.first['translation'], '你好');
      expect(words.first['tags'], contains('auto-fix'));
      // Self-consistency now passes.
      checkResourceSelfConsistency(parsed);
    });

    test('autoFixResources keeps existing words', () {
      final parsed = <String, dynamic>{
        'words': [
          {'id': 'w-exist', 'term': 'Merhaba', 'translation': '你好'},
        ],
        'expressions': <Map<String, dynamic>>[],
        'grammarPoints': <Map<String, dynamic>>[],
        'units': [
          {
            'lessons': [
              {
                'content': {
                  'stages': [
                    {
                      'items': [
                        {'runtimeType': 'showWord', 'wordId': 'w-exist'},
                      ],
                    },
                  ],
                },
              },
            ],
          },
        ],
      };
      normalizeResources(parsed);
      autoFixResources(parsed);
      expect((parsed['words'] as List).length, 1);
      checkResourceSelfConsistency(parsed);
    });

    test('checkResourceSelfConsistency throws on dangling wordId', () {
      final parsed = <String, dynamic>{
        'words': <Map<String, dynamic>>[],
        'expressions': <Map<String, dynamic>>[],
        'grammarPoints': <Map<String, dynamic>>[],
        'units': [
          {
            'lessons': [
              {
                'id': 'l1',
                'content': {
                  'stages': [
                    {
                      'items': [
                        {'runtimeType': 'showWord', 'wordId': 'w-missing'},
                      ],
                    },
                  ],
                },
              },
            ],
          },
        ],
      };
      normalizeResources(parsed);
      expect(
        () => checkResourceSelfConsistency(parsed),
        throwsA(isA<FormatException>()),
      );
    });

    test('iterItems yields items across stages, subLessons, listeningPhases',
        () {
      final lesson = <String, dynamic>{
        'content': {
          'stages': [
            {
              'items': [
                {'runtimeType': 'multipleChoice'},
              ],
            },
          ],
          'subLessons': [
            {
              'stages': [
                {
                  'items': [
                    {'runtimeType': 'fillBlank'},
                  ],
                },
              ],
            },
          ],
          'listeningPhases': [
            {
              'items': [
                {'runtimeType': 'listenAndPick'},
              ],
            },
          ],
        },
      };
      final items = iterItems(lesson).toList();
      expect(items.length, 3);
      expect(items.map((i) => i['runtimeType']).toList(),
          ['multipleChoice', 'fillBlank', 'listenAndPick']);
    });
  });
}
