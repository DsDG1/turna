// Regression tests for AnkiReviewAssembler.assembleBatch / assembleBatchAsync:
// the batch builder finds card Interactions inside Anki lesson bodies. Under
// the default built-in course scope Anki sections stay shells (units empty),
// so a review started without loading interactions finds nothing. The async
// path loads only the lessons that contain the batch's word ids (not the
// whole deck).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

Section _ankiDeckSection(String importId, String name, {int cardCount = 1}) {
  final lessons = <Lesson>[];
  // 20 cards per lesson (matches AnkiDeckAssembler.cardsPerLesson).
  const perLesson = 20;
  final lessonCount = (cardCount + perLesson - 1) ~/ perLesson;
  for (var li = 0; li < lessonCount; li++) {
    final start = li * perLesson;
    final end = (start + perLesson).clamp(0, cardCount);
    final stages = <Stage>[
      for (var i = start; i < end; i++)
        Stage(
          id: 'anki-$importId-u10-0-l$li-s$i',
          name: 'Card ${i + 1}',
          items: [
            Interaction.ankiCard(
              id: 'anki-$importId-c${i + 1}-c0',
              front: 'Front ${i + 1}',
              back: 'Back ${i + 1}',
              sourceNoteId: '${i + 1}',
            ),
          ],
        ),
    ];
    lessons.add(Lesson(
      id: 'anki-$importId-u10-0-l$li',
      name: '$name #${li + 1}',
      type: LessonType.normal,
      template: LessonTemplate.legacy,
      content: LessonContent(stages: stages),
    ));
  }

  return Section(
    id: 'anki-$importId-s10',
    name: name,
    description: 'Imported from Anki ($cardCount cards)',
    level: 'Anki',
    prerequisiteSectionIds: const [],
    units: [
      Unit(
        id: 'anki-$importId-u10-0',
        name: name,
        lessons: lessons,
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

  test(
      'due Anki card counts as due but sync batch is null while interactions '
      'are not loaded (root cause reproduction)', () {
    srs.registerWord('anki-deckaa-c1');
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
        reason: 'without preloaded Interactions the sync path finds nothing');
  });

  test('assembleBatch returns a lesson once interactions are preloaded',
      () async {
    srs.registerWord('anki-deckaa-c1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);
    await assembler.preloadInteractions();

    final lesson = assembler.assembleBatch();

    expect(lesson, isNotNull);
    final items = lesson!.flattenedStages.expand((s) => s.items).toList();
    expect(items, hasLength(1));
    expect(items.single.id, 'anki-review-anki-deckaa-c1');
  });

  test('assembleBatchAsync loads only the batch without full-deck preload',
      () async {
    srs.registerWord('anki-deckaa-c1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);

    final lesson = await assembler.assembleBatchAsync();

    expect(lesson, isNotNull);
    final items = lesson!.flattenedStages.expand((s) => s.items).toList();
    expect(items, hasLength(1));
    expect(items.single.id, 'anki-review-anki-deckaa-c1');
  });

  test('assembleReviewBatchAsync returns scheduling and render data directly',
      () async {
    srs.registerWord('anki-deckaa-c1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);

    final batch = await assembler.assembleReviewBatchAsync();

    expect(batch, hasLength(1));
    expect(batch.single.scheduled.wordId, 'anki-deckaa-c1');
    expect(batch.single.interaction.id, 'anki-review-anki-deckaa-c1');
    expect(batch.single.interaction, isA<AnkiCard>());
  });

  test('section-scoped async batch only picks cards from that deck', () async {
    srs.registerWord('anki-deckaa-c1');
    final assembler = AnkiReviewAssembler(srs, courseProvider);

    expect(
      await assembler.assembleBatchAsync(sectionId: 'anki-deckaa-s10'),
      isNotNull,
    );
    expect(
      await assembler.assembleBatchAsync(sectionId: 'anki-other-s10'),
      isNull,
    );
  });

  test('assembleBatchAsync scales to a multi-lesson deck without loading all',
      () async {
    // Replace the small deck with 60 cards across 3 lessons (simulates a
    // slice of a multi-thousand deck). Only 1 due card should still assemble.
    final db = await seedInMemoryCourseDb();
    final repo = CourseRepository(db);
    await repo.bulkInsertCourseTree(
      _ankiDeckSection('bigdeck', 'Big Deck', cardCount: 60),
    );
    CourseLoader.invalidateCaches();
    await courseProvider.reloadCourse();

    srs.registerWord('anki-bigdeck-c42');
    final assembler = AnkiReviewAssembler(srs, courseProvider);
    final lesson = await assembler.assembleBatchAsync();

    expect(lesson, isNotNull);
    final items = lesson!.flattenedStages.expand((s) => s.items).toList();
    expect(items, hasLength(1));
    expect(items.single.id, 'anki-review-anki-bigdeck-c42');
  });

  test('dueSnapshot counts due Anki cards in one pass by import id', () async {
    srs.registerWord('anki-deckaa-c1');
    // Future due — must not count.
    await srs.bulkImportStates({
      'anki-deckaa-c99': SrsWord(
        wordId: 'anki-deckaa-c99',
        dueAt: DateTime.now().add(const Duration(days: 30)),
        intervalDays: 30,
        ease: 2.5,
        reps: 1,
        lapses: 0,
      ),
    });
    // Non-Anki due card — must not count.
    srs.registerWord('tr-hello');

    final assembler = AnkiReviewAssembler(srs, courseProvider);
    final snap = assembler.dueSnapshot();
    expect(snap.total, 1);
    expect(snap.byImportId['deckaa'], 1);
    expect(snap.byImportId.containsKey('other'), isFalse);
  });
}
