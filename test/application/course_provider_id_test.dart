// Tests for CourseProvider's id-based selection API.
//
// The whole point of the refactor is that switching to a new section
// is keyed by a stable String id — never by an int index that could
// shift if a new section is inserted in the middle of the list.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/course_provider.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    test('load() called a second time leaves bodies intact (regression: tab-blank)',
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

      final otherUnitsCount = provider.findSectionById(other)?.units.length ?? 0;
      expect(otherUnitsCount, greaterThan(0));

      // Now a stray load() (e.g. from a tab round-trip firing the old
      // initState code path before the fix lands in production) must be
      // a no-op; the body for `other` must stay populated.
      await provider.load();
      expect(provider.findSectionById(other)?.units.length ?? 0,
          otherUnitsCount,
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
      expect(provider.sectionLoadState(firstSectionId!), SectionLoadState.loaded);
      expect(provider.currentSection?.units.length ?? 0, unitsBefore);
    });
  });
}
