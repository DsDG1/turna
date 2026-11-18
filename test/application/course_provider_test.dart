// Tests for CourseProvider:
// 1. id-based selection API (switching sections, finding units/lessons)
// 2. Course scope & fallback (Official Anki deck scoping + legacy fallback)
// 3. Course order & management (reordering, catalog ordering)
// 4. Official Anki course scope & multi-source isolation

import 'dart:async';

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
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/service/locator.dart';

import '../helpers/fixture_language_bundle.dart';
import '../helpers/in_memory_course_db.dart';

/// Seeds an active Official Anki v2 source and its `anki_course_tree_view` row.
Future<void> _seedOfficialDeck({
  required CourseDatabase db,
  required OfficialAnkiDatabase catalog,
  required String sourceId,
  required String name,
  int cardId = 1,
  int deckId = 10,
}) async {
  OfficialAnkiSourceDao(catalog).upsertSource(
    sourceId: sourceId,
    profileId: 'profile-default-01',
    sourceHash: 'hash-$sourceId',
    sourceSize: 1,
    displayName: name,
    state: 'active',
    backendCommit: 'test',
    nowMillis: 1,
  );
  await db.customStatement(
    'INSERT INTO anki_course_tree_view '
    '(source_id, card_id, note_id, deck_id, word_id, section_key, section_id, '
    ' unit_id, unit_key, lesson_id, lesson_key, source_hash, '
    ' mapping_version, rebuilt_at_millis) VALUES '
    '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
    [
      sourceId,
      cardId,
      cardId,
      deckId,
      'w-$sourceId-$cardId',
      '$name Section',
      'official-anki-$sourceId-s$deckId',
      'official-anki-$sourceId-s$deckId-u1',
      name,
      'official-anki-$sourceId-s$deckId-l1',
      'Lesson 1',
      'hash-$sourceId',
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
      unawaited(provider.selectUnit(u.id));
      unawaited(provider.selectLesson(l.id));
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
      // Move to a section with content so ensureSectionLoaded runs on a
      // section body. (NouveauTurkish currently has exactly one non-empty
      // section, nt-s1; sections.last is an idle empty shell, 0 units.)
      final other = provider.sections.first.id;
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
    late CourseDatabase db;
    late OfficialAnkiDatabase catalog;
    late AppPrefs appPrefs;

    const deckAScope = OfficialAnkiCourseScope(
      profileId: 'profile-default-01',
      sourceId: 'deckaa',
    );
    const deckBScope = OfficialAnkiCourseScope(
      profileId: 'profile-default-01',
      sourceId: 'deckbb',
    );

    setUp(() async {
      db = await seedInMemoryCourseDb();
      catalog = OfficialAnkiDatabase.memory();
      OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
      await _seedOfficialDeck(
        db: db,
        catalog: catalog,
        sourceId: 'deckaa',
        name: 'Deck A',
        cardId: 1,
      );
      await _seedOfficialDeck(
        db: db,
        catalog: catalog,
        sourceId: 'deckbb',
        name: 'Deck B',
        cardId: 2,
      );
      CourseLoader.invalidateCaches();

      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      // StreamingSharedPreferences.instance is cached for the whole test
      // file, so reset the scope key explicitly to keep tests independent.
      await appPrefs.setString(PrefsConstants.courseScope, '');
      await appPrefs.setStringList(PrefsConstants.courseOrder, const []);

      OfficialAnkiCourseEntry.flagsOf =
          () => OfficialAnkiFeatureFlags.productionAndroid;
      OfficialAnkiCourseEntry.activeSectionIds = () => {
            'official-anki-deckaa-s10',
            'official-anki-deckbb-s10',
          };
    });

    tearDown(() async {
      OfficialAnkiCourseEntry.resetHooks();
      OfficialAnkiCompositionRoot.readOnlyCatalog = null;
      CourseLoader.clearDatabaseOverride();
      catalog.close();
      await db.close();
    });

    test('default scope hides Anki decks but still lists deck entries',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(provider.scope, const BuiltinCourseScope('turkish'));
      expect(provider.sections, isNotEmpty);
      expect(
        provider.sections.every(
          (s) => s.level != 'Anki' && s.level != 'OfficialAnki',
        ),
        isTrue,
        reason: 'built-in scope must hide Anki deck sections',
      );

      // The unfiltered list and the catalog still see every deck.
      expect(
        provider.allSections.where((s) => s.level == 'OfficialAnki'),
        hasLength(2),
      );
      expect(
        provider.catalogEntries
            .where((e) => e.officialSourceId != null)
            .map((e) => e.officialSourceId),
        containsAll(['deckaa', 'deckbb']),
      );
      expect(
        provider.catalogEntries
            .where((e) => !e.isBuiltin)
            .map((e) => e.displayName),
        containsAll(['Deck A', 'Deck B']),
      );
    });

    test('setScope scopes the tree to one deck and persists', () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setScope(deckAScope);

      expect(provider.scope, deckAScope);
      expect(provider.sections, hasLength(1));
      expect(provider.sections.single.id, 'official-anki-deckaa-s10');
      expect(provider.currentSectionId, 'official-anki-deckaa-s10');
      // The deck body is populated from the v2 course-tree view.
      expect(provider.currentSection?.units, isNotEmpty);

      // A fresh provider restores the persisted scope.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.scope, deckAScope);
      expect(restored.sections.single.id, 'official-anki-deckaa-s10');
    });

    test('legacy string setCourseScope falls back to builtin (plan P1)',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      // Pre-cutover and retired legacy wire values fall back to a builtin course.
      await provider.setCourseScope('anki:deckbb');
      expect(provider.scope, isA<BuiltinCourseScope>());

      await provider.setCourseScope('course-scope:v1:legacy:deckbb');
      expect(provider.scope, isA<BuiltinCourseScope>());
    });

    test('switching back to the built-in scope restores the full course',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      await provider.setScope(deckBScope);
      expect(provider.sections.single.id, 'official-anki-deckbb-s10');

      await provider.setScope(const BuiltinCourseScope('turkish'));
      expect(provider.scope, const BuiltinCourseScope('turkish'));
      expect(
        provider.sections.every(
          (s) => s.level != 'Anki' && s.level != 'OfficialAnki',
        ),
        isTrue,
      );

      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.scope, const BuiltinCourseScope('turkish'));
    });

    test('falls back to built-in course when the scoped deck is gone',
        () async {
      // Simulate a persisted scope whose deck was uninstalled / retired.
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:gone');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        const BuiltinCourseScope('turkish'),
        reason: 'unknown deck scope must fall back to the built-in course',
      );
      expect(provider.sections, isNotEmpty);
      expect(
        provider.sections.every(
          (s) => s.level != 'Anki' && s.level != 'OfficialAnki',
        ),
        isTrue,
      );

      // The fallback is persisted, so a fresh provider stays builtin too.
      final restored = CourseProvider(appPrefs);
      await restored.load();
      expect(restored.scope, const BuiltinCourseScope('turkish'));
    });
  });

  group('CourseProvider course order (course management page)', () {
    late CourseDatabase db;
    late OfficialAnkiDatabase catalog;
    late AppPrefs appPrefs;
    late Set<String> activeIds;

    setUp(() async {
      // Turkish from the shipped bundle, French from the fixture overlay: the
      // order assertions below cover two builtin courses plus two decks, and
      // 0.9 ships a single builtin language.
      db = await seedInMemoryCourseDb(bundle: await frenchCourseFixtureBundle());
      catalog = OfficialAnkiDatabase.memory();
      OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
      await _seedOfficialDeck(
        db: db,
        catalog: catalog,
        sourceId: 'deckaa',
        name: 'Deck A',
        cardId: 1,
      );
      await _seedOfficialDeck(
        db: db,
        catalog: catalog,
        sourceId: 'deckbb',
        name: 'Deck B',
        cardId: 2,
      );
      CourseLoader.invalidateCaches();

      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.setString(PrefsConstants.courseScope, '');
      await appPrefs.setStringList(PrefsConstants.courseOrder, const []);

      activeIds = {
        'official-anki-deckaa-s10',
        'official-anki-deckbb-s10',
      };
      OfficialAnkiCourseEntry.flagsOf =
          () => OfficialAnkiFeatureFlags.productionAndroid;
      OfficialAnkiCourseEntry.activeSectionIds = () => activeIds;
    });

    tearDown(() async {
      OfficialAnkiCourseEntry.resetHooks();
      OfficialAnkiCompositionRoot.readOnlyCatalog = null;
      CourseLoader.clearDatabaseOverride();
      catalog.close();
      await db.close();
    });

    test('default order is built-in course first, decks appended after',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      final entries = provider.catalogEntries;
      expect(entries.first.isBuiltin, isTrue);
      expect(
        entries.skip(1).map((e) => e.officialSourceId),
        containsAll(['deckaa', 'deckbb']),
      );
      expect(entries.where((e) => e.isBuiltin).length, greaterThanOrEqualTo(1));
    });

    test('persistCourseOrder reorders entries and survives a restart',
        () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();

      const deckA = 'course-scope:v1:official:profile-default-01:deckaa';
      const deckB = 'course-scope:v1:official:profile-default-01:deckbb';
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

      const deckA = 'course-scope:v1:official:profile-default-01:deckaa';
      const deckB = 'course-scope:v1:official:profile-default-01:deckbb';
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
      expect(notifications, 1, reason: '同步通知让列表的落位动画与最终顺序同帧衔接');

      await pending;
      expect(
        provider.catalogEntries.map((e) => e.wireKey),
        [deckB, builtinWire, deckA, frenchWire],
      );
    });

    test('stored order drops deleted decks and appends unknown new decks',
        () async {
      const deckA = 'course-scope:v1:official:profile-default-01:deckaa';
      const deckB = 'course-scope:v1:official:profile-default-01:deckbb';
      const gone = 'course-scope:v1:official:profile-default-01:gone';
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
        provider.catalogEntries.map((e) => e.officialSourceId ?? 'builtin'),
        ['deckbb', 'builtin', 'deckaa', 'builtin'],
      );
    });

    test(
        'reloadCourse sees a newly imported Anki deck without manual '
        'invalidateCaches (import-path regression)', () async {
      final provider = CourseProvider(appPrefs);
      await provider.load();
      expect(
        provider.catalogEntries
            .where((e) => e.officialSourceId != null)
            .map((e) => e.officialSourceId),
        containsAll(['deckaa', 'deckbb']),
      );

      // Simulate an Official Anki import publishing a new deck while
      // CourseLoader shells are still memoized. reloadCourse itself must drop
      // that memo — the caller must not need a separate invalidateCaches().
      await _seedOfficialDeck(
        db: db,
        catalog: catalog,
        sourceId: 'deckcc',
        name: 'Deck C',
        cardId: 3,
      );
      activeIds.add('official-anki-deckcc-s10');
      await provider.reloadCourse();

      expect(
        provider.catalogEntries
            .where((e) => e.officialSourceId != null)
            .map((e) => e.officialSourceId),
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
        " unit_id, lesson_id, lesson_key, source_hash, "
        " mapping_version, rebuilt_at_millis) VALUES "
        "('$srcA', 1, 1, 10, 'w1', 'Deck A Top', 'official-anki-$srcA-s10', "
        "'official-anki-$srcA-s10-u1', 'official-anki-$srcA-s10-l1', 'lk', "
        "'hash-$srcA', 1, 1),"
        "('$srcA', 2, 2, 11, 'w2', 'Deck A Sub', 'official-anki-$srcA-s11', "
        "'official-anki-$srcA-s11-u1', 'official-anki-$srcA-s11-l1', 'lk', "
        "'hash-$srcA', 1, 1),"
        "('$srcB', 3, 3, 10, 'w3', 'Deck B Top', 'official-anki-$srcB-s10', "
        "'official-anki-$srcB-s10-u1', 'official-anki-$srcB-s10-l1', 'lk', "
        "'hash-$srcB', 1, 1)",
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

    test('a broken official view keeps builtin courses and records the error',
        () async {
      await db.customStatement('DROP TABLE anki_course_tree_view');
      await db.customStatement(
        'CREATE TABLE anki_course_tree_view (source_id TEXT)',
      );
      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(provider.officialTreeLoadError, isNotNull);
      expect(provider.bootFailed, isFalse);
      expect(provider.sections, isNotEmpty);
      expect(
        provider.sections.any((section) => section.level == 'OfficialAnki'),
        isFalse,
      );
    });

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

    test('two official sources are two distinct course entries (R1-3)',
        () async {
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

    test('official scope with no catalog entry still falls back to builtin',
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
        'legacy anki:<fullSourceId> scope value falls back to builtin '
        '(upgrade path retired, plan P1)', () async {
      await appPrefs.setString(PrefsConstants.courseScope, 'anki:$srcB');

      final provider = CourseProvider(appPrefs);
      await provider.load();

      expect(
        provider.scope,
        const BuiltinCourseScope('turkish'),
        reason: 'pre-cutover raw scope values are no longer resolved; the '
            'app lands on a usable builtin course instead of guessing',
      );
    });

    group('broken anki:src preference handling (R1-6 provider path)', () {
      test('with exactly one official source, anki:src falls back to builtin',
          () async {
        // Retire source B in the catalog so only A remains visible; the
        // retired source must not come back through any fallback.
        retireSource(srcB);
        await appPrefs.setString(PrefsConstants.courseScope, 'anki:src');

        final provider = CourseProvider(appPrefs);
        await provider.load();

        expect(
          provider.scope,
          const BuiltinCourseScope('turkish'),
          reason: 'the truncated-value repair chain is retired (plan P1); '
              'unparseable scopes land on a builtin course',
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
        expect(
            provider.sections.every((s) => s.level != 'OfficialAnki'), isTrue);
      });
    });
  });
}
