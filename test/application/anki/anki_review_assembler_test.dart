// Regression tests for AnkiReviewAssembler.assembleBatch: the batch builder
// finds card Interactions inside Anki section *bodies*, which are only
// populated after CourseProvider.ensureSectionLoaded runs. Under the default
// built-in course scope Anki sections stay shells (units empty), so a review
// started without loading the deck body finds nothing and wrongly reports
// "no cards due" even though the SRS queue has due cards.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/anki/anki_review_assembler.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/lesson_link_store.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/course/unit.dart';
import 'package:varnamala/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

Section _ankiDeckSection(String importId, String name) {
  return Section(
    id: 'anki-$importId-s10',
    name: name,
    description: 'Imported from Anki (1 cards)',
    level: 'Anki',
    prerequisiteSectionIds: const [],
    units: [
      Unit(
        id: 'anki-$importId-u10-0',
        name: name,
        lessons: [
          Lesson(
            id: 'anki-$importId-u10-0-l0',
            name: '$name #1',
            type: LessonType.normal,
            template: LessonTemplate.legacy,
            content: LessonContent(
              stages: [
                Stage(
                  id: 'anki-$importId-u10-0-l0-s0',
                  name: 'Card 1',
                  items: [
                    Interaction.ankiCard(
                      id: 'anki-$importId-n1-c0',
                      front: 'Front',
                      back: 'Back',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late CourseProvider courseProvider;
  late SrsProvider srs;

  setUp(() async {
    final db = await seedInMemoryCourseDb();
    final repo = CourseRepository(db);
    await repo.bulkInsertCourseTree(_ankiDeckSection('deckaa', 'Deck A'));
    CourseLoader.invalidateCaches();

    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.setString(PrefsConstants.courseScope, '');
    await prefs.preferences.setString(LocalStateKeys.srsState, '{}');

    srs = SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
    courseProvider = CourseProvider(prefs);
    await courseProvider.load();
  });

  test('due Anki card counts as due but batch is null while the deck body '
      'is still an unloaded shell (root cause reproduction)', () {
    srs.registerWord('anki-deckaa-n1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);

    expect(assembler.totalAnkiDueCount, 1,
        reason: 'the SRS queue reports the card as due');
    expect(
      courseProvider.allSections
          .firstWhere((s) => s.id == 'anki-deckaa-s10')
          .units,
      isEmpty,
      reason: 'default scope leaves Anki sections as shells',
    );
    expect(assembler.assembleBatch(), isNull,
        reason: 'without the section body no Interaction can be found');
  });

  test('assembleBatch returns a lesson once interactions are preloaded',
      () async {
    srs.registerWord('anki-deckaa-n1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);
    await assembler.preloadInteractions();

    final lesson = assembler.assembleBatch();

    expect(lesson, isNotNull);
    final items = lesson!.flattenedStages.expand((s) => s.items).toList();
    expect(items, hasLength(1));
    expect(items.single.id, 'anki-review-anki-deckaa-n1');
  });

  test('section-scoped preload and batch only pick cards from that deck',
      () async {
    srs.registerWord('anki-deckaa-n1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);
    await assembler.preloadInteractions(sectionId: 'anki-deckaa-s10');

    expect(assembler.assembleBatch(sectionId: 'anki-deckaa-s10'), isNotNull);
    expect(assembler.assembleBatch(sectionId: 'anki-other-s10'), isNull);
  });
}
