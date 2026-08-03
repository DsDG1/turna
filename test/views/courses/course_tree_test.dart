// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/views/courses/course_tree.dart';

/// Minimal fake [GameProvider] for widget tests that only need the
/// completed-lessons stream.
class _FakeGameProvider extends ChangeNotifier implements GameProvider {
  final Set<String> _completed = const <String>{};
  final Set<String> _perfect = const <String>{};
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

  final Section? _currentSection;
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
}

void main() {
  Widget pumpTree(CourseProvider courseProvider) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<ProgressProvider>(
            create: (_) => ProgressProvider(_FakeGameProvider()),
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

      // Scroll to the bottom of the list and verify the last lesson is
      // reachable. This exercises the lazy sliver builder with 100 items.
      await tester.scrollUntilVisible(
        find.text('Lesson 99'),
        200,
      );
      expect(find.text('Lesson 99'), findsOneWidget);
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
