import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/turkish_text.dart';

void main() {
  group('foldTurkish', () {
    test('İyi family matches typed iyi', () {
      expect(foldTurkish('İyi'), foldTurkish('iyi'));
      expect(foldTurkish('İYI'), foldTurkish('iyi'));
      expect(foldTurkish('IYI'), foldTurkish('iyi'));
    });

    test('İstanbul matches istanbul', () {
      expect(foldTurkish('İstanbul'), foldTurkish('istanbul'));
    });

    test('dır matches mixed-case dIr', () {
      expect(foldTurkish('dır'), foldTurkish('dIr'));
    });

    test('plain ASCII is unchanged aside from case', () {
      expect(foldTurkish('Hello'), foldTurkish('hello'));
      expect(foldTurkish('student'), 'student');
    });

    test('combining dot from default toLowerCase does not split the match', () {
      const combiningDotI = 'i\u0307';
      expect(combiningDotI.length, greaterThan(1));
      expect(foldTurkish(combiningDotI), foldTurkish('i'));
      expect(foldTurkish('İ'.toLowerCase()), foldTurkish('i'));
    });
  });
}
