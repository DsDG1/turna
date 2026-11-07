import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/course_answer.dart';

void main() {
  group('normalizeCourseAnswer', () {
    test('folds Turkish case, punctuation, and whitespace symmetrically', () {
      expect(
        normalizeCourseAnswer('  Teşekkürler!  '),
        normalizeCourseAnswer('teşekkürler'),
      );
      expect(normalizeCourseAnswer('Bir   çay, lütfen.'), 'bir çay lütfen');
      expect(normalizeCourseAnswer('İyi'), normalizeCourseAnswer('iyi'));
    });
  });

  group('matchesCourseAnswer', () {
    test('accepts canonical and declared alternatives', () {
      expect(
        matchesCourseAnswer('Bir çay lütfen!', 'Bir çay lütfen', const []),
        isTrue,
      );
      expect(
        matchesCourseAnswer(
          'Çay lütfen',
          'Bir çay lütfen',
          const ['Çay lütfen'],
        ),
        isTrue,
      );
      expect(
        matchesCourseAnswer('Çay', 'Bir çay lütfen', const ['Çay lütfen']),
        isFalse,
      );
    });
  });
}
