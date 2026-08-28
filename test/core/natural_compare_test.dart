import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/natural_compare.dart';

void main() {
  group('naturalCompare', () {
    test('orders digit runs numerically', () {
      expect(naturalCompare('Unit 2', 'Unit 10'), lessThan(0));
      expect(naturalCompare('Unit 10', 'Unit 2'), greaterThan(0));
      expect(naturalCompare('Unit 2', 'Unit 2'), 0);
      expect(naturalCompare('Lesson 9', 'Lesson 10'), lessThan(0));
    });

    test('is case-insensitive for letters', () {
      expect(naturalCompare('chapter a', 'Chapter B'), lessThan(0));
      // Case-folded ties fall back to raw code units: deterministic, total.
      final forward = naturalCompare('ABC', 'abc');
      expect(forward != 0, isTrue);
      expect(naturalCompare('abc', 'ABC'), -forward);
    });

    test('ignores leading zeros inside digit runs', () {
      // Equal numeric value: deterministic raw-code-unit tiebreak ('0' < '7').
      expect(naturalCompare('Unit 007', 'Unit 7'), lessThan(0));
      expect(naturalCompare('Unit 007', 'Unit 08'), lessThan(0));
    });

    test('handles digit runs of arbitrary length without overflow', () {
      final long = 'Unit ${'9' * 40}';
      expect(naturalCompare(long, 'Unit 1000'), greaterThan(0));
      expect(naturalCompare(long, 'Unit ${'9' * 40}0'), lessThan(0));
    });

    test('prefix, empty and mixed-run ordering', () {
      expect(naturalCompare('Unit', 'Unit 1'), lessThan(0));
      expect(naturalCompare('', 'Unit 1'), lessThan(0));
      expect(naturalCompare('Unit', ''), greaterThan(0));
      expect(naturalCompare('Unit 2', 'Unit2'), lessThan(0));
      expect(naturalCompare('第2课', '第10课'), lessThan(0));
      expect(naturalCompare('a1b2', 'a1b10'), lessThan(0));
    });

    test('sorts a course-like deck list into human order', () {
      final names = [
        'Unit 10',
        'unit 2',
        'Unit 1',
        'Alphabet',
        'Unit 21',
        'beta',
      ]..sort(naturalCompare);
      expect(names, [
        'Alphabet',
        'beta',
        'Unit 1',
        'unit 2',
        'Unit 10',
        'Unit 21',
      ]);
    });
  });
}
