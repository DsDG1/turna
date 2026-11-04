import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/dictionary_search.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/views/dictionary/dictionary_page.dart';

void main() {
  setUp(() {
    // resetForTest clears every global map and bumps the store generation,
    // so the memoized search index cannot leak entries from a previous test
    // that happened to seed the same map lengths.
    LanguageContentStore.resetForTest();
    vocabById.addAll({
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

  tearDown(LanguageContentStore.resetForTest);

  test('empty query returns no hits', () {
    expect(searchDictionary(''), isEmpty);
    expect(searchDictionary('   '), isEmpty);
  });

  test('matches term case-insensitively', () {
    final hits = searchDictionary('hab');
    expect(hits, hasLength(1));
    expect(hits.single.id, 'w-1');
    expect(hits.single.kind, DictionaryHitKind.vocab);
    expect(hits.single.posLabel, isNull);
  });

  testWidgets('noun hit shows the Chinese POS label', (tester) async {
    vocabById['w-3'] = const WordEntry(
      id: 'w-3',
      term: 'ev',
      translation: 'house',
      pos: 'noun',
    );
    final hit = searchDictionary('ev').single;
    expect(hit.posLabel, '名词');

    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: DictionaryHitRow(hit: hit),
        ),
      ),
    );
    // R11 阅读目录行：词性与释义合为 14sp 次级色一行。
    expect(find.text('名词 · house'), findsOneWidget);
    expect(find.text('ev'), findsOneWidget);
  });

  test('matches translation and tags', () {
    expect(searchDictionary('thank').single.id, 'w-2');
    expect(searchDictionary('greeting').single.id, 'w-1');
  });

  test('index rebuilds when globals are republished with different content',
      () {
    expect(searchDictionary('hab').single.id, 'w-1');

    // Same entry count, different content: only the store generation can
    // tell the memoized index apart from the previous seeding.
    LanguageContentStore.resetForTest();
    vocabById.addAll({
      'w-1': const WordEntry(id: 'w-1', term: 'Evet', translation: 'Yes'),
      'w-2': const WordEntry(id: 'w-2', term: 'Hayır', translation: 'No'),
    });
    expect(searchDictionary('evet').single.id, 'w-1');
    expect(searchDictionary('hab'), isEmpty);
  });

  test('index rebuilds after an in-place map insertion', () {
    expect(searchDictionary('zeytin'), isEmpty);
    vocabById['w-9'] = const WordEntry(
      id: 'w-9',
      term: 'Zeytin',
      translation: 'Olive',
    );
    expect(searchDictionary('zeytin').single.id, 'w-9');
  });
}
