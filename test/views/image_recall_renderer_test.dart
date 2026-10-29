import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/image_recall_renderer.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

/// ADR 0057 §4: image recall shows a prompt-side image, then reveals the text
/// and self-grades. The answer text does not exist in the tree before reveal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<bool>> pumpRecall(WidgetTester tester) async {
    final results = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageRecallRenderer().build(
            const Interaction.imageRecall(
              id: 'image-recall-1',
              imageAssets: ['prompt.png'],
              answerText: 'kedi',
            ),
            const InteractionState(),
            (correct, {userAnswerText, reviewQuality}) =>
                results.add(correct),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('answer text is absent until the reveal', (tester) async {
    await pumpRecall(tester);

    expect(find.text('kedi'), findsNothing);
    expect(find.text(AppStrings.lessonShowAnswer), findsOneWidget);
    expect(find.text(AppStrings.reviewBinaryRemembered), findsNothing);
  });

  testWidgets('reveal shows the answer and the binary grade row',
      (tester) async {
    await pumpRecall(tester);

    await tester.tap(find.text(AppStrings.lessonShowAnswer));
    await tester.pumpAndSettle();

    expect(find.text('kedi'), findsOneWidget);
    expect(find.text(AppStrings.reviewBinaryRemembered), findsOneWidget);
    expect(find.text(AppStrings.reviewBinaryForgotten), findsOneWidget);
  });

  testWidgets('"remembered" submits a passing recall with the good rating',
      (tester) async {
    final results = await pumpRecall(tester);

    await tester.tap(find.text(AppStrings.lessonShowAnswer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.reviewBinaryRemembered));
    await tester.pumpAndSettle();

    expect(results, [true]);
  });

  testWidgets('"forgotten" submits a failing recall', (tester) async {
    final results = await pumpRecall(tester);

    await tester.tap(find.text(AppStrings.lessonShowAnswer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.reviewBinaryForgotten));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  test('the interaction exposes its answer for mistake logging', () {
    const interaction = Interaction.imageRecall(
      imageAssets: ['prompt.png'],
      answerText: 'kedi',
    );

    expect(interactionCorrectAnswerLabel(interaction), 'kedi');
    // No text prompt on the question face, and no AI hint offer.
    expect(interactionPromptLabel(interaction), isEmpty);
    expect(interactionAiHintEligible(interaction), isFalse);
    expect(
      interactionCorrectAnswerLabel(
        const Interaction.dictation(audioAssets: [], expected: 'kopek'),
      ),
      'kopek',
    );
  });

  test('AnkiReviewRating is still the shared binary vocabulary', () {
    expect(AnkiReviewRating.again.quality, lessThan(AnkiReviewRating.good.quality));
  });
}
