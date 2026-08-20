import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_practice/card_classifier.dart';
import 'package:turna/application/anki_practice/card_classifier_models.dart';

void main() {
  group('AnkiPracticeCardClassifier', () {
    test('Rule 1: JS / script / type answer forces fidelity with confidence 1.0', () {
      const input = AnkiPracticeCardInput(
        questionText: 'Test <script>alert(1)</script>',
        answerText: 'Answer',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.fidelity);
      expect(result.confidence, 1.0);
      expect(result.evidence, contains('js_or_type_answer'));
    });

    test('Rule 2: Complex HTML tags force fidelity', () {
      const input = AnkiPracticeCardInput(
        questionText: '<table><tr><td>Table content</td></tr></table>',
        answerText: 'Answer',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.fidelity);
      expect(result.evidence, contains('complex_html'));
    });

    test('Rule 3: Cloze deletion extracts sentence and answer', () {
      const input = AnkiPracticeCardInput(
        isCloze: true,
        rawQuestionHtml: 'The capital of France is {{c1::Paris::city}}.',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.cloze);
      expect(result.clozeAnswer, 'Paris');
      expect(result.clozeSentence, 'The capital of France is _____.');
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Rule 4: Embedded options with clean answer parses to quiz', () {
      const input = AnkiPracticeCardInput(
        questionText: 'What is 2 + 2?\nA. 3\nB. 4\nC. 5',
        answerText: 'B',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.quiz);
      expect(result.options, ['3', '4', '5']);
      expect(result.correctIndex, 1);
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Rule 4 (Iron Law): Broken embedded options forces fidelity', () {
      const input = AnkiPracticeCardInput(
        questionText: 'What is this?\nA. Option 1\nB. Option 2',
        answerText: 'Unparseable Answer',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.fidelity);
      expect(result.looksLikeQuizButUnparsed, isTrue);
      expect(result.evidence, contains('embedded_options_unparsed'));
    });

    test('Rule 5: Front sound + short answer classifies as listen', () {
      const input = AnkiPracticeCardInput(
        rawQuestionHtml: '[sound:hello.mp3]',
        answerText: 'hello',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.listen);
      expect(result.audioFilename, 'hello.mp3');
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Rule 6: Basic vocab pair hello/你好 classifies as vocab', () {
      const input = AnkiPracticeCardInput(
        fieldNames: ['Front', 'Back'],
        fields: ['hello', '你好'],
        questionText: 'hello',
        answerText: '你好',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.vocab);
      expect(result.term, 'hello');
      expect(result.meaning, '你好');
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Rule 6: Chinese field names 正面/反面 classify as vocab with high confidence', () {
      const input = AnkiPracticeCardInput(
        fieldNames: ['正面', '反面'],
        fields: ['apple', '苹果'],
        questionText: 'apple',
        answerText: '苹果',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.vocab);
      expect(result.term, 'apple');
      expect(result.meaning, '苹果');
      expect(result.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Rule 7: Sentence front + short answer classifies as expression', () {
      const input = AnkiPracticeCardInput(
        questionText: 'Where is the nearest subway station?',
        answerText: '最近的地铁站在哪里？',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.expression);
      expect(result.term, 'Where is the nearest subway station?');
    });

    test('Rule 8: Long multiline answer stays flip', () {
      const input = AnkiPracticeCardInput(
        questionText: 'Explain quantum mechanics',
        answerText: 'Line 1\nLine 2\nLine 3\nLine 4 is very long explanation of physics.',
      );
      final result = AnkiPracticeCardClassifier.classify(input);
      expect(result.shape, AnkiPracticeShape.flip);
    });
  });
}
