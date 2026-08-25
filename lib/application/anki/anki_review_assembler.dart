// Project imports:
import 'package:turna/application/anki/anki_canonical_card_loader.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/course/stage.dart';

/// One legacy Anki scheduling row paired with its canonical render content.
/// Review UI consumes this directly instead of manufacturing a course Lesson.
class AnkiReviewBatchCard {
  const AnkiReviewBatchCard({
    required this.scheduled,
    required this.interaction,
  });

  final SrsWord scheduled;
  final Interaction interaction;
}

/// Assembles Anki review sessions by collecting due Anki cards from the SRS
/// queue and packaging them into temporary [Lesson]s for [LessonViewModel].
///
/// Mirrors [DailyChallengeAssembler] but sorts by due date (most overdue first)
/// instead of random sampling. Each batch holds at most [batchSize] cards.
///
/// Large decks (thousands of cards) are handled by loading only the lesson
/// bodies that contain the batch's word ids — never the whole deck.
class AnkiReviewAssembler {
  final SrsProvider _srsProvider;
  final CourseProvider _courseProvider;
  final AnkiNoteDao? _noteDao;
  final AnkiCanonicalCardLoader? _canonicalLoader;

  /// Maximum cards per review batch.
  static const int batchSize = 20;

  /// Prefix used to identify Anki card word ids in the SRS queue.
  static const String ankiPrefix = LegacyAnkiIdentifiers.ankiPrefix;

  /// [noteDao] enables the fidelity review path: cards whose
  /// `anki_cards_meta.render_mode` is `fidelity` are rendered on demand from
  /// the NoteStore (deep-adaptation plan §3.4) instead of loaded from lesson
  /// bodies. Null in tests that only exercise the structured path.
  AnkiReviewAssembler(this._srsProvider, this._courseProvider,
      {AnkiNoteDao? noteDao})
      : _noteDao = noteDao,
        _canonicalLoader =
            noteDao == null ? null : AnkiCanonicalCardLoader(noteDao);

  /// Interactions indexed by Anki word id, populated by
  /// [preloadInteractionsFor] / [assembleBatchAsync]. [assembleBatch]
  /// consults this map before falling back to scanning in-memory trees.
  final Map<String, Interaction> _preloadedInteractions = {};

  /// Load Interactions only for the given [wordIds] (typically one review
  /// batch of ≤20). Uses a content_json substring query so a 5k-card deck
  /// does not require 250 sequential lesson body loads.
  ///
  /// Prefer [assembleBatchAsync], which selects the batch then calls this.
  Future<void> preloadInteractionsFor(Iterable<String> wordIds) async {
    final missing = <String>[
      for (final id in wordIds)
        if (id.isNotEmpty && !_preloadedInteractions.containsKey(id)) id,
    ];
    if (missing.isEmpty) return;

    // The primary Anki review path is always canonical, independent of any
    // optional structured practice projection stored in course lessons.
    if (_canonicalLoader != null) {
      for (final id in missing) {
        final canonical = await _loadFidelityInteraction(id);
        if (canonical != null) _preloadedInteractions[id] = canonical;
      }
    }

    final unresolved =
        missing.where((id) => !_preloadedInteractions.containsKey(id)).toList();
    if (unresolved.isEmpty) return;
    final lessons = await CourseLoader.loadLessonsContainingAny(unresolved);
    for (final full in lessons) {
      _indexLessonInteractions(full);
    }
  }

  /// Build an [Interaction.ankiHtmlCard] for a due card not found in lesson
  /// bodies by loading its note + notetype from the NoteStore and rendering via
  /// [AnkiCardHtmlRenderer]. This is the fidelity review path (deep-adaptation
  /// plan §3.4): in Full-tree mode it serves cards the policy routed to
  /// fidelity (skipped in lessons); in Lite mode (no lessons) it serves every
  /// card as a fidelity flip. Returns null if [wordId] has no NoteStore data.
  Future<Interaction?> _loadFidelityInteraction(String wordId) async {
    return _canonicalLoader?.load(wordId);
  }

