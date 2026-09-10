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

  test('full-width letters fold to ASCII for scanning', () {
    expect(
      EmbeddedOptionsParser.looksLikeEmbeddedOptions('Ａ．北京\nＢ．上海\nＣ．广州'),
      isTrue,
    );
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions('首都：\nＡ．北京\nＢ．上海');
    expect(parsed, isNotNull);
    expect(parsed!.options, ['北京', '上海']);
    expect(parsed.prompt, '首都：');
  });

  test('ideographic full stop works as a label separator', () {
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions('题干\nA。甲\nB。乙');
    expect(parsed, isNotNull);
    expect(parsed!.options, ['甲', '乙']);
  });

  test('sequential space-separated labels look like options', () {
    expect(EmbeddedOptionsParser.looksLikeEmbeddedOptions('A 甲\nB 乙\nC 丙'), isTrue);
    // Prose with scattered standalone letters is not sequential.
    expect(
      EmbeddedOptionsParser.looksLikeEmbeddedOptions('A big cat and a small dog'),
      isFalse,
    );
  });

  test('parseCorrectIndices handles 。 suffixes and explanation tails', () {
    const options = ['甲', '乙', '丙'];
    expect(EmbeddedOptionsParser.parseCorrectIndices('B。', options), [1]);
    expect(EmbeddedOptionsParser.parseCorrectIndices('B.', options), [1]);
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('答案：B。解析：因为甲不正确。', options),
      [1],
    );
    expect(EmbeddedOptionsParser.parseCorrectIndices('B 解析：甲不正确', options), [1]);
    expect(EmbeddedOptionsParser.parseCorrectIndices('答案是AC', options), [0, 2]);
    // English answers containing clause words keep their full text.
    expect(
      EmbeddedOptionsParser.parseCorrectIndices('Ever since 1990', ['Ever since 1990', 'x']),
      [0],
    );
  });

  test('parseCorrectIndices aligns option text with whitespace differences', () {
    expect(EmbeddedOptionsParser.parseCorrectIndices('选项 一', ['选项一', '选项二']), [0]);
    expect(EmbeddedOptionsParser.parseCorrectIndices('选项二。', ['选项一', '选项二']), [1]);
  });

  test('unlabeled line pool parses as loose options', () {
    final parsed = EmbeddedOptionsParser.extractEmbeddedOptions('北京\n上海\n广州\n深圳');
    expect(parsed, isNotNull);
    expect(parsed!.loose, isTrue);
    expect(parsed.options, ['北京', '上海', '广州', '深圳']);
    expect(parsed.prompt, '');
    // A long paragraph line is not a pool member.
    expect(
      EmbeddedOptionsParser.extractEmbeddedOptions(
        '这是一段很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长的段落文字，'
        '超过了八十个字符的限制，所以不会被当成选项池',
      ),
      isNull,
    );
  });

  test('isBareLabelAnswer and hasUnlabeledOptionLines', () {
    expect(EmbeddedOptionsParser.isBareLabelAnswer('B'), isTrue);
    expect(EmbeddedOptionsParser.isBareLabelAnswer('B。'), isTrue);
    expect(EmbeddedOptionsParser.isBareLabelAnswer('③'), isTrue);
    expect(EmbeddedOptionsParser.isBareLabelAnswer('2'), isTrue);
    expect(EmbeddedOptionsParser.isBareLabelAnswer('北京'), isFalse);
    expect(EmbeddedOptionsParser.hasUnlabeledOptionLines('甲\n乙\n丙'), isTrue);
    expect(EmbeddedOptionsParser.hasUnlabeledOptionLines('甲\n乙'), isFalse);
  });

  test('extractBackFaceChoice resolves options plus explicit marker', () {
    final parsed = EmbeddedOptionsParser.extractBackFaceChoice(
      'A. 北京\nB. 上海\nC. 广州\n答案：B',
    );
    expect(parsed, isNotNull);
    expect(parsed!.options, ['北京', '上海', '广州']);
    expect(parsed.correctIndices, [1]);
    expect(parsed.prompt, '');
    // No explicit marker → not a back-face choice.
    expect(
      EmbeddedOptionsParser.extractBackFaceChoice('A. 北京\nB. 上海'),
      isNull,
    );
    // Multi-letter marker answers resolve to every index.
    expect(
      EmbeddedOptionsParser.extractBackFaceChoice('A. 北京\nB. 上海\nC. 广州\n答案：AC')
          ?.correctIndices,
      [0, 2],
    );
  });
}
