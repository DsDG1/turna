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
import 'package:turna/domain/repositories/i_mistake_repository.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/review/mistake_list_page.dart';
import 'package:turna/views/widgets/turna_icon.dart';

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

  MistakeEntry entry(String id, {String? wordId, String? grammarPointId}) =>
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

  testWidgets('cards show relative time and rewrite progress semantics', (
    tester,
  ) async {
    final now = DateTime.now();
    await mistakes.record(
      entry('w-1', wordId: 'word-1').copyWith(timestamp: now),
    );
    await mistakes.recordRewrite('w-1'); // one of two needed rewrites
    await pumpPage(tester);

    // 时间并入行内元信息（「类型 · 刚刚」），按包含断言。
    expect(find.textContaining(AppStrings.timeAgo(now)), findsOneWidget);
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

  testWidgets('the removed why-wrong action leaves no UI trace', (
    tester,
  ) async {
    await mistakes.record(entry('w-1', wordId: 'word-1'));
    await pumpPage(tester);

    expect(find.text('为什么错'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is TurnaIcon && w.id == TurnaIconId.spark,
      ),
      findsNothing,
    );
  });

  testWidgets('load error shows retry state and recovers on retry', (
    tester,
  ) async {
    mistakes.useRepository(_FlakyMistakeRepo([entry('w-retry', wordId: 'w1')]));
    await mistakes.ensureLoaded();
    expect(mistakes.hasLoadError, isTrue);

    await pumpPage(tester);
    expect(find.text(AppStrings.mistakesLoadFailed), findsOneWidget);
    expect(find.text(AppStrings.commonRetry), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonRetry));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.mistakesLoadFailed), findsNothing);
    expect(find.text('item-w-retry'), findsOneWidget);
  });
}

class _FlakyMistakeRepo implements IMistakeRepository {
  _FlakyMistakeRepo(this._entries);

  final List<MistakeEntry> _entries;
  int _calls = 0;

  @override
  Future<List<MistakeEntry>> load(String languageCode) async {
    _calls++;
    if (_calls == 1) throw StateError('mistake load error');
    return _entries;
  }

  @override
  Future<Map<String, int>> loadDailyCounts(String languageCode) async =>
      const <String, int>{};

  @override
  Future<int> loadMasteredTotal(String languageCode) async => 0;

  @override
  Future<void> replaceAll({
    required String languageCode,
    required List<MistakeEntry> entries,
    required Map<String, int> dailyCounts,
    required int masteredTotal,
    int maxEntries = IMistakeRepository.defaultMaxEntries,
  }) async {}

  @override
  Future<void> insertEntry({
    required String languageCode,
    required MistakeEntry entry,
    required Map<String, int> dailyCounts,
    required int masteredTotal,
    bool evictOldest = false,
  }) async {}

  @override
  Future<void> updateEntry({
    required String languageCode,
    required MistakeEntry entry,
    Map<String, int>? dailyCounts,
    int? masteredTotal,
  }) async {}

  @override
  Future<void> deleteEntriesByIds({
    required String languageCode,
    required Iterable<String> ids,
    Map<String, int>? dailyCounts,
    int? masteredTotal,
  }) async {}

  @override
  Future<void> deleteLanguage(String languageCode) async {}

  @override
  Future<bool> migrateFromPrefsJson({
    required String languageCode,
    required String logJson,
    required String dailyCountsJson,
    required int masteredTotal,
  }) async => false;
}
