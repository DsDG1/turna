// Tests for CourseCatalog.builtinLanguageOf — the section → builtin-language
// attribution shared by the course tree filter and the catalog counts.
//
// Semantics:
// - a section with a recorded language_code is attributed to that language;
// - a section id MISSING from a loaded map is a non-DB shell (v2 view etc.)
//   and belongs to no builtin language — NOT silently Turkish;
// - only when the whole map is unavailable (empty — e.g. the query failed)
//   do we degrade to the historical 'tr' fallback so the course doesn't
//   blank out.
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/application/language_registry.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('builtinLanguageOf', () {
    test('returns the recorded language, canonicalized', () {
      final map = {'s1': 'TR', 's2': 'fr'};
      expect(CourseCatalog.builtinLanguageOf('s1', map), LanguageCodes.turkish);
      expect(CourseCatalog.builtinLanguageOf('s2', map), LanguageCodes.french);
    });

    test('missing id in a loaded map belongs to no builtin language', () {
      final map = {'s1': 'tr'};
      expect(CourseCatalog.builtinLanguageOf('ghost', map), isNull);
    });

    test('empty map (query failed) degrades to turkish', () {
      expect(
        CourseCatalog.builtinLanguageOf('anything', const {}),
        LanguageCodes.turkish,
      );
    });
  });

  test('catalog does not count ghost shells toward any builtin language',
      () async {
    LanguageRegistry.instance.resetForTest();
    addTearDown(LanguageRegistry.instance.resetForTest);
    final db = await seedInMemoryCourseDb();
    addTearDown(() async {
      await db.close();
    });

    final shells = await CourseRepository(db).sectionShells();
    final trCountReal =
        shells.where((s) => !s.id.startsWith('fr-')).length;
    const ghost = Section(
      id: 'ghost-no-db-row',
      name: 'Ghost',
      units: [],
    );

    final catalog = await CourseCatalog.load(
      shells: [...shells, ghost],
      courseDb: db,
    );
    final tr = catalog
        .where((e) =>
            e.isBuiltin &&
            (e.scope as BuiltinCourseScope).canonicalLanguageCode ==
                LanguageCodes.turkish)
        .single;
    expect(
      tr.sectionCount,
      trCountReal,
      reason: 'the ghost shell has no language row and must not be '
          'attributed to Turkish',
    );
  });
}
