import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/lesson_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showLessonCompletionDialog', () {
    Future<void> openDialog(
      WidgetTester tester, {
      int correctCount = 8,
      int incorrectCount = 2,
      int totalCount = 10,
      int durationSeconds = 95,
      int xpEarned = 25,
      int gemsEarned = 15,
      bool wasPerfect = false,
      List<QuestionResult> questionResults = const [],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showLessonCompletionDialog(
                      context: context,
                      isMounted: () => true,
                      correctCount: correctCount,
                      incorrectCount: incorrectCount,
                      totalCount: totalCount,
                      durationSeconds: durationSeconds,
                      xpEarned: xpEarned,
                      gemsEarned: gemsEarned,
                      wasPerfect: wasPerfect,
                      questionResults: questionResults,
                      random: Random(0),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    testWidgets('shows a celebration title', (tester) async {
      await openDialog(tester);

      // Celebration titles are localized (keyed off styleIndex) rather than
      // stored on LessonCelebrationStyle, so resolve them via AppStrings.
      final titles = [
        AppStrings.lessonCompleteTitle1,
        AppStrings.lessonCompleteTitle2,
        AppStrings.lessonCompleteTitle3,
      ];
      expect(
        titles.any((t) => find.text(t).evaluate().isNotEmpty),
        isTrue,
        reason: 'expected one of $titles',
      );
    });

    testWidgets('renders correct, wrong, time and XP stats', (tester) async {
      await openDialog(
        tester,
        correctCount: 7,
        incorrectCount: 3,
        durationSeconds: 125,
        xpEarned: 10,
      );

      expect(find.text('正确'), findsOneWidget);
      expect(find.text('错误'), findsOneWidget);
      expect(find.text('用时'), findsOneWidget);
      expect(find.text('经验值'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2分5秒'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('shows accuracy percentage', (tester) async {
      await openDialog(
        tester,
        correctCount: 8,
        incorrectCount: 2,
        totalCount: 10,
      );

      expect(find.text('80%'), findsOneWidget);
      expect(find.text('正确率'), findsOneWidget);
    });

    testWidgets('shows perfect badge when wasPerfect is true', (tester) async {
      await openDialog(
        tester,
        correctCount: 5,
        incorrectCount: 0,
        totalCount: 5,
        wasPerfect: true,
      );

      expect(find.text('完美！全部答对。'), findsOneWidget);
    });

    testWidgets('lists question results with correct status', (tester) async {
      await openDialog(
        tester,
        correctCount: 2,
        incorrectCount: 1,
        totalCount: 3,
        questionResults: const [
          QuestionResult(prompt: 'Habari', correct: true),
          QuestionResult(
            prompt: 'Asante',
            correct: false,
            correctAnswer: 'Asante sana',
          ),
          QuestionResult(prompt: 'Jambo', correct: true),
        ],
      );

      expect(find.text('答题明细'), findsOneWidget);
      expect(find.text('1. Habari'), findsOneWidget);
      expect(find.text('2. Asante'), findsOneWidget);
      expect(find.text('3. Jambo'), findsOneWidget);
      expect(find.text('答案：Asante sana'), findsOneWidget);
    });

    testWidgets('dismisses on Continue tap', (tester) async {
      await openDialog(tester);

      expect(find.text('继续'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('继续'), findsNothing);
    });
  });
}
