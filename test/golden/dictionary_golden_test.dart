import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/languages/swahili_vocab.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/views/dictionary/dictionary_page.dart';
import 'package:varnamala/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    swahiliVocabById
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

  tearDown(swahiliVocabById.clear);

  Future<void> pumpDict(WidgetTester tester, ThemeMode mode) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: VarnamalaTheme.lightTheme,
        darkTheme: VarnamalaTheme.darkTheme,
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
