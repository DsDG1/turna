// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/courses/components/section_switcher.dart';
import 'package:turna/views/courses/course_tree.dart';

import '../../helpers/in_memory_course_db.dart';

/// Minimal fake [GameProvider] for widget tests that only need the
/// completed-lessons stream.
class _FakeGameProvider extends ChangeNotifier implements GameProvider {
  final Set<String> _completed = <String>{};
  final Set<String> _perfect = <String>{};
  final StreamController<Set<String>> _controller =
      StreamController<Set<String>>.broadcast();

  @override
  Set<String> get completedLessonIds => _completed;

  @override
  Set<String> get perfectLessonIds => _perfect;

  @override
  bool isLessonCompleted(String lessonId) => _completed.contains(lessonId);

  @override
  bool isLessonPerfect(String lessonId) => _perfect.contains(lessonId);

  @override
  Stream<Set<String>> get completedLessonsStream async* {
    yield Set.unmodifiable(_completed);
    yield* _controller.stream;
  }

  void complete(String lessonId, {bool perfect = false}) {
    _completed.add(lessonId);
    if (perfect) _perfect.add(lessonId);
    _controller.add(Set.unmodifiable(_completed));
  }

  // Stubs for the remaining GameProvider interface; not used by CourseTree.
  Stream get stateStream => StreamController.broadcast().stream;

  Stream<int> get streakStream => StreamController<int>.broadcast().stream;

  Stream<int> get scoreStream => StreamController<int>.broadcast().stream;

  @override
  StreakCheckResult get lastStreakCheckResult => StreakCheckResult.none;

  int get xpScore => 0;

  int get streak => 0;

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A fake [CourseProvider] that lets the test control the current section and
/// its load state without touching the real database.
class _FakeCourseProvider extends CourseProvider {
  _FakeCourseProvider({
    Section? currentSection,
    List<Section>? sections,
    required SectionLoadState loadState,
    Object? loadError,
    bool isLoaded = true,
  })  : _currentSection = currentSection,
        _sectionsOverride = sections,
        _loadState = loadState,
        _loadError = loadError,
        _isLoadedFlag = isLoaded;

  Section? _currentSection;
  final List<Section>? _sectionsOverride;
  final SectionLoadState _loadState;
  final Object? _loadError;
  final bool _isLoadedFlag;

  /// Ids passed to [ensureSectionLoaded] (defensive CourseTree schedule).
  final List<String> ensureCalledFor = [];

  /// How many times [reloadCourse] was invoked (empty-shell Retry).
  int reloadCourseCalls = 0;

  @override
  bool get isLoaded => _isLoadedFlag;

  @override
  List<Section> get sections {
    final override = _sectionsOverride;
    if (override != null) return override;
    final current = _currentSection;
    if (current != null) return [current];
    return const [];
  }

  @override
  String? get currentSectionId => _currentSection?.id;

  @override
  Section? get currentSection => _currentSection;

  @override
  SectionLoadState sectionLoadState(String id) => _loadState;

  @override
  Object? sectionLoadError(String id) => _loadError;

  @override
  bool get isCurrentSectionLoading => _loadState == SectionLoadState.loading;

  @override
  bool isSectionLoading(String id) => _loadState == SectionLoadState.loading;

  @override
  Future<void> ensureSectionLoaded(String id) async {
    ensureCalledFor.add(id);
  }

  @override
  Future<void> reloadSection(String id) async {
    // No-op for the error-state UI test; a real retry test would pump a new
    // provider with a loaded state.
    notifyListeners();
  }

  @override
  Future<void> reloadCourse() async {
    reloadCourseCalls++;
    notifyListeners();
  }

