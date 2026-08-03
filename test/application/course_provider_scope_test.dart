// Tests for CourseProvider's course scope: the Learn-page tree can be
// scoped to a single imported Anki deck ('anki:<importId>'), persisted via
// prefs, and falls back to the built-in course when the deck disappears.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

/// Build a minimal one-unit/one-lesson Anki deck section, mirroring what
/// AnkiDeckAssembler persists ('anki-<importId>-s<did>' id, level 'Anki').
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

  group('CourseProvider course scope', () {
    late AppPrefs appPrefs;

    setUp(() async {
      final db = await seedInMemoryCourseDb();
      final repo = CourseRepository(db);
      await repo.bulkInsertCourseTree(_ankiDeckSection('deckaa', 'Deck A'));
      await repo.bulkInsertCourseTree(_ankiDeckSection('deckbb', 'Deck B'));
      CourseLoader.invalidateCaches();

      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      // StreamingSharedPreferences.instance is cached for the whole test
      // file, so reset the scope key explicitly to keep tests independent.
      await appPrefs.setString(PrefsConstants.courseScope, '');
      await appPrefs.setStringList(PrefsConstants.courseOrder, const []);
    });

    test('default scope hides Anki decks but still lists deck entries',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(provider.courseScope, '');
      expect(provider.sections, isNotEmpty);
      expect(provider.sections.every((s) => s.level != 'Anki'), isTrue,
          reason: 'built-in scope must hide Anki deck sections');

      // The unfiltered list and the menu entries still see every deck.
      expect(
        provider.allSections.where((s) => s.level == 'Anki'),
        hasLength(2),
      );
      expect(
        provider.ankiDeckEntries.map((e) => e.importId),
        containsAll(['deckaa', 'deckbb']),
      );
      expect(
        provider.ankiDeckEntries.map((e) => e.name),
        containsAll(['Deck A', 'Deck B']),
      );
    });

    test('setCourseScope scopes the tree to one deck and persists', () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setCourseScope('anki:deckaa');

      expect(provider.courseScope, 'anki:deckaa');
      expect(provider.sections, hasLength(1));
      expect(provider.sections.single.id, 'anki-deckaa-s10');
      expect(provider.currentSectionId, 'anki-deckaa-s10');
      // Deck entries are scope-independent — the menu can still list both.
      expect(provider.ankiDeckEntries, hasLength(2));
      // The deck body loads through the standard lazy path.
      expect(provider.currentSection?.units, isNotEmpty);

      // A fresh provider restores the persisted scope.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.courseScope, 'anki:deckaa');
      expect(restored.sections.single.id, 'anki-deckaa-s10');
    });

    test('switching back to the built-in scope restores the full course',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setCourseScope('anki:deckbb');
      expect(provider.sections.single.id, 'anki-deckbb-s10');

      await provider.setCourseScope('');
      expect(provider.courseScope, '');
      expect(provider.sections.every((s) => s.level != 'Anki'), isTrue);

      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.courseScope, '');
    });

    test('falls back to built-in course when the scoped deck is gone',
        () async {
      // Simulate a persisted scope whose deck was uninstalled.
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:gone');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(provider.courseScope, '',
          reason: 'unknown deck scope must fall back to the built-in course');
      expect(provider.sections, isNotEmpty);
      expect(provider.sections.every((s) => s.level != 'Anki'), isTrue);

      // The fallback is persisted, so a fresh provider stays on '' too.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.courseScope, '');
    });
  });

  group('CourseProvider course order (course management page)', () {
    late AppPrefs appPrefs;

    setUp(() async {
      final db = await seedInMemoryCourseDb();
      final repo = CourseRepository(db);
      await repo.bulkInsertCourseTree(_ankiDeckSection('deckaa', 'Deck A'));
      await repo.bulkInsertCourseTree(_ankiDeckSection('deckbb', 'Deck B'));
      CourseLoader.invalidateCaches();

      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.setString(PrefsConstants.courseScope, '');
      await appPrefs.setStringList(PrefsConstants.courseOrder, const []);
    });

    test('default order is built-in course first, decks appended after',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      final entries = provider.courseEntries;
      expect(entries.first.scope, '');
      expect(entries.first.isBuiltin, isTrue);
      expect(
        entries.skip(1).map((e) => e.scope),
        containsAll(['anki:deckaa', 'anki:deckbb']),
      );
      expect(entries.skip(1).every((e) => !e.isBuiltin), isTrue);
    });

    test('persistCourseOrder reorders entries and survives a restart',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.persistCourseOrder(['anki:deckbb', '', 'anki:deckaa']);

      expect(
        provider.courseEntries.map((e) => e.scope),
        ['anki:deckbb', '', 'anki:deckaa'],
      );

      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(
        restored.courseEntries.map((e) => e.scope),
        ['anki:deckbb', '', 'anki:deckaa'],
      );
    });

    test('stored order drops deleted decks and appends unknown new decks',
        () async {
      // 'anki:gone' was uninstalled; deckbb is not in the stored order yet.
      await appPrefs.setStringList(
          PrefsConstants.courseOrder, ['anki:gone', 'anki:deckaa', '']);

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.courseEntries.map((e) => e.scope),
        ['anki:deckaa', '', 'anki:deckbb'],
        reason:
            'stale ids are dropped, the built-in course always appears, and '
            'decks missing from the stored order are appended at the end',
      );
    });

    test(
        'reloadCourse sees a newly imported Anki deck without manual '
        'invalidateCaches (import-path regression)', () async {
      final db = await seedInMemoryCourseDb();
      final writeRepo = CourseRepository(db);
      await writeRepo
          .bulkInsertCourseTree(_ankiDeckSection('deckaa', 'Deck A'));
      await writeRepo
          .bulkInsertCourseTree(_ankiDeckSection('deckbb', 'Deck B'));
      CourseLoader.invalidateCaches();

      final provider = CourseProvider(appPrefs);
      await provider.load();
      expect(
        provider.ankiDeckEntries.map((e) => e.importId),
        containsAll(['deckaa', 'deckbb']),
      );
      expect(
        provider.ankiDeckEntries.map((e) => e.importId),
        isNot(contains('deckcc')),
      );

      // Simulate Anki import writing a section while CourseLoader shells
      // are still memoized. reloadCourse itself must drop that memo — the
      // caller must not need a separate invalidateCaches().
      await writeRepo
          .bulkInsertCourseTree(_ankiDeckSection('deckcc', 'Deck C'));
      await provider.reloadCourse();

      expect(
        provider.ankiDeckEntries.map((e) => e.importId),
        containsAll(['deckaa', 'deckbb', 'deckcc']),
        reason: 'reloadCourse must invalidate CourseLoader so new imports '
            'appear as course entries without an app restart',
      );
    });
  });
}
