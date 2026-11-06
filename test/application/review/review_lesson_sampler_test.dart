import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/review/review_lesson_sampler.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/review_policy.dart';
import 'package:turna/domain/course/stage.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

Lesson _lesson(
  List<Interaction> items, {
  ReviewPolicy? policy,
}) {
  return Lesson(
    id: 'review-1',
    name: 'Review',
    type: LessonType.review,
    template: LessonTemplate.review,
    content: LessonContent(
      reviewPolicy: policy,
      stages: [Stage(id: 'pool', name: 'Pool', items: items)],
    ),
  );
}

Interaction _choice(String id) => Interaction.multipleChoice(
      id: id,
      prompt: id,
      options: const ['a', 'b'],
      correctIndex: 0,
    );

Interaction _fill(String id) => Interaction.fillBlank(
      id: id,
      sentence: '$id _____',
      answer: 'a',
    );

MistakeEntry _mistake(Interaction item, int index) => MistakeEntry(
      id: 'm-$index',
      lessonId: 'lesson',
      stageId: 'stage',
      interactionId: item.id,
      interactionSnapshot: item,
      timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
    );

void main() {
  const sampler = ReviewLessonSampler();

  test('leaves a lesson without reviewPolicy identical', () {
    final lesson = _lesson([_choice('a'), _fill('b')]);
    expect(
      identical(sampler.sample(lesson, mistakes: const [], random: Random(1)),
          lesson),
      isTrue,
    );
  });

  test('samples the requested number without replacement and preserves ids',
      () {
    final lesson = _lesson(
      [for (var i = 0; i < 18; i++) _choice('q-$i')],
      policy: const ReviewPolicy(minItems: 15, maxItems: 16),
    );
    final sampled = sampler.sample(
      lesson,
      mistakes: const [],
      random: _FixedRandom(0.2),
    );
    final items = sampled.content.stages.single.items;
    expect(items, hasLength(15));
    expect(items.map((item) => item.id).toSet(), hasLength(15));
    expect(
      items.every((item) => lesson.content.stages.single.items.contains(item)),
      isTrue,
    );
  });

  test('author weights change the selected type deterministically', () {
    final lesson = _lesson(
      [_fill('fill'), _choice('choice')],
      policy: const ReviewPolicy(
        minItems: 1,
        maxItems: 1,
        typeWeights: {'fillBlank': 3},
      ),
    );
    final sampled = sampler.sample(
      lesson,
      mistakes: const [],
      random: _FixedRandom(0.75),
    );
    expect(sampled.content.stages.single.items.single.id, 'fill');
  });

  test('current-course mistake snapshots boost their interaction type', () {
    final lesson = _lesson(
      [_fill('fill'), _choice('choice')],
      policy: const ReviewPolicy(minItems: 1, maxItems: 1),
    );
    final fill = lesson.content.stages.single.items.first;
    final sampled = sampler.sample(
      lesson,
      mistakes: [for (var i = 0; i < 3; i++) _mistake(fill, i)],
      random: _FixedRandom(0.75),
    );
    expect(sampled.content.stages.single.items.single.id, 'fill');
  });

  test('mistake boost is capped', () {
    final lesson = _lesson(
      [_fill('fill'), _choice('choice')],
      policy: const ReviewPolicy(minItems: 1, maxItems: 1),
    );
    final fill = lesson.content.stages.single.items.first;
    List<String> sampleWith(int count) => sampler
        .sample(
          lesson,
          mistakes: [for (var i = 0; i < count; i++) _mistake(fill, i)],
          random: _FixedRandom(0.75),
        )
        .content
        .stages
        .single
        .items
        .map((item) => item.id)
        .toList();
    expect(sampleWith(3), sampleWith(100));
  });
}
