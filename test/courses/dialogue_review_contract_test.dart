import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/review_policy.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';

Lesson _reviewLesson({ReviewPolicy? policy, LessonTemplate? template}) {
  return Lesson(
    id: 'review',
    name: 'Review',
    type: LessonType.review,
    template: template ?? LessonTemplate.review,
    content: LessonContent(
      reviewPolicy: policy,
      stages: [
        Stage(
          id: 'pool',
          name: 'Pool',
          items: [
            const Interaction.multipleChoice(
              id: 'q1',
              prompt: 'Question',
              options: ['A', 'B'],
              correctIndex: 0,
            ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  group('bundled dialogue lesson', () {
    test('real section JSON parses and passes the full validator', () {
      final section = parseSection(
        File('assets/courses/nouveau-turkish/sections/section1.json')
            .readAsStringSync(),
      );
      final lesson = section.units.single.lessons.firstWhere(
        (lesson) => lesson.id == 'nt-u1-l2-dialogue',
      );
      final scene = lesson.content.dialogueScene;
      expect(lesson.type, LessonType.dialogue);
      expect(lesson.template, LessonTemplate.dialogue);
      expect(scene, isNotNull);
      expect(scene!.turns, hasLength(7));
      expect(lesson.flattenedStages.single.items, hasLength(4));

      final wire =
          jsonDecode(jsonEncode(lesson.toJson())) as Map<String, dynamic>;
      final roundTrip = Lesson.fromJson(wire);
      expect(roundTrip.content.dialogueScene, scene);
      expect(
        () => validateCourse(
          [section],
          parseVocabulary(
            File('assets/courses/nouveau-turkish/vocab.json')
                .readAsStringSync(),
          ),
          parseExpressions(
            File('assets/courses/nouveau-turkish/expressions.json')
                .readAsStringSync(),
          ),
          parseGrammarPoints(
            File('assets/courses/nouveau-turkish/grammar_points.json')
                .readAsStringSync(),
          ),
        ),
        returnsNormally,
      );
    });

    test('a turn with an unknown speaker is rejected', () {
      final section = parseSection(
        File('assets/courses/nouveau-turkish/sections/section1.json')
            .readAsStringSync(),
      );
      final lesson = section.units.single.lessons.firstWhere(
        (lesson) => lesson.id == 'nt-u1-l2-dialogue',
      );
      final scene = lesson.content.dialogueScene!;
      final turns = scene.turns.toList();
      turns[0] = turns[0].copyWith(speakerId: 'missing');
      final broken = lesson.copyWith(
        content: lesson.content.copyWith(
          dialogueScene: scene.copyWith(turns: turns),
        ),
      );
      final brokenSection = section.copyWith(
        units: [
          section.units.single.copyWith(lessons: [broken]),
        ],
      );
      expect(
        () => validateCourse(
          [brokenSection],
          parseVocabulary(
            File('assets/courses/nouveau-turkish/vocab.json')
                .readAsStringSync(),
          ),
        ),
        throwsA(isA<CourseValidationException>()),
      );
    });
  });

  group('first complete unit candidate', () {
    test('real content has the intended recipe and metadata', () {
      final section = parseSection(
        File('assets/courses/nouveau-turkish/sections/section1.json')
            .readAsStringSync(),
      );
      final lessons = section.units.single.lessons;
      final playableNodes = lessons.fold<int>(
        0,
        (total, lesson) =>
            total +
            (lesson.content.subLessons.isEmpty
                ? 1
                : lesson.content.subLessons.length),
      );
      expect(lessons, hasLength(24));
      expect(playableNodes, 27);

      final l2 = lessons.firstWhere((lesson) => lesson.id == 'nt-u1-l3-order');
      expect(
        l2.content.subLessons.map(
          (sub) =>
              sub.stages.fold<int>(0, (n, stage) => n + stage.items.length),
        ),
        [12, 12],
      );
      final review = lessons.firstWhere(
        (lesson) => lesson.id == 'nt-u1-review-random',
      );
      expect(review.content.reviewPolicy?.minItems, 15);
      expect(review.content.reviewPolicy?.maxItems, 16);
      expect(review.content.stages.single.items, hasLength(18));

      final reading = lessons.firstWhere(
        (lesson) => lesson.id == 'nt-u1-read-1',
      );
      expect(
        reading.content.readingPassage?.wordFormMap['evde'],
        'nt-w-ev',
      );
      expect(reading.content.readingPassage?.imageAlt, isNotEmpty);

      final vocab = parseVocabulary(
        File('assets/courses/nouveau-turkish/vocab.json').readAsStringSync(),
      );
      expect(vocab, hasLength(17));
      expect(vocab.every((word) => word.level == 'A1'), isTrue);
      expect(
        vocab.every((word) => word.introducedInLessonId?.isNotEmpty == true),
        isTrue,
      );
      expect(
        vocab.firstWhere((word) => word.id == 'nt-w-cay').learningGoal,
        'production',
      );
    });
  });

  group('reviewPolicy validation', () {
    test('accepts a bounded gradable pool', () {
      expect(
        () => validateCourse(
          [
            SectionFactory.sectionWith(_reviewLesson(
              policy: const ReviewPolicy(minItems: 1, maxItems: 1),
            )),
          ],
          const [],
        ),
        returnsNormally,
      );
    });

    test('rejects a sample larger than the pool', () {
      expect(
        () => validateCourse(
          [
            SectionFactory.sectionWith(_reviewLesson(
              policy: const ReviewPolicy(minItems: 1, maxItems: 2),
            )),
          ],
          const [],
        ),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('rejects policy on a non-review template', () {
      expect(
        () => validateCourse(
          [
            SectionFactory.sectionWith(_reviewLesson(
              template: LessonTemplate.legacy,
              policy: const ReviewPolicy(minItems: 1, maxItems: 1),
            )),
          ],
          const [],
        ),
        throwsA(isA<CourseValidationException>()),
      );
    });
  });
}

abstract final class SectionFactory {
  static Section sectionWith(Lesson lesson) {
    return Section(
      id: 'section',
      name: 'Section',
      units: [
        Unit(id: 'unit', name: 'Unit', lessons: [lesson]),
      ],
    );
  }
}
