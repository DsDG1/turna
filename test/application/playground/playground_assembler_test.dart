// Unit tests for [PlaygroundContentSource] + [PlaygroundAssembler]:
// the Playground data pipeline must read the current language course only
// (计划 §6.2 三层隔离的第三层), behave deterministically under a fixed seed,
// and surface explanatory unavailable reasons instead of empty lessons.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/playground/playground_assembler.dart';
import 'package:turna/application/playground/playground_content_source.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';

/// Scope/section stub — overrides the read surface [PlaygroundContentSource]
/// touches so no DB path runs.
class _StubCourseProvider extends CourseProvider {
  _StubCourseProvider({
    String scopeWire = '',
    CourseScope? typedScope,
    this.sectionList = const [],
    this.allList,
    this.unit,
    this.failingSectionIds = const {},
  })  : _scopeWire = scopeWire,
        _typedScope = typedScope;

  final String _scopeWire;
  final CourseScope? _typedScope;

  /// The courseScope-filtered view — what Playground must read.
  final List<Section> sectionList;

  /// Optional different unfiltered view (all courses) to pin that the
  /// pipeline never falls back to [CourseProvider.allSections].
  final List<Section>? allList;
  final Unit? unit;
  final Set<String> failingSectionIds;

  @override
  String get courseScope => _scopeWire;

  @override
  CourseScope get scope =>
      _typedScope ??
      const BuiltinCourseScope('turkish');

  /// Scope view with failed sections shown as shells (empty units), the way
  /// an unloaded/erroring section really looks until its body loads.
  @override
  List<Section> get sections => [
        for (final s in sectionList)
          failingSectionIds.contains(s.id)
              ? _section(s.id, level: s.level)
              : s,
      ];

  @override
  List<Section> get allSections => allList ?? sectionList;

  @override
  String? get currentSectionId =>
      sectionList.isEmpty ? null : sectionList.first.id;

