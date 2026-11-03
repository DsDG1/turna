import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    testWidgets('harvest rows do not overflow at 200% text scale',
        (tester) async {
      // 真机收据（2026-10-20）：完成弹层在系统字体放大后曾报
      // `BOTTOM OVERFLOWED BY 25 PIXELS`。改用「结果一行 + 收获纵向」的
      // sheet 结构后守住同一回归：行高自适应、正文可滚动。
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showLessonCompletionDialog(
                    context: context,
                    isMounted: () => true,
                    correctCount: 8,
                    incorrectCount: 2,
                    totalCount: 10,
                    durationSeconds: 95,
                    xpEarned: 25,
                    gemsEarned: 15,
                    wasPerfect: false,
                    random: Random(0),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 收获行仍在树上（溢出会把它们挤出可视区）。
      expect(find.text(AppStrings.lessonCorrect), findsOneWidget);
      expect(find.text(AppStrings.lessonXp), findsOneWidget);
    });

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

    testWidgets('renders correct, wrong, time, XP and gems harvest rows',
        (tester) async {
      await openDialog(
        tester,
        correctCount: 7,
        incorrectCount: 3,
        durationSeconds: 125,
        xpEarned: 10,
        gemsEarned: 6,
      );

      expect(find.text('正确'), findsOneWidget);
      expect(find.text('错误'), findsOneWidget);
      expect(find.text('用时'), findsOneWidget);
      expect(find.text('经验值'), findsOneWidget);
      expect(find.text('宝石'), findsOneWidget);
      // 数值走 AnimatedCounter，pumpAndSettle 后落在终值。
      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('2分5秒'), findsOneWidget);
    });

    testWidgets('shows accuracy in the result line', (tester) async {
      await openDialog(
        tester,
        correctCount: 8,
        incorrectCount: 2,
        totalCount: 10,
      );

      // 结果一行是组合文案（`8 / 10 · 正确率 80%`），用包含式断言。
      expect(find.textContaining('80%'), findsOneWidget);
      expect(find.textContaining(AppStrings.lessonAccuracy), findsOneWidget);
    });

    testWidgets('shows perfect line when wasPerfect is true', (tester) async {
      await openDialog(
        tester,
        correctCount: 5,
        incorrectCount: 0,
        totalCount: 5,
        wasPerfect: true,
      );

      expect(find.text('完美！全部答对。'), findsOneWidget);
    });

    testWidgets('dismisses on Continue tap', (tester) async {
      await openDialog(tester);

      expect(find.text('继续'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('继续'), findsNothing);
    });

    // Regression for the completion-dialog pop loop: the host page sits
    // behind PopScope(canPop: false), so a maybePop after dismiss vetoes the
    // pop and re-enters the page's pop callback forever. The sheet must pop
    // unconditionally so the guarded host route actually leaves.
    testWidgets('Continue pops a PopScope-guarded host page', (tester) async {
      var blockedPops = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) blockedPops++;
              },
              child: Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showLessonCompletionDialog(
                      context: context,
                      isMounted: () => true,
                      correctCount: 8,
                      incorrectCount: 2,
                      totalCount: 10,
                      durationSeconds: 95,
                      xpEarned: 25,
                      gemsEarned: 15,
                      wasPerfect: false,
                      random: Random(0),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      expect(find.text('Open'), findsNothing);
      expect(blockedPops, 0);
    });
  });
}
