import 'package:auto_route/auto_route.dart';
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
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/play/play_hub_screen.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/playground/language_playground_page.dart';

import '../../helpers/in_memory_course_db.dart';

/// Scope-mutable stand-in so tests can flip the active course without a DB.
class _ScopeStubCourseProvider extends CourseProvider {
  _ScopeStubCourseProvider(String scopeWire) : _scopeWire = scopeWire;

  String _scopeWire;

  set scopeWire(String value) {
    _scopeWire = value;
    notifyListeners();
  }

  @override
  String get courseScope => _scopeWire;
}

/// Hand-written host route (no codegen) so router-level tests can push real
/// pages without dragging in the full app shell.
class _HubHostRoute extends PageRouteInfo<void> {
  const _HubHostRoute() : super(_HubHostRoute.name);

  static const String name = '_HubHostRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (_) => const Scaffold(body: PlayHubScreen()),
  );
}

class _HubTestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: _HubHostRoute.page, initial: true),
        AutoRoute(page: LanguagePlaygroundRoute.page),
      ];
}

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
            create: (_) => courseProvider ?? _ScopeStubCourseProvider(''),
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

  Widget routedTree(
    RootStackRouter router, {
    _ScopeStubCourseProvider? courseProvider,
  }) =>
      MaterialApp.router(
        routerConfig: router.config(),
        builder: (context, child) =>
            wrapProviders(child!, courseProvider: courseProvider),
      );

  testWidgets('renders redesigned play hub sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: hubTree()));
    await tester.pumpAndSettle();

    expect(find.text('Playground'), findsOneWidget);
    expect(find.text(AppStrings.playgroundHeroSubtitle), findsOneWidget);

    // 今日复习 Hero：标题 + 四队列速览 chips。
    expect(find.text(AppStrings.playTodayHeroTitle), findsOneWidget);
    expect(find.text(AppStrings.playTodayHeroAllClear), findsOneWidget);
    expect(find.text('错题 0'), findsOneWidget);
    expect(find.text('单词 0'), findsOneWidget);

    // 分区标题。
    expect(find.text(AppStrings.playQueueSectionTitle), findsOneWidget);
    expect(find.text(AppStrings.playPracticeToolsTitle), findsOneWidget);

    // 复习队列 2×2（「复习」不再与 Hero 重复出现两次）。
    expect(find.text('错题复习'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('语法复习'), findsOneWidget);
    expect(find.text('Anki 复习'), findsNothing);

    // AI 助手：单行卡 + 引擎状态 chip（默认空配置 -> 未配置）。
    expect(find.byType(AiAssistantTile), findsOneWidget);
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('设计课程（AI）'), findsNothing);
    expect(find.text('导入教材'), findsNothing);
    expect(find.text('全部 AI 功能'), findsNothing);

    // 练习工具三列。
    expect(find.text('薄弱单词'), findsOneWidget);
    expect(find.text('词典'), findsOneWidget);
    expect(find.text('复习进度'), findsOneWidget);

    // 旧版分区已退役。
    expect(find.text('今日重点'), findsNothing);
    expect(find.text('复习中心'), findsNothing);
    expect(find.text('工具'), findsNothing);

    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('playground hero is fully hidden for Anki course scope',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
          home: hubTree(courseProvider: _ScopeStubCourseProvider('anki:deck1'))),
    );
    await tester.pumpAndSettle();

    // Hero、文案与其专属间距一起消失；今日复习 Hero 与队列仍在。
    expect(find.byType(PlaygroundHero), findsNothing);
    expect(find.text('Playground'), findsNothing);
    expect(find.text(AppStrings.playgroundHeroSubtitle), findsNothing);
    expect(find.text(AppStrings.playTodayHeroTitle), findsOneWidget);
    expect(find.text(AppStrings.playQueueSectionTitle), findsOneWidget);
    expect(find.text('Anki 复习'), findsOneWidget);
    expect(find.text('错题复习'), findsNothing);
    expect(find.text('语法复习'), findsNothing);
    expect(find.text('薄弱单词'), findsNothing);
  });

  testWidgets('playground hero visibility follows course switches',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final courseProvider = _ScopeStubCourseProvider('');
    await tester
        .pumpWidget(MaterialApp(home: hubTree(courseProvider: courseProvider)));
    await tester.pumpAndSettle();
    expect(find.text('Playground'), findsOneWidget);

    // 语言 → Anki：IndexedStack 保留的 Play Hub 必须随 scope 通知重建。
    courseProvider.scopeWire = 'anki:deck1';
    await tester.pumpAndSettle();
    expect(find.text('Playground'), findsNothing);

    // Anki → 语言：入口恢复。
    courseProvider.scopeWire = '';
    await tester.pumpAndSettle();
    expect(find.text('Playground'), findsOneWidget);
  });

  testWidgets('playground hero opens the playground page, not match words',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(routedTree(_HubTestRouter()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Playground'));
    await tester.tap(find.text('Playground'));
    await tester.pumpAndSettle();

    // 独立 Playground 首页（而非旧的单词配对页）。
    expect(find.byType(LanguagePlaygroundPage), findsOneWidget);
    expect(find.text(AppStrings.playgroundSmartStartTitle), findsOneWidget);
    expect(find.text('HOST'), findsNothing);
  });

  testWidgets('Anki review tile opens the shared session host', (tester) async {
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
          courseProvider: _ScopeStubCourseProvider('anki:deck1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Anki 复习'));
    await tester.tap(find.text('Anki 复习'));
    await tester.pump();
    expect(opened, FormalReviewLauncher.sessionRouteName);
  });

  group('today hero due number (OfficialFormalDueRepository reactivity)', () {
    // Hero 大数字读的是 due 仓库单例；测试里用 debug seam 顶掉真实同步，
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

    /// Hero 右侧大数字（digit-only Text，队列 chip 是「Anki N」不会误配）。
    String heroNumber(WidgetTester tester) {
      final digitOnly = RegExp(r'^\d+$');
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(TodayHeroCard),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != null &&
                digitOnly.hasMatch(widget.data!),
          ),
        ),
      ).toList();
      return texts.isEmpty ? '<missing>' : texts.first.data!;
    }

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
            courseProvider: _ScopeStubCourseProvider('anki:deck1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 空快照：大数字 0。
      expect(heroNumber(tester), '0');

      // 仓库 commit（无 setState、无 provider 变化）→ Hero 必须重建。
      commitDueSnapshot('src-a', {11, 22});
      await tester.pumpAndSettle();

      expect(heroNumber(tester), '2',
          reason: 'due 仓库是 ChangeNotifier，Play Hub 必须订阅它的通知，'
              '否则数字冻结在 mount 时的值（一直 0 的根因）');
    });

    testWidgets('returning from the anki session re-syncs the due snapshot',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var dueAfterSync = const <int>{};
      var refreshRuns = 0;
      OfficialAnkiHomeDueSync.debugRefreshOverride = () async {
        refreshRuns++;
        commitDueSnapshot('src-b', dueAfterSync);
      };
      FormalReviewNavigator.debugOpenSession = (context, sectionId) async {};
      addTearDown(() => FormalReviewNavigator.debugOpenSession = null);

      await tester.pumpWidget(
        MaterialApp(
          home: hubTree(
            courseProvider: _ScopeStubCourseProvider('anki:deck1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // initState 的首次 due 刷新。
      expect(refreshRuns, 1);
      expect(heroNumber(tester), '0');

      // 模拟一次复习会话结束（调度器还欠 2 张）：pop 返回后必须重取快照。
      dueAfterSync = {11, 22};
      await tester.ensureVisible(find.text('Anki 复习'));
      await tester.tap(find.text('Anki 复习'));
      await tester.pumpAndSettle();

      expect(refreshRuns, 2,
          reason: '复习会话只改调度器，返回 Play 页必须显式 refresh，'
              '否则仓库里的 schedulerDue 还是进会话前的旧值');
      expect(heroNumber(tester), '2');
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
            courseProvider: _ScopeStubCourseProvider('anki:deck1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Anki 复习'));
      await tester.longPress(find.text('Anki 复习'));
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

      await tester.longPress(find.text(AppStrings.playTodayHeroTitle));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.playPopupNextQueueLabel), findsOneWidget);
      expect(
        find.text(AppStrings.playTodayHeroAllClear),
        findsWidgets, // Hero 副标题 + 浮窗「下一个」行。
      );
    });
  });
}