  /// @Deprecated Prefer [assembleBatchAsync] or [preloadInteractionsFor].
  ///
  /// Historical full-deck preload. Kept for tests that explicitly want every
  /// interaction indexed; **do not call from review UI** — a 5k-card deck
  /// would load hundreds of lesson bodies and appear to hang.
  Future<void> preloadInteractions({String? sectionId}) async {
    final targetImportId =
        sectionId == null ? null : importIdFromSectionId(sectionId);

    bool targets(Section section) =>
        section.id.startsWith(ankiPrefix) &&
        (targetImportId == null ||
            importIdFromSectionId(section.id) == targetImportId);

    for (final shell in _courseProvider.allSections) {
      if (!targets(shell)) continue;
      final l1 = await CourseLoader.loadSection(shell.id);
      for (final unit in l1.units) {
        for (final lesson in unit.lessons) {
          final full = await CourseLoader.loadLessonById(lesson.id);
          _indexLessonInteractions(full);
        }
      }
    }
  }

  void _indexLessonInteractions(Lesson full) {
    // Interaction ids are "${wordId}-c${ord}" where wordId is the card-level
    // `anki-<importId>-c<cardId>` (decision 2). Index by word id so a due
    // SrsWord resolves to its Interaction in O(1). A previous note-based
    // `anki-<importId>-n<noteId>` index was removed: every lookup is now
    // card-based and [_findInteractionForWord] no longer falls back to
    // sourceNoteId, so that entry was unreadable dead state.
    for (final stage in full.flattenedStages) {
      for (final item in stage.items) {
        final cIdx = item.id.lastIndexOf('-c');
        if (cIdx > 0) {
          _preloadedInteractions[item.id.substring(0, cIdx)] = item;
        }
      }
    }
  }

  /// Collect all due Anki cards, optionally filtered by [sectionId].
  ///
  /// Scans [SrsProvider.state] directly (not [SrsProvider.getDueWords]) so a
  /// 5k-card Anki import does not rebuild/sort the mixed language+Anki due
  /// list on every hub tile. Returns cards sorted by due date (most overdue
  /// first); leeches are deprioritized to the end.
  List<SrsWord> collectDue({
    String? sectionId,
    String? importId,
    DateTime? now,
  }) {
    final cutoff = now ?? DateTime.now();
    assert(sectionId == null || importId == null);
    final sectionImportId = importId ??
        (sectionId == null ? null : _extractImportIdFromSection(sectionId));

    final ankiDue = <SrsWord>[];
    final intro = CardIntroductionStore.resolve();
    for (final w in _srsProvider.state.values) {
      if (!w.wordId.startsWith(ankiPrefix)) continue;
      if (w.isSuspended || w.isBuried) continue;
      if (w.dueAt.isAfter(cutoff)) continue;
      if (sectionImportId != null &&
          _extractImportId(w.wordId) != sectionImportId) {
        continue;
      }
      if (!intro.isFormallyEligibleWord(w)) continue;
      ankiDue.add(w);
    }

    ankiDue.sort((a, b) {
      if (a.isLeech != b.isLeech) return a.isLeech ? 1 : -1;
      return a.dueAt.compareTo(b.dueAt);
    });
    return ankiDue;
  }

  /// Number of due Anki cards, optionally filtered by section.
  /// Prefer [dueCountBySection] on the hub to avoid N full scans.
  int dueCount({String? sectionId}) => collectDue(sectionId: sectionId).length;

  /// Select the next due batch and load only its Interactions from the DB.
  ///
  /// This is the production path for review sessions — O(batch) lesson body
  /// loads instead of O(deck) so multi-thousand-card decks open promptly.
  Future<Lesson?> assembleBatchAsync({
    String? sectionId,
    int offset = 0,
    int? count,
    int? maxNew,
    int? maxReview,
  }) async {
    final cards = await assembleReviewBatchAsync(
      sectionId: sectionId,
      offset: offset,
      count: count,
      maxNew: maxNew,
      maxReview: maxReview,
    );
    if (cards.isEmpty) return null;
    return _buildLessonFromDue(cards.map((card) => card.scheduled).toList());
  }

