import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_practice/embedded_options.dart';

void main() {
  group('EmbeddedOptionsParser', () {
    test('extractEmbeddedOptions parses classic line-oriented A/B/C/D', () {
      const front = 'What is the capital of France?\nA. London\nB. Paris\nC. Berlin\nD. Madrid';
      final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
      expect(parsed, isNotNull);
      expect(parsed!.prompt, 'What is the capital of France?');
      expect(parsed.options, ['London', 'Paris', 'Berlin', 'Madrid']);
    });

    test('extractEmbeddedOptions parses inline A./B./C./D. without newlines', () {
      const front = '下列关于光合作用说法正确的是A. 仅在白天进行B. 产物只有氧气C. 需要叶绿体D. 不消耗水';
      final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
      expect(parsed, isNotNull);
      expect(parsed!.prompt, '下列关于光合作用说法正确的是');
      expect(parsed.options, ['仅在白天进行', '产物只有氧气', '需要叶绿体', '不消耗水']);
    });

    test('parseCorrectIndices supports letter, numeric, and prefix formats', () {
      final options = ['Alpha', 'Beta', 'Gamma', 'Delta'];
      expect(EmbeddedOptionsParser.parseCorrectIndices('B', options), [1]);
      expect(EmbeddedOptionsParser.parseCorrectIndices('答案：B', options), [1]);
      expect(EmbeddedOptionsParser.parseCorrectIndices('正确答案: A, C', options), [0, 2]);
      expect(EmbeddedOptionsParser.parseCorrectIndices('1, 4', options), [0, 3]);
      expect(EmbeddedOptionsParser.parseCorrectIndices('Beta', options), [1]);
    });

    test('choiceCardinality detects single and multi options from prompt', () {
      expect(
        EmbeddedOptionsParser.choiceCardinality(prompt: '下列单项选择题：'),
        PracticeChoiceCardinality.single,
      );
      expect(
        EmbeddedOptionsParser.choiceCardinality(prompt: '请选择所有正确选项（多选）：'),
        PracticeChoiceCardinality.multi,
      );
      expect(
        EmbeddedOptionsParser.choiceCardinality(prompt: 'What is this?'),
        PracticeChoiceCardinality.unknown,
      );
    });

    test('detectChoiceLayout detects structured MCQ columns', () {
      final layout = EmbeddedOptionsParser.detectChoiceLayout(
        fieldNames: ['Stem', 'Option A', 'Option B', 'Option C', 'Option D', 'Answer'],
        notetypeName: 'Multiple Choice',
      );
      expect(layout, isNotNull);
      expect(layout!.promptIndex, 0);
      expect(layout.optionIndices, [1, 2, 3, 4]);
      expect(layout.answerIndex, 5);
      expect(layout.multi, isFalse);
    });
  });
}
