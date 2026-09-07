import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/lesson/components/interactions/show_word_renderer.dart';

import '../../../helpers/in_memory_course_db.dart';

import 'fake_audio_controller.dart';
import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
    vocabById['w-test-show'] = const WordEntry(
      id: 'w-test-show',
      term: 'Habari',
      translation: 'Hello',
    );
  });

  tearDown(() {
    vocabById.remove('w-test-show');
  });

  testWidgets('ShowWord builds and submits correct on tap', (tester) async {
    final renderer = ShowWordRenderer(FakeAudioController());
    const interaction = Interaction.showWord(
      id: 'sw-1',
      wordId: 'w-test-show',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.text('Habari'), findsOneWidget);

    await tester.tap(find.text('点击继续'));
    await tester.pumpAndSettle();

    expect(harness.submissions, [(true, null)]);
  });

  testWidgets('ShowWord speaks term and context sentence on tap',
      (tester) async {
    final audio = FakeAudioController();
    final renderer = ShowWordRenderer(audio);
    const interaction = Interaction.showWord(
      id: 'sw-1',
      wordId: 'w-test-show',
      context: 'Habari asubuhi. — Good morning.',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.text('Habari'), findsOneWidget);
    expect(find.text('Habari asubuhi. — Good morning.'), findsOneWidget);

    // Tapping the word speaks the term and does not submit.
    await tester.tap(find.text('Habari'));
    await tester.pumpAndSettle();
    expect(audio.lastSpoken, 'Habari');
    expect(harness.submissions, isEmpty);

    // Tapping the context sentence speaks only the target-language part.
    await tester.tap(find.text('Habari asubuhi. — Good morning.'));
    await tester.pumpAndSettle();
    expect(audio.lastSpoken, 'Habari asubuhi.');
    expect(harness.submissions, isEmpty);
  });

  testWidgets('ShowWord renders long terms on narrow screens without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    final audio = FakeAudioController();
    final renderer = ShowWordRenderer(audio);
    const interaction = Interaction.showWord(
      id: 'sw-long',
      wordId: 'w-long',
      term: 'affedersiniz',
      translation: 'excuse me',
      context: 'affedersiniz — excuse me',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.text('affedersiniz'), findsOneWidget);
    expect(find.text('excuse me'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('affedersiniz'));
    await tester.pumpAndSettle();
    expect(audio.lastSpoken, 'affedersiniz');
    expect(tester.takeException(), isNull);
  });

  testWidgets('canonicalLink fail-closes without opening vocab or Legacy',
      (tester) async {
    OfficialAnkiCourseEntry.resetHooks();
    addTearDown(OfficialAnkiCourseEntry.resetHooks);
    OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags();
    final renderer = ShowWordRenderer(FakeAudioController());
    final interaction = Interaction.showWord(
      id: 'sw-link',
      wordId: officialAnkiCanonicalWordId(sourceId: 'src1', cardId: 1),
      context: 'official-canonical-link:src1:1',
    );
    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.byKey(const Key('official-canonical-fail-closed')),
        findsOneWidget);
    expect(find.byKey(const Key('official-canonical-continue')), findsNothing);
    expect(find.text('Habari'), findsNothing);
    expect(find.byType(OfficialAnkiReviewerPage), findsNothing);
  });

  testWidgets('canonicalLink renders inline without a route push',
      (tester) async {
    ensurePathProviderMockForTest();
    OfficialAnkiCourseEntry.resetHooks();
    addTearDown(OfficialAnkiCourseEntry.resetHooks);
    OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags(
          engine: true,
          catalogReady: true,
          runtimeCapable: true,
          platformReady: true,
          renderer: true,
        );
    final renderer = ShowWordRenderer(FakeAudioController());
    final interaction = Interaction.showWord(
      id: 'sw-link',
      wordId: officialAnkiCanonicalWordId(sourceId: 'src1', cardId: 9),
      context: 'official-canonical-link:src1:9',
    );
    await tester.pumpWidget(harness.buildRouted(renderer, interaction));
    // AutoRoute resolves the initial host page asynchronously; boot then
    // fails deterministically (no worker session in the test environment).
    await tester.pumpAndSettle();

    // No route push ever happens: the card itself is the surface.
    expect(find.byType(OfficialAnkiReviewerPage), findsNothing);
    expect(find.byKey(const Key('official-canonical-boot-failed')),
        findsOneWidget);
    // Release hatch: a card whose boot failed must not stall the lesson.
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('official-canonical-continue')),
    );
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('official-canonical-continue')));
    await tester.pumpAndSettle();
    expect(harness.submissions, [(true, null)]);
  });
}
