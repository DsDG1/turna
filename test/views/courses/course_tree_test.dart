// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/course_provider.dart';
import 'package:words625/application/game_provider.dart';
import 'package:words625/application/progress_provider.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/lesson_content.dart';
import 'package:words625/domain/course/section.dart';
import 'package:words625/domain/course/unit.dart';
import 'package:words625/views/courses/course_tree.dart';

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
  Stream<Map<String, dynamic>> get stateStream =>
      StreamController<Map<String, dynamic>>.broadcast().stream;

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
    required Section currentSection,
    required SectionLoadState loadState,
    Object? loadError,
  })  : _currentSection = currentSection,
        _loadState = loadState,
        _loadError = loadError;

  final Section _currentSection;
  final SectionLoadState _loadState;
  final Object? _loadError;

  @override
  List<Section> get sections => [_currentSection];

  @override
  String? get currentSectionId => _currentSection.id;

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
  Future<void> reloadSection(String id) async {
    // No-op for the error-state UI test; a real retry test would pump a new
    // provider with a loaded state.
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

      expect(find.text('Loading courses...'), findsOneWidget);
      expect(find.text('No units available'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows the empty state when the section has no units',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: _shellSection('s-empty'),
        loadState: SectionLoadState.loaded,
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('No units available'), findsOneWidget);
      expect(find.text('Loading courses...'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows an error retry button when loading failed',
        (tester) async {
      final provider = _FakeCourseProvider(
        currentSection: _shellSection('s-error'),
        loadState: SectionLoadState.error,
        loadError: 'Section query failed',
      );

      await tester.pumpWidget(pumpTree(provider));

      expect(find.text('Could not load section'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No units available'), findsNothing);
      expect(find.text('Loading courses...'), findsNothing);
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
      expect(find.text('No units available'), findsNothing);
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
