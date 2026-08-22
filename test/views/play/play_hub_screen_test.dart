import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
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
  _ScopeStubCourseProvider(String scope) : _scope = scope;

  String _scope;

  set scope(String value) {
    _scope = value;
    notifyListeners();
  }

  @override
  String get courseScope => _scope;
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
          ChangeNotifierProvider(
            create: (_) => GameProvider.forTesting(prefs),
          ),
          ChangeNotifierProvider<AiEngineConfigHolder>(
            create: (_) => AiEngineConfigHolder(),
          ),
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

  testWidgets('renders play hub sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(home: hubTree()));
    await tester.pumpAndSettle();

    expect(find.text('Playground'), findsOneWidget);
    expect(find.text(AppStrings.playgroundHeroSubtitle), findsOneWidget);
    expect(find.text('今日重点'), findsOneWidget);
    expect(find.text('复习中心'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('错题复习'), findsOneWidget);
    expect(find.text('复习'), findsNWidgets(2));
    expect(find.text('语法复习'), findsOneWidget);
    expect(find.text('薄弱单词'), findsOneWidget);
    expect(find.text('Anki 复习'), findsOneWidget);
    expect(find.text('词典'), findsOneWidget);

    // AI 助手 分区（快捷入口 + 引擎状态行）。
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('设计课程（AI）'), findsOneWidget);
    expect(find.text('导入教材'), findsOneWidget);
    expect(find.text('全部 AI 功能'), findsOneWidget);
    // 默认空配置 -> 引擎未就绪。
    expect(find.text('未配置'), findsOneWidget);

    expect(find.byType(PageView), findsNothing);
    expect(find.text('你的最佳'), findsNothing);
    expect(find.text('总经验值'), findsNothing);
  });

  testWidgets('playground hero is fully hidden for Anki course scope',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: hubTree(courseProvider: _ScopeStubCourseProvider('anki:deck1'))),
    );
    await tester.pumpAndSettle();

    // Hero、文案与其专属间距一起消失；下一分区自然上移。
    expect(find.byType(PlaygroundHero), findsNothing);
    expect(find.text('Playground'), findsNothing);
    expect(find.text(AppStrings.playgroundHeroSubtitle), findsNothing);
    expect(find.text('今日重点'), findsOneWidget);
  });

  testWidgets('playground hero visibility follows course switches',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final courseProvider = _ScopeStubCourseProvider('');
    await tester.pumpWidget(MaterialApp(home: hubTree(courseProvider: courseProvider)));
    await tester.pumpAndSettle();
    expect(find.text('Playground'), findsOneWidget);

    // 语言 → Anki：IndexedStack 保留的 Play Hub 必须随 scope 通知重建。
    courseProvider.scope = 'anki:deck1';
    await tester.pumpAndSettle();
    expect(find.text('Playground'), findsNothing);

    // Anki → 语言：入口恢复。
    courseProvider.scope = '';
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

    await tester.pumpWidget(MaterialApp(home: hubTree()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Anki 复习'));
    await tester.tap(find.text('Anki 复习'));
    await tester.pump();
    expect(opened, FormalReviewLauncher.sessionRouteName);
  });
}
