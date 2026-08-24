// Tests for CourseProvider's course scope: the Learn-page tree can be
// scoped to a single imported Anki course via the typed CourseScope API,
// persisted with the v1 codec, and falls back to the built-in course when
// the course disappears.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/course_scope.dart';
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

const builtinWire = 'course-scope:v1:builtin:turkish';

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

      expect(provider.scope, const BuiltinCourseScope('turkish'));
      expect(provider.sections, isNotEmpty);
      expect(provider.sections.every((s) => s.level != 'Anki'), isTrue,
          reason: 'built-in scope must hide Anki deck sections');

      // The unfiltered list and the catalog still see every deck.
      expect(
        provider.allSections.where((s) => s.level == 'Anki'),
        hasLength(2),
      );
      expect(
        provider.catalogEntries
            .where((e) => e.legacyImportId != null)
            .map((e) => e.legacyImportId),
        containsAll(['deckaa', 'deckbb']),
      );
      expect(
        provider.catalogEntries.where((e) => !e.isBuiltin).map((e) => e.displayName),
        containsAll(['Deck A', 'Deck B']),
      );
    });

    test('setScope scopes the tree to one deck and persists', () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setScope(const LegacyAnkiCourseScope('deckaa'));

      expect(provider.scope, const LegacyAnkiCourseScope('deckaa'));
      expect(provider.sections, hasLength(1));
      expect(provider.sections.single.id, 'anki-deckaa-s10');
      expect(provider.currentSectionId, 'anki-deckaa-s10');
      // The deck body loads through the standard lazy path.
      expect(provider.currentSection?.units, isNotEmpty);

      // A fresh provider restores the persisted scope.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.scope, const LegacyAnkiCourseScope('deckaa'));
      expect(restored.sections.single.id, 'anki-deckaa-s10');
    });

    test('legacy string setCourseScope resolves via the catalog', () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setCourseScope('anki:deckbb');

      expect(provider.scope, const LegacyAnkiCourseScope('deckbb'));
      expect(provider.sections.single.id, 'anki-deckbb-s10');
    });

    test('switching back to the built-in scope restores the full course',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setScope(const LegacyAnkiCourseScope('deckbb'));
      expect(provider.sections.single.id, 'anki-deckbb-s10');

      await provider.setScope(const BuiltinCourseScope('turkish'));
      expect(provider.scope, const BuiltinCourseScope('turkish'));
      expect(provider.sections.every((s) => s.level != 'Anki'), isTrue);

      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.scope, const BuiltinCourseScope('turkish'));
    });

    test('falls back to built-in course when the scoped deck is gone',
        () async {
      // Simulate a persisted scope whose deck was uninstalled.
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:gone');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        const BuiltinCourseScope('turkish'),
        reason: 'unknown deck scope must fall back to the built-in course',
      );
      expect(provider.sections, isNotEmpty);
      expect(provider.sections.every((s) => s.level != 'Anki'), isTrue);

      // The fallback is persisted, so a fresh provider stays builtin too.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.scope, const BuiltinCourseScope('turkish'));
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

      final entries = provider.catalogEntries;
      expect(entries.first.isBuiltin, isTrue);
      expect(
        entries.skip(1).map((e) => e.legacyImportId),
        containsAll(['deckaa', 'deckbb']),
      );
      expect(entries.skip(1).every((e) => !e.isBuiltin), isTrue);
    });

    test('persistCourseOrder reorders entries and survives a restart',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      final deckA = LegacyAnkiCourseScope('deckaa').wireKey;
      final deckB = LegacyAnkiCourseScope('deckbb').wireKey;
      await provider.persistCourseOrder([deckB, builtinWire, deckA]);

      expect(
        provider.catalogEntries.map((e) => e.wireKey),
        [deckB, builtinWire, deckA],
      );

      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(
        restored.catalogEntries.map((e) => e.wireKey),
        [deckB, builtinWire, deckA],
      );
    });

    test('stored order drops deleted decks and appends unknown new decks',
        () async {
      final deckA = LegacyAnkiCourseScope('deckaa').wireKey;
      final deckB = LegacyAnkiCourseScope('deckbb').wireKey;
      final gone = LegacyAnkiCourseScope('gone').wireKey;
      // 'gone' was uninstalled; deckbb is not in the stored order yet.
      await appPrefs.setStringList(
          PrefsConstants.courseOrder, [gone, deckA, builtinWire]);

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.catalogEntries.map((e) => e.wireKey),
        [deckA, builtinWire, deckB],
        reason:
            'stale ids are dropped, the built-in course always appears, and '
            'courses missing from the stored order are appended at the end',
      );
    });

    test('legacy stored order strings are mapped onto v1 wires', () async {
      await appPrefs.setStringList(
          PrefsConstants.courseOrder, ['anki:deckbb', '', 'anki:deckaa']);

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.catalogEntries.map((e) => e.legacyImportId ?? 'builtin'),
        ['deckbb', 'builtin', 'deckaa'],
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
        provider.catalogEntries
            .where((e) => e.legacyImportId != null)
            .map((e) => e.legacyImportId),
        containsAll(['deckaa', 'deckbb']),
      );

      // Simulate Anki import writing a section while CourseLoader shells
      // are still memoized. reloadCourse itself must drop that memo — the
      // caller must not need a separate invalidateCaches().
      await writeRepo
          .bulkInsertCourseTree(_ankiDeckSection('deckcc', 'Deck C'));
      await provider.reloadCourse();

      expect(
        provider.catalogEntries
            .where((e) => e.legacyImportId != null)
            .map((e) => e.legacyImportId),
        containsAll(['deckaa', 'deckbb', 'deckcc']),
        reason: 'reloadCourse must invalidate CourseLoader so new imports '
            'appear as course entries without an app restart',
      );
    });
  });
}
