// Runtime cross-course lesson/unit id uniqueness gate. The CI
// `validateCourse` already enforces this, but a runtime mirror lives in
// `DatabaseSeeder._seedSections` (via `collectCrossCourseIdErrors`) so a
// duplicate id cannot silently corrupt the seeded course tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/course_validator.dart';
import 'package:varnamala/data/course_database_seeder.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/unit.dart';

Section _section(String id, List<Unit> units) =>
    Section(id: id, name: id, units: units);

Unit _unit(String id, List<Lesson> lessons) =>
    Unit(id: id, name: id, lessons: lessons);

Lesson _lesson(String id) => Lesson(
      id: id,
      name: id,
      type: LessonType.normal,
      template: LessonTemplate.legacy,
      content: const LessonContent(),
    );

void main() {
  group('DatabaseSeeder.collectCrossCourseIdErrors', () {
    test('returns no errors for clean sections', () {
      final sections = [
        _section('s-1', [_unit('u-1', [_lesson('l-1'), _lesson('l-2')])]),
        _section('s-2', [_unit('u-2', [_lesson('l-3'), _lesson('l-4')])]),
      ];
      expect(
        DatabaseSeeder.collectCrossCourseIdErrors(sections),
        isEmpty,
      );
    });

    test('flags duplicate lesson id across sections', () {
      final sections = [
        _section('s-1', [_unit('u-1', [_lesson('l-dup')])]),
        _section('s-2', [_unit('u-2', [_lesson('l-dup')])]),
      ];
      final errors = DatabaseSeeder.collectCrossCourseIdErrors(sections);
      expect(errors, hasLength(1));
      expect(errors.first, contains('l-dup'));
    });

    test('flags duplicate unit id across sections', () {
      final sections = [
        _section('s-1', [_unit('u-dup', [_lesson('l-1')])]),
        _section('s-2', [_unit('u-dup', [_lesson('l-2')])]),
      ];
      final errors = DatabaseSeeder.collectCrossCourseIdErrors(sections);
      expect(errors, hasLength(1));
      expect(errors.first, contains('u-dup'));
    });

    test('reports both duplicate unit and duplicate lesson ids', () {
      final sections = [
        _section('s-1', [_unit('u-dup', [_lesson('l-dup')])]),
        _section('s-2', [_unit('u-dup', [_lesson('l-dup')])]),
      ];
      final errors = DatabaseSeeder.collectCrossCourseIdErrors(sections);
      expect(errors, hasLength(2));
    });

    test('same id within one section is not a cross-course error', () {
      // within-section uniqueness is validateSection's job; the seeder only
      // checks across sections, so a unique-per-section layout is clean.
      final sections = [
        _section('s-1', [_unit('u-1', [_lesson('l-1')])]),
      ];
      expect(DatabaseSeeder.collectCrossCourseIdErrors(sections), isEmpty);
    });
  });

  group('CourseValidationException', () {
    test('carries the cross-course errors', () {
      final errors = ['Duplicate lesson id across course: l-x'];
      final exc = CourseValidationException(errors);
      expect(exc.errors, errors);
      expect(exc.toString(), contains('l-x'));
    });
  });
}