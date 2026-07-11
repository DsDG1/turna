import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/domain/course/lesson.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late db.CourseDatabase database;
  late CourseRepository repo;

  setUp(() async {
    database = db.CourseDatabase(NativeDatabase.memory());
    repo = CourseRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedMinimalCourse() async {
    await database.into(database.sections).insert(
          const db.SectionsCompanion(
            id: Value('s-1'),
            name: Value('Section 1'),
            description: Value('First section'),
            sortOrder: Value(1),
          ),
        );
    await database.into(database.units).insert(
          const db.UnitsCompanion(
            id: Value('u-1'),
            sectionId: Value('s-1'),
            name: Value('Unit 1'),
            sortOrder: Value(1),
          ),
        );
    await database.into(database.units).insert(
          const db.UnitsCompanion(
            id: Value('u-2'),
            sectionId: Value('s-1'),
            name: Value('Unit 2'),
            sortOrder: Value(2),
          ),
        );
    await database.into(database.lessons).insert(
          const db.LessonsCompanion(
            id: Value('l-1'),
            unitId: Value('u-1'),
            name: Value('Lesson 1'),
            type: Value('normal'),
            template: Value('intro'),
            sortOrder: Value(1),
          ),
        );
    await database.into(database.lessons).insert(
          const db.LessonsCompanion(
            id: Value('l-2'),
            unitId: Value('u-1'),
            name: Value('Lesson 2'),
            type: Value('normal'),
            template: Value('practice'),
            sortOrder: Value(2),
          ),
        );
    await database.into(database.lessonContents).insert(
          const db.LessonContentsCompanion(
            lessonId: Value('l-1'),
            contentJson: Value('{"stages":[]}'),
          ),
        );
    await database.into(database.lessonContents).insert(
          const db.LessonContentsCompanion(
            lessonId: Value('l-2'),
            contentJson: Value('{"stages":[]}'),
          ),
        );
  }

  group('sectionShells', () {
    test('returns sections ordered by sortOrder', () async {
      await database.into(database.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-b'),
              name: Value('Section B'),
              sortOrder: Value(2),
            ),
          );
      await database.into(database.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-a'),
              name: Value('Section A'),
              sortOrder: Value(1),
            ),
          );

      final shells = await repo.sectionShells();
      expect(shells.map((s) => s.id), ['s-a', 's-b']);
      expect(shells.first.units, isEmpty);
    });

    test('decodes prerequisiteSectionIds JSON', () async {
      await database.into(database.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-2'),
              name: Value('Section 2'),
              prerequisiteSectionIds: Value('["s-1"]'),
            ),
          );

      final shells = await repo.sectionShells();
      final s2 = shells.firstWhere((s) => s.id == 's-2');
      expect(s2.prerequisiteSectionIds, ['s-1']);
    });

    test('degrades corrupted prerequisiteSectionIds to empty list', () async {
      await database.into(database.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-bad'),
              name: Value('Bad Section'),
              prerequisiteSectionIds: Value('not-json'),
            ),
          );

      final shells = await repo.sectionShells();
      final bad = shells.firstWhere((s) => s.id == 's-bad');
      expect(bad.prerequisiteSectionIds, isEmpty);
    });
  });

  group('section', () {
    test('rebuilds units and lessons in sortOrder', () async {
      await seedMinimalCourse();

      final section = await repo.section('s-1');
      expect(section.id, 's-1');
      expect(section.units.map((u) => u.id), ['u-1', 'u-2']);
      expect(section.units.first.lessons.map((l) => l.id), ['l-1', 'l-2']);
    });

    test('throws ArgumentError for unknown section id', () async {
      expect(() => repo.section('missing'), throwsArgumentError);
    });

    test('groups lessons under the correct unit', () async {
      await seedMinimalCourse();
      await database.into(database.lessons).insert(
            const db.LessonsCompanion(
              id: Value('l-3'),
              unitId: Value('u-2'),
              name: Value('Lesson 3'),
              type: Value('normal'),
              template: Value('review'),
              sortOrder: Value(1),
            ),
          );
      await database.into(database.lessonContents).insert(
            const db.LessonContentsCompanion(
              lessonId: Value('l-3'),
              contentJson: Value('{"stages":[]}'),
            ),
          );

      final section = await repo.section('s-1');
      final unit1 = section.units.firstWhere((u) => u.id == 'u-1');
      final unit2 = section.units.firstWhere((u) => u.id == 'u-2');
      expect(unit1.lessons.map((l) => l.id), ['l-1', 'l-2']);
      expect(unit2.lessons.map((l) => l.id), ['l-3']);
    });

    test('degrades corrupted unit prerequisiteUnitIds to empty list', () async {
      await database.into(database.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-1'),
              name: Value('Section 1'),
            ),
          );
      await database.into(database.units).insert(
            const db.UnitsCompanion(
              id: Value('u-1'),
              sectionId: Value('s-1'),
              name: Value('Unit 1'),
              prerequisiteUnitIds: Value('not-json'),
            ),
          );

      final section = await repo.section('s-1');
      expect(section.units.first.prerequisiteUnitIds, isEmpty);
    });
  });

  group('lessonById', () {
    test('returns a single lesson with content', () async {
      await seedMinimalCourse();

      final lesson = await repo.lessonById('l-1');
      expect(lesson.id, 'l-1');
      expect(lesson.name, 'Lesson 1');
      expect(lesson.template, LessonTemplate.intro);
      expect(lesson.content.stages, isEmpty);
    });

    test('throws ArgumentError for unknown lesson id', () async {
      expect(() => repo.lessonById('missing'), throwsArgumentError);
    });

    // NOTE: _toLesson currently does not catch jsonDecode/LessonContent.fromJson
    // errors. This test documents the current behavior and will be flipped to
    // expect a degraded empty LessonContent once future4 Phase 17 adds the
    // try/catch guard.
    test('currently throws when content JSON is corrupted', () async {
      await database.into(database.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-1'),
              name: Value('Section 1'),
            ),
          );
      await database.into(database.units).insert(
            const db.UnitsCompanion(
              id: Value('u-1'),
              sectionId: Value('s-1'),
              name: Value('Unit 1'),
            ),
          );
      await database.into(database.lessons).insert(
            const db.LessonsCompanion(
              id: Value('l-bad'),
              unitId: Value('u-1'),
              name: Value('Bad Lesson'),
            ),
          );
      await database.into(database.lessonContents).insert(
            const db.LessonContentsCompanion(
              lessonId: Value('l-bad'),
              contentJson: Value('not-json'),
            ),
          );

      expect(() => repo.lessonById('l-bad'), throwsException);
    });
  });

  group('grammarPoints', () {
    test('degrades corrupted practiceItems to empty list', () async {
      await database.into(database.grammarPoints).insert(
            const db.GrammarPointsCompanion(
              id: Value('gp-1'),
              title: Value('Grammar 1'),
              practiceItems: Value('not-json'),
            ),
          );

      final points = await repo.grammarPoints();
      expect(points, hasLength(1));
      expect(points.first.practiceItems, isEmpty);
    });
  });

  group('vocabulary', () {
    test('degrades corrupted tags to empty list', () async {
      await database.into(database.vocabulary).insert(
            const db.VocabularyCompanion(
              id: Value('w-1'),
              term: Value('hello'),
              translation: Value('habari'),
              tags: Value('not-json'),
            ),
          );

      final words = await repo.vocabulary();
      expect(words.first.tags, isEmpty);
    });
  });
}
