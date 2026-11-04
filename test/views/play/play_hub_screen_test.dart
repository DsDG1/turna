import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/play/play_hub_screen.dart';
import 'package:turna/views/widgets/directory_rows.dart';

import '../../helpers/in_memory_course_db.dart';

/// Scope-mutable stand-in so tests can flip the active course without a DB.
/// 练习台按当前课程 scope 裁剪队列（ADR 0037 / 0067）：语言课程显示语言
/// 三队列，记忆卡课程显示记忆卡复习行。
class _ScopeStubCourseProvider extends CourseProvider {
  _ScopeStubCourseProvider({CourseScope initialScope = const BuiltinCourseScope('turkish')})
      : _scope = initialScope;

  CourseScope _scope;

  set scope(CourseScope value) {
    _scope = value;
    notifyListeners();
  }

  @override
  CourseScope get scope => _scope;
}

const _ankiScope = OfficialAnkiCourseScope(
  profileId: 'profile-default-01',
  sourceId: 'deck1',
);

/// 行内计数位：定位「记忆卡复习」行（DirectoryTaskRow）内的计数字段。
Finder deckRowCountLabel() => find.descendant(
      of: find.ancestor(
        of: find.text('记忆卡复习'),
        matching: find.byType(DirectoryTaskRow),
      ),
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.data != '记忆卡复习',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
  });

  /// Wraps [child] in the provider stack PlayHubScreen selects from.
  /// Accessibility/Settings 只被长按浮窗的触感路径读取，一并注入。
  Widget wrapProviders(
    Widget child, {
    _ScopeStubCourseProvider? courseProvider,
  }) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CourseProvider>(
            create: (_) => courseProvider ?? _ScopeStubCourseProvider(),
          ),
          ChangeNotifierProvider(create: (_) => MistakeProvider(prefs)),
          ChangeNotifierProvider(
            create: (_) => SrsProvider(
              prefs,
              LessonLinkStore(prefs),
              emptySrsStateDao(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => GrammarReviewProvider(
              prefs,
              LessonLinkStore(prefs),
              emptySrsStateDao(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => GameProvider.forTesting(prefs)),
          ChangeNotifierProvider<AiEngineConfigHolder>(
            create: (_) => AiEngineConfigHolder(),
          ),
          ChangeNotifierProvider(create: (_) => AccessibilityProvider(prefs)),
          ChangeNotifierProvider(create: (_) => SettingsProvider(prefs)),
        ],
        child: child,
      );

  Widget hubTree({_ScopeStubCourseProvider? courseProvider}) => wrapProviders(
        const Scaffold(body: PlayHubScreen()),
        courseProvider: courseProvider,
      );

  testWidgets('renders redesigned play hub sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: hubTree()));
    await tester.pumpAndSettle();

    // 页内页头：pageTitle + 日期行。
    expect(find.text(AppStrings.playTitle), findsOneWidget);

    // 今日复习玻璃对象：标签 + 大数字 + 开始 CTA。
    expect(find.text(AppStrings.reviewTodayTitle), findsOneWidget);
    expect(find.text(AppStrings.playTodayStartReview), findsOneWidget);
    expect(
      tester.widget<Text>(
        find.byKey(const Key('play-today-hero-number')),
      ).data,
      '0',
    );

    // 分区标题。
    expect(find.text(AppStrings.playQueueSectionTitle), findsOneWidget);
    expect(find.text(AppStrings.playPracticeToolsTitle), findsOneWidget);

    // 复习队列 = 有顺序的任务行（错题 clay 置顶 / SRS teal / 语法 sky /
    // 智能练习芦苇青）。语言课程激活时没有记忆卡复习行。
    expect(find.text('错题复习'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('语法复习'), findsOneWidget);
    expect(find.text('智能练习'), findsOneWidget);
    expect(find.text('记忆卡复习'), findsNothing);

    // 智能练习：默认空配置 -> 行内「未配置」计数位。
    final smartRow = find.ancestor(
      of: find.text('智能练习'),
      matching: find.byType(DirectoryTaskRow),
    );
    expect(
      find.descendant(of: smartRow, matching: find.text('未配置')),
      findsOneWidget,
    );

    // 工具文字索引：每日挑战 / 薄弱单词 / 词典 / 复习进度（练习台不再有
    // 记忆卡入口，ADR 0067）。
    expect(find.text('每日挑战'), findsOneWidget);
    expect(find.text('薄弱单词'), findsOneWidget);
    expect(find.text('词典'), findsOneWidget);
    expect(find.text('复习进度'), findsOneWidget);

    expect(find.byType(PageView), findsNothing);
  });

  testWidgets(
    'anki course swaps language queues for the memory-card row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: hubTree(
            courseProvider: _ScopeStubCourseProvider(initialScope: _ankiScope),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ADR 0037：记忆卡课程激活时语言三队列让位给记忆卡复习。
      expect(find.text('错题复习'), findsNothing);
      expect(find.text('复习'), findsNothing);
      expect(find.text('语法复习'), findsNothing);
      expect(find.text('记忆卡复习'), findsOneWidget);
      expect(find.text('智能练习'), findsOneWidget);

      // 工具索引与当前课程无关，常驻。
      expect(find.text('每日挑战'), findsOneWidget);
      expect(find.text('薄弱单词'), findsOneWidget);
      expect(find.text('词典'), findsOneWidget);
      expect(find.text('复习进度'), findsOneWidget);
    },
  );

  testWidgets('queue follows scope changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final courseProvider = _ScopeStubCourseProvider();
    await tester.pumpWidget(
        MaterialApp(home: hubTree(courseProvider: courseProvider)));
    await tester.pumpAndSettle();
    expect(find.text('错题复习'), findsOneWidget);
    expect(find.text('记忆卡复习'), findsNothing);

    // 语言 → 记忆卡：IndexedStack 保留的 Play Hub 必须随 scope 通知重建。
    courseProvider.scope = _ankiScope;
    await tester.pumpAndSettle();
    expect(find.text('记忆卡复习'), findsOneWidget);
    expect(find.text('错题复习'), findsNothing,
        reason: '记忆卡课程激活时语言队列必须让位');

    // 记忆卡 → 语言（切回语言课程）：记忆卡行消失，语言队列回来。
    courseProvider.scope = const BuiltinCourseScope('turkish');
    await tester.pumpAndSettle();
    expect(find.text('记忆卡复习'), findsNothing);
    expect(find.text('错题复习'), findsOneWidget);
  });

  testWidgets('memory card row opens the formal review session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    OfficialAnkiHomeDueSync.debugRefreshOverride = () async {};
    addTearDown(() => OfficialAnkiHomeDueSync.debugRefreshOverride = null);
    String? opened;
    FormalReviewNavigator.debugOpenSession = (context, sectionId) async {
      opened = FormalReviewLauncher.sessionRouteName;
    };
    addTearDown(() => FormalReviewNavigator.debugOpenSession = null);

    await tester.pumpWidget(
      MaterialApp(
        home: hubTree(
          courseProvider: _ScopeStubCourseProvider(initialScope: _ankiScope),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('记忆卡复习'));
    await tester.tap(find.text('记忆卡复习'));
    await tester.pumpAndSettle();

    expect(
      opened,
      FormalReviewLauncher.sessionRouteName,
      reason: '记忆卡复习行点按直开正式复习（ADR 0037），不再绕道中枢',
    );
  });

  group('today hero due number (OfficialFormalDueRepository reactivity)', () {
    // 记忆卡行的计数位读 due 仓库单例；测试里用 debug seam 顶掉真实同步，
    // 并用 resetForTest 隔离进程级快照。
    setUp(() {
      OfficialFormalDueRepository.instance.resetForTest();
      OfficialAnkiHomeDueSync.debugRefreshOverride = () async {};
      // TTL 是进程级静态：同 isolate 里更早的测试可能已置位，不清掉的话
      // initState 刷新会被跳过（这正是生产端「5 分钟内重进不刷新」的行为）。
      PlayHubScreen.resetDueRefreshTtlForTest();
    });

    tearDown(() {
      OfficialAnkiHomeDueSync.debugRefreshOverride = null;
      OfficialFormalDueRepository.instance.resetForTest();
    });

    void commitDueSnapshot(String importId, Set<int> schedulerDue) {
      OfficialFormalDueRepository.instance.commit(
        OfficialFormalDueUpdate(
          bySource: {
            importId: buildFormalDuePerSource(
              importId: importId,
              schedulerDueCardIds: schedulerDue,
              schedulerDueSynced: true,
              activePlacementCardIds: schedulerDue,
              suspendedCardIds: const {},
              buriedCardIds: const {},
              retiredCardIds: const {},
            ),
          },
          rawDueBySource: const {},
          turnaDue: 0,
          unintroducedNew: 0,
        ),
        basedOnGeneration: OfficialFormalDueRepository.instance.generation,
      );
    }

    testWidgets('follows repository commits without any setState',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: hubTree(
            courseProvider:
                _ScopeStubCourseProvider(initialScope: _ankiScope),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 空快照：行内计数位不显示数字（0 不占位）。
      expect(deckRowCountLabel(), findsNothing);

      // 仓库 commit（无 setState、无 provider 变化）→ 记忆卡行必须重建。
      commitDueSnapshot('deck1', {11, 22});
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(deckRowCountLabel()).data, '2',
          reason: 'due 仓库是 ChangeNotifier，Play Hub 必须订阅它的通知，'
              '否则计数冻结在 mount 时的值');
    });

    testWidgets('returning from the anki session re-syncs the due snapshot',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var dueAfterSync = const <int>{};
      var refreshRuns = 0;
      OfficialAnkiHomeDueSync.debugRefreshOverride = () async {
        refreshRuns++;
        commitDueSnapshot('deck1', dueAfterSync);
      };
      FormalReviewNavigator.debugOpenSession = (context, sectionId) async {};
      addTearDown(() => FormalReviewNavigator.debugOpenSession = null);

      await tester.pumpWidget(
        MaterialApp(
          home: hubTree(
            courseProvider:
                _ScopeStubCourseProvider(initialScope: _ankiScope),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // initState 的首次 due 刷新。
      expect(refreshRuns, 1);

      // 模拟一次复习会话结束（调度器还欠 2 张）：经长按浮窗「进入」开
      // 会话，pop 返回后必须重取快照。
      dueAfterSync = {11, 22};
      await tester.ensureVisible(find.text('记忆卡复习'));
      await tester.longPress(find.text('记忆卡复习'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.playPopupEnter));
      await tester.pumpAndSettle();

      expect(refreshRuns, 2,
          reason: '复习会话只改调度器，返回 Play 页必须显式 refresh，'
              '否则仓库里的 schedulerDue 还是进会话前的旧值');
      expect(tester.widget<Text>(deckRowCountLabel()).data, '2');
    });

    testWidgets('returning to the Play tab re-syncs the due snapshot',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var refreshRuns = 0;
      OfficialAnkiHomeDueSync.debugRefreshOverride = () async {
        refreshRuns++;
      };

      // 本页在 TabStack 里永久挂载，切回来不会重跑 initState —— 这条测试
      // 锁住「靠 tab 通知刷新」这个唯一通道。
      final owned = !getIt.isRegistered<TabRouter>();
      final router = owned ? TabRouter() : getIt<TabRouter>();
      if (owned) getIt.registerSingleton<TabRouter>(router);
      addTearDown(() async {
        if (owned) await getIt.unregister<TabRouter>();
      });

      await tester.pumpWidget(MaterialApp(home: hubTree()));
      await tester.pumpAndSettle();
      expect(refreshRuns, 1, reason: '首次挂载刷一次');

      router.switchTo(TabDestination.learn);
      await tester.pumpAndSettle();
      // 跨过 3 秒防抖，模拟真实的「切走一会儿再回来」。
      PlayHubScreen.resetDueRefreshTtlForTest();
      router.switchTo(TabDestination.play);
      await tester.pumpAndSettle();

      expect(refreshRuns, 2, reason: '切回练习页必须重取 due 快照，否则数字永远停在首次挂载时的值');
    });

    testWidgets('an unavailable due snapshot shows em-dash, not a stale 0',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      OfficialAnkiHomeDueSync.debugRefreshOverride = () async {};

      await tester.pumpWidget(
        MaterialApp(
          home: hubTree(
            courseProvider:
                _ScopeStubCourseProvider(initialScope: _ankiScope),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(deckRowCountLabel(), findsNothing);

      // 同步失败：行内显示「—」（fail-closed，不冒充 0）；重试条回到
      // 本页（记忆卡中枢已撤销，ADR 0067）。
      OfficialFormalDueRepository.instance.markUnavailable(StateError('boom'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(deckRowCountLabel()).data, '—');
      expect(
        find.byKey(const Key('play-anki-due-unavailable')),
        findsOneWidget,
      );
    });
  });

  group('long-press info popup', () {
    testWidgets('mistake tile long-press shows data panel, scrim closes it',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(home: hubTree()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('错题复习'));
      await tester.pumpAndSettle();

      // 浮窗数据行 + 进入按钮出现。
      expect(find.text(AppStrings.playPopupMistakePending), findsOneWidget);
      expect(find.text(AppStrings.playPopupMistakeGrammar), findsOneWidget);
      expect(find.text(AppStrings.playPopupMistakeRewrite), findsOneWidget);
      expect(find.text(AppStrings.playPopupEnter), findsOneWidget);

      // 点遮罩关闭。
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.playPopupMistakePending), findsNothing);
      expect(find.text(AppStrings.playPopupEnter), findsNothing);
    });

    testWidgets('anki popup enter button opens the shared session host',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      String? opened;
      FormalReviewNavigator.debugOpenSession = (context, sectionId) async {
        opened = FormalReviewLauncher.sessionRouteName;
      };
      addTearDown(() => FormalReviewNavigator.debugOpenSession = null);

      await tester.pumpWidget(
        MaterialApp(
          home: hubTree(
            courseProvider:
                _ScopeStubCourseProvider(initialScope: _ankiScope),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('记忆卡复习'));
      await tester.longPress(find.text('记忆卡复习'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.playPopupAnkiTotal), findsOneWidget);
      expect(find.text(AppStrings.playPopupAnkiLegacy), findsOneWidget);
      expect(find.text(AppStrings.playPopupAnkiOfficial), findsOneWidget);

      await tester.tap(find.text(AppStrings.playPopupEnter));
      await tester.pumpAndSettle();

      // 进入 = 关浮窗 + 走同一 Anki 会话入口。
      expect(opened, FormalReviewLauncher.sessionRouteName);
      expect(find.text(AppStrings.playPopupAnkiTotal), findsNothing);
    });

    testWidgets('today hero long-press shows queue overview panel',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(home: hubTree()));
      await tester.pumpAndSettle();

      await tester.longPress(find.text(AppStrings.reviewTodayTitle));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.playPopupNextQueueLabel), findsOneWidget);
    });
  });

  testWidgets(
    'queue grid and practice tools survive 200% text scale on a narrow phone',
    (tester) async {
      // 真机收据（2026-10-20）：系统字体放大后队列格子报
      // `BOTTOM OVERFLOWED BY 11 PIXELS`，工具行被外层 `SizedBox(height: 104)`
      // 掐住。两处都改成行高自适应网格，这里守住回归。
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: hubTree(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 队列与工具行在首屏之外，滚到可见才算真正布局过。
      await tester.scrollUntilVisible(
        find.text(AppStrings.playPracticeToolsTitle),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(AppStrings.playQueueSectionTitle), findsOneWidget);
      expect(find.text(AppStrings.playPracticeToolsTitle), findsOneWidget);
    },
  );
}
