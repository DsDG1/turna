import 'package:flutter_test/flutter_test.dart';
import 'package:words625/domain/course/lesson_word_link.dart';

void main() {
  group('LessonWordLink', () {
    test('serializes and deserializes', () {
      final link = LessonWordLink(
        wordId: 'w-hello',
        lessonId: 'l-greetings-1',
        lessonName: 'Greetings',
        type: LinkType.word,
        firstSeenAt: DateTime(2026, 7, 9, 10, 30),
      );

      final json = link.toJson();
      final recovered = LessonWordLink.fromJson(json);

      expect(recovered.wordId, 'w-hello');
      expect(recovered.lessonId, 'l-greetings-1');
      expect(recovered.lessonName, 'Greetings');
      expect(recovered.type, LinkType.word);
      expect(recovered.firstSeenAt, link.firstSeenAt);
    });

    test('defaults to LinkType.word', () {
      final link = LessonWordLink(
        wordId: 'w-hello',
        lessonId: 'l-greetings-1',
        lessonName: 'Greetings',
        firstSeenAt: DateTime.utc(2026, 7, 9),
      );
      expect(link.type, LinkType.word);
    });
  });
}
