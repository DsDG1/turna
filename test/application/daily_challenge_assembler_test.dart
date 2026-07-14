// Unit tests for [DailyChallengeAssembler]: pool collection filters out
// non-gradable interactions, sampling is without replacement and caps at the
// pool size, and the assembled [Lesson] has the right shape.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/daily_challenge_assembler.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/course/unit.dart';

class _StubCourseProvider extends CourseProvider {
  final List<Section> _sections;
  _StubCourseProvider(this._sections);
  @override
  List<Section> get sections => _sections;
}

Lesson _lessonWith(List<Interaction> items) => Lesson(
      id: 'lesson-${items.length}',
      name: 'Lesson',
      template: LessonTemplate.legacy,
      content: LessonContent(
        stages: [Stage(id: 's', name: 'Stage', items: items)],
      ),
    );

Section _sectionWith(List<Lesson> lessons) => Section(
      id: 'sec',
      name: 'Section',
      units: [Unit(id: 'u', name: 'Unit', lessons: lessons)],
    );

void main() {
  group('isChallengeGradable', () {
    test('excludes ShowWord and ListenOnly, keeps the rest', () {
      expect(isChallengeGradable(const Interaction.showWord(wordId: 'w')),
          isFalse);
      expect(isChallengeGradable(const Interaction.listenOnly(transcript: 't')),
          isFalse);
      expect(
        isChallengeGradable(
          const Interaction.multipleChoice(
            prompt: 'p',
            options: ['a', 'b'],
            correctIndex: 0,
          ),
        ),
        isTrue,
      );
      expect(
        isChallengeGradable(
          const Interaction.fillBlank(sentence: '___', answer: 'a'),
        ),
        isTrue,
      );
    });
  });

  group('pickChallengeItems', () {
    test('returns count items without replacement', () {
      final pool = [
        for (var i = 0; i < 20; i++)
          Interaction.multipleChoice(
            id: 'q$i',
            prompt: 'p$i',
            options: const ['a', 'b'],
            correctIndex: 0,
          ),
      ];
      final picked = pickChallengeItems(pool, 15, Random(42));
      expect(picked, hasLength(15));
      final ids = picked.map((e) => e.id).toSet();
      expect(ids, hasLength(15)); // no duplicates
    });

    test('returns all (shuffled) when pool smaller than count', () {
      final pool = [
        for (var i = 0; i < 5; i++)
          Interaction.multipleChoice(
            id: 'q$i',
            prompt: 'p$i',
            options: const ['a', 'b'],
            correctIndex: 0,
          ),
      ];
      final picked = pickChallengeItems(pool, 15, Random(1));
      expect(picked, hasLength(5));
      expect(picked.map((e) => e.id).toSet(), hasLength(5));
    });

    test('empty pool or non-positive count yields empty', () {
      expect(pickChallengeItems(const [], 15, Random(0)), isEmpty);
      expect(pickChallengeItems(
        [const Interaction.fillBlank(sentence: 's', answer: 'a')],
        0,
        Random(0),
      ), isEmpty);
    });
  });

  group('DailyChallengeAssembler.assemble', () {
    test('collects only gradable items and caps at 15', () {
      final gradable = [
        for (var i = 0; i < 20; i++)
          Interaction.multipleChoice(
            id: 'mcq-$i',
            prompt: 'p$i',
            options: const ['a', 'b'],
            correctIndex: 0,
          ),
      ];
      final nonGradable = [
        const Interaction.showWord(wordId: 'w1'),
        const Interaction.listenOnly(transcript: 't1'),
      ];
      final section = _sectionWith([
        _lessonWith([...gradable, ...nonGradable]),
      ]);
      final assembler = DailyChallengeAssembler(_StubCourseProvider([section]));

      final lesson = assembler.assemble(count: 15, random: Random(7));

      expect(lesson.id, DailyChallengeAssembler.lessonId);
      expect(lesson.type, LessonType.challenge);
      expect(lesson.template, LessonTemplate.legacy);
      final items = lesson.flattenedStages.single.items;
      expect(items, hasLength(15));
      // None of the picked items are the non-gradable originals.
      expect(items.whereType<ShowWord>(), isEmpty);
      expect(items.whereType<ListenOnly>(), isEmpty);
    });

    test('stamps each item with a unique stable id', () {
      final pool = [
        for (var i = 0; i < 18; i++)
          Interaction.multipleChoice(
            id: '',
            prompt: 'p$i',
            options: const ['a', 'b'],
            correctIndex: 0,
          ),
      ];
      final section = _sectionWith([_lessonWith(pool)]);
      final assembler = DailyChallengeAssembler(_StubCourseProvider([section]));

      final lesson = assembler.assemble(count: 15, random: Random(3));
      final items = lesson.flattenedStages.single.items;
      final ids = items.map((e) => e.id).toList();
      expect(ids, hasLength(15));
      expect(ids.toSet(), hasLength(15)); // all unique
      for (var i = 0; i < ids.length; i++) {
        expect(ids[i], 'challenge-$i');
      }
    });

    test('returns everything when fewer than 15 gradable exist', () {
      final pool = [
        const Interaction.fillBlank(id: 'f1', sentence: '___', answer: 'a'),
        const Interaction.fillBlank(id: 'f2', sentence: '___', answer: 'b'),
        const Interaction.showWord(wordId: 'w'), // filtered out
      ];
      final section = _sectionWith([_lessonWith(pool)]);
      final assembler = DailyChallengeAssembler(_StubCourseProvider([section]));

      final lesson = assembler.assemble(count: 15, random: Random(0));
      expect(lesson.flattenedStages.single.items, hasLength(2));
    });

    test('empty course yields an empty challenge', () {
      final assembler =
          DailyChallengeAssembler(_StubCourseProvider(const []));
      final lesson = assembler.assemble(count: 15, random: Random(0));
      expect(lesson.type, LessonType.challenge);
      expect(lesson.flattenedStages.single.items, isEmpty);
    });
  });
}