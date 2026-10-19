import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
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

  testWidgets('shows Anki binary recall buttons after reveal settles', (
    tester,
  ) async {
    await pumpCard(
      tester,
      onSubmit: (_, {userAnswerText, reviewQuality}) {},
    );
    await revealAnswer(tester);

    expect(find.text('不记得'), findsOneWidget);
    expect(find.text('记得'), findsOneWidget);
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
    expect(find.text('不记得'), findsNothing);
    expect(find.text('显示答案'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('不记得'), findsOneWidget);
    expect(find.text('显示答案'), findsNothing);
  });

  testWidgets('Remembered submits success with quality 4', (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await revealAnswer(tester);

    await tester.tap(find.text('记得'));
    expect(results, [(true, 4)]);
  });

  testWidgets('Forgotten submits failure with quality 1', (tester) async {
    final results = <(bool, int?)>[];
    await pumpCard(
      tester,
      onSubmit: (correct, {userAnswerText, reviewQuality}) =>
          results.add((correct, reviewQuality)),
    );
    await revealAnswer(tester);

    await tester.tap(find.text('不记得'));
    expect(results, [(false, 1)]);
  });

  testWidgets('the card offers no read-aloud control on either face',
      (tester) async {
    // Read-aloud was an addition, not a rendering: the two faces carry no
    // language semantics (see `Interaction.ankiCard`), so speaking them used
    // the course voice on text the course never taught.
    await pumpCard(
      tester,
      onSubmit: (_, {userAnswerText, reviewQuality}) {},
    );
    expect(find.byIcon(Icons.record_voice_over_rounded), findsNothing);
    expect(find.byTooltip('朗读'), findsNothing);

    await revealAnswer(tester);
    expect(find.text('Back side'), findsOneWidget);
    expect(find.byIcon(Icons.record_voice_over_rounded), findsNothing);
    expect(find.byTooltip('朗读'), findsNothing);
  });

  testWidgets("the card's own media strip still mounts after the removal",
      (tester) async {
    // The removal is scoped to app-side TTS. `[sound:]` media is the card's own
    // content and has to keep reaching the learner, so the strip must still be
    // built for a card that carries audio. The strip's own play/resolve
    // contract is covered by `anki_media_strip_test.dart`; here the assertion
    // stops at "it is mounted", because resolving the ref needs path_provider
    // and never completes on a bare test host.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnkiCardRenderer().build(
            const Interaction.ankiCard(
              id: 'anki-review-w2',
              front: 'Front side',
              back: 'Back side',
              audioAssets: ['anki://import-1/clip.mp3'],
            ),
            const InteractionState(),
            (_, {userAnswerText, reviewQuality}) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AnkiMediaStrip), findsOneWidget);
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
    expect(find.text('不记得'), findsNothing);
    expect(results, isEmpty);
  });
}
