// Tests for CourseProvider's id-based selection API.
//
// The whole point of the refactor is that switching to a new section
// is keyed by a stable String id — never by an int index that could
// shift if a new section is inserted in the middle of the list.

import 'package:flutter_test/flutter_test.dart';
import 'package:words625/application/course_provider.dart';

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

    test('switchToSection by id moves the cursor', () {
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
  });
}
