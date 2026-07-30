// Project imports:
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_importer.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/anki/anki_organization_resolver.dart';
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
/// (Section -> Unit -> Lesson -> Stage -> Interaction) and writes to DB.
///
/// Mapping rules:
/// - Top-level deck -> Section (id = "anki-<importId>-s<did>", level = "Anki")
/// - Direct sub-deck -> Unit; no sub-decks -> single Unit
/// - Within a Unit, cards are grouped into Lessons by their carried metadata
///   (notetype "unit"/"lesson" fields or `unit::`/`lesson::` tags) when
///   [smartGrouping] is on; otherwise (or when a card carries no metadata) they
///   fall back to fixed 20-card chunks named "Unit #N".
/// - Each Stage holds one Interaction.
class AnkiDeckAssembler {
  static const int cardsPerLesson = 20;

  /// Assemble and persist the course tree from an [AnkiCollection].
  ///
  /// [smartGrouping] (default true) organizes cards into named Units/Lessons
  /// from their tags/notetype fields instead of flat 20-card chunks. Disable
  /// to force the flat chunking regardless of metadata.
  Future<AnkiImportSummary> assemble({
    required AnkiCollection collection,
    required String importId,
    required ICourseRepository repo,
    Map<int, NotetypeMapping>? mappingOverrides,
    bool smartGrouping = true,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final adapter = AnkiCardAdapter();
    const resolver = AnkiOrganizationResolver();

    final notesById = <int, AnkiNote>{};
    for (final note in collection.notes) {
      notesById[note.id] = note;
    }

    final mappings = <int, NotetypeMapping>{};
    for (final entry in collection.notetypes.entries) {
      mappings[entry.key] = mappingOverrides?[entry.key] ??
          AnkiCardAdapter.inferMapping(entry.value);
    }

    final cardsByDeck = <int, List<AnkiCardData>>{};
    for (final card in collection.cards) {
      cardsByDeck.putIfAbsent(card.did, () => []).add(card);
    }

    // Distractors for MCQ generation. Back-face values feed forward cards;
    // front-face values feed reversed cards (whose answer is the front face).
    // ankiCard mappings are included so the adapter's auto-decide path can
    // upgrade generic flip cards to real questions.
    final allTerms = <String>[];
    final allFrontTerms = <String>[];
    for (final note in collection.notes) {
      final mapping = mappings[note.mid];
      if (mapping == null) continue;
      if (mapping.type == NotetypeMappingType.wordEntry ||
          mapping.type == NotetypeMappingType.ankiCard ||
          mapping.type == NotetypeMappingType.multipleChoice ||
          mapping.type == NotetypeMappingType.listenPick) {
        if (mapping.backFieldIndex < note.fields.length) {
          final v = AnkiCardAdapter.stripHtmlPublic(
              note.fields[mapping.backFieldIndex]);
          if (v.isNotEmpty) allTerms.add(v);
        }
        if (mapping.frontFieldIndex < note.fields.length) {
          final v = AnkiCardAdapter.stripHtmlPublic(
              note.fields[mapping.frontFieldIndex]);
          if (v.isNotEmpty) allFrontTerms.add(v);
        }
      }
    }

    final topLevelDecks = collection.decks.values
        .where((d) => d.parentId == 0 || !collection.decks.containsKey(d.parentId))
        .where((d) => d.id != 1) // Skip "Default" deck
        .toList();

    if (topLevelDecks.isEmpty && cardsByDeck.isNotEmpty) {
      final defaultDeck = collection.decks[1];
      if (defaultDeck != null) topLevelDecks.add(defaultDeck);
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

      // Sources: direct child decks, plus the parent deck itself when it has
      // cards directly in it. If there are no children, the deck is the source.
      final childDecks = collection.decks.values
          .where((d) => d.parentId == deck.id)
          .toList();
      final sources = <AnkiDeckInfo>[
        ...childDecks,
        if (childDecks.isEmpty || (cardsByDeck[deck.id] ?? []).isNotEmpty) deck,
      ];

      // Group cards by unit key (smart) or by deck fallback name.
      final unitGroups = <String, List<AnkiCardData>>{};
      final unitOrder = <String>[];
      for (final d in sources) {
        final deckCards = cardsByDeck[d.id] ?? [];
        if (deckCards.isEmpty) continue;
        final fallbackName = _unitFallbackName(d, deck, childDecks.isEmpty);
        for (final card in deckCards) {
          final note = notesById[card.nid];
          String unitKey;
          if (smartGrouping && note != null) {
            final nt = collection.notetypes[note.mid];
            unitKey = (nt != null ? resolver.resolve(note, nt).unitKey : null) ??
                fallbackName;
          } else {
            unitKey = fallbackName;
          }
          if (!unitGroups.containsKey(unitKey)) {
            unitGroups[unitKey] = [];
            unitOrder.add(unitKey);
          }
          unitGroups[unitKey]!.add(card);
        }
      }

      final units = <Unit>[];
      for (var i = 0; i < unitOrder.length; i++) {
        final unitName = unitOrder[i];
        final unitCards = unitGroups[unitName]!;
        final unit = _buildUnit(
          unitName: unitName,
          unitId: 'anki-$importId-u${deck.id}-$i',
          importId: importId,
          deckId: deck.id,
          cards: unitCards,
          notesById: notesById,
          notetypes: collection.notetypes,
          mappings: mappings,
          adapter: adapter,
          resolver: resolver,
          smartGrouping: smartGrouping,
          distractors: allTerms,
          frontDistractors: allFrontTerms,
          wordEntries: allWordEntries,
        );
        if (unit != null) {
          units.add(unit);
          totalCards += unitCards.length;
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

  /// Fallback unit name when a card carries no unit metadata.
  String _unitFallbackName(AnkiDeckInfo d, AnkiDeckInfo parent, bool noChildren) {
    if (noChildren) return _shortDeckName(parent.name);
    if (d.id == parent.id) return '${_shortDeckName(parent.name)} (general)';
    return _shortDeckName(d.name);
  }

  Unit? _buildUnit({
    required String unitName,
    required String unitId,
    required String importId,
    required int deckId,
    required List<AnkiCardData> cards,
    required Map<int, AnkiNote> notesById,
    required Map<int, AnkiNotetype> notetypes,
    required Map<int, NotetypeMapping> mappings,
    required AnkiCardAdapter adapter,
    required AnkiOrganizationResolver resolver,
    required bool smartGrouping,
    required List<String> distractors,
    required List<String> frontDistractors,
    required List<WordEntry> wordEntries,
  }) {
    if (cards.isEmpty) return null;

    // Group cards by lesson key (smart) or null (fallback chunk).
    final lessonGroups = <String?, List<AnkiCardData>>{};
    final lessonOrder = <String?>[];
    for (final card in cards) {
      final note = notesById[card.nid];
      String? lessonKey;
      if (smartGrouping && note != null) {
        final nt = notetypes[note.mid];
        lessonKey = nt != null ? resolver.resolve(note, nt).lessonKey : null;
      }
      if (!lessonGroups.containsKey(lessonKey)) {
        lessonGroups[lessonKey] = [];
        lessonOrder.add(lessonKey);
      }
      lessonGroups[lessonKey]!.add(card);
    }

    final lessons = <Lesson>[];
    for (final lessonKey in lessonOrder) {
      final groupCards = lessonGroups[lessonKey]!;
      final multiChunk = groupCards.length > cardsPerLesson;
      for (var chunkIdx = 0;
          chunkIdx * cardsPerLesson < groupCards.length;
          chunkIdx++) {
        final start = chunkIdx * cardsPerLesson;
        final end = (start + cardsPerLesson).clamp(0, groupCards.length);
        final chunk = groupCards.sublist(start, end);

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
            notetype: notetypes[note.mid],
            distractors: distractors,
            frontDistractors: frontDistractors,
          );

          if (result.wordEntry != null) {
            wordEntries.add(result.wordEntry!);
          }

          stages.add(Stage(
            id: '$unitId-l$chunkIdx-s$i',
            name: 'Card ${start + i + 1}',
            items: [result.interaction],
          ));
        }

        if (stages.isEmpty) continue;

        final chunkNum = chunkIdx + 1;
        final name = lessonKey == null
            ? '$unitName #$chunkNum'
            : (multiChunk ? '$lessonKey #$chunkNum' : lessonKey);
        lessons.add(Lesson(
          id: '$unitId-l$chunkIdx',
          name: name,
          type: LessonType.normal,
          template: LessonTemplate.legacy,
          content: LessonContent(stages: stages),
        ));
      }
    }

    if (lessons.isEmpty) return null;

    return Unit(
      id: unitId,
      name: unitName,
      lessons: lessons,
    );
  }

  /// Extract the short name from a hierarchical deck name ("Parent::Child" -> "Child").
  static String _shortDeckName(String name) {
    if (name.contains('::')) {
      return name.substring(name.lastIndexOf('::') + 2);
    }
    return name;
  }
}
