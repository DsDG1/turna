// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

/// Mock repository that captures written sections and vocabulary.
class MockCourseRepository implements ICourseRepository {
  final List<Section> writtenSections = [];
  final List<WordEntry> writtenVocabulary = [];

  @override
  Future<void> bulkInsertCourseTree(Section section) async {
    writtenSections.add(section);
  }

  @override
  Future<void> bulkInsertVocabulary(List<WordEntry> words) async {
    writtenVocabulary.addAll(words);
  }

  @override
  Future<int> deleteByTag(String tag) async => 0;

  @override
  Future<void> deleteSection(String sectionId) async {}

  @override
  Future<void> deleteOfficialProjection(String sourceId) async {}

  @override
  Future<List<Section>> sectionShells() async => [];

  @override
  Future<Section> section(String id) async => throw UnimplementedError();

  @override
  Future<Lesson> lessonById(String id) async => throw UnimplementedError();

  @override
  Future<List<Lesson>> lessonsContainingAny(Iterable<String> needles) async =>
      const [];

  @override
  Future<String?> sectionIdForUnit(String unitId) async => null;

  @override
  Future<String?> sectionIdForLesson(String lessonId) async => null;

  @override
  Future<List<WordEntry>> vocabulary() async => [];

  @override
  Future<List<GrammarPoint>> grammarPoints() async => [];

  @override
  Future<GrammarPoint?> grammarPointById(String id) async => null;

  @override
  Future<List<Expression>> expressions() async => [];

  @override
  Future<Expression?> expressionById(String id) async => null;

  @override
  Future<List<db.AnkiImport>> ankiImports() async => [];
}

