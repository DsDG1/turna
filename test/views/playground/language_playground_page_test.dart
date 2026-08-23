// Widget tests for [LanguagePlaygroundPage] — the second isolation layer
// (计划 §6.2): the page re-checks eligibility on entry and on course
// switches, never starts content loads for an Anki scope, and safely
// returns (or blocks inline when there is nothing to pop back to).

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/playground/language_playground_page.dart';

/// Scope-mutable provider with in-memory course content — flipping [scope]
/// notifies like a real course switch without any DB.
class _StubCourseProvider extends CourseProvider {
  _StubCourseProvider({required String scope})
      : _scope = scope,
        super();

  String _scope;
  List<Section> _sectionList = [];

  set scope(String value) {
    _scope = value;
    notifyListeners();
  }

  set sectionList(List<Section> value) {
    _sectionList = value;
    notifyListeners();
  }

  @override
  String get courseScope => _scope;

  @override
  List<Section> get sections => _sectionList;

  @override
  String? get currentSectionId =>
      _sectionList.isEmpty ? null : _sectionList.first.id;

  @override
  Section? get currentSection {
    final id = currentSectionId;
    for (final s in _sectionList) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Unit? get currentUnit => _sectionList.firstOrNull?.units.firstOrNull;

  @override
  Future<void> ensureSectionLoaded(String id) async {}

  @override
  SectionLoadState sectionLoadState(String id) => SectionLoadState.loaded;
}

class _HostRoute extends PageRouteInfo<void> {
  const _HostRoute() : super(_HostRoute.name);

  static const String name = '_HostRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (_) => const Scaffold(body: Center(child: Text('HOST'))),
  );
}

class _HostedPlaygroundRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: _HostRoute.page, initial: true),
        AutoRoute(page: LanguagePlaygroundRoute.page),
      ];
}

/// Deep-link shape: the playground is the only route — nothing to pop back.
class _DeepLinkRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: LanguagePlaygroundRoute.page, initial: true),
      ];
}

