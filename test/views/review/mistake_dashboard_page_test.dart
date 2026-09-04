// Widget tests for the mistake dashboard: KPI values from provider
// aggregates, 14-day trend summary, type distribution, frequent-mistake
// badges, oldest entries, and the fully-empty state.

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
import 'package:turna/views/review/mistake_dashboard_page.dart';
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
    await prefs.preferences.setString(
      LocalStateKeys.mistakeDailyCounts,
      '{}',
    );
    await prefs.preferences.setInt(LocalStateKeys.mistakeMasteredTotal, 0);
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
    // 加高视口：ListView 懒构建，让 KPI/趋势/分布/高频/最久各区块一次挂载。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<MistakeProvider>.value(
        value: mistakes,
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const MistakeDashboardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a fresh install shows the empty state', (tester) async {
    await pumpPage(tester);
    expect(find.text(AppStrings.mistakeDashboardTitle), findsOneWidget);
    expect(find.text(AppStrings.mistakeDashboardEmptyTitle), findsOneWidget);
  });

  testWidgets('KPIs, trend, distribution, frequent and oldest render',
      (tester) async {
    await mistakes.record(entry('w-1', wordId: 'word-dup'));
    await mistakes.record(entry('w-2', wordId: 'word-dup'));
    await mistakes.record(entry('g-1', grammarPointId: 'grammar-1'));
    await mistakes.recordRewrite('g-1'); // one rewrite → 待巩固 1

    await pumpPage(tester);

    // KPI row: 3 active, 0 mastered, 1 to consolidate.
    expect(find.text(AppStrings.mistakeDashboardActiveLabel), findsOneWidget);
    expect(find.text(AppStrings.mistakeDashboardMasteredLabel), findsOneWidget);
    expect(
      find.text(AppStrings.mistakeDashboardConsolidateLabel),
      findsOneWidget,
    );

    // Trend summary: all 3 mistakes landed today.
    expect(
      find.text(AppStrings.mistakeDashboardTrendSummary(1, 3)),
      findsOneWidget,
    );

    // Distribution legend: 2 words (67%) and 1 grammar (33%).
    expect(find.text('2 · 67%'), findsOneWidget);
    expect(find.text('1 · 33%'), findsOneWidget);

    // Frequent section: word-dup appears twice.
    expect(
      find.text(AppStrings.mistakeDashboardFrequentTitle),
      findsOneWidget,
    );
    expect(find.text(AppStrings.mistakeDashboardTimes(2)), findsOneWidget);

    // Oldest section shows today's entries as "刚刚".
    expect(
      find.text(AppStrings.mistakeDashboardOldestTitle),
      findsOneWidget,
    );
    expect(find.text(AppStrings.timeAgo(DateTime.now())), findsWidgets);
  });

  testWidgets('mastered-only history still renders the dashboard',
      (tester) async {
    await mistakes.record(entry('w-1', wordId: 'word-1'));
    await mistakes.recordRewrite('w-1');
    await mistakes.recordRewrite('w-1'); // mastered out of the log

    await pumpPage(tester);

    // The log is empty now, but the aggregate keeps the page alive.
    expect(find.text(AppStrings.mistakeDashboardEmptyTitle), findsNothing);
    expect(find.text(AppStrings.mistakeDashboardActiveLabel), findsOneWidget);
    expect(find.text('1'), findsWidgets); // mastered total KPI
  });
}
