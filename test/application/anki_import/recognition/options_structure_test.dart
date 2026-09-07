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
    expect(
      EmbeddedOptionsParser.parseOptionPool('北京||上海||广州||深圳'),
      ['北京', '上海', '广州', '深圳'],
    );
    expect(
      EmbeddedOptionsParser.parseOptionPool('Item1###Item2###Item3'),
      ['Item1', 'Item2', 'Item3'],
    );
  });

  test('extractEmbeddedOptions supports circled numbers and Chinese brackets', () {
    const circled = '下列属于偶数的是：\n① 1\n② 2\n③ 3\n④ 4';
    final parsedCircled = EmbeddedOptionsParser.extractEmbeddedOptions(circled);
    expect(parsedCircled, isNotNull);
    expect(parsedCircled!.options, ['1', '2', '3', '4']);
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('②、④', parsedCircled.options),
      [1, 3],
    );

    const chineseBrackets = '单选题：\n（A） 苹果\n（B） 香蕉\n（C） 橙子';
    final parsedBrackets = EmbeddedOptionsParser.extractEmbeddedOptions(chineseBrackets);
    expect(parsedBrackets, isNotNull);
    expect(parsedBrackets!.options, ['苹果', '香蕉', '橙子']);
  });

  test('extractMultiFieldOptions collects separate option columns', () {
    final fieldNames = ['Question', 'OptionA', 'OptionB', 'OptionC', 'OptionD', 'Answer'];
    final fieldValues = [
      '我国第一部宪法颁布年份？',
      '1949年',
      '1954年',
      '1978年',
      '1982年',
      'B',
    ];

    final options = EmbeddedOptionsParser.extractMultiFieldOptions(
      fieldNames,
      fieldValues,
    );
    expect(options, ['1949年', '1954年', '1978年', '1982年']);

    final correct = EmbeddedOptionsParser.parseCorrectIndices(
      fieldValues[5],
      options!,
    );
    expect(correct, [1]);
  });

  test('options with media preserve [sound:] and <img> tags', () {
    const front = '听音选图：\nA. <img src="dog.jpg"> [sound:dog.mp3]\nB. <img src="cat.jpg"> [sound:cat.mp3]';
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    expect(parsed, isNotNull);
    expect(parsed!.options.length, 2);
    expect(parsed.options[0], contains('<img src="dog.jpg">'));
    expect(parsed.options[0], contains('[sound:dog.mp3]'));
  });

  test('HTML line breaks become newlines before option parsing', () {
    const front = 'Which animal barks?<br>A. Cat<br>B. Dog<br>C. Bird';
    expect(EmbeddedOptionsParser.looksLikeEmbeddedOptions(front), isTrue);
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    expect(parsed, isNotNull);
    expect(parsed!.options, ['Cat', 'Dog', 'Bird']);
    expect(parsed.prompt, 'Which animal barks?');
  });

  test('div-wrapped options and entities are normalized', () {
    const front =
        '<div>我国的首都是哪里？</div><div>A.&nbsp;上海</div><div>B. 北京</div><div>C. 广州</div>';
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    expect(parsed, isNotNull);
    expect(parsed!.options, ['上海', '北京', '广州']);
    expect(EmbeddedOptionsParser.parseCorrectIndices('B', parsed.options), [1]);
  });

  test('answer with repeated option label aligns by exact text', () {
    const options = ['上海', '北京', '广州'];
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('B. 北京', options),
      [1],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('（B）北京', options),
      [1],
    );
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('答案：C. 广州', options),
      [2],
    );
  });

  test('inline numbered options parse from a single line', () {
    const front = '选出偶数：1. 3 2. 4 3. 5 4. 7';
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions(front);
    expect(parsed, isNotNull);
    expect(parsed!.options, ['3', '4', '5', '7']);
    expect(parsed.prompt, '选出偶数：');
    expect(EmbeddedOptionsParser.parseCorrectIndices('2', parsed.options), [1]);
  });
}
