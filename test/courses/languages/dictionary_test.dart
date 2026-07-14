// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/languages/dictionary.dart';
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/course/word_entry.dart';

void main() {
  setUp(() {
    vocabById
      ..clear()
      ..addAll({
        'w-merhaba': const WordEntry(
          id: 'w-merhaba',
          term: 'Merhaba',
          translation: 'Hello',
          tags: ['greeting'],
        ),
        'w-tesekkur': const WordEntry(
          id: 'w-tesekkur',
          term: 'Teşekkür ederim',
          translation: 'Thank you',
          pronunciation: 'teh-sheh-koor eh-deh-reem',
          tags: ['polite'],
        ),
      });

    vocabByTerm
      ..clear()
      ..addAll({
        'merhaba': vocabById['w-merhaba']!,
        'teşekkür ederim': vocabById['w-tesekkur']!,
      });

    vocabByTranslation
      ..clear()
      ..addAll({
        'hello': vocabById['w-merhaba']!,
        'thank you': vocabById['w-tesekkur']!,
      });
  });

  tearDown(() {
    vocabById.clear();
    vocabByTerm.clear();
    vocabByTranslation.clear();
  });

  group('getWordMeaning', () {
    test('returns English translation for a target-language term', () {
      expect(getWordMeaning('Merhaba'), 'Hello');
      expect(getWordMeaning('Teşekkür ederim'), 'Thank you');
    });

    test('returns target-language term for an English translation', () {
      expect(getWordMeaning('Hello'), 'Merhaba');
      expect(getWordMeaning('Thank you'), 'Teşekkür ederim');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(getWordMeaning('  MERHABA  '), 'Hello');
      expect(getWordMeaning('  hello '), 'Merhaba');
    });

    test('returns "--" for unknown words', () {
      expect(getWordMeaning('Bilinmeyen'), '--');
      expect(getWordMeaning('Unknown'), '--');
    });

    test('returns "--" for empty or whitespace-only input', () {
      expect(getWordMeaning(''), '--');
      expect(getWordMeaning('   '), '--');
    });
  });
}