  @override
  Section? get currentSection {
    final id = currentSectionId;
    for (final s in sectionList) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Unit? get currentUnit => unit;

  @override
  Future<void> ensureSectionLoaded(String id) async {}

  @override
  SectionLoadState sectionLoadState(String id) =>
      failingSectionIds.contains(id)
          ? SectionLoadState.error
          : SectionLoadState.loaded;
}

Lesson _lesson(String id, List<Interaction> items) => Lesson(
      id: id,
      name: 'Lesson $id',
      template: LessonTemplate.legacy,
      content: LessonContent(
        stages: [Stage(id: 's-$id', name: 'Stage', items: items)],
      ),
    );

Section _section(
  String id, {
  String? level,
  List<Unit> units = const [],
}) =>
    Section(id: id, name: 'Section $id', level: level, units: units);

Unit _unit(String id, List<Lesson> lessons) =>
    Unit(id: id, name: 'Unit $id', lessons: lessons);

const _mcq = Interaction.multipleChoice(
  prompt: 'p',
  options: ['a', 'b'],
  correctIndex: 0,
);
const _fill = Interaction.fillBlank(sentence: '___', answer: 'a');

void main() {
  group('PlaygroundContentSource.collectFromSections', () {
    test('rejects Anki and OfficialAnki level sections', () {
      final language = _section('sec-lang',
          units: [_unit('u1', [_lesson('l1', const [_mcq])])]);
      final legacyAnki = _section('anki-k-s1',
          level: 'Anki',
          units: [_unit('u2', [_lesson('l2', const [_mcq])])]);
      final officialAnki = _section('official-anki-k-s1',
          level: 'OfficialAnki',
          units: [_unit('u3', [_lesson('l3', const [_mcq])])]);

      final bundle = PlaygroundContentSource.collectFromSections(
        [language, legacyAnki, officialAnki],
      );

      expect(bundle.candidates, hasLength(1));
      expect(bundle.candidates.single.lessonId, 'l1');
    });

    test('AnkiCard and AnkiHtmlCard never enter the pool', () {
      const items = [
        _mcq,
        Interaction.ankiCard(front: 'f', back: 'b'),
        Interaction.ankiHtmlCard(frontHtml: '<p>f</p>', backHtml: '<p>b</p>'),
      ];
      final bundle = PlaygroundContentSource.collectFromSections(
        [_section('sec', units: [_unit('u', [_lesson('l', items)])])],
      );

      expect(bundle.candidates, hasLength(1));
      expect(bundle.candidates.single.interaction, isA<MultipleChoice>());
    });

    test('collects ShowWord word ids for the match word-pair source', () {
      final bundle = PlaygroundContentSource.collectFromSections(
        [_section(
          'sec',
          units: [
            _unit('u', [
              _lesson('l', const [
                Interaction.showWord(id: 'sw1', wordId: 'w-merhaba'),
                Interaction.showWord(id: 'sw2', wordId: 'w-ev'),
                Interaction.showWord(id: 'sw3', wordId: 'w-merhaba'), // dup
                Interaction.showWord(id: 'sw4', wordId: ''), // skipped
                _mcq,
              ]),
            ]),
          ],
        )],
      );

      expect(bundle.wordIds, {'w-merhaba', 'w-ev'});
      expect(bundle.candidates, hasLength(5));
    });

    test('unit filter restricts the scan to one unit', () {
      final section = _section('sec', units: [
        _unit('u1', [_lesson('l1', const [_mcq])]),
        _unit('u2', [_lesson('l2', const [_fill])]),
      ]);

      final bundle = PlaygroundContentSource.collectFromSections(
        [section],
        unitId: 'u2',
      );

      expect(bundle.candidates.map((c) => c.lessonId), ['l2']);
    });
  });

  group('PlaygroundAssembler.assemble', () {
    test('rejects an Anki course scope with ineligibleCourse', () async {
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(
          scopeWire: 'anki:deck1',
          sectionList: [
            _section('anki-deck1-s1',
                level: 'Anki',
                units: [_unit('u', [_lesson('l', const [_mcq])])]),
          ],
        ),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(mode: PlaygroundMode.smartMix),
        courseScope: 'anki:deck1',
        random: Random(1),
      );

      expect(
        result,
        isA<PlaygroundUnavailable>().having(
          (u) => u.reason,
          'reason',
          PlaygroundUnavailableReason.ineligibleCourse,
        ),
      );
    });

    test('whole-course scope filters Anki sections out of the scope view',
        () async {
      final provider = _StubCourseProvider(sectionList: [
        _section('lang-s1',
            units: [_unit('u', [_lesson('l1', const [_mcq])])]),
        _section('anki-other-s1',
            level: 'Anki',
            units: [_unit('u', [_lesson('l2', const [_fill])])]),
      ]);
      final assembler = PlaygroundAssembler.forCourseProvider(provider);

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(
          mode: PlaygroundMode.smartMix,
          contentScope: PlaygroundContentScope.wholeCourse,
          targetQuestionCount: 10,
        ),
        courseScope: '',
        random: Random(1),
      );

      final ready = result as PlaygroundReady;
      expect(ready.metadata.questionCount, 1);
      expect(ready.metadata.sourceLessonIds, {'l1'});
    });

    test('whole-course scope reads sections(), never allSections', () async {
      final provider = _StubCourseProvider(
        sectionList: [
          _section('lang-s1',
              units: [_unit('u', [_lesson('l1', const [_mcq])])]),
        ],
        allList: [
          _section('lang-s1',
              units: [_unit('u', [_lesson('l1', const [_mcq])])]),
          // Another course's language-looking section, visible only through
          // allSections — must never leak into the pool.
          _section('other-course-s1',
              units: [_unit('u', [_lesson('l2', const [_fill])])]),
        ],
      );
      final bundle = await PlaygroundContentSource(provider)
          .load(PlaygroundContentScope.wholeCourse);

      expect(bundle.candidates.map((c) => c.lessonId), ['l1']);
    });

    test('all sections failing to load surfaces sectionLoadFailed', () async {
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(
          sectionList: [
            _section('s1', units: [_unit('u', [_lesson('l', const [_mcq])])]),
          ],
          failingSectionIds: {'s1'},
        ),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(
          mode: PlaygroundMode.smartMix,
          contentScope: PlaygroundContentScope.wholeCourse,
        ),
        courseScope: '',
        random: Random(1),
      );

      expect(
        (result as PlaygroundUnavailable).reason,
        PlaygroundUnavailableReason.sectionLoadFailed,
      );
    });

