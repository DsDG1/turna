@Tags(['golden'])
library;

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
import 'package:turna/application/progress_provider.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/courses/course_tree.dart';
import 'package:turna/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessibilityProvider accessibility;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    accessibility = AccessibilityProvider(AppPrefs(preferences));
  });

  Future<void> pumpCourseTree(
    WidgetTester tester,
    ThemeMode themeMode,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = _GoldenGameProvider(
      completed: const {'lesson-normal', 'lesson-listening'},
      perfect: const {'lesson-normal'},
    );
    final progress = ProgressProvider(game);
    addTearDown(progress.dispose);
    addTearDown(game.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CourseProvider>.value(
            value: _GoldenCourseProvider(_section),
          ),
          ChangeNotifierProvider<AccessibilityProvider>.value(
            value: accessibility,
          ),
          ChangeNotifierProvider<ProgressProvider>.value(value: progress),
        ],
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          darkTheme: TurnaTheme.darkTheme,
          themeMode: themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const Scaffold(body: CourseTree()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常交流'));
    await tester.pumpAndSettle();
  }

  testWidgets('course tree expanded light golden', (tester) async {
    await pumpCourseTree(tester, ThemeMode.light);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/course_tree_expanded_light.png'),
    );
  });

  testWidgets('course tree expanded dark golden', (tester) async {
    await pumpCourseTree(tester, ThemeMode.dark);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/course_tree_expanded_dark.png'),
    );
  });
}

class _GoldenCourseProvider extends CourseProvider {
  final Section section;

  _GoldenCourseProvider(this.section);

  @override
  bool get isLoaded => true;

  @override
  List<Section> get sections => [section];

  @override
  String get currentSectionId => section.id;

  @override
  Section get currentSection => section;

  @override
  SectionLoadState sectionLoadState(String id) => SectionLoadState.loaded;
}

class _GoldenGameProvider extends ChangeNotifier implements GameProvider {
  final Set<String> _completed;
  final Set<String> _perfect;

  _GoldenGameProvider({
    required Set<String> completed,
    required Set<String> perfect,
  })  : _completed = completed,
        _perfect = perfect;

  @override
  Set<String> get completedLessonIds => _completed;

  @override
  Set<String> get perfectLessonIds => _perfect;

  @override
  bool isLessonCompleted(String lessonId) => _completed.contains(lessonId);

  @override
  bool isLessonPerfect(String lessonId) => _perfect.contains(lessonId);

  @override
  Stream<Set<String>> get completedLessonsStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _section = Section(
  id: 'section1',
  name: 'A1 · 基础交流',
  description: '',
  prerequisiteSectionIds: [],
  units: [
    Unit(
      id: 'daily-conversation',
      name: '日常交流',
      description: '问候、介绍自己，并理解简单的日常表达',
      prerequisiteUnitIds: [],
      lessons: [
        Lesson(
          id: 'lesson-normal',
          name: '问候与自我介绍',
          type: LessonType.normal,
          template: LessonTemplate.legacy,
          prerequisiteLessonIds: [],
          content: LessonContent(),
        ),
        Lesson(
          id: 'lesson-listening',
          name: '听力：初次见面',
          type: LessonType.listening,
          template: LessonTemplate.legacy,
          prerequisiteLessonIds: [],
          content: LessonContent(),
        ),
        Lesson(
          id: 'lesson-reading',
          name: '阅读：咖啡馆里的对话',
          type: LessonType.reading,
          template: LessonTemplate.legacy,
          prerequisiteLessonIds: [],
          content: LessonContent(),
        ),
        Lesson(
          id: 'lesson-review',
          name: '复习本单元',
          type: LessonType.review,
          template: LessonTemplate.legacy,
          prerequisiteLessonIds: [],
          content: LessonContent(),
        ),
        Lesson(
          id: 'lesson-challenge',
          name: '挑战：完成一段对话',
          type: LessonType.challenge,
          template: LessonTemplate.legacy,
          prerequisiteLessonIds: [],
          content: LessonContent(),
        ),
      ],
    ),
  ],
);
