// Tests for CourseProvider:
// 1. id-based selection API (switching sections, finding units/lessons)
// 2. Course scope & fallback (legacy Anki deck scoping)
// 3. Course order & management (reordering, catalog ordering)
// 4. Official Anki course scope & multi-source isolation

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart' show CourseDatabase;
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
/// AnkiDeckAssembler persists (`anki-<importId>-s<did>` id, level 'Anki').
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

const builtinWire = 'course-scope:v1:builtin:tr';
const frenchWire = 'course-scope:v1:builtin:fr';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('CourseProvider id addressing', () {
    late CourseProvider provider;

    setUp(() async {
      await seedInMemoryCourseDb();
      provider = CourseProvider();
      await provider.load();
    });

    test('starts with first section selected', () {
      expect(provider.sections, isNotEmpty);
      expect(provider.currentSectionId, provider.sections.first.id);
    });

    // The Turkish scaffold ships a single section, so the cross-section
    // "moves the cursor" / "clears selection" cases are skipped until real
    // multi-section content is authored.
    test('switchToSection by id moves the cursor', () {
      if (provider.sections.length < 2) return; // scaffold has one section
      final target = provider.sections[1].id;
      provider.switchToSection(target);
      expect(provider.currentSectionId, target);
      expect(provider.currentSection?.id, target);
    });

    test('switchToSection with unknown id is a no-op', () {
      final before = provider.currentSectionId;
      provider.switchToSection('does-not-exist');
      expect(provider.currentSectionId, before);
    });

    test('switching section clears unit/lesson selection', () async {
      if (provider.sections.length < 2) return; // scaffold has one section
      final a = provider.sections[0];
      // Section 0's body is pre-loaded by load(); select a unit + lesson.
      final u = a.units.first;
      final l = u.lessons.first;
      provider.selectUnit(u.id);
      provider.selectLesson(l.id);
      expect(provider.selectedUnitId, u.id);
      expect(provider.selectedLessonId, l.id);

      // Switch to section 1 (its body loads on demand) and wait for it.
      final target = provider.sections[1].id;
      provider.switchToSection(target);
      await provider.ensureSectionLoaded(target);
      expect(provider.selectedUnitId, isNull);
      expect(provider.selectedLessonId, isNull);
    });

    test('findLessonById resolves across sections (any position)', () async {
      // Pre-load every section's body so cross-section lookups can resolve.
      for (final s in provider.sections) {
        await provider.ensureSectionLoaded(s.id);
      }
      for (final s in provider.sections) {
        for (final u in s.units) {
          for (final l in u.lessons) {
            final found = provider.findLessonById(l.id);
            expect(found?.id, l.id,
                reason: 'lookup by id should not depend on position');
          }
        }
      }
    });

    test('findUnitById resolves across sections (any position)', () async {
      for (final s in provider.sections) {
        await provider.ensureSectionLoaded(s.id);
      }
      for (final s in provider.sections) {
        for (final u in s.units) {
          final found = provider.findUnitById(u.id);
          expect(found?.id, u.id);
        }
      }
    });

    test('findLessonById returns null for unknown id', () {
      expect(provider.findLessonById('l-does-not-exist'), isNull);
    });

    test('selectLesson with unknown id is a no-op', () {
      provider.selectLesson('l-does-not-exist');
      expect(provider.selectedLessonId, isNull);
    });

    // Regression: CourseProvider.load() was previously unconditional, so a
    // tab round-trip (AnimatedSwitcher rebuilt CourseTree from a new State,
    // which fired its initState load() call) would re-assign `_sections`
    // back to shells while `_loadedSectionIds` still claimed the section
    // was loaded. The user saw a blank Course Tree. After the fix load()
    // is idempotent (early-returns when `_isLoaded` is true), so the
    // cached full bodies survive any number of re-entries.
    test(
        'load() called a second time leaves bodies intact (regression: tab-blank)',
        () async {
      await provider.load();
      final firstSectionId = provider.currentSectionId;
      final firstUnitsCount = provider.currentSection?.units.length ?? 0;
      expect(firstUnitsCount, greaterThan(0),
          reason: 'first load() should populate the current section body');

      // Simulate what used to happen on a tab round-trip: a second load().
      await provider.load();

      expect(provider.isLoaded, isTrue);
      expect(provider.currentSectionId, firstSectionId);
      expect(provider.currentSection?.units.length ?? 0, firstUnitsCount,
          reason: 'second load() must not reset the body to shells');
    });

    test('load() after switching sections still no-ops on second entry',
        () async {
      await provider.load();
      // Move to a different section so the provider's currentSectionId
      // changes — this exercises ensureSectionLoaded on a different id.
      final other = provider.sections.last.id;
      provider.switchToSection(other);
      await provider.ensureSectionLoaded(other);

      final otherUnitsCount =
          provider.findSectionById(other)?.units.length ?? 0;
      expect(otherUnitsCount, greaterThan(0));

      // Now a stray load() (e.g. from a tab round-trip firing the old
      // initState code path before the fix lands in production) must be
      // a no-op; the body for `other` must stay populated.
      await provider.load();
      expect(
          provider.findSectionById(other)?.units.length ?? 0, otherUnitsCount,
          reason: 'third load() must not reset the body for the switched-to '
              'section');
    });

    test('ensureSectionLoaded reports error for unknown section id', () async {
      await provider.load();
      const unknownId = 's-does-not-exist';

      await provider.ensureSectionLoaded(unknownId);

      expect(provider.sectionLoadState(unknownId), SectionLoadState.error);
      expect(provider.sectionLoadError(unknownId), isNotNull);
      expect(provider.findSectionById(unknownId), isNull);
    });

    test('reloadSection resets state and retries loading', () async {
      await provider.load();
      final sectionId = provider.currentSectionId!;
      final unitsBefore = provider.currentSection!.units.length;
      expect(unitsBefore, greaterThan(0));
      expect(provider.sectionLoadState(sectionId), SectionLoadState.loaded);

      await provider.reloadSection(sectionId);

      expect(provider.sectionLoadState(sectionId), SectionLoadState.loaded);
      expect(provider.currentSection!.units.length, unitsBefore);
    });

    test('reloadCourse resets shells and reloads first section body', () async {
      await provider.load();
      final firstSectionId = provider.currentSectionId;
      final unitsBefore = provider.currentSection?.units.length ?? 0;
      expect(firstSectionId, isNotNull);
      expect(unitsBefore, greaterThan(0));

      await provider.reloadCourse();

      expect(provider.isLoaded, isTrue);
      expect(provider.sections, isNotEmpty);
      expect(provider.currentSectionId, firstSectionId);
      expect(
          provider.sectionLoadState(firstSectionId!), SectionLoadState.loaded);
      expect(provider.currentSection?.units.length ?? 0, unitsBefore);
    });
  });

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
      expect(entries.where((e) => e.isBuiltin).length, greaterThanOrEqualTo(1));
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
        [deckB, builtinWire, deckA, frenchWire],
      );

      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(
        restored.catalogEntries.map((e) => e.wireKey),
        [deckB, builtinWire, deckA, frenchWire],
      );
    });

    test('persistCourseOrder applies the new order before its first await',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      final deckA = LegacyAnkiCourseScope('deckaa').wireKey;
      final deckB = LegacyAnkiCourseScope('deckbb').wireKey;
      var notifications = 0;
      provider.addListener(() => notifications++);

      // 不 await：断言须在第一个 await 之前成立——ReorderableListView
      // 松手当帧就要拿到最终顺序并重建，否则卡片先弹回原位、目录
      // reload 落地后再瞬移到新位置（课程管理拖动排序的闪现）。
      final pending = provider.persistCourseOrder([deckB, builtinWire, deckA]);

      expect(
        provider.catalogEntries.map((e) => e.wireKey),
        [deckB, builtinWire, deckA, frenchWire],
      );
      expect(notifications, 1,
          reason: '同步通知让列表的落位动画与最终顺序同帧衔接');

      await pending;
      expect(
        provider.catalogEntries.map((e) => e.wireKey),
        [deckB, builtinWire, deckA, frenchWire],
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
        [deckA, builtinWire, frenchWire, deckB],
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
        ['deckbb', 'builtin', 'deckaa', 'builtin'],
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

  group('CourseProvider official scope', () {
    late CourseDatabase db;
    late AppPrefs appPrefs;
    late OfficialAnkiDatabase catalog;

    const srcA = 'src-4f8b2c9d1e';
    const srcB = 'src-99aa88bb77';

    setUp(() async {
      db = await seedInMemoryCourseDb();
      catalog = OfficialAnkiDatabase.memory();
      OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
      // The catalog ledger + course tree view a real v2 publish writes: one
      // active source row per official source (display name lives there), and
      // view rows for each of its sections — official section shells come
      // from the view alone (Step 6 removed the drift-table assembly).
      final sources = OfficialAnkiSourceDao(catalog);
      for (final (sourceId, name) in const [
        (srcA, 'Deck A'),
        (srcB, 'Deck B'),
      ]) {
        sources.upsertSource(
          sourceId: sourceId,
          profileId: 'profile-default-01',
          sourceHash: 'hash-$sourceId',
          sourceSize: 1,
          displayName: name,
          state: 'active',
          backendCommit: 'test',
          nowMillis: 1,
        );
      }
      await db.customStatement(
        "INSERT INTO anki_course_tree_view "
        "(source_id, card_id, note_id, deck_id, word_id, section_key, section_id, "
        " unit_id, lesson_id, lesson_key, presentation_kind, source_hash, "
        " mapping_version, rebuilt_at_millis) VALUES "
        "('$srcA', 1, 1, 10, 'w1', 'Deck A Top', 'official-anki-$srcA-s10', "
        "'official-anki-$srcA-s10-u1', 'official-anki-$srcA-s10-l1', 'lk', "
        "'flip', 'hash-$srcA', 1, 1),"
        "('$srcA', 2, 2, 11, 'w2', 'Deck A Sub', 'official-anki-$srcA-s11', "
        "'official-anki-$srcA-s11-u1', 'official-anki-$srcA-s11-l1', 'lk', "
        "'flip', 'hash-$srcA', 1, 1),"
        "('$srcB', 3, 3, 10, 'w3', 'Deck B Top', 'official-anki-$srcB-s10', "
        "'official-anki-$srcB-s10-u1', 'official-anki-$srcB-s10-l1', 'lk', "
        "'flip', 'hash-$srcB', 1, 1)",
      );
      CourseLoader.invalidateCaches();

      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.setString(PrefsConstants.courseScope, '');
      await appPrefs.setStringList(PrefsConstants.courseOrder, const []);

      // Course entry flags on (production profile), projections active.
      OfficialAnkiCourseEntry.flagsOf =
          () => OfficialAnkiFeatureFlags.productionAndroid;
      OfficialAnkiCourseEntry.activeSectionIds = () => {
            'official-anki-$srcA-s10',
            'official-anki-$srcA-s11',
            'official-anki-$srcB-s10',
          };
    });

    tearDown(() async {
      OfficialAnkiCourseEntry.resetHooks();
      OfficialAnkiCompositionRoot.readOnlyCatalog = null;
      catalog.close();
      await db.close();
    });

    void retireSource(String sourceId) {
      OfficialAnkiSourceDao(catalog).upsertSource(
        sourceId: sourceId,
        profileId: 'profile-default-01',
        sourceHash: 'hash-$sourceId',
        sourceSize: 1,
        displayName: sourceId,
        state: 'retired',
        backendCommit: 'test',
        nowMillis: 2,
      );
    }

    test('builtin scope hides BOTH legacy and official Anki sections (R1-2)',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(provider.scope, const BuiltinCourseScope('turkish'));
      expect(provider.sections, isNotEmpty);
      expect(
        provider.sections.any((s) =>
            s.level == 'Anki' ||
            s.level == 'OfficialAnki' ||
            OfficialAnkiCourseEntry.isOfficialSectionId(s.id)),
        isFalse,
        reason: 'the builtin language course must never show an Anki section',
      );
    });

    test('full src-<random> sourceId round-trips scope → filter → entries',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setScope(OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcA,
      ));

      expect(
        provider.scope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcA,
        ),
      );
      // Only source A's sections, both decks of it.
      expect(provider.sections.map((s) => s.id).toSet(), {
        'official-anki-$srcA-s10',
        'official-anki-$srcA-s11',
      });

      // Restart keeps the exact full sourceId.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(
        restored.scope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcA,
        ),
        reason: 'the persisted scope must carry the complete sourceId, never '
            'the truncated "src"',
      );
      expect(restored.sections, hasLength(2));
    });

    test('two official sources are two distinct course entries (R1-3)', () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      final official = provider.catalogEntries
          .where((e) => e.officialSourceId != null)
          .toList();
      expect(official, hasLength(2));
      expect(official.map((e) => e.officialSourceId).toSet(), {srcA, srcB});
      expect(official.map((e) => e.displayName), ['Deck A', 'Deck B']);
    });

    test('selecting source B shows only B sections; A untouched (R1-3)',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setScope(OfficialAnkiCourseScope(
        profileId: 'profile-default-01',
        sourceId: srcB,
      ));

      expect(
        provider.sections.map((s) => s.id),
        ['official-anki-$srcB-s10'],
      );
    });

    test(
        'empty visibility set does not bounce an installed official source '
        'back to the built-in course', () async {
      OfficialAnkiCourseEntry.activeSectionIds = () => {};
      await appPrefs.setString(
        PrefsConstants.courseScope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcA,
        ).wireKey,
      );

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcA,
        ),
      );
      expect(provider.sections.map((s) => s.id).toSet(), {
        'official-anki-$srcA-s10',
        'official-anki-$srcA-s11',
      });
    });

    test(
        'official scope with no catalog entry still falls back to builtin',
        () async {
      OfficialAnkiCourseEntry.activeSectionIds = () => {};
      retireSource(srcA);
      retireSource(srcB);
      await appPrefs.setString(
        PrefsConstants.courseScope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcA,
        ).wireKey,
      );

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(provider.scope, const BuiltinCourseScope('turkish'));
      expect(
        provider.sections.any(
          (s) => OfficialAnkiCourseEntry.isOfficialSectionId(s.id),
        ),
        isFalse,
      );
    });

    test(
        'legacy anki:<fullSourceId> scope value resolves to the official '
        'source (upgrade path)', () async {
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:$srcB');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        OfficialAnkiCourseScope(
          profileId: 'profile-default-01',
          sourceId: srcB,
        ),
      );
      expect(provider.sections, hasLength(1));
    });

    group('broken anki:src preference handling (R1-6 provider path)', () {
      test('with exactly one official source, anki:src re-binds to it', () async {
        // Retire source B in the catalog so only A remains visible; the
        // retired source must not come back through any fallback.
        retireSource(srcB);
        await appPrefs.setString(PrefsConstants.courseScope, 'anki:src');

        final provider = CourseProvider(appPrefs);
        await provider.load();

        expect(
          provider.scope,
          OfficialAnkiCourseScope(
            profileId: 'profile-default-01',
            sourceId: srcA,
          ),
          reason: 'a truncated anki:src with one source re-binds to that '
              'source instead of guessing',
        );
      });

      test('with multiple official sources, anki:src falls back to builtin',
          () async {
        await appPrefs.setString(PrefsConstants.courseScope, 'anki:src');

        final provider = CourseProvider(appPrefs);
        await provider.load();

        expect(
          provider.scope,
          const BuiltinCourseScope('turkish'),
          reason: 'ambiguity must fall back to builtin, never pick the first '
              'source',
        );
        expect(provider.sections.every((s) => s.level != 'OfficialAnki'), isTrue);
      });
    });
  });
}
