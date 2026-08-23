// Unit tests for [PlaygroundIndex] (Plan 3 §22.1): one traversal produces
// availability AND counts that agree with the assembler's per-mode logic,
// and dedup keeps repeated authored questions out of every count.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/playground/playground_assembler.dart';
import 'package:turna/application/playground/playground_content_source.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/application/playground/playground_index.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';

Lesson _lesson(String id, List<Interaction> items) => Lesson(
      id: id,
      name: 'Lesson $id',
      template: LessonTemplate.legacy,
      content: LessonContent(
        stages: [Stage(id: 's-$id', name: 'Stage', items: items)],
      ),
    );

Section _section(String id, {List<Unit> units = const []}) =>
    Section(id: id, name: 'Section $id', units: units);

Unit _unit(String id, List<Lesson> lessons) =>
    Unit(id: id, name: 'Unit $id', lessons: lessons);

const _mcq = Interaction.multipleChoice(
  prompt: 'p',
  options: ['a', 'b'],
  correctIndex: 0,
);
const _fill = Interaction.fillBlank(sentence: '___', answer: 'a');

void main() {
  test('single-pass counts equal the assembler per-mode dedupe counts', () {
    final sections = [
      _section('s1', units: [
        _unit('u1', [
          _lesson('l1', const [_mcq, _mcq, _fill]), // _mcq duplicated by id
          _lesson('l2', const [_fill]),
        ]),
      ]),
    ];
    final bundle = PlaygroundContentSource.collectFromSections(sections);

    final index = PlaygroundIndex.build(bundle);

    // Availability agrees with the assembler.
    expect(index.availableModes, PlaygroundAssembler.availableModes(bundle));

    // Counts agree with per-mode where+dedupe.
    for (final mode in [
      PlaygroundMode.quickChoice,
      PlaygroundMode.fillBlank,
      PlaygroundMode.smartMix,
      PlaygroundMode.dailyMix,
    ]) {
      final perMode = PlaygroundAssembler.dedupeCandidates(
        bundle.candidates
            .where(
                (c) => PlaygroundAssembler.matchesMode(mode, c.interaction))
            .toList(growable: false),
      ).length;
      expect(index.counts[mode], perMode, reason: '$mode count mismatch');
    }

    // Duplicated interaction ids count once (dedupe inside the index).
    expect(index.counts[PlaygroundMode.quickChoice], 1);
    // Both _fill instances are const-identical (same authored question) and
    // therefore dedupe to a single candidate.
    expect(index.counts[PlaygroundMode.fillBlank], 1);
    expect(index.candidateCount, 2);
  });

  test('wordMatch availability follows the word-pair minimum', () {
    final bundle = PlaygroundContentBundle(
      candidates: const [],
      wordIds: {'w1', 'w2', 'w3'},
      failedSectionIds: const {},
      resolvedScope: PlaygroundContentScope.recent,
    );
    expect(PlaygroundIndex.build(bundle).availableModes,
        isNot(contains(PlaygroundMode.wordMatch)));

    final enough = PlaygroundContentBundle(
      candidates: const [],
      wordIds: {'w1', 'w2', 'w3', 'w4', 'w5'},
      failedSectionIds: const {},
      resolvedScope: PlaygroundContentScope.recent,
    );
    final index = PlaygroundIndex.build(enough);
    expect(index.availableModes, contains(PlaygroundMode.wordMatch));
    expect(index.counts[PlaygroundMode.wordMatch], 5);
  });

  test('empty bundle yields no available modes and zero counts', () {
    final index =
        PlaygroundIndex.build(const PlaygroundContentBundle(
            candidates: [],
            wordIds: {},
            failedSectionIds: {},
            resolvedScope: PlaygroundContentScope.recent));
    expect(index.availableModes, isEmpty);
    expect(index.candidateCount, 0);
    expect(index.counts[PlaygroundMode.wordMatch] ?? 0, 0);
  });
}
