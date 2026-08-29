import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';

void main() {
  test('line-oriented parse extracts prompt and options', () {
    const front = 'Which animal barks?\nA. Cat\nB. Dog\nC. Bird';
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    expect(parsed, isNotNull);
    expect(parsed!.prompt, 'Which animal barks?');
    expect(parsed.options, ['Cat', 'Dog', 'Bird']);
  });

  test('inline parse handles options jammed into one paragraph', () {
    const front = 'Pick: A. Cat B. Dog C. Bird';
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    expect(parsed, isNotNull);
    expect(parsed!.options, ['Cat', 'Dog', 'Bird']);
    expect(parsed.prompt, 'Pick:');
  });

  test('parseCorrectIndices resolves exact, letters, and numbers', () {
    const options = ['Cat', 'Dog', 'Bird'];
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('Dog', options),
      [1],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('B', options),
      [1],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('2', options),
      [1],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('A、C', options),
      [0, 2],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('答案：A', options),
      [0],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('nothing matches', options),
      isEmpty,
    );
  });

  test('option and answer field name probes', () {
    expect(EmbeddedOptionsParser.isOptionFieldName('option'), isTrue);
    expect(EmbeddedOptionsParser.isOptionFieldName('option_b'), isTrue);
    expect(EmbeddedOptionsParser.isOptionFieldName('选项a'), isTrue);
    expect(EmbeddedOptionsParser.isOptionFieldName('answer'), isFalse);
    expect(EmbeddedOptionsParser.isAnswerFieldName('正确答案'), isTrue);
  });

  test('parseOptionPool splits, trims, dedupes, and caps', () {
    expect(
      EmbeddedOptionsParser.parseOptionPool('巴黎|伦敦|柏林|马德里'),
      ['巴黎', '伦敦', '柏林', '马德里'],
    );
    expect(
      EmbeddedOptionsParser.parseOptionPool('a\n\nb; a, c'),
      ['a', 'b', 'c'],
    );
    final many =
        List.generate(12, (i) => 'opt$i').join('|');
    expect(EmbeddedOptionsParser.parseOptionPool(many), hasLength(8));
    expect(EmbeddedOptionsParser.parseOptionPool('  '), isEmpty);
  });
}
