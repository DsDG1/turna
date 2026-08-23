// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart' show visibleForTesting;

// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';
import 'package:turna/courses/course_validator.dart';
import 'package:turna/application/anki/anki_render_policy.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

/// Summary of a completed Anki import.
class AnkiImportSummary {
  final String importId;
  final int sectionCount;
  final int unitCount;
  final int lessonCount;
  final int cardCount;
  final int wordEntryCount;
  final int sourceCardCount;
  final int structuredCardCount;
  final int fidelityCardCount;
  final int unknownTemplateCount;
  final int suspendedCardCount;
  final int buriedCardCount;
  final bool hasScheduling;
  final bool hasReviewHistory;
  final int missingMediaCount;
  final int failedMediaCount;
  final List<String> platformDowngrades;

  const AnkiImportSummary({
    required this.importId,
    required this.sectionCount,
    required this.unitCount,
    required this.lessonCount,
    required this.cardCount,
    required this.wordEntryCount,
    this.sourceCardCount = 0,
    this.structuredCardCount = 0,
    this.fidelityCardCount = 0,
    this.unknownTemplateCount = 0,
    this.suspendedCardCount = 0,
    this.buriedCardCount = 0,
    this.hasScheduling = false,
    this.hasReviewHistory = false,
    this.missingMediaCount = 0,
    this.failedMediaCount = 0,
    this.platformDowngrades = const [],
  });

  AnkiImportSummary copyWith({
    int? missingMediaCount,
    int? failedMediaCount,
  }) =>
      AnkiImportSummary(
        importId: importId,
        sectionCount: sectionCount,
        unitCount: unitCount,
        lessonCount: lessonCount,
        cardCount: cardCount,
        wordEntryCount: wordEntryCount,
        sourceCardCount: sourceCardCount,
        structuredCardCount: structuredCardCount,
        fidelityCardCount: fidelityCardCount,
        unknownTemplateCount: unknownTemplateCount,
        suspendedCardCount: suspendedCardCount,
        buriedCardCount: buriedCardCount,
        hasScheduling: hasScheduling,
        hasReviewHistory: hasReviewHistory,
        missingMediaCount: missingMediaCount ?? this.missingMediaCount,
        failedMediaCount: failedMediaCount ?? this.failedMediaCount,
        platformDowngrades: platformDowngrades,
      );
}

/// Assembles parsed Anki data into Turna's course tree structure
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
///
/// **Tree-size caps** (see [kMaxLessonsPerUnit] / [kMaxUnitsPerSection]): a
/// multi-thousand-card deck can produce hundreds of 20-card lessons under one
/// unit name. After build, oversized units are split into parts of at most
/// [kMaxLessonsPerUnit] lessons, and when a deck still has more than
/// [kMaxUnitsPerSection] units those are packed into additional Sections
/// (`…-p1`, `…-p2`, …) so [validateSectionTree] never fails on open.
class AnkiDeckAssembler {
  static const int cardsPerLesson = 20;