  /// Production review batch without the historical synthetic-Lesson layer.
  Future<List<AnkiReviewBatchCard>> assembleReviewBatchAsync({
    String? sectionId,
    String? importId,
    int offset = 0,
    int? count,
    int? maxNew,
    int? maxReview,
  }) async {
    assert(sectionId == null || importId == null);
    var candidates = collectDue(sectionId: sectionId, importId: importId);
    if (sectionId != null && _noteDao != null) {
      final importId = importIdFromSectionId(sectionId);
      final rootDid = _deckIdFromSectionId(sectionId);
      if (importId.isNotEmpty && rootDid != null) {
        // Filter to the deck subtree in two queries (deck ids + their word
        // ids) + an in-memory set membership test, instead of an N+1
        // `cardMetaByWordId` lookup per due candidate. Without this a 500-due
        // card batch issued 500 sequential reads every time a review session
        // opened, before _sliceDueBatch capped the batch at 20.
        final allowed =
            await _noteDao.deckIdsIncludingDescendants(importId, rootDid);
        final allowedWordIds =
            await _noteDao.wordIdsForDecks(importId, allowed);
        candidates =
            candidates.where((w) => allowedWordIds.contains(w.wordId)).toList();
      }
    }
    final due = _sliceDueBatch(
      candidates,
      sectionId: sectionId,
      offset: offset,
      count: count,
      maxNew: maxNew,
      maxReview: maxReview,
    );
    if (due == null || due.isEmpty) return const <AnkiReviewBatchCard>[];

    await preloadInteractionsFor(due.map((w) => w.wordId));
    final cards = <AnkiReviewBatchCard>[];
    for (final scheduled in due) {
      final interaction = _preloadedInteractions[scheduled.wordId] ??
          _findInteractionForWord(scheduled.wordId);
      if (interaction == null) continue;
      cards.add(
        AnkiReviewBatchCard(
          scheduled: scheduled,
          interaction: interaction.copyWith(
            id: 'anki-review-${scheduled.wordId}',
          ),
        ),
      );
    }
    return cards;
  }

  /// Assemble the next batch of due cards into a temporary [Lesson].
  ///
  /// Synchronous: expects Interactions already in [_preloadedInteractions]
  /// (via [preloadInteractionsFor] / [preloadInteractions]) or loaded section
  /// trees. Prefer [assembleBatchAsync] from UI code.
  ///
  /// [maxNew] / [maxReview] cap how many new (reps == 0) and review
  /// (reps > 0) cards may enter the batch — pass the daily remaining quotas
  /// from `AnkiDeckManager` to enforce per-day limits.
  ///
  /// Returns `null` if no cards are due.
  Lesson? assembleBatch({
    String? sectionId,
    int offset = 0,
    int? count,
    int? maxNew,
    int? maxReview,
  }) {
    final due = _selectDueBatch(
      sectionId: sectionId,
      offset: offset,
      count: count,
      maxNew: maxNew,
      maxReview: maxReview,
    );
    if (due == null || due.isEmpty) return null;
    return _buildLessonFromDue(due);
  }

  List<SrsWord>? _selectDueBatch({
    String? sectionId,
    int offset = 0,
    int? count,
    int? maxNew,
    int? maxReview,
  }) {
    final due = collectDue(sectionId: sectionId);
    return _sliceDueBatch(
      due,
      sectionId: sectionId,
      offset: offset,
      count: count,
      maxNew: maxNew,
      maxReview: maxReview,
    );
  }

  List<SrsWord>? _sliceDueBatch(
    List<SrsWord> candidates, {
    String? sectionId,
    int offset = 0,
    int? count,
    int? maxNew,
    int? maxReview,
  }) {
    var due = candidates;
    if (due.isEmpty || offset >= due.length) return null;

    // Apply daily new/review caps before slicing the batch.
    if (maxNew != null || maxReview != null) {
      var newTaken = 0;
      var reviewTaken = 0;
      due = due.where((w) {
        if (w.reps == 0) {
          if (maxNew != null && newTaken >= maxNew) return false;
          newTaken++;
        } else {
          if (maxReview != null && reviewTaken >= maxReview) return false;
          reviewTaken++;
        }
        return true;
      }).toList();
      if (due.isEmpty || offset >= due.length) return null;
    }

    final batchCount = count ?? batchSize;
    final end = (offset + batchCount).clamp(0, due.length);
    final batch = due.sublist(offset, end);
    if (batch.isEmpty) return null;
    return batch;
  }

  Lesson? _buildLessonFromDue(List<SrsWord> batch) {
    final interactions = <Interaction>[];
    for (final srsWord in batch) {
      final interaction = _preloadedInteractions[srsWord.wordId] ??
          _findInteractionForWord(srsWord.wordId);
      if (interaction != null) {
        interactions
            .add(interaction.copyWith(id: 'anki-review-${srsWord.wordId}'));
      }
    }

    if (interactions.isEmpty) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final stage = Stage(
      id: 'anki-review-stage-$timestamp',
      name: 'Anki Review',
      items: interactions,
    );

    return Lesson(
      id: 'anki-review-$timestamp',
      name: 'Anki Review (${interactions.length} cards)',
      type: LessonType.review,
      template: LessonTemplate.legacy,
      content: LessonContent(stages: [stage]),
    );
  }