Section _languageSection() => Section(
      id: 'sec-1',
      name: 'Section 1',
      units: [
        Unit(
          id: 'unit-1',
          name: 'Unit 1',
          lessons: [
            Lesson(
              id: 'lesson-1',
              name: 'Lesson 1',
              template: LessonTemplate.legacy,
              content: LessonContent(
                stages: [
                  Stage(
                    id: 'stage-1',
                    name: 'Stage',
                    items: const [
                      Interaction.multipleChoice(
                        id: 'q1',
                        prompt: 'Merhaba 的意思是？',
                        options: ['你好', '再见'],
                        correctIndex: 0,
                      ),
                      Interaction.multipleChoice(
                        id: 'q2',
                        prompt: 'Ev 的意思是？',
                        options: ['房子', '车'],
                        correctIndex: 0,
                      ),
                      Interaction.showWord(id: 'sw1', wordId: 'w-merhaba'),
                      Interaction.showWord(id: 'sw2', wordId: 'w-ev'),
                      Interaction.showWord(id: 'sw3', wordId: 'w-su'),
                      Interaction.showWord(id: 'sw4', wordId: 'w-kitap'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
  });

  Widget routedTree(
    RootStackRouter router,
    _StubCourseProvider courseProvider,
  ) =>
      MaterialApp.router(
        routerConfig: router.config(),
        builder: (context, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider<CourseProvider>.value(
              value: courseProvider,
            ),
            ChangeNotifierProvider(create: (_) => MistakeProvider(prefs)),
          ],
          child: child,
        ),
      );

  testWidgets('playground page loads availability; modes show coming-soon '
      'while session execution is off (Plan 3 §22.4)', (tester) async {
    final courseProvider = _StubCourseProvider(scope: '')
      ..sectionList = [_languageSection()];
    final router = _HostedPlaygroundRouter();

    await tester.pumpWidget(routedTree(router, courseProvider));
    await tester.pumpAndSettle();
    unawaited(router.push(const LanguagePlaygroundRoute()));
    await tester.pumpAndSettle();

    expect(find.byType(LanguagePlaygroundPage), findsOneWidget);
    expect(find.text(AppStrings.playgroundSmartStartTitle), findsOneWidget);
    // 会话执行未接入前，所有模式格以「即将推出」禁用态呈现，不显示成
    // 可用后点击只弹 toast（Plan 3 §22.4）。
    expect(find.text(AppStrings.playgroundModeSmartMix), findsOneWidget);
    expect(find.text(AppStrings.playgroundModeWordMatch), findsOneWidget);
    expect(find.text(AppStrings.playgroundModeDictation), findsOneWidget);
    expect(find.text(AppStrings.playgroundComingSoon), findsNWidgets(8));
    expect(find.text(AppStrings.playgroundModeCount(2)), findsNothing);
  });

  testWidgets('smart start taps show the coming-soon placeholder',
      (tester) async {
    final courseProvider = _StubCourseProvider(scope: '')
      ..sectionList = [_languageSection()];
    final router = _HostedPlaygroundRouter();

    await tester.pumpWidget(routedTree(router, courseProvider));
    await tester.pumpAndSettle();
    unawaited(router.push(const LanguagePlaygroundRoute()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.playgroundSmartStartTitle));
    await tester.pump();

    expect(find.text(AppStrings.playgroundComingSoon), findsNWidgets(8 + 1));
  });

  testWidgets('entering with an Anki scope pops back with a toast',
      (tester) async {
    final courseProvider = _StubCourseProvider(scope: 'anki:deck1')
      ..sectionList = [_languageSection()];
    final router = _HostedPlaygroundRouter();

    await tester.pumpWidget(routedTree(router, courseProvider));
    await tester.pumpAndSettle();
    unawaited(router.push(const LanguagePlaygroundRoute()));
    await tester.pumpAndSettle();

    // 页面二次资格检查：提示一次并安全返回宿主页。
    expect(find.text(AppStrings.playgroundBlockedToast), findsOneWidget);
    expect(find.text('HOST'), findsOneWidget);
    expect(find.byType(LanguagePlaygroundPage), findsNothing);
  });

  testWidgets('deep link with an Anki scope blocks inline instead of loading',
      (tester) async {
    final courseProvider = _StubCourseProvider(scope: 'anki:official-1')
      ..sectionList = [_languageSection()];

    await tester.pumpWidget(routedTree(_DeepLinkRouter(), courseProvider));
    await tester.pumpAndSettle();

    // 没有可返回页面：就地拦截，不渲染任何练习内容。
    expect(find.text(AppStrings.playgroundBlockedTitle), findsOneWidget);
    expect(find.text(AppStrings.playgroundSmartStartTitle), findsNothing);
    expect(find.text(AppStrings.playgroundModeSmartMix), findsNothing);
  });

  testWidgets('deep-link blocked page recovers when the course becomes eligible',
      (tester) async {
    final courseProvider = _StubCourseProvider(scope: 'anki:deck1')
      ..sectionList = [_languageSection()];

    await tester.pumpWidget(routedTree(_DeepLinkRouter(), courseProvider));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.playgroundBlockedTitle), findsOneWidget);

    courseProvider.scope = '';
    await tester.pumpAndSettle();

    // 课程切回语言 scope：解除就地拦截并恢复 availability 加载，而不是
    // 永远停留在拦截态。
    expect(find.text(AppStrings.playgroundBlockedTitle), findsNothing);
    expect(find.text(AppStrings.playgroundSmartStartTitle), findsOneWidget);
    expect(find.text(AppStrings.playgroundModeSmartMix), findsOneWidget);
  });

  testWidgets('switching to an Anki course while open exits the playground',
      (tester) async {
    final courseProvider = _StubCourseProvider(scope: '')
      ..sectionList = [_languageSection()];
    final router = _HostedPlaygroundRouter();

    await tester.pumpWidget(routedTree(router, courseProvider));
    await tester.pumpAndSettle();
    unawaited(router.push(const LanguagePlaygroundRoute()));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePlaygroundPage), findsOneWidget);

    courseProvider.scope = 'anki:deck1';
    await tester.pumpAndSettle();

    expect(find.byType(LanguagePlaygroundPage), findsNothing);
    expect(find.text('HOST'), findsOneWidget);
    expect(find.text(AppStrings.playgroundBlockedToast), findsOneWidget);
  });

  testWidgets('content scope chips reload availability', (tester) async {
    final courseProvider = _StubCourseProvider(scope: '')
      ..sectionList = [_languageSection()];
    final router = _HostedPlaygroundRouter();

    await tester.pumpWidget(routedTree(router, courseProvider));
    await tester.pumpAndSettle();
    unawaited(router.push(const LanguagePlaygroundRoute()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.playgroundScopeWeak));
    await tester.pumpAndSettle();

    // 薄弱内容没有错题记录：模式仍在（会话执行未接入，统一禁用态），
    // 计数徽标不显示。
    expect(find.text(AppStrings.playgroundModeSmartMix), findsOneWidget);
    expect(find.text(AppStrings.playgroundComingSoon), findsNWidgets(8));
    expect(find.text(AppStrings.playgroundModeCount(2)), findsNothing);
  });

  testWidgets('weak scope feeds mistake entries into availability',
      (tester) async {
    final courseProvider = _StubCourseProvider(scope: '')
      ..sectionList = [_languageSection()];
    final router = _HostedPlaygroundRouter();
    final mistakes = MistakeProvider(prefs);
    addTearDown(mistakes.dispose);
    for (var i = 0; i < 4; i++) {
      await mistakes.record(
        MistakeEntry(
          id: 'm$i',
          lessonId: 'lesson-1',
          stageId: 'stage-1',
          interactionId: 'q$i',
          wordId: 'w-$i',
          timestamp: DateTime(2026, 8, 22),
          interactionSnapshot: Interaction.multipleChoice(
            id: 'q$i',
            prompt: 'p',
            options: const ['a', 'b'],
            correctIndex: 0,
          ),
        ),
      );
    }

    await tester.pumpWidget(routedTree(router, courseProvider));
    await tester.pumpAndSettle();
    unawaited(router.push(const LanguagePlaygroundRoute()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.playgroundScopeWeak));
    await tester.pumpAndSettle();

    // 会话执行未接入：计数徽标统一由「即将推出」取代；题量数据的正确性
    // 由 playground_index_test 与内容源测试守护。
    expect(find.text(AppStrings.playgroundComingSoon), findsNWidgets(8));
    expect(find.text(AppStrings.playgroundModeCount(4)), findsNothing);
  });
}
