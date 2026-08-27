import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/study_session/anki_review_content.dart';
import 'package:turna/application/study_session/anki_study_session_host.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';

void main() {
  StudyItem itemFor(Interaction interaction) {
    return AnkiStudySessionHost.itemFromReviewCard(
      wordId: 'anki-imp1-c42',
      interaction: interaction,
      mode: StudyMode.review,
      courseId: 'anki-imp1',
    );
  }

  test('fidelity presentation maps to OfficialTemplateContent from its card',
      () {
    const interaction = Interaction.ankiHtmlCard(
      id: 'anki-imp1-c42-c0',
      frontHtml: '<b>kedi</b>',
      backHtml: '<i>cat</i>',
      mediaBasePath: '/media/imports/imp1',
    );
    final item = itemFor(interaction);
    final content = reviewContentFor(item, fidelityInteractions: {
      item.sessionItemId: interaction as AnkiHtmlCard,
    });

    expect(content, isA<OfficialTemplateContent>());
    final official = content as OfficialTemplateContent;
    expect(official.frontHtml, '<b>kedi</b>');
    expect(official.backHtml, '<i>cat</i>');
    expect(official.mediaBasePath, '/media/imports/imp1');
  });

  test('fidelity presentation without its card degrades to empty content', () {
    final item = itemFor(
      const Interaction.ankiHtmlCard(frontHtml: 'f', backHtml: 'b'),
    );
    final content = reviewContentFor(item);

    expect(content, isA<StandardCourseCardContent>());
    expect((content as StandardCourseCardContent).frontText, '');
    expect(content.backText, '');
  });

  test('flip presentation keeps front/back text', () {
    final content = reviewContentFor(
      itemFor(const Interaction.ankiCard(front: 'kedi', back: 'cat')),
    );

    expect(content, isA<StandardCourseCardContent>());
    final standard = content as StandardCourseCardContent;
    expect(standard.frontText, 'kedi');
    expect(standard.backText, 'cat');
    expect(standard.interaction, isNull);
  });

  test('structured presentation carries the interaction and its answer', () {
    const interaction = Interaction.multipleChoice(
      prompt: 'Choose the cat',
      options: ['kedi', 'köpek'],
      correctIndex: 0,
    );
    final content = reviewContentFor(itemFor(interaction));

    expect(content, isA<StandardCourseCardContent>());
    final standard = content as StandardCourseCardContent;
    expect(standard.frontText, 'Choose the cat');
    expect(standard.backText, 'kedi');
    expect(standard.interaction, same(interaction));
  });
}
