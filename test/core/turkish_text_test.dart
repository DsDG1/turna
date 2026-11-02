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

    test('circumflex vowels fold to basic Latin vowels', () {
      expect(foldTurkish('hâlâ'), foldTurkish('hala'));
      expect(foldTurkish('kâğıt'), foldTurkish('kağıt'));
      // `û` 是长音戴帽符, 折成 `u`; 但 `ü` 是双点符 (前元音和谐), 是土耳其语
      // 独立字母, 不折 —— 跟读打分依赖这一点: `ü→u` 必须算作一次"元音质量"
      // 失误 (`teşekkürler` vs `tesekkurler` = 两处差异 = 未命中), 若在这里
      // 折掉, ASR 容差会被悄悄放宽.
      expect(foldTurkish('sükûn'), 'sükun');
    });
  });
}
