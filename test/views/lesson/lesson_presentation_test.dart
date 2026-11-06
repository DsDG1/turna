import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/listening_phase.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_presentation.dart';
import 'package:turna/views/lesson/components/listening_audio_panel.dart';
import 'package:turna/views/lesson/components/listening_phase_header.dart';
import 'package:turna/views/widgets/session_shell.dart';

import 'renderers/fake_audio_controller.dart';

void main() {
  group('LessonPresentationProfile', () {
    test('every lesson template has a distinct presentation entry', () {
      for (final template in LessonTemplate.values) {
        final profile = lessonPresentationProfile(template);
        expect(profile.label, isNotEmpty);
        expect(profile.maxWidth, greaterThan(0));
      }
      expect(
        lessonPresentationProfile(LessonTemplate.reading).maxWidth,
        greaterThan(lessonPresentationProfile(LessonTemplate.intro).maxWidth),
      );
      expect(
        lessonPresentationProfile(LessonTemplate.mastery).progressStyle,
        SessionProgressStyle.bar,
      );
    });

    test('maps a flattened listening stage back to its source phase', () {
      const phase = ListeningPhase(
        id: 'dialogue-1',
        name: 'At the market',
        type: ListeningPhaseType.dialogue,
        audioAsset: 'sounds/market.mp3',
        transcript: 'A: Merhaba!',
        items: [
          Interaction.multipleChoice(
            prompt: 'Where are they?',
            options: ['Market', 'School'],
            correctIndex: 0,
          ),
        ],
      );
      const lesson = Lesson(
        id: 'listening-1',
        name: 'Listening',
        type: LessonType.listening,
        template: LessonTemplate.listening,
        content: LessonContent(listeningPhases: [phase]),
      );

      final stage = lesson.flattenedStages.single;
      expect(listeningPhaseForStage(lesson, stage), same(phase));
      expect(listeningPhaseForStage(lesson, null), isNull);
    });
  });

  group('ListeningPhaseHeader', () {
    late FakeAudioController audio;

    setUp(() async {
      await getIt.reset();
      audio = FakeAudioController();
      getIt.registerSingleton<AudioController>(audio);
    });

    tearDown(getIt.reset);

    testWidgets('unlocks the transcript only after playback and on demand',
        (tester) async {
      const phase = ListeningPhase(
        id: 'dialogue-1',
        name: 'Greetings',
        type: ListeningPhaseType.dialogue,
        audioAsset: 'sounds/greetings.mp3',
        transcript: 'A: Merhaba! B: Nasılsın?',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ListeningPhaseHeader(phase: phase)),
        ),
      );

      expect(find.text(phase.transcript), findsNothing);
      expect(find.text('查看听力原文'), findsNothing);

      await tester.tap(find.byType(SpeakerHero));
      await tester.pumpAndSettle();
      expect(audio.spoken, ['sounds/greetings.mp3']);
      expect(find.text(phase.transcript), findsNothing);

      await tester.tap(find.text('查看听力原文'));
      await tester.pumpAndSettle();
      expect(find.text(phase.transcript), findsOneWidget);

      await tester.tap(find.text('收起听力原文'));
      await tester.pumpAndSettle();
      expect(find.text(phase.transcript), findsNothing);
    });
  });

  group('ListeningAudioPanel', () {
    testWidgets('reduced motion makes transcript transition immediate',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ListeningAudioPanel(
                title: '对话理解',
                prompt: '听对话',
                hasPlayed: true,
                showTranscript: true,
                transcript: 'Merhaba',
                onPlay: () {},
              ),
            ),
          ),
        ),
      );

      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
    });

    testWidgets('compact panel fits a narrow screen at 200 percent text',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ListeningAudioPanel(
                  title: '对话理解',
                  prompt: '听一段较长的对话，然后回答问题',
                  hasPlayed: true,
                  showTranscript: true,
                  transcript: 'A: Merhaba!\nB: Nasılsın?',
                  onPlay: () {},
                  onToggleTranscript: () {},
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
