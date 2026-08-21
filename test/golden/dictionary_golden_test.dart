@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/views/dictionary/dictionary_page.dart';
import 'package:turna/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    vocabById
      ..clear()
      ..addAll({
        'w-1': const WordEntry(
          id: 'w-1',
          term: 'Habari',
          translation: 'Hello',
          pronunciation: 'ha-ba-ri',
        ),
      });
  });

  tearDown(vocabById.clear);

  Future<void> pumpDict(WidgetTester tester, ThemeMode mode) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        darkTheme: TurnaTheme.darkTheme,
        themeMode: mode,
        home: const DictionaryPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Habari');
    await tester.pumpAndSettle();
  }

  testWidgets('dictionary light golden', (tester) async {
    await pumpDict(tester, ThemeMode.light);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dictionary_light.png'),
    );
  });

  testWidgets('dictionary dark golden', (tester) async {
    await pumpDict(tester, ThemeMode.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dictionary_dark.png'),
    );
  });
}