  /// Assemble and persist the course tree from an [AnkiCollection].
  ///
  /// [smartGrouping] (default true) organizes cards into named Units/Lessons
  /// from their tags/notetype fields instead of flat 20-card chunks. Disable
  /// to force the flat chunking regardless of metadata.
  ///
  /// [sectionBetaGrouping] (default false, Plan 1 Phase 5) lifts explicit
  /// section/chapter metadata into semantic Sections. Off by default and only
  /// affects new imports; existing course trees are never rewritten.
  Future<AnkiImportSummary> assemble({
    required AnkiCollection collection,
    required String importId,
    required ICourseRepository repo,
    AnkiNoteDao? noteDao,
    Map<int, NotetypeMapping>? mappingOverrides,
    bool smartGrouping = true,
    bool sectionBetaGrouping = false,
    int liteThreshold = 2000,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final adapter = AnkiCardAdapter();
    const resolver = AnkiOrganizationResolver();

    if (collection.cards.isEmpty) {
      throw const AnkiImportValidationException(
        code: 'NO_CARDS',
        message: 'The package contains no Anki cards.',
      );
    }

    final notesById = <int, AnkiNote>{};
    for (final note in collection.notes) {
      notesById[note.id] = note;
    }
    final missingNoteCardIds = <int>[
      for (final card in collection.cards)
        if (!notesById.containsKey(card.nid)) card.id,
    ];
    if (missingNoteCardIds.isNotEmpty) {
      throw AnkiImportValidationException(
        code: 'CARD_NOTE_MISSING',
        message:
            '${missingNoteCardIds.length} card(s) reference missing notes.',
        sourceIds: missingNoteCardIds,
      );
    }
    final referencedNoteIds = collection.cards.map((card) => card.nid).toSet();
    final missingNotetypeNoteIds = <int>[
      for (final note in collection.notes)
        if (referencedNoteIds.contains(note.id) &&
            !collection.notetypes.containsKey(note.mid))
          note.id,
    ];
    if (missingNotetypeNoteIds.isNotEmpty) {
      throw AnkiImportValidationException(
        code: 'NOTETYPE_MISSING',
        message:
            '${missingNotetypeNoteIds.length} note(s) reference missing note types.',
        sourceIds: missingNotetypeNoteIds,
      );
    }

    final mappings = <int, NotetypeMapping>{};
    for (final entry in collection.notetypes.entries) {
      mappings[entry.key] = mappingOverrides?[entry.key] ??
          AnkiCardAdapter.inferMapping(entry.value);
    }

    final decks = Map<int, AnkiDeckInfo>.of(collection.decks);
    final sourceDeckIds = collection.decks.keys.toSet();
    final recoveredDeckIds = <int>{};
    final cardsByDeck = <int, List<AnkiCardData>>{};
    for (final card in collection.cards) {
      cardsByDeck.putIfAbsent(card.did, () => []).add(card);
      // Damaged/third-party packages sometimes retain cards whose deck entry
      // is absent from col.decks. Anki cards must not disappear because their
      // navigation metadata is incomplete; recover them into a synthetic
      // top-level deck with the original did preserved.
      decks.putIfAbsent(
        card.did,
        () {
          recoveredDeckIds.add(card.did);
          return AnkiDeckInfo(
            id: card.did,
            name: 'Recovered deck ${card.did}',
            cardCount: 0,
          );
        },
      );
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

    final topLevelDecks = decks.values
        .where((d) => d.parentId == 0 || !decks.containsKey(d.parentId))
        // Keep Default when it (or any of its subdecks) carries cards, or when
        // it is the only deck. Dropping an empty Default whose subdecks hold
        // cards would orphan those cards: the subdecks are not top-level, so
        // nothing would index them and the count-reconciliation check would
        // abort the whole import.
        .where((d) =>
            d.id != 1 ||
            (cardsByDeck[d.id]?.isNotEmpty ?? false) ||
            decks.length == 1 ||
            _deckTreeHasCards(d.id, decks, cardsByDeck))
        .toList();

    if (topLevelDecks.isEmpty && cardsByDeck.isNotEmpty) {
      // A cyclic/malformed hierarchy must not make the import invisible.
      // Break all parent links. Promoting only one node from a cycle while
      // retaining its descendants would index the same Card more than once.
      for (final entry in decks.entries.toList()) {
        decks[entry.key] = entry.value.copyWith(parentId: 0);
      }
      topLevelDecks.addAll(
        decks.values.where((deck) => cardsByDeck[deck.id]?.isNotEmpty ?? false),
      );
    }

    var totalSections = 0;
    var totalUnits = 0;
    var totalLessons = 0;
    var totalCards = 0;
    var totalWordEntries = 0;
    final allWordEntries = <WordEntry>[];
    final practiceProjections = <AnkiPracticeProjectionRecord>[];
    // Yield to the event loop when the main isolate has been busy for a full
    // frame so a multi-thousand-card import keeps the progress UI painting
    // instead of freezing. Time-based (not card-count-based) because per-card
    // cost varies widely between decks.
    final yieldStopwatch = Stopwatch()..start();

    for (var deckIdx = 0; deckIdx < topLevelDecks.length; deckIdx++) {
      final deck = topLevelDecks[deckIdx];
      if (isCancelled != null && isCancelled()) {
        throw const AnkiImportCancelled();
      }
      if (onProgress != null && topLevelDecks.isNotEmpty) {
        final p = deckIdx / topLevelDecks.length;
        onProgress(p, 'Building deck ${deckIdx + 1}/${topLevelDecks.length}');
      }
      final baseSectionId = 'anki-$importId-s${deck.id}';
      final baseSectionName = _shortDeckName(deck.name);

      // Sources: direct child decks, plus the parent deck itself when it has
      // cards directly in it. If there are no children, the deck is the source.
      final childDecks =
          decks.values.where((d) => d.parentId == deck.id).toList();
      final descendantDecks = _descendantsOf(deck.id, decks);
      final sources = <AnkiDeckInfo>[
        ...descendantDecks,
        if ((cardsByDeck[deck.id] ?? []).isNotEmpty) deck,
      ];
      if (sources.isEmpty && decks.length == 1) sources.add(deck);

      // Large decks use lightweight CardRef-like AnkiHtmlCard interactions.
      // Lite is a storage/loading policy only; it must never remove cards from
      // the navigable Section/Unit/Lesson tree.
      final deckCardTotal = sources
          .map((d) => cardsByDeck[d.id]?.length ?? 0)
          .fold<int>(0, (a, b) => a + b);
      final useLazyCardRefs =
          liteThreshold > 0 && deckCardTotal >= liteThreshold;

      // Group cards by unit key (smart) or by deck fallback name. On the
      // Section-Beta path each unit group also tallies its cards' explicit
      // section keys so semantic sections can be built later (majority wins;
      // units without card-level sections fall back to the unit-name prefix).
      final unitGroups = <String, List<AnkiCardData>>{};
      final unitOrder = <String>[];
      final sectionTallyByUnit = <String, Map<String, int>>{};
      final effectiveSectionBeta = sectionBetaGrouping && smartGrouping;
      for (final d in sources) {
        final deckCards = cardsByDeck[d.id] ?? [];
        if (deckCards.isEmpty) continue;
        final fallbackName = _unitFallbackName(d, deck, childDecks.isEmpty);
        for (final card in deckCards) {
          final note = notesById[card.nid];
          String unitKey;
          if (smartGrouping && note != null) {
            final nt = collection.notetypes[note.mid];
            final org = nt != null
                ? resolver.resolve(note, nt,
                    sectionBeta: effectiveSectionBeta)
                : null;
            unitKey = org?.unitKey ?? fallbackName;
            if (effectiveSectionBeta) {
              final section = org?.sectionKey;
              if (section != null) {
                final tally =
                    sectionTallyByUnit.putIfAbsent(unitKey, () => {});
                tally[section] = (tally[section] ?? 0) + 1;
              }
            }
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
        if (isCancelled != null && isCancelled()) {
          throw const AnkiImportCancelled();
        }
        final unitName = unitOrder[i];
        final unitCards = unitGroups[unitName]!;
        if (onProgress != null && unitOrder.isNotEmpty) {
          final deckBase =
              topLevelDecks.isEmpty ? 0.0 : deckIdx / topLevelDecks.length;
          final deckSpan =
              topLevelDecks.isEmpty ? 1.0 : 1.0 / topLevelDecks.length;
          final p = deckBase + deckSpan * ((i + 1) / unitOrder.length) * 0.85;
          onProgress(
            p.clamp(0.0, 0.95),
            'Deck ${deckIdx + 1}/${topLevelDecks.length}: '
            'unit ${i + 1}/${unitOrder.length}',
          );
        }
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
          practiceProjections: practiceProjections,
          forceLazyCardRefs: useLazyCardRefs,
        );
        if (unit != null) {
          // Enforce kMaxLessonsPerUnit so validateSectionTree never rejects
          // a multi-thousand-card flat unit (e.g. 550 lessons > max 40).
          units.addAll(splitOversizedUnit(unit));
          totalCards += unitCards.length;
          if (yieldStopwatch.elapsedMilliseconds >= 16) {
            yieldStopwatch.reset();
            // Let the progress indicator / cancel flag paint.
            await Future<void>.delayed(Duration.zero);
          }
        }
      }

      if (units.isEmpty) {
        // Reaching this branch now means cards could not be indexed (for
        // example every Card references a missing Note), not merely that they
        // require fidelity rendering. Keep a shell for diagnostics; the
        // import validator treats non-empty source + zero indexed lessons as
        // an error before declaring the import successful.
        final cardTotal =
            unitGroups.values.fold<int>(0, (s, list) => s + list.length);
        await repo.bulkInsertCourseTree(Section(
          id: baseSectionId,
          name: baseSectionName,
          description: 'Imported from Anki ($cardTotal cards)',
          level: 'Anki',
          prerequisiteSectionIds: const [],
          units: [
            Unit(
              id: 'anki-$importId-u${deck.id}-0',
              name: baseSectionName,
              lessons: const [],
            ),
          ],
        ));
        totalSections++;
        totalCards += cardTotal;
        continue;
      }

      // Pack units into one or more sections under the same import (extra
      // parts get id/name suffix `-pN` / ` (N+1)`). On the Section-Beta path
      // units with explicit or prefix-derived sections become semantic
      // sections instead of mechanical parts.
      final cardTotal = units.fold<int>(
          0,
          (s, u) =>
              s + u.lessons.fold(0, (a, l) => a + l.flattenedStages.length));
      final description = 'Imported from Anki ($cardTotal cards)';
      final cardSectionByUnit = <String, String>{
        for (final e in sectionTallyByUnit.entries)
          if (_majoritySection(e.value) != null)
            e.key: _majoritySection(e.value)!,
      };
      final sections = effectiveSectionBeta
          ? buildSemanticSections(
              baseSectionId: baseSectionId,
              baseName: baseSectionName,
              description: description,
              units: units,
              cardSectionByUnit: cardSectionByUnit,
            )
          : packUnitsIntoSections(
              baseSectionId: baseSectionId,
              baseName: baseSectionName,
              description: description,
              units: units,
            );

      for (var sIdx = 0; sIdx < sections.length; sIdx++) {
        if (isCancelled != null && isCancelled()) {
          throw const AnkiImportCancelled();
        }
        final section = sections[sIdx];
        if (onProgress != null) {
          onProgress(
            ((deckIdx + 0.9) /
                    (topLevelDecks.isEmpty ? 1 : topLevelDecks.length))
                .clamp(0.0, 0.98),
            sections.length == 1
                ? 'Writing deck ${deckIdx + 1}/${topLevelDecks.length}…'
                : 'Writing deck ${deckIdx + 1}/${topLevelDecks.length} '
                    'part ${sIdx + 1}/${sections.length}…',
          );
        }
        await repo.bulkInsertCourseTree(section);
        totalSections++;
        totalUnits += section.units.length;
        totalLessons +=
            section.units.fold<int>(0, (sum, u) => sum + u.lessons.length);
      }
    }

    if (isCancelled != null && isCancelled()) {
      throw const AnkiImportCancelled();
    }

    if (allWordEntries.isNotEmpty) {
      await repo.bulkInsertVocabulary(allWordEntries);
      totalWordEntries = allWordEntries.length;
    }
    if (onProgress != null) onProgress(1.0, 'Finishing import');

    if (totalSections == 0) {
      throw const AnkiImportValidationException(
        code: 'NO_SECTIONS_CREATED',
        message:
            'Cards were parsed, but no navigable Anki section was created.',
      );
    }
    if (totalLessons == 0) {
      throw const AnkiImportValidationException(
        code: 'NO_LESSONS_CREATED',
        message: 'Cards were parsed, but no navigable Anki lesson was created.',
      );
    }
    if (totalCards != collection.cards.length) {
      throw AnkiImportValidationException(
        code: 'COUNT_RECONCILIATION_FAILED',
        message: 'Parsed ${collection.cards.length} cards but indexed '
            '$totalCards cards.',
      );
    }

    // NoteStore: source-of-truth notetypes (templates + css + allowJs) + raw
    // note fields + card meta, so the fidelity track can re-render cards from
    // the original templates without re-parsing the .apkg (deep-adaptation plan
    // §3.2.1). Written for every import; the Lite/Full-tree distinction (阶段 4)
    // only affects whether structured lessons are also built.
    if (noteDao != null) {
      await _writeNoteStore(
        collection: collection,
        importId: importId,
        noteDao: noteDao,
        mappings: mappings,
        resolvedDecks: decks,
        sourceDeckIds: sourceDeckIds,
        cardsByDeck: cardsByDeck,
        recoveredDeckIds: recoveredDeckIds,
        practiceProjections: practiceProjections,
      );
    }

    final modes = [
      for (final card in collection.cards)
        _renderModeFor(
          collection: collection,
          card: card,
          notesById: notesById,
          mappings: mappings,
        ),
    ];
    final unknownTemplates = collection.cards.where((card) {
      final note = notesById[card.nid];
      final nt = note == null ? null : collection.notetypes[note.mid];
      return nt == null || nt.templates.isEmpty;
    }).length;

    return AnkiImportSummary(
      importId: importId,
      sectionCount: totalSections,
      unitCount: totalUnits,
      lessonCount: totalLessons,
      cardCount: totalCards,
      wordEntryCount: totalWordEntries,
      sourceCardCount: collection.cards.length,
      structuredCardCount:
          modes.where((mode) => mode == AnkiRenderMode.structured).length,
      fidelityCardCount:
          modes.where((mode) => mode == AnkiRenderMode.fidelity).length,
      unknownTemplateCount: unknownTemplates,
      suspendedCardCount:
          collection.cards.where((card) => card.queue == -1).length,
      buriedCardCount:
          collection.cards.where((card) => card.queue == -2).length,
      // `collectionCreationTime` (col.crt) is non-zero for every real
      // collection, so it must not gate this flag - otherwise scheduling is
      // always reported as migrated, even for a deck of all-new cards.
      hasScheduling: collection.cards.any(
            (card) => card.queue != 0 || card.reps != 0 || card.ivl != 0,
          ),
      hasReviewHistory: collection.revlog.isNotEmpty,
    );
  }

  /// Write the Anki NoteStore (notetypes + raw notes + card meta) so the
  /// fidelity track can re-render cards from source templates later without
  /// re-parsing the .apkg. Raw note fields are kept as HTML (not stripped).
  Future<void> _writeNoteStore({
    required AnkiCollection collection,
    required String importId,
    required AnkiNoteDao noteDao,
    required Map<int, NotetypeMapping> mappings,
    required Map<int, AnkiDeckInfo> resolvedDecks,
    required Set<int> sourceDeckIds,
    required Map<int, List<AnkiCardData>> cardsByDeck,
    required Set<int> recoveredDeckIds,
    required List<AnkiPracticeProjectionRecord> practiceProjections,
  }) async {
    final notesById = <int, AnkiNote>{
      for (final n in collection.notes) n.id: n
    };
    await noteDao.upsertNotetypeBatch([
      for (final nt in collection.notetypes.values)
        AnkiNotetypeRecord(
          importId: importId,
          mid: nt.id,
          name: nt.name,
          isCloze: nt.isCloze,
          fieldNames: nt.fieldNames,
          templates: nt.templates,
          css: nt.css,
          allowJs: _notetypeAllowsJs(nt),
        ),
    ]);
    await noteDao.upsertNoteBatch([
      for (final n in collection.notes)
        AnkiNoteRecord(
          importId: importId,
          noteId: n.id,
          mid: n.mid,
          tags: n.tags,
          fields: n.fields,
          sfld: n.sortField,
          guid: n.guid,
          mod: n.mod,
        ),
    ]);
    await noteDao.upsertCardMetaBatch([
      for (final c in collection.cards)
        AnkiCardMetaRecord(
          importId: importId,
          cardId: c.id,
          noteId: c.nid,
          ord: c.ord,
          did: c.did,
          wordId: 'anki-$importId-c${c.id}',
          renderMode: _renderModeFor(
            collection: collection,
            card: c,
            notesById: notesById,
            mappings: mappings,
          ).name,
          schedulingJson: _schedulingJson(c),
          suspended: c.queue == -1,
          buriedUntil: c.queue == -2 ? _tomorrowTimestamp() : null,
        ),
    ]);
    await noteDao.replaceDeckIndex(
      importId,
      [
        for (final deck in resolvedDecks.values)
          AnkiDeckIndexRecord(
            did: deck.id,
            name: deck.name,
            parentDid: deck.parentId,
            cardCount: cardsByDeck[deck.id]?.length ?? 0,
            recovered: recoveredDeckIds.contains(deck.id) ||
                !sourceDeckIds.contains(deck.id),
          ),
      ],
    );
    await noteDao.replacePracticeProjections(importId, practiceProjections);
    await noteDao.replaceImportIssues(
      importId,
      [
        for (final did in recoveredDeckIds)
          AnkiImportIssueRecord(
            severity: 'warning',
            code: 'DECK_METADATA_RECOVERED',
            entityType: 'deck',
            entityId: '$did',
            message:
                'Cards referenced deck $did, but the package had no deck metadata.',
          ),
      ],
    );
  }

  /// Per-card render-mode decision via [AnkiRenderPolicy] (阶段 3). Falls back
  /// to [AnkiRenderMode.hybrid] when the card's note/notetype can't be resolved.
  AnkiRenderMode _renderModeFor({
    required AnkiCollection collection,
    required AnkiCardData card,
    required Map<int, AnkiNote> notesById,
    required Map<int, NotetypeMapping> mappings,
  }) {
    final note = notesById[card.nid];
    if (note == null) return AnkiRenderMode.hybrid;
    final nt = collection.notetypes[note.mid];
    if (nt == null) return AnkiRenderMode.hybrid;
    final mapping = mappings[note.mid] ?? AnkiCardAdapter.inferMapping(nt);
    return const AnkiRenderPolicy().decide(
      notetype: nt,
      note: note,
      card: card,
      mapping: mapping,
    );
  }

  /// Whether any template body contains JS (`<script>` or inline `on*=`
  /// handlers), gating the fidelity WebView's javascriptMode (decision 3).
  static bool _notetypeAllowsJs(AnkiNotetype nt) {
    for (final t in nt.templates) {
      if (t.qfmt.contains('<script') || t.afmt.contains('<script')) return true;
      if (_onHandlerRe.hasMatch(t.qfmt) || _onHandlerRe.hasMatch(t.afmt)) {
        return true;
      }
    }
    return false;
  }

  static final RegExp _onHandlerRe =
      RegExp(r'\son[a-z]+\s*=', caseSensitive: false);

  /// Split a unit whose lesson count exceeds [kMaxLessonsPerUnit] into
  /// consecutive parts. Lesson ids stay unchanged (already unique from build).
  /// Part units use id suffix `-p0`, `-p1`, … and names like `Name (1)`.
  @visibleForTesting
  static List<Unit> splitOversizedUnit(
    Unit unit, {
    int maxLessonsPerUnit = kMaxLessonsPerUnit,
  }) {
    final max = maxLessonsPerUnit < 1 ? 1 : maxLessonsPerUnit;
    if (unit.lessons.length <= max) return [unit];

    final parts = <Unit>[];
    var part = 0;
    for (var i = 0; i < unit.lessons.length; i += max) {
      final end = (i + max).clamp(0, unit.lessons.length);
      final slice = unit.lessons.sublist(i, end);
      parts.add(Unit(
        id: '${unit.id}-p$part',
        name: '${unit.name} (${part + 1})',
        description: unit.description,
        prerequisiteUnitIds: part == 0 ? unit.prerequisiteUnitIds : const [],
        lessons: slice,
      ));
      part++;
    }
    return parts;
  }

  /// Pack [units] into sections of at most [kMaxUnitsPerSection] each.
  /// First section keeps [baseSectionId] / [baseName]; further parts append
  /// `-p1`, `-p2` and ` (2)`, ` (3)` so the course tree stays navigable.
  @visibleForTesting
  static List<Section> packUnitsIntoSections({
    required String baseSectionId,
    required String baseName,
    required String description,
    required List<Unit> units,
    int maxUnitsPerSection = kMaxUnitsPerSection,
  }) {
    if (units.isEmpty) return const [];
    final max = maxUnitsPerSection < 1 ? 1 : maxUnitsPerSection;
    if (units.length <= max) {
      return [
        Section(
          id: baseSectionId,
          name: baseName,
          description: description,
          level: 'Anki',
          prerequisiteSectionIds: const [],
          units: units,
        ),
      ];
    }

    final sections = <Section>[];
    var part = 0;
    for (var i = 0; i < units.length; i += max) {
      final end = (i + max).clamp(0, units.length);
      final slice = units.sublist(i, end);
      sections.add(Section(
        id: part == 0 ? baseSectionId : '$baseSectionId-p$part',
        name: '$baseName (${part + 1})',
        description: description,
        level: 'Anki',
        prerequisiteSectionIds: const [],
        units: slice,
      ));
      part++;
    }
    return sections;
  }

  /// Section-Beta grouping algorithm, version 1. Evidence priority:
  ///   1. explicit section/chapter/章 field or tag (card-level, tallied per
  ///      unit in [cardSectionByUnit] — majority wins);
  ///   2. unit-name prefix such as "Chapter 1", "Ch.2", "第 3 章";
  ///   3. no evidence -> the historical [packUnitsIntoSections] safety
  ///      chunk, which is NOT semantic grouping.
  /// Units with the same section key share one Section (id suffix `-secN`,
  /// capped at [maxUnitsPerSection] per section with `-pN` overflow parts).
  @visibleForTesting
  static List<Section> buildSemanticSections({
    required String baseSectionId,
    required String baseName,
    required String description,
    required List<Unit> units,
    Map<String, String> cardSectionByUnit = const {},
    int maxUnitsPerSection = kMaxUnitsPerSection,
  }) {
    if (units.isEmpty) return const [];

    // Bucket units by section key in first-seen order; null keeps the base
    // bucket that preserves the historical section id/name.
    final bucketOrder = <String?>[];
    final buckets = <String?, List<Unit>>{};
    final displayNames = <String, String>{};
    for (final unit in units) {
      final derived = AnkiOrganizationResolver.sectionKeyFromUnitName(
        unit.name,
      );
      final key = cardSectionByUnit[unit.name] ?? derived?.$1;
      if (!buckets.containsKey(key)) {
        buckets[key] = [];
        bucketOrder.add(key);
        if (key != null && derived != null && derived.$1 == key) {
          displayNames[key] = derived.$2;
        }
      }
      buckets[key]!.add(unit);
    }

    final semanticCount =
        bucketOrder.whereType<String>().toList().length;
    if (semanticCount == 0) {
      return packUnitsIntoSections(
        baseSectionId: baseSectionId,
        baseName: baseName,
        description: description,
        units: units,
        maxUnitsPerSection: maxUnitsPerSection,
      );
    }

    final sections = <Section>[];
    var secIdx = 0;
    for (final key in bucketOrder) {
      final bucketUnits = buckets[key]!;
      if (key == null) {
        sections.addAll(packUnitsIntoSections(
          baseSectionId: baseSectionId,
          baseName: baseName,
          description: description,
          units: bucketUnits,
          maxUnitsPerSection: maxUnitsPerSection,
        ));
        continue;
      }
      final id = '$baseSectionId-sec$secIdx';
      final name = displayNames[key] ?? key;
      sections.addAll(packUnitsIntoSections(
        baseSectionId: id,
        baseName: name,
        description: '$description;grouping=section-beta-v1',
        units: bucketUnits,
        maxUnitsPerSection: maxUnitsPerSection,
      ));
      secIdx++;
    }
    return sections;
  }

  static String? _majoritySection(Map<String, int> tally) {
    String? best;
    var bestCount = 0;
    for (final e in tally.entries) {
      if (e.value > bestCount) {
        best = e.key;
        bestCount = e.value;
      }
    }
    return best;
  }

  /// Fallback unit name when a card carries no unit metadata.
  String _unitFallbackName(
      AnkiDeckInfo d, AnkiDeckInfo parent, bool noChildren) {
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
    required List<AnkiPracticeProjectionRecord> practiceProjections,
    required bool forceLazyCardRefs,
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

          final nt = notetypes[note.mid];
          final mode = nt == null
              ? AnkiRenderMode.hybrid
              : const AnkiRenderPolicy().decide(
                  notetype: nt,
                  note: note,
                  card: card,
                  mapping: mapping,
                );
          final wordId = 'anki-$importId-c${card.id}';
          final Interaction interaction;
          if (forceLazyCardRefs || mode == AnkiRenderMode.fidelity) {
            // Empty HTML is an intentional lazy reference. The renderer and
            // review assembler resolve it from the canonical NoteStore using
            // [wordId], preserving fidelity without duplicating large HTML in
            // every Lesson JSON row.
            interaction = Interaction.ankiHtmlCard(
              id: '$wordId-c${card.ord}',
              frontHtml: '',
              backHtml: '',
              sourceNoteId: '${note.id}',
              sourceCardId: '${card.id}',
              wordId: wordId,
            );
            practiceProjections.add(AnkiPracticeProjectionRecord(
              cardId: card.id,
              kind: 'canonical',
              status: mode == AnkiRenderMode.fidelity
                  ? 'fidelity_required'
                  : 'not_materialized',
              confidence: 1,
              evidence: {
                'renderMode': mode.name,
                'lazyCachePolicy': forceLazyCardRefs,
              },
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ));
          } else {
            final result = adapter.adapt(
              note,
              card,
              importId: importId,
              mapping: mapping,
              notetype: nt,
              distractors: distractors,
              frontDistractors: frontDistractors,
            );
            interaction = result.interaction;
            final isCanonical =
                interaction is AnkiCard || interaction is AnkiHtmlCard;
            practiceProjections.add(AnkiPracticeProjectionRecord(
              cardId: card.id,
              kind: isCanonical ? 'canonical' : 'structured',
              status: isCanonical ? 'fallback' : 'generated',
              confidence: isCanonical ? 1 : 0.9,
              evidence: {
                'mappingType': mapping.type.name,
                'renderMode': mode.name,
                'resolvedInteraction': interaction.runtimeType.toString(),
              },
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ));
            if (result.wordEntry != null) {
              wordEntries.add(result.wordEntry!);
            }
          }

          stages.add(Stage(
            id: '$unitId-l$chunkIdx-s$i',
            name: 'Card ${start + i + 1}',
            items: [interaction],
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

  int _tomorrowTimestamp() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day)
        .millisecondsSinceEpoch;
  }

  /// Return every nested child in stable map order. Anki deck exports are
  /// allowed to list grandchildren before parents, so this operates on the
  /// already-resolved parent ids rather than relying on JSON order.
  List<AnkiDeckInfo> _descendantsOf(
    int parentId,
    Map<int, AnkiDeckInfo> decks,
  ) {
    final result = <AnkiDeckInfo>[];
    final seen = <int>{};
    void visit(int id) {
      for (final child in decks.values.where((d) => d.parentId == id)) {
        if (!seen.add(child.id)) continue;
        result.add(child);
        visit(child.id);
      }
    }

    visit(parentId);
    return result;
  }

  /// Whether [deckId] or any of its descendant decks carries at least one
  /// card. Used to decide whether an empty Default deck (id=1) must still
  /// anchor a top-level section so its subdecks' cards get indexed.
  bool _deckTreeHasCards(
    int deckId,
    Map<int, AnkiDeckInfo> decks,
    Map<int, List<AnkiCardData>> cardsByDeck,
  ) {
    if ((cardsByDeck[deckId] ?? const []).isNotEmpty) return true;
    for (final desc in _descendantsOf(deckId, decks)) {
      if ((cardsByDeck[desc.id] ?? const []).isNotEmpty) return true;
    }
    return false;
  }

  String _schedulingJson(AnkiCardData card) => jsonEncode({
        'type': card.type,
        'queue': card.queue,
        'due': card.due,
        'ivl': card.ivl,
        'factor': card.factor,
        'reps': card.reps,
        'lapses': card.lapses,
        'left': card.left,
        'odue': card.odue,
        'odid': card.odid,
        'flags': card.flags,
        'data': card.data,
      });
}

/// A stable, user-reportable import invariant failure.
class AnkiImportValidationException implements Exception {
  final String code;
  final String message;
  final List<int> sourceIds;

  const AnkiImportValidationException({
    required this.code,
    required this.message,
    this.sourceIds = const [],
  });

  @override
  String toString() => sourceIds.isEmpty
      ? 'AnkiImportValidationException[$code]: $message'
      : 'AnkiImportValidationException[$code]: $message '
          '(source ids: ${sourceIds.take(20).join(', ')})';
}
