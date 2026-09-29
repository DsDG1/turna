import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/dictionary_search.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/views/dictionary/dictionary_page.dart';

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
          body: DictionaryHitTile(hit: hit, onSpeak: () {}),
        ),
      ),
    );
    expect(find.text('名词'), findsOneWidget);
    expect(find.text('ev'), findsOneWidget);
  });

  test('matches translation and tags', () {
    expect(searchDictionary('thank').single.id, 'w-2');
    expect(searchDictionary('greeting').single.id, 'w-1');
  });
}
