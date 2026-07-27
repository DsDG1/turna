// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_deck_assembler.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/domain/course/expression.dart';
import 'package:varnamala/domain/course/grammar_point.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/domain/repositories/i_course_repository.dart';

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
  Future<List<Section>> sectionShells() async => [];

  @override
  Future<Section> section(String id) async => throw UnimplementedError();

  @override
  Future<Lesson> lessonById(String id) async => throw UnimplementedError();

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
  Future<void> recordAnkiImport(db.AnkiImportsCompanion companion) async {}

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

    test('generates AnkiCard interactions for Front/Back fields', () async {
      final collection = _buildTestCollection(cardCount: 2);

      await assembler.assemble(
        collection: collection,
        importId: 'type',
        repo: repo,
      );

      final section = repo.writtenSections.first;
      final firstStage = section.units.first.lessons.first.flattenedStages.first;
      final interaction = firstStage.items.first;

      // Front/Back heuristic → wordEntry → MultipleChoice
      expect(interaction, isA<MultipleChoice>());
    });

    test('empty collection produces no sections', () async {
      final collection = const AnkiCollection(
        notetypes: {},
        decks: {},
        notes: [],
        cards: [],
      );

      final summary = await assembler.assemble(
        collection: collection,
        importId: 'empty',
        repo: repo,
      );

      expect(repo.writtenSections, isEmpty);
      expect(summary.cardCount, 0);
    });
  });
}
