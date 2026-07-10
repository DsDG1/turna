// Round-trip test: raw section JSON -> in-memory DB -> domain model -> JSON.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/domain/course/lesson.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseSeeder round-trip', () {
    test('section4.json survives parse -> seed -> read -> serialize', () async {
      final raw = await rootBundle.loadString(
        '${SwahiliCourse.baseDir}/sections/section4.json',
      );
      final originalSection = parseSwahiliSection(raw);

      final db = await seedInMemoryCourseDb();
      final repo = CourseRepository(db);
      final roundTripped = await repo.section(originalSection.id);

      // Section identity preserved.
      expect(roundTripped.id, originalSection.id);
      expect(roundTripped.name, originalSection.name);
      expect(roundTripped.description, originalSection.description);

      // Unit identities preserved.
      expect(
        roundTripped.units.map((u) => u.id).toList(),
        originalSection.units.map((u) => u.id).toList(),
      );
      expect(
        roundTripped.units.map((u) => u.name).toList(),
        originalSection.units.map((u) => u.name).toList(),
      );

      // Lesson identities preserved.
      final originalLessons = <Lesson>[
        for (final u in originalSection.units) ...u.lessons,
      ];
      final roundTrippedLessons = <Lesson>[
        for (final u in roundTripped.units) ...u.lessons,
      ];
      expect(
        roundTrippedLessons.map((l) => l.id).toList(),
        originalLessons.map((l) => l.id).toList(),
      );
      expect(
        roundTrippedLessons.map((l) => l.name).toList(),
        originalLessons.map((l) => l.name).toList(),
      );

      // Templates and types preserved.
      for (var i = 0; i < originalLessons.length; i++) {
        expect(
          roundTrippedLessons[i].template,
          originalLessons[i].template,
          reason: 'template mismatch for ${originalLessons[i].id}',
        );
        expect(
          roundTrippedLessons[i].type,
          originalLessons[i].type,
          reason: 'type mismatch for ${originalLessons[i].id}',
        );
      }

      // Lesson content JSON serializes back to the same shape.
      for (var i = 0; i < originalLessons.length; i++) {
        final originalJson = originalLessons[i].content.toJson();
        final roundJson = roundTrippedLessons[i].content.toJson();
        expect(
          jsonEncode(roundJson),
          jsonEncode(originalJson),
          reason: 'content JSON mismatch for ${originalLessons[i].id}',
        );
      }
    });
  });
}
