import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/dialogue_scene.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/dialogue_scene_header.dart';

const _scene = DialogueScene(
  id: 'scene',
  title: 'At the cafe',
  characters: [
    DialogueCharacter(id: 'ayse', name: 'Ayşe'),
    DialogueCharacter(id: 'learner', name: '你'),
  ],
  turns: [
    DialogueTurn(id: 't1', speakerId: 'ayse', text: 'Selam'),
    DialogueTurn(id: 't2', speakerId: 'learner', interactionId: 'reply-1'),
    DialogueTurn(id: 't3', speakerId: 'ayse', text: 'Buyurun'),
    DialogueTurn(id: 't4', speakerId: 'learner', interactionId: 'reply-2'),
  ],
);

const _items = [
  Interaction.fillBlank(
    id: 'reply-1',
    sentence: '_____',
    answer: 'Merhaba',
  ),
  Interaction.fillBlank(
    id: 'reply-2',
    sentence: '_____',
    answer: 'Teşekkürler',
  ),
];

Widget _header({String current = 'reply-1', bool submitted = false}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: DialogueSceneHeader(
          scene: _scene,
          interactions: _items,
          currentInteractionId: current,
          currentSubmitted: submitted,
        ),
      ),
    ),
  );
}

void main() {
  test('visible turns stop at the current learner response', () {
    final turns = visibleDialogueTurns(_scene, 'reply-1');
    expect(turns.map((turn) => turn.id), ['t1', 't2']);
  });

  testWidgets('future turns and the current answer stay hidden',
      (tester) async {
    await tester.pumpWidget(_header());

    expect(find.text('Selam'), findsOneWidget);
    expect(find.text(AppStrings.lessonDialogueYourTurn), findsOneWidget);
    expect(find.text('Merhaba'), findsNothing);
    expect(find.text('Buyurun'), findsNothing);
    expect(find.text('Teşekkürler'), findsNothing);
  });

  testWidgets('submission reveals only the current response', (tester) async {
    await tester.pumpWidget(_header(submitted: true));

    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.text('Buyurun'), findsNothing);
    expect(find.text('Teşekkürler'), findsNothing);
  });

  testWidgets('transcript contains visible turns but no future content',
      (tester) async {
    await tester.pumpWidget(_header());
    await tester.tap(find.byTooltip(AppStrings.lessonDialogueFullTranscript));
    await tester.pumpAndSettle();

    expect(find.text('Selam'), findsWidgets);
    expect(find.text(AppStrings.lessonDialogueYourTurn), findsWidgets);
    expect(find.text('Merhaba'), findsNothing);
    expect(find.text('Buyurun'), findsNothing);
  });

  testWidgets('advancing reveals intervening character lines', (tester) async {
    await tester.pumpWidget(_header(current: 'reply-2'));

    expect(find.text('Merhaba'), findsOneWidget);
    expect(find.text('Buyurun'), findsOneWidget);
    expect(find.text('Teşekkürler'), findsNothing);
  });

  testWidgets('narrow screen at 200 percent does not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _header(),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
