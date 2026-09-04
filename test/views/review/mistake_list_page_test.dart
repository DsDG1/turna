// Widget tests for the mistake list page: filter chips switch the visible
// subset, the dashboard entry lives in the app bar, and the removed
// "why wrong" feature leaves no trace in the UI.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/review/mistake_list_page.dart';
import 'package:turna/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late MistakeProvider mistakes;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setString(LocalStateKeys.mistakeLog, '[]');
    mistakes = MistakeProvider(prefs);
  });

  MistakeEntry entry(
    String id, {
    String? wordId,
    String? grammarPointId,
  }) =>
      MistakeEntry(
        id: id,
        lessonId: 'lesson-1',
        stageId: 'stage-1',
        interactionId: 'item-$id',
        wordId: wordId,
        grammarPointId: grammarPointId,
        interactionSnapshot: Interaction.multipleChoice(
          id: 'item-$id',
          prompt: 'Pick one',
          options: ['a', 'b', 'c'],
          correctIndex: 0,
        ),
        userAnswer: 'wrong',
        correctAnswer: 'a',
        timestamp: DateTime.now(),
      );

  Future<void> pumpPage(WidgetTester tester) async {
    // 加高视口：SliverList 懒构建，默认 800x600 放不下 3 张卡片。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<MistakeProvider>.value(
        value: mistakes,
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const MistakeListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle(); // entrance stagger animations
  }

  testWidgets('empty log shows the empty state, not filters', (tester) async {
    await pumpPage(tester);
    expect(find.text(AppStrings.reviewMyMistakesTitle), findsOneWidget);
    expect(find.text(AppStrings.reviewNoMistakesRecorded), findsOneWidget);
    expect(find.text('全部 0'), findsNothing);
  });

  testWidgets('filter chips carry counts and narrow the list', (tester) async {
    await mistakes.record(entry('w-1', wordId: 'word-1'));
    await mistakes.record(entry('w-2', wordId: 'word-2'));
    await mistakes.record(entry('g-1', grammarPointId: 'grammar-1'));
    await pumpPage(tester);

    // Counts on the chips reflect the full log.
    expect(find.text('全部 3'), findsOneWidget);
    expect(find.text('单词 2'), findsOneWidget);
    expect(find.text('语法 1'), findsOneWidget);
    expect(find.text('item-w-1'), findsOneWidget);
    expect(find.text('item-g-1'), findsOneWidget);

    // Switch to words only: grammar card disappears.
    await tester.tap(find.text('单词 2'));
    await tester.pumpAndSettle();
    expect(find.text('item-w-1'), findsOneWidget);
    expect(find.text('item-w-2'), findsOneWidget);
    expect(find.text('item-g-1'), findsNothing);

    // Switch to grammar only.
    await tester.tap(find.text('语法 1'));
    await tester.pumpAndSettle();
    expect(find.text('item-g-1'), findsOneWidget);
    expect(find.text('item-w-1'), findsNothing);
  });

  testWidgets('cards show relative time and rewrite progress semantics',
      (tester) async {
    final now = DateTime.now();
    await mistakes.record(
      entry('w-1', wordId: 'word-1').copyWith(timestamp: now),
    );
    await mistakes.recordRewrite('w-1'); // one of two needed rewrites
    await pumpPage(tester);

    expect(find.text(AppStrings.timeAgo(now)), findsOneWidget);
    // Semantics widget 携带重写进度文本（无障碍：进度不只靠颜色表达）。
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label ==
                AppStrings.reviewRewriteProgress(
                  1,
                  MistakeProvider.rewriteGoal,
                ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the removed why-wrong action leaves no UI trace', (tester) async {
    await mistakes.record(entry('w-1', wordId: 'word-1'));
    await pumpPage(tester);

    expect(find.text('为什么错'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
  });
}
