// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
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
      final interaction = _findInteractionForWord(srsWord.wordId);
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

  /// Find the Interaction for a given Anki word id by searching loaded sections.
  Interaction? _findInteractionForWord(String wordId) {
    // The interaction id is "${wordId}-c${ord}" — search by prefix
    for (final section in _courseProvider.sections) {
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
