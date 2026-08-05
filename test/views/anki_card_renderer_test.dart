import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/anki_card_renderer.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

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
  }

  Future<void> revealAnswer(WidgetTester tester) async {
    await tester.tap(find.text('显示答案'));
    // Wait for the scale-pulse animation + status listener rebuild so grade
    // buttons appear only after the pulse completes.
    await tester.pumpAndSettle();
  }

  testWidgets('shows Anki four-grade buttons after reveal settles', (
    tester,
  ) async {
    await pumpCard(
      tester,
      onSubmit: (_, {userAnswerText, reviewQuality}) {},
    );
    await revealAnswer(tester);

    expect(find.text('重来'), findsOneWidget);
    expect(find.text('困难'), findsOneWidget);
    expect(find.text('良好'), findsOneWidget);
    expect(find.text('简单'), findsOneWidget);
  });

  testWidgets('grade buttons are deferred until pulse completes',
      (tester) async {
    await pumpCard(
      tester,
      onSubmit: (_, {userAnswerText, reviewQuality}) {},
    );

    await tester.tap(find.text('显示答案'));
    // Mid-pulse: face may already switch, but grades must not appear yet.
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('重来'), findsNothing);
    expect(find.text('显示答案'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('重来'), findsOneWidget);
    expect(find.text('显示答案'), findsNothing);
  });

  testWidgets('Hard submits success with distinct quality 3', (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await revealAnswer(tester);

    await tester.tap(find.text('困难'));
    expect(results, [(true, 3)]);
  });

  testWidgets('Again submits failure with quality 1', (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await revealAnswer(tester);

    await tester.tap(find.text('重来'));
    expect(results, [(false, 1)]);
  });

  testWidgets('tapping the revealed card flips back to the front',
      (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await revealAnswer(tester);
    expect(find.text('Back side'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('anki-flip-card-surface')));
    await tester.pumpAndSettle();

    expect(find.text('Front side'), findsOneWidget);
    expect(find.text('Back side'), findsNothing);
    expect(find.text('显示答案'), findsOneWidget);
    expect(find.text('重来'), findsNothing);
    expect(results, isEmpty);
  });
}
