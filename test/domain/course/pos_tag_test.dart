import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/pos_tag.dart';

void main() {
  group('PosTag.parse', () {
    test('parses all 10 closed-set tags (case/whitespace tolerant)', () {
      for (final tag in PosTag.values) {
        expect(PosTag.parse(tag.name), tag);
        expect(PosTag.parse(' ${tag.name.toUpperCase()} '), tag);
      }
      expect(PosTag.values.length, 10);
    });

    test('null / empty / unknown -> null (never throws)', () {
      expect(PosTag.parse(null), isNull);
      expect(PosTag.parse(''), isNull);
      expect(PosTag.parse('   '), isNull);
      expect(PosTag.parse('bogus'), isNull);
    });
  });

  test('posTagLabel maps to Chinese label or name', () {
    expect(posTagLabel(PosTag.noun), '名词');
    expect(posTagLabel(null), '');
    expect(posTagLabel(PosTag.determiner), '限定词');
  });

  test('closed set mirrors GUI pos_constants.py (10 classes)', () {
    // If this breaks, update the GUI mirror in
    // tool/gui/src/backend/experience/pos_constants.py to match.
    final names = PosTag.values.map((t) => t.name).toSet();
    expect(
      names,
      {
        'noun',
        'verb',
        'adjective',
        'adverb',
        'pronoun',
        'preposition',
        'conjunction',
        'interjection',
        'numeral',
        'determiner',
      },
    );
  });
}