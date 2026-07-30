// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/section.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/domain/course/stage.dart';

/// Assembles Anki review sessions by collecting due Anki cards from the SRS
/// queue and packaging them into temporary [Lesson]s for [LessonViewModel].
///
/// Mirrors [DailyChallengeAssembler] but sorts by due date (most overdue first)
/// instead of random sampling. Each batch holds at most [batchSize] cards.
class AnkiReviewAssembler {
  final SrsProvider _srsProvider;
  final CourseProvider _courseProvider;

  /// Maximum cards per review batch.
  static const int batchSize = 20;

  /// Prefix used to identify Anki card word ids in the SRS queue.
  static const String ankiPrefix = 'anki-';

  AnkiReviewAssembler(this._srsProvider, this._courseProvider);

  /// Interactions indexed by Anki word id, populated by
  /// [preloadInteractions]. [assembleBatch] consults this map before
  /// falling back to scanning the in-memory section trees.
  final Map<String, Interaction> _preloadedInteractions = {};

  /// Load the card Interactions for the target Anki section(s).
  ///
  /// [assembleBatch] is synchronous and previously scanned
  /// [CourseProvider.allSections] — but those are shells (units empty) until
  /// [CourseProvider.ensureSectionLoaded] runs, and even then lessons carry
  /// metadata only (empty content) until their bodies are loaded via
  /// [CourseLoader.loadLessonById]. A freshly imported deck has neither, so
  /// every due card missed its Interaction and the review session wrongly
  /// reported "no cards due". Call this before [assembleBatch].
  Future<void> preloadInteractions({String? sectionId}) async {
    final targetImportId =
        sectionId == null ? null : importIdFromSectionId(sectionId);

    bool targets(Section section) =>
        section.id.startsWith(ankiPrefix) &&
        (targetImportId == null ||
            importIdFromSectionId(section.id) == targetImportId);

    // Load each target section's L1 tree straight from the loader (not via
    // CourseProvider.ensureSectionLoaded, which only resolves sections in
    // the active scope), then load every lesson body and index its items by
    // word id. Both loads are cached by CourseLoader, so repeat reviews of
    // the same deck are cheap.
    for (final shell in _courseProvider.allSections) {
      if (!targets(shell)) continue;
      final importId = importIdFromSectionId(shell.id);
      final l1 = await CourseLoader.loadSection(shell.id);
      for (final unit in l1.units) {
        for (final lesson in unit.lessons) {
          final full = await CourseLoader.loadLessonById(lesson.id);
          for (final stage in full.flattenedStages) {
            for (final item in stage.items) {
              // Interaction ids are "${wordId}-c${ord}" — index by word id.
              final cIdx = item.id.lastIndexOf('-c');
              if (cIdx > 0) {
                _preloadedInteractions[item.id.substring(0, cIdx)] = item;
              }
              // Anki cards also match by source note id — mirror the
              // fallback in [_findInteractionForWord].
              if (item is AnkiCard &&
                  (item.sourceNoteId?.isNotEmpty ?? false)) {
                _preloadedInteractions[
                    'anki-$importId-n${item.sourceNoteId}'] = item;
              }
            }
          }
        }
      }
    }
  }

  /// Collect all due Anki cards, optionally filtered by [sectionId].
  ///
  /// Returns word ids sorted by due date (most overdue first).
  List<SrsWord> collectDue({String? sectionId}) {
    final dueWords = _srsProvider.getDueWords();

    final ankiDue = dueWords.where((w) {
      if (!w.wordId.startsWith(ankiPrefix)) return false;
      if (sectionId == null) return true;
      // Filter by section: wordId format is "anki-<importId>-n<noteId>"
      // Section id format is "anki-<importId>-s<deckId>"
      // Match on importId prefix
      final importId = _extractImportId(w.wordId);
      final sectionImportId = _extractImportIdFromSection(sectionId);
      return importId == sectionImportId;
    }).toList();

    // Sort by due date (most overdue first)
    ankiDue.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return ankiDue;
  }

  /// Number of due Anki cards, optionally filtered by section.
  int dueCount({String? sectionId}) => collectDue(sectionId: sectionId).length;

  /// Assemble the next batch of due cards into a temporary [Lesson].
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
    var due = collectDue(sectionId: sectionId);
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

    // Collect interactions for this batch by looking up lesson content
    final interactions = <Interaction>[];
    for (final srsWord in batch) {
      final interaction = _preloadedInteractions[srsWord.wordId] ??
          _findInteractionForWord(srsWord.wordId);
      if (interaction != null) {
        interactions.add(interaction.copyWith(id: 'anki-review-${srsWord.wordId}'));
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

  /// Due count per section (sectionId → count).
  Map<String, int> dueCountBySection() {
    final due = collectDue();
    final result = <String, int>{};

    for (final word in due) {
      final importId = _extractImportId(word.wordId);
      if (importId.isEmpty) continue;
      // Group by import id (sections share the same import id)
      result[importId] = (result[importId] ?? 0) + 1;
    }

    return result;
  }

  // ─── Private helpers ───────────────────────────────────────────────

  /// Fallback interaction lookup: find the Interaction for a given Anki word
  /// id by searching sections whose lesson bodies happen to be loaded in
  /// memory. The primary path is [_preloadedInteractions] (populated by
  /// [preloadInteractions]); this scan stays for callers that never preload.
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
              // Match AnkiCard by sourceNoteId or by id prefix
              if (item is AnkiCard) {
                final expectedPrefix = wordId;
                if (item.id.startsWith(expectedPrefix) ||
                    item.sourceNoteId == _extractNoteId(wordId)) {
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

  /// Extract import id from a word id: "anki-<importId>-n<noteId>" → importId
  String _extractImportId(String wordId) {
    // Format: anki-<importId>-n<noteId>
    final parts = wordId.split('-');
    if (parts.length >= 3) {
      // Rejoin all parts between first "anki-" and last "-n..."
      final nIdx = wordId.lastIndexOf('-n');
      if (nIdx > 5) {
        return wordId.substring(5, nIdx);
      }
    }
    return '';
  }

  /// Extract import id from a section id: "anki-<importId>-s<deckId>" → importId
  String _extractImportIdFromSection(String sectionId) =>
      importIdFromSectionId(sectionId);

  /// Public static form of [_extractImportIdFromSection], for UI code that
  /// needs the import id behind a section (e.g. deck uninstall).
  static String importIdFromSectionId(String sectionId) {
    final sIdx = sectionId.lastIndexOf('-s');
    if (sIdx > 5) {
      return sectionId.substring(5, sIdx);
    }
    return '';
  }

  /// Extract note id from word id: "anki-<importId>-n<noteId>" → noteId
  String _extractNoteId(String wordId) {
    final nIdx = wordId.lastIndexOf('-n');
    if (nIdx >= 0 && nIdx + 2 < wordId.length) {
      return wordId.substring(nIdx + 2);
    }
    return '';
  }
}
