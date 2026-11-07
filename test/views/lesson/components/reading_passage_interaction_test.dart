import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/reading_passage.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';

void main() {
  setUp(() {
    vocabById['nt-w-ev'] = const WordEntry(
      id: 'nt-w-ev',
      term: 'ev',
      translation: '房子',
      pronunciation: 'ev',
    );
  });
  tearDown(() => vocabById.remove('nt-w-ev'));

  testWidgets('opens a linked gloss for an explicitly mapped word form', (
    tester,
  ) async {
    const passage = ReadingPassage(
      title: 'Evimde',
      paragraphs: ['Evimde bilinmeyen'],
      linkedWordIds: ['nt-w-ev'],
      wordFormMap: {'evimde': 'nt-w-ev'},
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LessonReadingPassageCard(passage: passage)),
      ),
    );

    await tester.tap(find.text(AppStrings.lessonReadingExpand));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InkWell, 'Evimde'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'bilinmeyen'), findsNothing);

    await tester.tap(find.widgetWithText(InkWell, 'Evimde'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect((dialog.title! as Text).data, 'ev');
    expect(find.text('房子'), findsOneWidget);
  });
}
