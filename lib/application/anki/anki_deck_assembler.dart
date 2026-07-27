// Project imports:
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_importer.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/stage.dart';
import 'package:varnamala/domain/course/unit.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/domain/repositories/i_course_repository.dart';

/// Summary of a completed Anki import.
class AnkiImportSummary {
  final String importId;
  final int sectionCount;
  final int unitCount;
  final int lessonCount;
  final int cardCount;
  final int wordEntryCount;

  const AnkiImportSummary({
    required this.importId,
    required this.sectionCount,
    required this.unitCount,
    required this.lessonCount,
    required this.cardCount,
    required this.wordEntryCount,
  });
}

/// Assembles parsed Anki data into Varnamala's course tree structure
/// (Section → Unit → Lesson → Stage → Interaction) and writes to DB.
///
/// Mapping rules:
/// - Top-level deck → Section (id = "anki-<importId>-s<did>", level = "Anki")
/// - Sub-deck → Unit; no sub-decks → single Unit
/// - Every 20 cards → one Lesson (template: legacy)
/// - Each Stage holds one Interaction
class AnkiDeckAssembler {
  static const int cardsPerLesson = 20;

  /// Assemble and persist the course tree from an [AnkiCollection].
  ///
  /// Returns an import summary with counts.
  ///
  /// [onProgress] receives (0..1, message) as decks are processed.
  /// [isCancelled] is polled between decks; returning true aborts assembly with
  /// an [AnkiImportCancelled] exception. Any sections already written remain
  /// in the DB (the caller is expected to roll back via [AnkiDeckManager] or
  /// accept the partial import).
  Future<AnkiImportSummary> assemble({
    required AnkiCollection collection,
    required String importId,
    required ICourseRepository repo,
    Map<int, NotetypeMapping>? mappingOverrides,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final adapter = AnkiCardAdapter();

    // Build note lookup
    final notesById = <int, AnkiNote>{};
    for (final note in collection.notes) {
      notesById[note.id] = note;
    }

    // Infer mappings for each notetype
    final mappings = <int, NotetypeMapping>{};
    for (final entry in collection.notetypes.entries) {
      mappings[entry.key] = mappingOverrides?[entry.key] ??
          AnkiCardAdapter.inferMapping(entry.value);
    }

    // Group cards by deck
    final cardsByDeck = <int, List<AnkiCardData>>{};
    for (final card in collection.cards) {
      cardsByDeck.putIfAbsent(card.did, () => []).add(card);
    }

    // Collect distractors for MCQ generation (all back-field values)
    final allTerms = <String>[];
    for (final note in collection.notes) {
      final mapping = mappings[note.mid];
      if (mapping != null && mapping.type == NotetypeMappingType.wordEntry) {
        if (mapping.backFieldIndex < note.fields.length) {
          allTerms.add(AnkiCardAdapter.stripHtmlPublic(
              note.fields[mapping.backFieldIndex]));
        }
      }
    }

    // Identify top-level decks (parentId == 0 or not present)
    final topLevelDecks = collection.decks.values
        .where((d) => d.parentId == 0 || !collection.decks.containsKey(d.parentId))
        .where((d) => d.id != 1) // Skip "Default" deck
        .toList();

    // If no top-level decks found (all cards in default), create one section
    if (topLevelDecks.isEmpty && cardsByDeck.isNotEmpty) {
      final defaultDeck = collection.decks[1];
      if (defaultDeck != null) {
        topLevelDecks.add(defaultDeck);
      }
    }

    var totalUnits = 0;
    var totalLessons = 0;
    var totalCards = 0;
    var totalWordEntries = 0;
    final allWordEntries = <WordEntry>[];

    for (var deckIdx = 0; deckIdx < topLevelDecks.length; deckIdx++) {
      final deck = topLevelDecks[deckIdx];
      if (isCancelled != null && isCancelled()) {
        throw const AnkiImportCancelled();
      }
      if (onProgress != null && topLevelDecks.isNotEmpty) {
        final p = deckIdx / topLevelDecks.length;
        onProgress(p, 'Building deck ${deckIdx + 1}/${topLevelDecks.length}');
      }
      final sectionId = 'anki-$importId-s${deck.id}';

      // Find child decks
      final childDecks = collection.decks.values
          .where((d) => d.parentId == deck.id)
          .toList();

      final units = <Unit>[];

      if (childDecks.isEmpty) {
        // Single unit for this deck
        final deckCards = cardsByDeck[deck.id] ?? [];
        if (deckCards.isEmpty) continue;

        final unit = _buildUnit(
          deckId: deck.id,
          deckName: deck.name,
          importId: importId,
          cards: deckCards,
          notesById: notesById,
          mappings: mappings,
          adapter: adapter,
          distractors: allTerms,
          wordEntries: allWordEntries,
        );
        if (unit != null) {
          units.add(unit);
          totalCards += deckCards.length;
        }
      } else {
        // One unit per child deck
        for (final child in childDecks) {
          final childCards = cardsByDeck[child.id] ?? [];
          if (childCards.isEmpty) continue;

          final unit = _buildUnit(
            deckId: child.id,
            deckName: _shortDeckName(child.name),
            importId: importId,
            cards: childCards,
            notesById: notesById,
            mappings: mappings,
            adapter: adapter,
            distractors: allTerms,
            wordEntries: allWordEntries,
          );
          if (unit != null) {
            units.add(unit);
            totalCards += childCards.length;
          }
        }

        // Also include cards directly in the parent deck
        final parentCards = cardsByDeck[deck.id] ?? [];
        if (parentCards.isNotEmpty) {
          final unit = _buildUnit(
            deckId: deck.id,
            deckName: '${_shortDeckName(deck.name)} (general)',
            importId: importId,
            cards: parentCards,
            notesById: notesById,
            mappings: mappings,
            adapter: adapter,
            distractors: allTerms,
            wordEntries: allWordEntries,
          );
          if (unit != null) {
            units.add(unit);
            totalCards += parentCards.length;
          }
        }
      }

      if (units.isEmpty) continue;

      final section = Section(
        id: sectionId,
        name: _shortDeckName(deck.name),
        description: 'Imported from Anki (${deck.cardCount} cards)',
        level: 'Anki',
        prerequisiteSectionIds: const [],
        units: units,
      );

      await repo.bulkInsertCourseTree(section);
      totalUnits += units.length;
      totalLessons += units.fold<int>(0, (sum, u) => sum + u.lessons.length);
    }

    if (isCancelled != null && isCancelled()) {
      throw const AnkiImportCancelled();
    }

    // Bulk insert word entries
    if (allWordEntries.isNotEmpty) {
      await repo.bulkInsertVocabulary(allWordEntries);
      totalWordEntries = allWordEntries.length;
    }
    if (onProgress != null) onProgress(1.0, 'Finishing import');

    return AnkiImportSummary(
      importId: importId,
      sectionCount: topLevelDecks.length,
      unitCount: totalUnits,
      lessonCount: totalLessons,
      cardCount: totalCards,
      wordEntryCount: totalWordEntries,
    );
  }

  Unit? _buildUnit({
    required int deckId,
    required String deckName,
    required String importId,
    required List<AnkiCardData> cards,
    required Map<int, AnkiNote> notesById,
    required Map<int, NotetypeMapping> mappings,
    required AnkiCardAdapter adapter,
    required List<String> distractors,
    required List<WordEntry> wordEntries,
  }) {
    if (cards.isEmpty) return null;

    final unitId = 'anki-$importId-u$deckId';
    final lessons = <Lesson>[];

    // Split cards into chunks of [cardsPerLesson]
    for (var chunkIdx = 0;
        chunkIdx * cardsPerLesson < cards.length;
        chunkIdx++) {
      final start = chunkIdx * cardsPerLesson;
      final end =
          (start + cardsPerLesson).clamp(0, cards.length);
      final chunk = cards.sublist(start, end);

      final lessonId = 'anki-$importId-l$deckId-$chunkIdx';
      final stages = <Stage>[];

      for (var i = 0; i < chunk.length; i++) {
        final card = chunk[i];
        final note = notesById[card.nid];
        if (note == null) continue;

        final mapping = mappings[note.mid] ??
            const NotetypeMapping(
              type: NotetypeMappingType.ankiCard,
              frontFieldIndex: 0,
              backFieldIndex: 1,
            );

        final result = adapter.adapt(
          note,
          card,
          importId: importId,
          mapping: mapping,
          distractors: distractors,
        );

        if (result.wordEntry != null) {
          wordEntries.add(result.wordEntry!);
        }

        stages.add(Stage(
          id: '$lessonId-s$i',
          name: 'Card ${start + i + 1}',
          items: [result.interaction],
        ));
      }

      if (stages.isEmpty) continue;

      final chunkNum = chunkIdx + 1;
      lessons.add(Lesson(
        id: lessonId,
        name: '$deckName #$chunkNum',
        type: LessonType.normal,
        template: LessonTemplate.legacy,
        content: LessonContent(stages: stages),
      ));
    }

    if (lessons.isEmpty) return null;

    return Unit(
      id: unitId,
      name: deckName,
      lessons: lessons,
    );
  }

  /// Extract the short name from a hierarchical deck name ("Parent::Child" → "Child").
  static String _shortDeckName(String name) {
    if (name.contains('::')) {
      return name.substring(name.lastIndexOf('::') + 2);
    }
    return name;
  }
}