  void showSection(Section section) {
    _currentSection = section;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessibilityProvider accessibility;
  late AppPrefs appPrefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);
    accessibility = AccessibilityProvider(appPrefs);
  });

  Widget pumpTree(
    CourseProvider courseProvider, {
    _FakeGameProvider? gameProvider,
    SrsProvider? srsProvider,
    MistakeProvider? mistakeProvider,
    bool disableAnimations = false,
    TextScaler? textScaler,
  }) {
    final game = gameProvider ?? _FakeGameProvider();
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: textScaler,
        ),
        child: child!,
      ),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<AccessibilityProvider>.value(
            value: accessibility,
          ),
          ChangeNotifierProvider<ProgressProvider>(
            create: (_) => ProgressProvider(game),
          ),
          if (srsProvider != null)
            ChangeNotifierProvider<SrsProvider>.value(value: srsProvider),
          if (mistakeProvider != null)
            ChangeNotifierProvider<MistakeProvider>.value(
              value: mistakeProvider,
            ),
        ],
        child: const Scaffold(body: CourseTree()),
      ),
    );
  }

  group('CourseTree', () {
    testWidgets('shows a loading indicator while the section is loading',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: _shellSection('s-loading'),
        loadState: SectionLoadState.loading,
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('正在加载课程…'), findsOneWidget);
      expect(find.text('暂无可用单元'), findsNothing);
      expect(find.text('重试'), findsNothing);
      // loading is not initial — defensive ensure must not fire
      await tester.pump();
      expect(provider.ensureCalledFor, isEmpty);
    });

    testWidgets('shows the empty state when the section has no units',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: _shellSection('s-empty'),
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('暂无可用单元'), findsOneWidget);
      expect(find.text('正在加载课程…'), findsNothing);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('shows an error retry button when loading failed',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: _shellSection('s-error'),
        loadState: SectionLoadState.error,
        loadError: 'Section query failed',
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('无法加载章节'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('暂无可用单元'), findsNothing);
      expect(find.text('正在加载课程…'), findsNothing);
    });

    testWidgets(
        'shows course-empty error (not infinite spinner) when loaded with no sections',
        (tester) async {
      final provider = _FakeCourseProvider(
        sections: const [],
        loadState: SectionLoadState.initial,
        isLoaded: true,
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('无法加载课程'), findsOneWidget);
      expect(find.text('未找到课程章节。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('正在加载课程…'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(provider.reloadCourseCalls, 1);
    });

    testWidgets(
        'still shows spinner when sections are empty but load not finished',
        (tester) async {
      final provider = _FakeCourseProvider(
        sections: const [],
        loadState: SectionLoadState.initial,
        isLoaded: false,
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('正在加载课程…'), findsOneWidget);
      expect(find.text('无法加载课程'), findsNothing);
    });

    testWidgets('defensively ensures section body when load state is initial',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: _shellSection('s-init'),
        loadState: SectionLoadState.initial,
      );

      await tester.pumpWidget(pumpTree(provider));
      expect(find.text('正在加载课程…'), findsOneWidget);
      // pumpWidget completes a frame, so the post-frame ensure may already
      // have run; an extra pump covers bindings that defer it.
      await tester.pump();
      expect(provider.ensureCalledFor, contains('s-init'));
    });

    testWidgets('renders unit cards when the section is loaded',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: const Section(
          id: 's-loaded',
          name: 'Loaded Section',
          description: '',
          prerequisiteSectionIds: [],
          units: [
            Unit(
              id: 'u-1',
              name: 'Unit One',
              description: '',
              prerequisiteUnitIds: [],
              lessons: [
                Lesson(
                  id: 'l-1',
                  name: 'Lesson One',
                  description: '',
                  type: LessonType.normal,
                  template: LessonTemplate.legacy,
                  prerequisiteLessonIds: [],
                  content: LessonContent(),
                ),
              ],
            ),
          ],
        ),
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));
      await tester.pumpAndSettle();

      expect(find.text('Unit One'), findsOneWidget);
      expect(find.text('暂无可用单元'), findsNothing);
    });

    testWidgets(
        'expanding a unit with 100 lessons renders them without building '
        'all tiles eagerly', (tester) async {
      final lessons = List.generate(
        100,
        (i) => Lesson(
          id: 'l-$i',
          name: 'Lesson $i',
          description: '',
          type: LessonType.normal,
          template: LessonTemplate.legacy,
          prerequisiteLessonIds: const [],
          content: const LessonContent(),
        ),
      );
      final provider = _FakeCourseProvider(
        currentSection: Section(
          id: 's-big-unit',
          name: 'Big Unit Section',
          description: '',
          prerequisiteSectionIds: const [],
          units: [
            Unit(
              id: 'u-big',
              name: 'Big Unit',
              description: '',
              prerequisiteUnitIds: const [],
              lessons: lessons,
            ),
          ],
        ),
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));
      await tester.pumpAndSettle();

      // Unit is collapsed by default.
      expect(find.text('Big Unit'), findsOneWidget);
      expect(find.text('Lesson 0'), findsNothing);

      // Expand the unit.
      await tester.tap(find.text('Big Unit'));
      await tester.pumpAndSettle();

      // First lesson appears after expand.
      expect(find.text('Lesson 0'), findsOneWidget);
      expect(find.text('Lesson 99'), findsNothing);

      // Scroll to the bottom of the list and verify the last lesson is
      // reachable. This exercises the lazy sliver builder with 100 items.
      await tester.scrollUntilVisible(
        find.text('Lesson 99'),
        200,
      );
      expect(find.text('Lesson 99'), findsOneWidget);
    });

    testWidgets('unit progress refreshes from ProgressProvider only',
        (tester) async {
      final game = _FakeGameProvider();
      final section = _testSection(
        id: 's-progress',
        unitName: 'Progress Unit',
        lessons: [_testLesson('progress-lesson', 'Progress Lesson')],
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider, gameProvider: game));
      await tester.pumpAndSettle();
      expect(find.text('0/1'), findsOneWidget);

      game.complete('progress-lesson', perfect: true);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('0/1'), findsNothing);
    });

    testWidgets('due lessons use one primary attention state', (tester) async {
      final linkStore = LessonLinkStore(appPrefs);
      await linkStore.upsertFirstSeen(
        ids: const ['due-word'],
        lessonId: 'attention-lesson',
        lessonName: 'Attention Lesson',
        type: LinkType.word,
      );
      getIt.pushNewScope();
      addTearDown(() => getIt.popScope());
      getIt.registerSingleton<LessonLinkStore>(linkStore);

      final srs = SrsProvider(appPrefs, linkStore, emptySrsStateDao())
        ..registerWord('due-word');
      final mistakes = MistakeProvider(appPrefs);
      addTearDown(srs.dispose);
      addTearDown(mistakes.dispose);

      final section = _testSection(
        id: 's-attention',
        unitName: 'Attention Unit',
        lessons: [_testLesson('attention-lesson', 'Attention Lesson')],
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(
        pumpTree(
          provider,
          srsProvider: srs,
          mistakeProvider: mistakes,
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 项待复习'), findsOneWidget);

      await tester.tap(find.text('Attention Unit'));
      await tester.pumpAndSettle();
      expect(find.text('1 项待复习'), findsNWidgets(2));
      expect(find.textContaining('需加强'), findsNothing);
    });

    testWidgets('uses a short shared reveal animation for visible lessons',
        (tester) async {
      final section = _testSection(
        id: 's-motion',
        unitName: 'Motion Unit',
        lessons: [_testLesson('motion-lesson', 'Motion Lesson')],
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Motion Unit'));
      await tester.pump();

      final reveal = find.byKey(
        const ValueKey<String>('lesson-reveal-motion-lesson'),
      );
      expect(reveal, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      final transition = tester.widget<FadeTransition>(reveal);
      expect(transition.opacity.value, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(find.text('Motion Lesson'), findsOneWidget);
    });

    testWidgets('reduced motion reveals lessons without transition widgets',
        (tester) async {
      final section = _testSection(
        id: 's-reduced-motion',
        unitName: 'Quiet Unit',
        lessons: [_testLesson('quiet-lesson', 'Quiet Lesson')],
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(
        pumpTree(provider, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quiet Unit'));
      await tester.pump();

      expect(find.text('Quiet Lesson'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('lesson-reveal-quiet-lesson')),
        findsNothing,
      );
    });

    testWidgets('section switcher collapses and remains pinned while scrolling',
        (tester) async {
      final lessons = List.generate(
        30,
        (i) => _testLesson('sticky-$i', 'Sticky Lesson $i'),
      );
      final section = _testSection(
        id: 's-sticky',
        sectionName: 'Sticky Section',
        unitName: 'Sticky Unit',
        lessons: lessons,
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(
        pumpTree(provider, disableAnimations: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SectionSwitcher)).height,
        SectionSwitcherHeaderDelegate.expandedExtent,
      );

      await tester.tap(find.text('Sticky Unit'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sticky Section'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SectionSwitcher)).height,
        SectionSwitcherHeaderDelegate.compactExtent,
      );
    });

    testWidgets('preserves the expanded unit independently for each section',
        (tester) async {
      final first = _testSection(
        id: 's-first',
        sectionName: 'First Section',
        unitName: 'First Unit',
        lessons: [_testLesson('first-lesson', 'First Lesson')],
      );
      final second = _testSection(
        id: 's-second',
        sectionName: 'Second Section',
        unitName: 'Second Unit',
        lessons: [_testLesson('second-lesson', 'Second Lesson')],
      );
      final provider = _FakeCourseProvider(
        currentSection: first,
        sections: [first, second],
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First Unit'));
      await tester.pumpAndSettle();
      expect(find.text('First Lesson'), findsOneWidget);

      provider.showSection(second);
      await tester.pumpAndSettle();
      expect(find.text('Second Unit'), findsOneWidget);
      expect(find.text('Second Lesson'), findsNothing);

      provider.showSection(first);
      await tester.pumpAndSettle();
      expect(find.text('First Lesson'), findsOneWidget);
    });

    testWidgets(
        'narrow large-text layout does not overflow and hides lesson descriptions',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final lessons = List.generate(
        16,
        (i) => _testLesson(
          'large-$i',
          'A long lesson title number $i',
          description: 'Lesson descriptions should stay hidden',
        ),
      );
      final section = _testSection(
        id: 's-large-text',
        sectionName: 'A long section name for a narrow screen',
        unitName: 'A long unit name for a narrow screen',
        unitDescription: 'Only this single-line unit description is retained',
        lessons: lessons,
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(
        pumpTree(
          provider,
          disableAnimations: true,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('A long unit name for a narrow screen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Lesson descriptions should stay hidden'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('unit semantics expose progress and expanded state',
        (tester) async {
      final section = _testSection(
        id: 's-semantics',
        unitName: 'Semantic Unit',
        lessons: [_testLesson('semantic-lesson', 'Semantic Lesson')],
      );
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));
      await tester.pumpAndSettle();
      final collapsed = find.bySemanticsLabel('Semantic Unit，0/1');
      expect(collapsed, findsOneWidget);
      expect(
        tester.getSemantics(collapsed),
        isSemantics(
          label: 'Semantic Unit，0/1',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('Semantic Unit'));
      await tester.pumpAndSettle();
      final expanded = find.bySemanticsLabel('Semantic Unit，0/1');
      expect(
        tester.getSemantics(expanded),
        isSemantics(
          label: 'Semantic Unit，0/1',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('highlights the next-up lesson with next-up indicator tag',
        (tester) async {
      final section = _testSection(
        id: 's-next-up',
        unitName: 'Next Up Unit',
        lessons: [
          _testLesson('l-1', 'Lesson Completed'),
          _testLesson('l-2', 'Lesson Next Up'),
        ],
      );
      final game = _FakeGameProvider()..complete('l-1');
      final provider = _FakeCourseProvider(
        currentSection: section,
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider, gameProvider: game));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next Up Unit'));
      await tester.pumpAndSettle();

      expect(find.text('下一课'), findsOneWidget);
      expect(find.text('Lesson Next Up'), findsOneWidget);
    });

    testWidgets(
        'transitions smoothly between sections with AnimatedSwitcher viewport',
        (tester) async {
      final s1 = _testSection(
        id: 's-1',
        unitName: 'Unit 1',
        lessons: [_testLesson('l-1', 'Lesson 1')],
      );
      final s2 = _testSection(
        id: 's-2',
        unitName: 'Unit 2',
        lessons: [_testLesson('l-2', 'Lesson 2')],
      );
      final provider = _FakeCourseProvider(
        currentSection: s1,
        sections: [s1, s2],
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('section-viewport-s-1')),
        findsOneWidget,
      );

      provider.showSection(s2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('section-viewport-s-2')),
        findsOneWidget,
      );
      expect(find.text('Unit 2'), findsOneWidget);
    });
  });
}

Section _shellSection(String id) => Section(
      id: id,
      name: id,
      description: '',
      prerequisiteSectionIds: const [],
      units: const [],
    );

Section _testSection({
  required String id,
  String? sectionName,
  required String unitName,
  String unitDescription = '',
  required List<Lesson> lessons,
}) =>
    Section(
      id: id,
      name: sectionName ?? id,
      description: '',
      prerequisiteSectionIds: const [],
      units: [
        Unit(
          id: '$id-unit',
          name: unitName,
          description: unitDescription,
          prerequisiteUnitIds: const [],
          lessons: lessons,
        ),
      ],
    );

Lesson _testLesson(
  String id,
  String name, {
  String description = '',
}) =>
    Lesson(
      id: id,
      name: name,
      description: description,
      type: LessonType.normal,
      template: LessonTemplate.legacy,
      prerequisiteLessonIds: const [],
      content: const LessonContent(),
    );
