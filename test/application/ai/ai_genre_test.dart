// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/ai/ai_genre.dart';

void main() {
  group('ai_genre', () {
    test('genreToTemplate maps known tags', () {
      expect(genreToTemplate('[intro]'), 'intro');
      expect(genreToTemplate('[listening]'), 'listening');
      expect(genreToTemplate('[mastery]'), 'mastery');
      expect(genreToTemplate('intro'), 'intro');
      expect(genreToTemplate('[unknown]'), 'mixed');
    });

    test('templateLabel returns human-readable label', () {
      expect(templateLabel('intro'), '认识新词');
      expect(templateLabel('listening'), '听力训练');
      expect(templateLabel('unknown'), 'unknown');
    });

    test('parseGenreTag returns first recognized tag or null', () {
      expect(parseGenreTag('Travel [listening] vocab'), '[listening]');
      expect(parseGenreTag('no tags here'), isNull);
      expect(parseGenreTag('[unknown]'), isNull);
      expect(parseGenreTag(null), isNull);
      expect(parseGenreTag(''), isNull);
    });

    test('genreTagsInText returns all recognized tags in order', () {
      expect(
        genreTagsInText('[intro] then [listening] then [unknown]'),
        ['[intro]', '[listening]'],
      );
      expect(genreTagsInText('[intro] [intro]'), ['[intro]']);
      expect(genreTagsInText(''), isEmpty);
    });

    test('allGenreTags returns 7 tags', () {
      expect(allGenreTags().length, 7);
    });

    test('genrePromptBlock lists all tags', () {
      final block = genrePromptBlock();
      for (final tag in allGenreTags()) {
        expect(block.contains(tag), isTrue);
      }
    });
  });
}