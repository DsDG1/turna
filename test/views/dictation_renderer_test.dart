import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/dictation_renderer.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';

import 'lesson/renderers/renderer_test_helper.dart';

/// ADR 0057 §4: dictation is audio-in, typed-out. The answer must not be
/// readable (or screen-read) before submit.
///
/// 渲染器不再自己画 CTA —— "核对" 由页面底栏承担, 所以测试必须挂真实的
/// [PracticeSessionBody], 否则按钮根本不存在 (见 renderer_test_helper.dart
/// 的同一说明).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<bool>> pumpDictation(
    WidgetTester tester, {
    required String expected,
  }) async {
    final results = <bool>[];
    var state = const InteractionState();
    late StateSetter rebuild;
    final renderer = DictationRenderer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return PracticeSessionBody(
                submitted: state.submitted,
                autoAdvance: renderer.autoAdvance,
                continueLabel: AppStrings.lessonContinueUpper,
                onAdvance: () {},
                child: renderer.build(
                  Interaction.dictation(
                    id: 'dictation-1',
                    audioAssets: const ['word.mp3'],
                    expected: expected,
                  ),
                  state,
                  (correct, {userAnswerText, reviewQuality}) {
                    results.add(correct);
                    rebuild(() {
                      state = InteractionState(
                        submitted: true,
                        correct: correct,
                        userAnswerText: userAnswerText,
                      );
                    });
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('the answer is not on the question face', (tester) async {
    await pumpDictation(tester, expected: 'kedi');

    expect(find.text('kedi'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(AppStrings.lessonDictationPrompt), findsOneWidget);
  });

  testWidgets('a correct answer submits true without a correction banner',
      (tester) async {
    final results = await pumpDictation(tester, expected: 'kedi');

    await enterText(tester, 'kedi');
    await tapCheck(tester);

    expect(results, [true]);
    expect(find.byType(LessonCorrectAnswerBanner), findsNothing);
  });

  testWidgets('a wrong answer submits false and shows the expected text',
      (tester) async {
    final results = await pumpDictation(tester, expected: 'kedi');

    await enterText(tester, 'kopek');
    await tapCheck(tester);

    expect(results, [false]);
    expect(find.byType(LessonCorrectAnswerBanner), findsOneWidget);
    // The banner renders "答案: <expected>" through RichText.
    expect(
      find.textContaining('kedi', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('Turkish case folding is accepted', (tester) async {
    final results = await pumpDictation(tester, expected: 'İstanbul');

    await enterText(tester, 'istanbul');
    await tapCheck(tester);

    expect(results, [true]);
  });
}