  /// Total due count across all Anki sections.
  int get totalAnkiDueCount => collectDue().length;

  /// Scheduler-due Anki cards that are not yet introduced in the course.
  int unintroducedDueCount({String? sectionId, DateTime? now}) {
    final cutoff = now ?? DateTime.now();
    final sectionImportId =
        sectionId == null ? null : _extractImportIdFromSection(sectionId);
    final intro = CardIntroductionStore.resolve();
    var n = 0;
    for (final w in _srsProvider.state.values) {
      if (!w.wordId.startsWith(ankiPrefix)) continue;
      if (w.isSuspended || w.isBuried) continue;
      if (w.dueAt.isAfter(cutoff)) continue;
      if (sectionImportId != null &&
          _extractImportId(w.wordId) != sectionImportId) {
        continue;
      }
      if (intro.isFormallyEligibleWord(w)) continue;
      n++;
    }
    return n;
  }

  /// Due count keyed by import id (one scan). Hub tiles for multiple sections
  /// of the same import share a count — word ids only carry importId, not
  /// deck/section id.
  Map<String, int> dueCountBySection() {
    final cutoff = DateTime.now();
    final result = <String, int>{};
    final intro = CardIntroductionStore.resolve();
    for (final word in _srsProvider.state.values) {
      if (!word.wordId.startsWith(ankiPrefix)) continue;
      if (word.isSuspended || word.isBuried) continue;
      if (word.dueAt.isAfter(cutoff)) continue;
      if (!intro.isFormallyEligibleWord(word)) continue;
      final importId = _extractImportId(word.wordId);
      if (importId.isEmpty) continue;
      result[importId] = (result[importId] ?? 0) + 1;
    }
    return result;
  }

  /// Total due + per-import counts in one pass (hub cold path).
  ({int total, Map<String, int> byImportId}) dueSnapshot() {
    final byImport = dueCountBySection();
    var total = 0;
    for (final n in byImport.values) {
      total += n;
    }
    return (total: total, byImportId: byImport);
  }

  // ─── Private helpers ───────────────────────────────────────────────

  /// Fallback interaction lookup: find the Interaction for a given Anki word
  /// id by searching sections whose lesson bodies happen to be loaded in
  /// memory. The primary path is [_preloadedInteractions] (populated by
  /// [preloadInteractionsFor]); this scan stays for callers that never preload.
  Interaction? _findInteractionForWord(String wordId) {
    // The interaction id is "${wordId}-c${ord}" — search by prefix.
    // allSections: review must find cards even when the course scope hides
    // Anki decks from the Learn-page tree.
    for (final section in _courseProvider.allSections) {
      if (!section.id.startsWith('anki-')) continue;
      for (final unit in section.units) {
        for (final lesson in unit.lessons) {
          for (final stage in lesson.flattenedStages) {
            for (final item in stage.items) {
              // Match AnkiCard by id prefix (card-level wordId, decision 2).
              if (item is AnkiCard) {
                if (item.id.startsWith(wordId)) {
                  return item;
                }
              }
              // Also match other interaction types adapted from Anki
              if (item.id.startsWith(wordId)) {
                return item;
              }
            }
          }
        }
      }
    }
    return null;
  }

  /// Extract import id from a word id (card-level, decision 2):
  /// `anki-<importId>-c<cardId>`. The `<cardId>` segment is always last,
  /// so lastIndexOf('-c') finds the importId / cardId separator.
  String _extractImportId(String wordId) {
    final cIdx = wordId.lastIndexOf('-c');
    if (cIdx > 5) {
      return wordId.substring(5, cIdx);
    }
    return '';
  }

  /// Extract import id from a section id: `anki-<importId>-s<deckId>` → importId
  String _extractImportIdFromSection(String sectionId) =>
      importIdFromSectionId(sectionId);

  static String importIdFromWordId(String wordId) =>
      LegacyAnkiIdentifiers.importIdFromWordId(wordId);

  static String importIdFromSectionId(String sectionId) =>
      LegacyAnkiIdentifiers.importIdFromSectionId(sectionId);

  static int? _deckIdFromSectionId(String sectionId) {
    final sIdx = sectionId.lastIndexOf('-s');
    if (sIdx < 0) return null;
    final suffix = sectionId.substring(sIdx + 2).replaceFirst(
          RegExp(r'-p\d+$'),
          '',
        );
    return int.tryParse(suffix);
  }
}
