// Unit tests: AI practice content verification (the hard gate that keeps
// unanswerable questions out of the library).

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_quality.dart';

Map<String, dynamic> _item(Map<String, dynamic> item) => item;

Map<String, dynamic> _section({
  required List<Map<String, dynamic>> items,
  String template = 'practice',
  List<Map<String, dynamic>>? words,
  Map<String, dynamic>? readingPassage,
}) {
  return {
    'id': 'sec-1',
    'name': 'Test section',
    'words': words ??
        [
          {'id': 'w1', 'term': 'merhaba', 'translation': '你好'},
        ],
    'expressions': const [],
    'grammarPoints': const [],
    'units': [
      {
        'id': 'u1',
        'name': 'Unit 1',
        'lessons': [
          {
            'id': 'l1',
            'name': 'Lesson 1',
            'template': template,
            'content': {
              if (readingPassage != null) 'readingPassage': readingPassage,
              'stages': [
                {'id': 'st1', 'name': 'Practice', 'items': items},
              ],
            },
          },
        ],
      },
    ],
  };
}

Map<String, dynamic> _showWord(String wordId) =>
    _item({'runtimeType': 'showWord', 'wordId': wordId});

Map<String, dynamic> _mcq({
  List<String> options = const ['a', 'b', 'c', 'd'],
  int correctIndex = 0,
  String prompt = 'Pick one',
}) =>
    _item({
      'runtimeType': 'multipleChoice',
      'prompt': prompt,
      'options': options,
      'correctIndex': correctIndex,
    });

void main() {
  test('a clean section passes with no blocking findings', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _mcq(),
      _mcq(prompt: 'Pick two'),
      _mcq(prompt: 'Pick three'),
    ]));
    expect(report.passed, isTrue, reason: report.blockingMessages.join(' | '));
  });

  test('an out-of-range correctIndex blocks', () {
    // Rendering does `options[correctIndex]`, so this throws a RangeError
    // mid-exercise instead of being caught by the structural validator.
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _mcq(correctIndex: 9),
      _mcq(prompt: 'x'),
      _mcq(prompt: 'y'),
    ]));
    expect(report.passed, isFalse);
    expect(report.blocking.map((i) => i.code), contains('item.bad-index'));
  });

  test('duplicate options block', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _mcq(options: const ['a', 'a', 'b', 'c']),
      _mcq(prompt: 'x'),
      _mcq(prompt: 'y'),
    ]));
    expect(report.passed, isFalse);
    expect(
      report.blocking.map((i) => i.code),
      contains('item.duplicate-options'),
    );
  });

  test('a non-4 option count is advisory, not blocking', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _mcq(options: const ['a', 'b', 'c'], prompt: 'p1'),
      _mcq(prompt: 'p2'),
      _mcq(prompt: 'p3'),
    ]));
    expect(report.passed, isTrue);
    expect(report.advisory.map((i) => i.code), contains('item.option-count'));
  });

  test('fillBlank without a blank marker blocks', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _item({
        'runtimeType': 'fillBlank',
        'sentence': 'Merhaba dunya',
        'answer': 'merhaba',
      }),
      _mcq(prompt: 'x'),
      _mcq(prompt: 'y'),
    ]));
    expect(report.passed, isFalse);
    expect(report.blocking.map((i) => i.code), contains('fillBlank.no-blank'));
  });

  test('reorderSentence with mismatched tokens blocks', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _item({
        'runtimeType': 'reorderSentence',
        'scrambled': ['a', 'b', 'c'],
        'correct': ['a', 'b', 'd'],
      }),
      _mcq(prompt: 'x'),
      _mcq(prompt: 'y'),
    ]));
    expect(report.passed, isFalse);
    expect(
      report.blocking.map((i) => i.code),
      contains('reorder.token-mismatch'),
    );
  });

  test('every word must be shown somewhere in the section', () {
    final report = AiPracticeQualityChecker.check(_section(
      words: [
        {'id': 'w1', 'term': 'merhaba', 'translation': '你好'},
        {'id': 'w2', 'term': 'gunaydin', 'translation': '早安'},
      ],
      items: [_showWord('w1'), _mcq(), _mcq(prompt: 'x'), _mcq(prompt: 'y')],
    ));
    expect(report.passed, isFalse);
    expect(report.blocking.map((i) => i.code), contains('word.unused'));
  });

  test('placeholder text blocks', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _mcq(prompt: 'TODO 补一题'),
      _mcq(prompt: 'x'),
      _mcq(prompt: 'y'),
    ]));
    expect(report.passed, isFalse);
    expect(report.blocking.map((i) => i.code), contains('item.placeholder'));
  });

  test('a reading lesson without paragraphs blocks', () {
    final report = AiPracticeQualityChecker.check(_section(
      template: 'reading',
      readingPassage: const {'title': 'R', 'paragraphs': <String>[]},
      items: [_showWord('w1'), _mcq(), _mcq(prompt: 'x'), _mcq(prompt: 'y')],
    ));
    expect(report.passed, isFalse);
    expect(report.blocking.map((i) => i.code), contains('reading.no-passage'));
  });

  test('an empty stage blocks', () {
    final report = AiPracticeQualityChecker.check({
      'id': 's',
      'words': const [],
      'units': [
        {
          'id': 'u1',
          'lessons': [
            {
              'id': 'l1',
              'name': 'L1',
              'template': 'practice',
              'content': {
                'stages': [
                  {'id': 'st1', 'name': 'Empty', 'items': const []},
                ],
              },
            },
          ],
        },
      ],
    });
    expect(report.passed, isFalse);
    expect(report.blocking.map((i) => i.code), contains('stage.empty'));
  });

  test('report JSON round-trips so the library can show it later', () {
    final report = AiPracticeQualityChecker.check(_section(items: [
      _showWord('w1'),
      _mcq(correctIndex: 7),
      _mcq(prompt: 'x'),
      _mcq(prompt: 'y'),
    ]));
    final parsed = AiPracticeQualityReport.tryParse(report.toJsonString());
    expect(parsed, isNotNull);
    expect(parsed!.passed, report.passed);
    expect(parsed.blocking.first.code, report.blocking.first.code);
  });
}