    test('current-unit scope surfaces sectionLoadFailed when the body fails '
        'to load', () async {
      // 失败的 Section 保留壳（currentSection 非 null、units 为空），必须
      // 经由 load state 检测，而不是把空内容误报为 noCourseContent。
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(
          sectionList: [
            _section('s1', units: [_unit('u', [_lesson('l', const [_mcq])])]),
          ],
          failingSectionIds: {'s1'},
        ),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(
          mode: PlaygroundMode.smartMix,
          contentScope: PlaygroundContentScope.currentUnit,
        ),
        courseScope: '',
        random: Random(1),
      );

      expect(
        (result as PlaygroundUnavailable).reason,
        PlaygroundUnavailableReason.sectionLoadFailed,
      );
    });

    test('empty content yields noCourseContent, not an empty lesson',
        () async {
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(
          sectionList: [_section('s1', units: [_unit('u', [_lesson('l', const [])])])],
        ),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(mode: PlaygroundMode.smartMix),
        courseScope: '',
        random: Random(1),
      );

      expect(
        (result as PlaygroundUnavailable).reason,
        PlaygroundUnavailableReason.noCourseContent,
      );
    });

    test('content without matching mode yields noItemsForMode plus alternatives',
        () async {
      // Pool has only a listening item; a dictation session cannot run.
      const listen = Interaction.listenAndPick(
        audioAsset: 'a.mp3',
        prompt: 'p',
        options: ['a', 'b'],
        correctIndex: 0,
      );
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(
          sectionList: [
            _section('s1', units: [_unit('u', [_lesson('l', const [listen])])]),
          ],
        ),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(mode: PlaygroundMode.dictation),
        courseScope: '',
        random: Random(1),
      );

      final unavailable = result as PlaygroundUnavailable;
      expect(unavailable.reason, PlaygroundUnavailableReason.noItemsForMode);
      expect(
        unavailable.availableAlternatives,
        containsAll([
          PlaygroundMode.smartMix,
          PlaygroundMode.listenAndPick,
          PlaygroundMode.dailyMix,
        ]),
      );
      expect(unavailable.availableAlternatives, isNot(contains(PlaygroundMode.dictation)));
    });

    test('mode → interaction mapping', () {
      bool matches(PlaygroundMode m, Interaction i) =>
          PlaygroundAssembler.matchesMode(m, i);

      expect(matches(PlaygroundMode.quickChoice, _mcq), isTrue);
      expect(
        matches(
          PlaygroundMode.quickChoice,
          const Interaction.readingMcq(
            prompt: 'p',
            options: ['a'],
            correctIndex: 0,
          ),
        ),
        isTrue,
      );
      expect(
        matches(PlaygroundMode.listenAndPick,
            const Interaction.listenAndPick(
          audioAsset: 'a',
          prompt: 'p',
          options: ['a'],
          correctIndex: 0,
        )),
        isTrue,
      );
      expect(
        matches(PlaygroundMode.dictation,
            const Interaction.typeTheWord(
          audioAsset: 'a',
          prompt: 'p',
          expected: 'e',
        )),
        isTrue,
      );
      expect(
        matches(PlaygroundMode.sentenceOrder,
            const Interaction.reorderSentence(
          scrambled: ['b', 'a'],
          correct: ['a', 'b'],
        )),
        isTrue,
      );
      expect(matches(PlaygroundMode.fillBlank, _fill), isTrue);
      expect(
        matches(
          PlaygroundMode.translation,
          const Interaction.translateSentence(
            source: 's',
            expected: 'e',
          ),
        ),
        isTrue,
      );
      // Smart mix pools every gradable item but not display/listen-only.
      expect(matches(PlaygroundMode.smartMix, _mcq), isTrue);
      expect(
        matches(PlaygroundMode.smartMix,
            const Interaction.showWord(wordId: 'w')),
        isFalse,
      );
      expect(
        matches(PlaygroundMode.smartMix,
            const Interaction.listenOnly(transcript: 't')),
        isFalse,
      );
      // Anki cards never match any mode even if a caller smuggles one in.
      expect(
        matches(
          PlaygroundMode.smartMix,
          const Interaction.ankiCard(front: 'f', back: 'b'),
        ),
        isFalse,
      );
      expect(
        matches(
          PlaygroundMode.quickChoice,
          const Interaction.ankiHtmlCard(
            frontHtml: 'f',
            backHtml: 'b',
          ),
        ),
        isFalse,
      );
    });

    test('dedupe drops repeated authored questions within a session', () {
      final candidates = [
        const PlaygroundInteractionCandidate(
          interaction: Interaction.multipleChoice(
            id: 'q1',
            prompt: 'p',
            options: ['a', 'b'],
            correctIndex: 0,
          ),
          lessonId: 'l1',
        ),
        const PlaygroundInteractionCandidate(
          interaction: Interaction.multipleChoice(
            id: 'q1', // same lesson + id → duplicate
            prompt: 'p',
            options: ['a', 'b'],
            correctIndex: 0,
          ),
          lessonId: 'l1',
        ),
        const PlaygroundInteractionCandidate(
          interaction: Interaction.multipleChoice(
            id: 'q1', // same id, different lesson → distinct
            prompt: 'p',
            options: ['a', 'b'],
            correctIndex: 0,
          ),
          lessonId: 'l2',
        ),
      ];

      final deduped = PlaygroundAssembler.dedupeCandidates(candidates);
      expect(deduped, hasLength(2));
      expect(deduped.map((c) => c.lessonId), ['l1', 'l2']);
    });

    test('same seed is stable, different seed may vary', () async {
      final section = _section('s1', units: [
        _unit('u', [
          _lesson('l', [
            for (var i = 0; i < 12; i++)
              Interaction.multipleChoice(
                id: 'q$i',
                prompt: 'p$i',
                options: const ['a', 'b'],
                correctIndex: 0,
              ),
          ]),
        ]),
      ]);
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(sectionList: [section]),
      );
      const config = PlaygroundSessionConfig(
        mode: PlaygroundMode.quickChoice,
        targetQuestionCount: 5,
      );

      Future<List<String>> run(int seed) async {
        final result = await assembler.assemble(
          config,
          courseScope: '',
          random: Random(seed),
        );
        final ready = result as PlaygroundReady;
        // Items are re-stamped with per-position ids, so compare the
        // content-bearing prompt to observe the actual selection.
        return ready.lesson.flattenedStages.single.items
            .map((i) => (i as MultipleChoice).prompt)
            .toList();
      }

      final a = await run(42);
      final b = await run(42);
      final c = await run(7);

      expect(a, b); // deterministic under a fixed seed
      expect(a, hasLength(5)); // trimmed to targetQuestionCount
      // Different seed produces a different selection for this pool size.
      expect(a, isNot(c));
    });

    test('wordMatch needs at least 4 word ids, then exposes them', () async {
      Future<Object> assemble(List<Interaction> items) async {
        final assembler = PlaygroundAssembler.forCourseProvider(
          _StubCourseProvider(
            sectionList: [
              _section('s1', units: [_unit('u', [_lesson('l', items)])]),
            ],
          ),
        );
        return await assembler.assemble(
          const PlaygroundSessionConfig(mode: PlaygroundMode.wordMatch),
          courseScope: '',
          random: Random(1),
        );
      }

      final tooFew = await assemble(const [
        Interaction.showWord(id: 'a', wordId: 'w1'),
        Interaction.showWord(id: 'b', wordId: 'w2'),
        Interaction.showWord(id: 'c', wordId: 'w3'),
        _mcq,
      ]);
      expect(
        (tooFew as PlaygroundUnavailable).reason,
        PlaygroundUnavailableReason.noItemsForMode,
      );

      final enough = await assemble(const [
        Interaction.showWord(id: 'a', wordId: 'w1'),
        Interaction.showWord(id: 'b', wordId: 'w2'),
        Interaction.showWord(id: 'c', wordId: 'w3'),
        Interaction.showWord(id: 'd', wordId: 'w4'),
      ]);
      final ready = enough as PlaygroundReady;
      expect(ready.wordIds, hasLength(4));
      expect(ready.metadata.questionCount, 4);
    });

    test('weak scope re-filters Anki snapshots from mistake entries',
        () async {
      const ankiSnapshot = Interaction.ankiCard(
        front: 'f',
        back: 'b',
      );
      final entries = [
        MistakeEntry(
          id: 'm1',
          lessonId: 'l1',
          stageId: 's',
          interactionId: 'i1',
          timestamp: DateTime(2026, 8, 22),
          interactionSnapshot: ankiSnapshot, // must be rejected
        ),
        MistakeEntry(
          id: 'm2',
          lessonId: 'l1',
          stageId: 's',
          interactionId: 'i2',
          timestamp: DateTime(2026, 8, 22),
          wordId: 'w1',
          interactionSnapshot: _mcq,
        ),
      ];
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(
          mode: PlaygroundMode.smartMix,
          contentScope: PlaygroundContentScope.weak,
        ),
        courseScope: '',
        random: Random(1),
        weakEntries: entries,
      );

      final ready = result as PlaygroundReady;
      expect(ready.metadata.questionCount, 1);
      expect(ready.lesson.flattenedStages.single.items.single, isA<MultipleChoice>());
    });

    test('current-unit scope only scans the selected unit', () async {
      final provider = _StubCourseProvider(
        sectionList: [
          _section('s1', units: [
            _unit('u1', [_lesson('l1', const [_mcq])]),
            _unit('u2', [_lesson('l2', const [_fill])]),
          ]),
        ],
        unit: _unit('u1', [_lesson('l1', const [_mcq])]),
      );
      final assembler = PlaygroundAssembler.forCourseProvider(provider);

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(
          mode: PlaygroundMode.smartMix,
          contentScope: PlaygroundContentScope.currentUnit,
        ),
        courseScope: '',
        random: Random(1),
      );

      final ready = result as PlaygroundReady;
      expect(ready.metadata.sourceLessonIds, {'l1'});
    });

    test('assembled lesson carries the synthetic playground identity',
        () async {
      final assembler = PlaygroundAssembler.forCourseProvider(
        _StubCourseProvider(
          sectionList: [
            _section('s1', units: [_unit('u', [_lesson('l', const [_mcq, _fill])])]),
          ],
        ),
      );

      final result = await assembler.assemble(
        const PlaygroundSessionConfig(mode: PlaygroundMode.smartMix),
        courseScope: '',
        random: Random(1),
      );

      final ready = result as PlaygroundReady;
      expect(ready.lesson.id, PlaygroundAssembler.lessonId);
      expect(ready.lesson.type, LessonType.challenge);
      final items = ready.lesson.flattenedStages.single.items;
      expect(items.map((i) => i.id), ['pg-0', 'pg-1']);
    });
  });
}
