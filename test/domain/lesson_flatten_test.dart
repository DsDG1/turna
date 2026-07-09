// Unit tests for [Lesson.flattenedStages] across all lesson templates.

import 'package:flutter_test/flutter_test.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/lesson_content.dart';
import 'package:words625/domain/course/listening_phase.dart';
import 'package:words625/domain/course/stage.dart';
import 'package:words625/domain/course/sub_lesson.dart';

void main() {
  const stageA = Stage(
    id: 'stage-a',
    name: 'Stage A',
    items: [],
  );
  const stageB = Stage(
    id: 'stage-b',
    name: 'Stage B',
    items: [],
  );

  group('Lesson.flattenedStages', () {
    test('legacy returns content.stages unchanged', () {
      final lesson = Lesson(
        id: 'l-legacy',
        name: 'Legacy',
        template: LessonTemplate.legacy,
        content: const LessonContent(stages: [stageA, stageB]),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 2);
      expect(flat[0].id, 'stage-a');
      expect(flat[1].id, 'stage-b');
    });

    test('review returns content.stages unchanged', () {
      final lesson = Lesson(
        id: 'l-review',
        name: 'Review',
        template: LessonTemplate.review,
        content: const LessonContent(stages: [stageA, stageB]),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 2);
      expect(flat.map((s) => s.id), ['stage-a', 'stage-b']);
    });

    test('mastery returns content.stages unchanged', () {
      final lesson = Lesson(
        id: 'l-mastery',
        name: 'Mastery',
        template: LessonTemplate.mastery,
        content: const LessonContent(stages: [stageA, stageB]),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 2);
      expect(flat.map((s) => s.id), ['stage-a', 'stage-b']);
    });

    test('reading returns content.stages unchanged', () {
      final lesson = Lesson(
        id: 'l-reading',
        name: 'Reading',
        template: LessonTemplate.reading,
        content: const LessonContent(stages: [stageA, stageB]),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 2);
      expect(flat.map((s) => s.id), ['stage-a', 'stage-b']);
    });

    test('intro flattens sub-lessons with prefixed stage ids', () {
      final lesson = Lesson(
        id: 'l-intro',
        name: 'Intro',
        template: LessonTemplate.intro,
        content: LessonContent(
          subLessons: [
            const SubLesson(
              id: 'sub-1',
              name: 'Sub 1',
              stages: [stageA],
            ),
            const SubLesson(
              id: 'sub-2',
              name: 'Sub 2',
              stages: [stageB],
            ),
          ],
        ),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 2);
      expect(flat[0].id, 'sub-sub-1-stage-a');
      expect(flat[0].name, 'Sub 1 > Stage A');
      expect(flat[1].id, 'sub-sub-2-stage-b');
      expect(flat[1].name, 'Sub 2 > Stage B');
    });

    test('practice flattens sub-lessons with prefixed stage ids', () {
      final lesson = Lesson(
        id: 'l-practice',
        name: 'Practice',
        template: LessonTemplate.practice,
        content: LessonContent(
          subLessons: [
            const SubLesson(
              id: 'sub-1',
              name: 'Sub 1',
              stages: [stageA],
            ),
          ],
        ),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 1);
      expect(flat.single.id, 'sub-sub-1-stage-a');
    });

    test('listening flattens phases into stages', () {
      final lesson = Lesson(
        id: 'l-listening',
        name: 'Listening',
        template: LessonTemplate.listening,
        content: LessonContent(
          listeningPhases: [
            const ListeningPhase(
              id: 'lp-1',
              name: 'Word Pairing',
              type: ListeningPhaseType.wordPairing,
              items: [
                Interaction.multipleChoice(
                  id: 'mcq-1',
                  prompt: 'Pick',
                  options: ['A', 'B'],
                  correctIndex: 0,
                ),
              ],
            ),
            const ListeningPhase(
              id: 'lp-2',
              name: 'Summary',
              type: ListeningPhaseType.summary,
              transcript: 'Hello world.',
            ),
          ],
        ),
      );

      final flat = lesson.flattenedStages;
      expect(flat.length, 2);

      // Word-pairing phase keeps its items.
      expect(flat[0].id, 'lp-lp-1');
      expect(flat[0].items.length, 1);
      expect(flat[0].items.first, isA<MultipleChoice>());

      // Summary phase with no items synthesizes a ListenOnly.
      expect(flat[1].id, 'lp-lp-2');
      expect(flat[1].items.length, 1);
      expect(flat[1].items.first, isA<ListenOnly>());
      final listenOnly = flat[1].items.first as ListenOnly;
      expect(listenOnly.transcript, 'Hello world.');
    });
  });
}
