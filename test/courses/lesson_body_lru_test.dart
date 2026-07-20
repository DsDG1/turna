import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:drift/drift.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late db.CourseDatabase database;

  setUp(() async {
    database = db.CourseDatabase(NativeDatabase.memory());
    CourseLoader.overrideDatabase(() => database);

    await database.into(database.sections).insert(
          const db.SectionsCompanion(
            id: Value('s-1'),
            name: Value('S'),
          ),
        );
    await database.into(database.units).insert(
          const db.UnitsCompanion(
            id: Value('u-1'),
            sectionId: Value('s-1'),
            name: Value('U'),
          ),
        );

    // Cap + 5 lessons so LRU must evict.
    final n = CourseLoader.lessonBodyCacheCap + 5;
    for (var i = 0; i < n; i++) {
      final id = 'l-$i';
      await database.into(database.lessons).insert(
            db.LessonsCompanion(
              id: Value(id),
              unitId: const Value('u-1'),
              name: Value('L$i'),
              sortOrder: Value(i),
            ),
          );
      await database.into(database.lessonContents).insert(
            db.LessonContentsCompanion(
              lessonId: Value(id),
              contentJson: Value(
                '{"stages":[{"id":"st","name":"S","items":[]}]}',
              ),
            ),
          );
    }
  });

  tearDown(() async {
    CourseLoader.invalidateCaches();
    await database.close();
  });

  test('loadLessonById caches and remains correct under LRU pressure', () async {
    final cap = CourseLoader.lessonBodyCacheCap;
    // Fill beyond cap.
    for (var i = 0; i < cap + 5; i++) {
      final lesson = await CourseLoader.loadLessonById('l-$i');
      expect(lesson.id, 'l-$i');
      expect(lesson.content.stages, isNotEmpty);
    }
    // Early ids may have been evicted; reloading still works.
    final again = await CourseLoader.loadLessonById('l-0');
    expect(again.id, 'l-0');
    expect(again.content.stages, isNotEmpty);

    // Recent id should still resolve (and be cache-friendly).
    final recent = await CourseLoader.loadLessonById('l-${cap + 4}');
    expect(recent.id, 'l-${cap + 4}');
  });
}