void main() {
  group('AnkiDeckAssembler', () {
    late AnkiDeckAssembler assembler;
    late MockCourseRepository repo;

    setUp(() {
      assembler = AnkiDeckAssembler();
      repo = MockCourseRepository();
    });

    AnkiCollection _buildTestCollection({int cardCount = 5}) {
      final notes = <AnkiNote>[];
      final cards = <AnkiCardData>[];

      for (var i = 0; i < cardCount; i++) {
        notes.add(AnkiNote(
          id: 1000 + i,
          mid: 1,
          fields: ['Question $i', 'Answer $i'],
        ));
        cards.add(AnkiCardData(
          id: 2000 + i,
          nid: 1000 + i,
          did: 10,
          queue: 0,
          factor: 2500,
        ));
      }

      return AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Basic',
            fieldNames: ['Front', 'Back'],
            templateNames: ['Card 1'],
          ),
        },
        decks: {
          10: const AnkiDeckInfo(id: 10, name: 'Test Deck', cardCount: 5),
        },
        notes: notes,
        cards: cards,
      );
    }

    test('creates section with level "Anki"', () async {
      final collection = _buildTestCollection(cardCount: 3);

      final summary = await assembler.assemble(
        collection: collection,
        importId: 'test1',
        repo: repo,
      );

      expect(repo.writtenSections.length, 1);
      final section = repo.writtenSections.first;
      expect(section.level, 'Anki');
      expect(section.id, startsWith('anki-test1-'));
      expect(summary.cardCount, 3);
    });

    test('splits cards into lessons of 20', () async {
      final collection = _buildTestCollection(cardCount: 45);

      await assembler.assemble(
        collection: collection,
        importId: 'split',
        repo: repo,
      );

      final section = repo.writtenSections.first;
      final unit = section.units.first;
      // 45 cards / 20 per lesson = 3 lessons (20 + 20 + 5)
      expect(unit.lessons.length, 3);
      expect(unit.lessons[0].flattenedStages.length, 20);
      expect(unit.lessons[1].flattenedStages.length, 20);
      expect(unit.lessons[2].flattenedStages.length, 5);
    });

    test('uses LessonTemplate.legacy', () async {
      final collection = _buildTestCollection(cardCount: 5);

      await assembler.assemble(
        collection: collection,
        importId: 'tmpl',
        repo: repo,
      );

      final section = repo.writtenSections.first;
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          expect(lesson.template, LessonTemplate.legacy);
        }
      }
    });

    test('handles child decks as separate units', () async {
      final collection = AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Basic',
            fieldNames: ['Front', 'Back'],
          ),
        },
        decks: {
          10: const AnkiDeckInfo(id: 10, name: 'Parent'),
          11: const AnkiDeckInfo(id: 11, name: 'Parent::Child1', parentId: 10),
          12: const AnkiDeckInfo(id: 12, name: 'Parent::Child2', parentId: 10),
        },
        notes: [
          const AnkiNote(id: 1, mid: 1, fields: ['Q1', 'A1']),
          const AnkiNote(id: 2, mid: 1, fields: ['Q2', 'A2']),
        ],
        cards: [
          const AnkiCardData(id: 101, nid: 1, did: 11),
          const AnkiCardData(id: 102, nid: 2, did: 12),
        ],
      );

      await assembler.assemble(
        collection: collection,
        importId: 'multi',
        repo: repo,
      );

      final section = repo.writtenSections.first;
      expect(section.units.length, 2);
      expect(section.units[0].name, 'Child1');
      expect(section.units[1].name, 'Child2');
    });

    test(
        'empty Default deck with card-carrying subdecks is kept (no orphaned cards)',
        () async {
      // Regression: an empty Default (id=1) whose subdecks hold cards, alongside
      // another top-level deck, used to be dropped by the top-level filter -
      // orphaning the subdecks' cards and aborting the import via
      // COUNT_RECONCILIATION_FAILED.
      final collection = AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Basic',
            fieldNames: ['Front', 'Back'],
          ),
        },
        decks: {
          1: const AnkiDeckInfo(id: 1, name: 'Default'),
          2: const AnkiDeckInfo(id: 2, name: 'Default::Sub', parentId: 1),
          3: const AnkiDeckInfo(id: 3, name: 'German'),
        },
        notes: [
          const AnkiNote(id: 1, mid: 1, fields: ['Q1', 'A1']),
          const AnkiNote(id: 2, mid: 1, fields: ['Q2', 'A2']),
          const AnkiNote(id: 3, mid: 1, fields: ['Q3', 'A3']),
        ],
        cards: [
          const AnkiCardData(id: 101, nid: 1, did: 2), // Default::Sub
          const AnkiCardData(id: 102, nid: 2, did: 3), // German
          const AnkiCardData(id: 103, nid: 3, did: 3), // German
        ],
      );

      final summary = await assembler.assemble(
        collection: collection,
        importId: 'defaultsub',
        repo: repo,
      );

      // Import succeeds and every card is indexed (reconciliation passes).
      expect(summary.cardCount, 3);
      // Two top-level sections: Default (anchoring its subdeck's card) + German.
      expect(repo.writtenSections.length, 2);
    });

    test('generates AnkiCard interactions for Front/Back fields', () async {
      // 4 cards -> 3 distractors for each (>=2 threshold) so the adapter
      // builds MultipleChoice. A 2-card deck has only 1 distractor and the
      // adapter (correctly) falls back to type-the-answer FillBlank instead of
      // fabricating a fake MCQ (deep-adaptation plan "禁止伪 MCQ" rule).
      final collection = _buildTestCollection(cardCount: 4);

      await assembler.assemble(
        collection: collection,
        importId: 'type',
        repo: repo,
      );

      final section = repo.writtenSections.first;
      final firstStage =
          section.units.first.lessons.first.flattenedStages.first;
      final interaction = firstStage.items.first;

      // Front/Back heuristic → wordEntry → Flip (not sibling-distractor MCQ)
      expect(interaction, isA<AnkiCard>());
    });

    test('mappingOverrides are respected (swapped front/back field indices)',
        () async {
      // The import wizard lets the user override the inferred notetype
      // mapping; the override flows into the assembler via mappingOverrides.
      // Swap the front/back field indices and assert the MultipleChoice
      // prompt follows the override (Front field by default, Back field when
      // swapped). If mappingOverrides were ignored, both prompts would match.
      final collection = _buildTestCollection(cardCount: 4);

      // Default inferred mapping (Front=0/Back=1): front is the Front field.
      await AnkiDeckAssembler().assemble(
        collection: collection,
        importId: 'default',
        repo: repo,
      );
      var face = repo.writtenSections.first.units.first.lessons.first
          .flattenedStages.first.items.first as AnkiCard;
      expect(face.front, 'Question 0');

      // Override: swap front/back indices -> front becomes the Back field.
      repo.writtenSections.clear();
      await AnkiDeckAssembler().assemble(
        collection: collection,
        importId: 'override',
        repo: repo,
        mappingOverrides: {
          1: const NotetypeMapping(
            type: NotetypeMappingType.wordEntry,
            frontFieldIndex: 1,
            backFieldIndex: 0,
          ),
        },
      );
      face = repo.writtenSections.first.units.first.lessons.first.flattenedStages
          .first.items.first as AnkiCard;
      expect(face.front, 'Answer 0');
    });

    test('Lite mode keeps every card in navigable lazy lessons', () async {
      final collection = _buildTestCollection(cardCount: 10);
      await assembler.assemble(
        collection: collection,
        importId: 'lite',
        repo: repo,
        liteThreshold: 5, // force Lite for the 10-card deck
      );
      final section = repo.writtenSections.first;
      expect(section.level, 'Anki');
      expect(section.units, hasLength(1));
      expect(section.units.first.lessons, isNotEmpty);
      final items = section.units.first.lessons
          .expand((lesson) => lesson.flattenedStages)
          .expand((stage) => stage.items)
          .toList();
      expect(items, hasLength(10));
      expect(items, everyElement(isA<AnkiHtmlCard>()));
      expect(
        items.cast<AnkiHtmlCard>(),
        everyElement(
          isA<AnkiHtmlCard>()
              .having((card) => card.frontHtml, 'frontHtml', isEmpty)
              .having((card) => card.backHtml, 'backHtml', isEmpty)
              .having((card) => card.wordId, 'wordId', isNotEmpty),
        ),
      );
    });

    test('all-fidelity deck keeps lazy card references in lessons', () async {
      // A notetype whose templates contain <script> routes every card to
      // fidelity (policy rule 1). Rendering is lazy, but navigation and
      // card-count reconciliation must remain complete.
      final collection = AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Encrypted',
            fieldNames: ['Front', 'Back'],
            templates: [
              AnkiTemplate(
                  name: 'C',
                  qfmt: '{{Front}}<script>decrypt()</script>',
                  afmt: '{{Back}}'),
            ],
          ),
        },
        decks: {10: const AnkiDeckInfo(id: 10, name: 'Enc', cardCount: 2)},
        notes: [
          AnkiNote(id: 1, mid: 1, fields: const ['q1', 'a1']),
          AnkiNote(id: 2, mid: 1, fields: const ['q2', 'a2']),
        ],
        cards: [
          AnkiCardData(id: 100, nid: 1, did: 10, queue: 0),
          AnkiCardData(id: 101, nid: 2, did: 10, queue: 0),
        ],
      );
      await assembler.assemble(
          collection: collection, importId: 'enc', repo: repo);
      final section = repo.writtenSections.first;
      expect(section.level, 'Anki');
      expect(section.units, hasLength(1));
      final items = section.units.first.lessons
          .expand((lesson) => lesson.flattenedStages)
          .expand((stage) => stage.items)
          .toList();
      expect(items, hasLength(2));
      expect(items, everyElement(isA<AnkiHtmlCard>()));
    });

    test('empty collection fails instead of reporting a blank success',
        () async {
      final collection = const AnkiCollection(
        notetypes: {},
        decks: {},
        notes: [],
        cards: [],
      );

      await expectLater(
        assembler.assemble(
          collection: collection,
          importId: 'empty',
          repo: repo,
        ),
        throwsA(
          isA<AnkiImportValidationException>()
              .having((error) => error.code, 'code', 'NO_CARDS'),
        ),
      );
      expect(repo.writtenSections, isEmpty);
    });

    test('missing deck metadata is recovered without losing the card',
        () async {
      final collection = AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Basic',
            fieldNames: ['Front', 'Back'],
          ),
        },
        decks: const {},
        notes: const [
          AnkiNote(id: 1, mid: 1, fields: ['Question', 'Answer']),
        ],
        cards: const [AnkiCardData(id: 2, nid: 1, did: 999)],
      );

      final summary = await assembler.assemble(
        collection: collection,
        importId: 'recovery',
        repo: repo,
      );

      expect(summary.cardCount, 1);
      expect(repo.writtenSections, hasLength(1));
      expect(repo.writtenSections.single.name, 'Recovered deck 999');
      expect(repo.writtenSections.single.units.single.lessons, isNotEmpty);
    });

    test('card referencing a missing note blocks all writes', () async {
      final collection = AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Basic',
            fieldNames: ['Front', 'Back'],
          ),
        },
        decks: const {1: AnkiDeckInfo(id: 1, name: 'Default')},
        notes: const [],
        cards: const [AnkiCardData(id: 2, nid: 404, did: 1)],
      );

      await expectLater(
        assembler.assemble(
          collection: collection,
          importId: 'broken',
          repo: repo,
        ),
        throwsA(
          isA<AnkiImportValidationException>()
              .having((error) => error.code, 'code', 'CARD_NOTE_MISSING'),
        ),
      );
      expect(repo.writtenSections, isEmpty);
    });

    AnkiCollection _buildTaggedCollection(
        List<({String tags, int id})> entries) {
      final notes = <AnkiNote>[];
      final cards = <AnkiCardData>[];
      for (final e in entries) {
        notes.add(AnkiNote(
          id: e.id,
          mid: 1,
          fields: ['Q${e.id}', 'A${e.id}'],
          tags: e.tags,
        ));
        cards.add(AnkiCardData(id: 2000 + e.id, nid: e.id, did: 10, queue: 0));
      }
      return AnkiCollection(
        notetypes: {
          1: const AnkiNotetype(
            id: 1,
            name: 'Basic',
            fieldNames: ['Front', 'Back'],
          ),
        },
        decks: {
          10: const AnkiDeckInfo(id: 10, name: 'Flat Deck', cardCount: 4),
        },
        notes: notes,
        cards: cards,
      );
    }

    test('smart grouping splits lessons by lesson:: tags', () async {
      final collection = _buildTaggedCollection([
        (tags: 'lesson::A', id: 1),
        (tags: 'lesson::A', id: 2),
        (tags: 'lesson::B', id: 3),
        (tags: 'lesson::B', id: 4),
      ]);

      await assembler.assemble(
        collection: collection,
        importId: 'smart',
        repo: repo,
      );

      final unit = repo.writtenSections.first.units.first;
      expect(unit.name, 'Flat Deck');
      expect(unit.lessons.map((l) => l.name).toSet(), {'A', 'B'});
      final byName = {
        for (final l in unit.lessons) l.name: l.flattenedStages.length
      };
      expect(byName['A'], 2);
      expect(byName['B'], 2);
    });

    test('smart grouping splits units by unit:: tags', () async {
      final collection = _buildTaggedCollection([
        (tags: 'unit::1', id: 1),
        (tags: 'unit::1', id: 2),
        (tags: 'unit::2', id: 3),
        (tags: 'unit::2', id: 4),
      ]);

      await assembler.assemble(
        collection: collection,
        importId: 'units',
        repo: repo,
      );

      final section = repo.writtenSections.first;
      expect(section.units.map((u) => u.name).toSet(), {'1', '2'});
      // No lesson tags -> each unit gets one fallback chunk lesson.
      for (final u in section.units) {
        expect(u.lessons.length, 1);
        expect(u.lessons.first.flattenedStages.length, 2);
      }
    });

    test('smartGrouping disabled keeps flat chunking even with tags', () async {
      final collection = _buildTaggedCollection([
        (tags: 'lesson::A', id: 1),
        (tags: 'lesson::B', id: 2),
        (tags: 'lesson::A', id: 3),
        (tags: 'lesson::B', id: 4),
      ]);

      await assembler.assemble(
        collection: collection,
        importId: 'flat',
        repo: repo,
        smartGrouping: false,
      );

      final unit = repo.writtenSections.first.units.first;
      // 4 cards, no smart grouping -> one flat chunk lesson.
      expect(unit.lessons.length, 1);
      expect(unit.lessons.first.name, 'Flat Deck #1');
      expect(unit.lessons.first.flattenedStages.length, 4);
    });

    test('a lesson:: group larger than 20 splits into #N chunks', () async {
      // 22 cards all in lesson::Big -> two chunks: 'Big' and 'Big #2'.
      final entries = [
        for (var i = 0; i < 22; i++) (tags: 'lesson::Big', id: i + 1),
      ];
      final collection = _buildTaggedCollection(entries);

      await assembler.assemble(
        collection: collection,
        importId: 'big',
        repo: repo,
      );

      final unit = repo.writtenSections.first.units.first;
      expect(unit.lessons.length, 2);
      expect(unit.lessons[0].name, 'Big #1');
      expect(unit.lessons[0].flattenedStages.length, 20);
      expect(unit.lessons[1].name, 'Big #2');
      expect(unit.lessons[1].flattenedStages.length, 2);
    });

    group('tree-size caps (kMaxLessonsPerUnit / kMaxUnitsPerSection)', () {
      test('splitOversizedUnit chunks lessons into parts of max 40', () {
        final lessons = [
          for (var i = 0; i < 55; i++)
            Lesson(
              id: 'u0-l$i',
              name: 'L$i',
              type: LessonType.normal,
              template: LessonTemplate.legacy,
              content: const LessonContent(),
            ),
        ];
        final unit = Unit(id: 'u0', name: 'Big', lessons: lessons);
        final parts = AnkiDeckAssembler.splitOversizedUnit(unit);

        expect(parts, hasLength(2)); // 40 + 15
        expect(parts[0].id, 'u0-p0');
        expect(parts[0].name, 'Big (1)');
        expect(parts[0].lessons, hasLength(40));
        expect(parts[1].id, 'u0-p1');
        expect(parts[1].name, 'Big (2)');
        expect(parts[1].lessons, hasLength(15));
        // Original lesson ids preserved (stable word/lesson references).
        expect(parts[0].lessons.first.id, 'u0-l0');
        expect(parts[1].lessons.first.id, 'u0-l40');
      });

      test('splitOversizedUnit is a no-op at the limit', () {
        final lessons = [
          for (var i = 0; i < 40; i++)
            Lesson(
              id: 'u0-l$i',
              name: 'L$i',
              type: LessonType.normal,
              template: LessonTemplate.legacy,
              content: const LessonContent(),
            ),
        ];
        final unit = Unit(id: 'u0', name: 'Exact', lessons: lessons);
        final parts = AnkiDeckAssembler.splitOversizedUnit(unit);
        expect(parts, hasLength(1));
        expect(parts.single.id, 'u0');
        expect(parts.single.name, 'Exact');
      });

      test('packUnitsIntoSections creates extra sections beyond 60 units', () {
        final units = [
          for (var i = 0; i < 65; i++)
            Unit(
              id: 'u$i',
              name: 'U$i',
              lessons: [
                Lesson(
                  id: 'u$i-l0',
                  name: 'L',
                  type: LessonType.normal,
                  template: LessonTemplate.legacy,
                  content: const LessonContent(),
                ),
              ],
            ),
        ];
        final sections = AnkiDeckAssembler.packUnitsIntoSections(
          baseSectionId: 'anki-imp-s10',
          baseName: 'Huge Deck',
          description: 'Imported from Anki',
          units: units,
        );

        expect(sections, hasLength(2)); // 60 + 5
        expect(sections[0].id, 'anki-imp-s10');
        expect(sections[0].name, 'Huge Deck (1)');
        expect(sections[0].units, hasLength(60));
        expect(sections[0].level, 'Anki');
        expect(sections[1].id, 'anki-imp-s10-p1');
        expect(sections[1].name, 'Huge Deck (2)');
        expect(sections[1].units, hasLength(5));
      });

      test('assemble splits a flat deck that would exceed 40 lessons/unit',
          () async {
        // 41 lessons × 20 cards = 820 cards → one logical unit must become
        // two units (40 + 1) so validateSectionTree accepts the tree.
        final collection = _buildTestCollection(cardCount: 820);

        final summary = await assembler.assemble(
          collection: collection,
          importId: 'oversize',
          repo: repo,
          smartGrouping: false,
        );

        expect(repo.writtenSections, isNotEmpty);
        for (final section in repo.writtenSections) {
          expect(section.units.length, lessThanOrEqualTo(60));
          for (final unit in section.units) {
            expect(
              unit.lessons.length,
              lessThanOrEqualTo(40),
              reason: 'unit ${unit.id} must stay within kMaxLessonsPerUnit',
            );
          }
        }
        final allUnits = repo.writtenSections.expand((s) => s.units).toList();
        expect(allUnits.length, greaterThanOrEqualTo(2));
        expect(
          allUnits.fold<int>(0, (s, u) => s + u.lessons.length),
          41,
        );
        expect(summary.cardCount, 820);
        expect(summary.lessonCount, 41);
      });
    });
  });
}
