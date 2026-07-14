import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/dictionary_search.dart';
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/course/word_entry.dart';

void main() {
  setUp(() {
    vocabById
      ..clear()
      ..addAll({
        'w-1': const WordEntry(
          id: 'w-1',
          term: 'Habari',
          translation: 'Hello',
          tags: ['greeting'],
        ),
        'w-2': const WordEntry(
          id: 'w-2',
          term: 'Asante',
          translation: 'Thank you',
          tags: ['polite'],
        ),
      });
  });

  tearDown(vocabById.clear);

  test('empty query returns no hits', () {
    expect(searchDictionary(''), isEmpty);
    expect(searchDictionary('   '), isEmpty);
  });

  test('matches term case-insensitively', () {
    final hits = searchDictionary('hab');
    expect(hits, hasLength(1));
    expect(hits.single.id, 'w-1');
    expect(hits.single.kind, DictionaryHitKind.vocab);
  });

  test('matches translation and tags', () {
    expect(searchDictionary('thank').single.id, 'w-2');
    expect(searchDictionary('greeting').single.id, 'w-1');
  });
}
