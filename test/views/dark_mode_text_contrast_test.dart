// Flutter imports:
import 'package:flutter/material.dart';
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
import 'package:turna/views/theme.dart';

/// Reuses the fake-provider shape from course_tree_test.dart, trimmed to what
/// the dark-mode contrast smoke test needs.
class _FakeGameProvider extends ChangeNotifier implements GameProvider {
  @override
  Set<String> get completedLessonIds => const {};

  @override
  Set<String> get perfectLessonIds => const {};

  @override
  bool isLessonCompleted(String lessonId) => false;

  @override
  bool isLessonPerfect(String lessonId) => false;

  @override
  Stream<Set<String>> get completedLessonsStream async* {
    yield const {};
  }

  Stream get stateStream => const Stream.empty();
  Stream<int> get streakStream => const Stream.empty();
  Stream<int> get scoreStream => const Stream.empty();

  @override
  StreakCheckResult get lastStreakCheckResult => StreakCheckResult.none;

  int get xpScore => 0;
  int get streak => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCourseProvider extends CourseProvider {
  _FakeCourseProvider(this._section) : _loadState = SectionLoadState.loaded;

  final Section _section;
  final SectionLoadState _loadState;

  @override
  bool get isLoaded => true;

  @override
  List<Section> get sections => [_section];

  @override
  String? get currentSectionId => _section.id;

  @override
  Section? get currentSection => _section;

  @override
  SectionLoadState sectionLoadState(String id) => _loadState;

  @override
  Object? sectionLoadError(String id) => null;

  @override
  bool get isCurrentSectionLoading => false;

  @override
  bool isSectionLoading(String id) => false;

  @override
  Future<void> ensureSectionLoaded(String id) async {}

  @override
  Future<void> reloadSection(String id) async {}

  @override
  Future<void> reloadCourse() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Section _loadedSection() => const Section(
      id: 's-dark',
      name: 'Dark Section',
      description: '',
      prerequisiteSectionIds: [],
      units: [
        Unit(
          id: 'u-1',
          name: 'Greetings',
          description: 'Say hello in Turkish',
          prerequisiteUnitIds: [],
          lessons: [
            Lesson(
              id: 'l-1',
              name: 'Jambo',
              description: 'Hello',
              type: LessonType.normal,
              template: LessonTemplate.legacy,
              prerequisiteLessonIds: [],
              content: LessonContent(),
            ),
          ],
        ),
      ],
    );

void main() {
  group('dark-mode text contrast', () {
    testWidgets('no visible Text uses the near-black textPrimary token',
        (tester) async {
      final courseProvider = _FakeCourseProvider(_loadedSection());

      await tester.pumpWidget(
        MaterialApp(
          theme: TurnaTheme.darkTheme,
          darkTheme: TurnaTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<CourseProvider>.value(
                  value: courseProvider),
              ChangeNotifierProvider<ProgressProvider>(
                create: (_) => ProgressProvider(_FakeGameProvider()),
              ),
            ],
            child: const Scaffold(body: CourseTree()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Every rendered Text must NOT be the static near-black token — that
      // would be invisible on the dark card background.
      const nearBlack = TurnaTheme.textPrimary;
      final texts = tester.widgetList<Text>(find.byType(Text));
      expect(texts, isNotEmpty);
      for (final t in texts) {
        final color = t.style?.color;
        if (color == null) continue; // inherited from theme — fine
        expect(
          color,
          isNot(nearBlack),
          reason: 'Text "${t.data}" uses the static near-black textPrimary '
              'token, which is invisible in dark mode.',
        );
      }

      // Sanity: the unit card background adapted (not a hardcoded white slab).
      final cardBg = TurnaTheme.cardBg(
        tester.element(find.byType(CourseTree)),
      );
      expect(cardBg, isNot(Colors.white));
    });
  });
}
