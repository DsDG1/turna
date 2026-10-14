import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/application/study_session/anki_review_content.dart';
import 'package:turna/application/study_session/anki_study_session_host.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';
import 'package:turna/views/review/components/flutter_course_card_body.dart';
import 'package:turna/views/review/components/study_card_surface.dart';

void main() {
  const cardKey = CanonicalCardKey(
      backend: AnkiBackendKind.official,
      profileId: 'profile-default-01',
      sourceId: 'source-test',
      cardId: 1);
  const fidelity = FidelityCardPresentation(
      cardKey: cardKey,
      templateRef: CanonicalTemplateRef(notetypeId: 1, ordinal: 0),
      sourceFingerprint: 'html');

  test('formal content preserves author CSS and media path', () {
    final item = AnkiStudySessionHost.itemFor(
        key: cardKey,
        presentation: fidelity,
        mode: StudyMode.review,
        courseId: 'course');
    final content = reviewContentFor(item, fidelityInteractions: {
      item.sessionItemId: const Interaction.ankiHtmlCard(
          id: 'html',
          frontHtml: '<b>question</b>',
          backHtml: '<b>answer</b>',
          css: '.card { color: red; }',
          mediaBasePath: '/media') as AnkiHtmlCard,
    }) as OfficialTemplateContent;
    expect(content.css, '.card { color: red; }');
    expect(content.mediaBasePath, '/media');
  });

  testWidgets(
      'unavailable official renderer fails without text downgrade or success receipt',
      (tester) async {
    final receipts = <PresentationReceipt>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StudyCardSurface(
      presentation: fidelity,
      content: const OfficialTemplateContent(
          frontHtml: '<b>secret question</b>',
          backHtml: '<b>secret answer</b>'),
      isRevealed: false,
      onReveal: _noop,
      onPresented: receipts.add,
    ))));
    await tester.pump();
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('secret question'), findsNothing);
    expect(receipts, hasLength(1));
    expect(receipts.single.ok, isFalse);
    expect(receipts.single.renderer, PresentationRendererKind.officialTemplate);
  });
  testWidgets('structured MCQ uses the course renderer instead of flip text',
      (tester) async {
    const interaction = Interaction.multipleChoice(
      id: 'mc-1',
      prompt: 'Choose the target',
      options: ['kedi', 'köpek', 'kuş'],
      correctIndex: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyCardSurface(
            content: const StandardCourseCardContent(
              frontText: 'kedi',
              backText: 'cat',
              interaction: interaction,
            ),
            isRevealed: false,
            onReveal: _noop,
            renderers: {
              MultipleChoiceRenderer(),
              MultiSelectRenderer(),
              FillBlankRenderer(),
              ListenAndPickRenderer(),
              TypeTheWordRenderer(),
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Choose the target'), findsOneWidget);
    expect(find.text('kedi'), findsOneWidget);
    expect(find.text('köpek'), findsOneWidget);
    expect(find.byType(FlutterCourseCardBody), findsNothing);
  });

  testWidgets('flip content still uses the shared flip surface',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudyCardSurface(
            content: StandardCourseCardContent(
              frontText: 'merhaba',
              backText: 'hello',
            ),
            isRevealed: false,
            onReveal: _noop,
          ),
        ),
      ),
    );
    expect(find.byType(FlutterCourseCardBody), findsOneWidget);
    expect(find.text('merhaba'), findsOneWidget);
    expect(find.text('hello'), findsNothing);
  });
}

void _noop() {}
