import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/anki_card_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const interaction = Interaction.ankiCard(
    id: 'anki-review-w1',
    front: 'Front side',
    back: 'Back side',
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required OnInteractionSubmit onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        
        
        home: Scaffold(
          body: AnkiCardRenderer().build(
            interaction,
            const InteractionState(),
            onSubmit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Reveal the back so the grade buttons appear.
    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows exactly two grade buttons (binary grading)', (
    tester,
  ) async {
    await pumpCard(tester, onSubmit: (_, {userAnswerText}) {});

    expect(find.text('不认识'), findsOneWidget);
    expect(find.text('认识'), findsOneWidget);
    // No remnants of the old 4-button grading.
    expect(find.text('Again'), findsNothing);
    expect(find.text('Hard'), findsNothing);
    expect(find.text('Good'), findsNothing);
    expect(find.text('Easy'), findsNothing);
  });

  testWidgets('"Know it" submits correct = true', (tester) async {
    final results = <bool>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText}) => results.add(correct),
    );

    await tester.tap(find.text('认识'));
    expect(results, [true]);
  });

  testWidgets('"Don\'t know" submits correct = false', (tester) async {
    final results = <bool>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText}) => results.add(correct),
    );

    await tester.tap(find.text('不认识'));
    expect(results, [false]);
  });
}
