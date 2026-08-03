// Project imports:
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/stage.dart';

/// Result of assembling a mistake-review session.
///
/// [entryIds] is ordered 1:1 with the interactions in [lesson]'s single stage,
/// so a consumer can zip it with `LessonViewModel.questionResults` to learn
/// which source mistakes were answered correctly.
class MistakeReviewAssembly {
  final Lesson lesson;
  final List<String?> entryIds;

  const MistakeReviewAssembly({required this.lesson, required this.entryIds});
}

/// Builds a synthetic mistake-review lesson (ADR-aligned, mirrors
/// [WeakWordQuizAssembler] but reuses each mistake's frozen
/// `interactionSnapshot` so all mixed interaction types render through the
/// existing renderer dispatch).
///
/// Up to [maxItems] of the most recent mistakes with a non-null snapshot are
/// included. "做完则掌握" — the caller clears only the entries answered
/// correctly, using [entryIds] to map results back.
class MistakeReviewAssembler {
  static const String lessonId = 'mistake-review';
  static const String stageId = 'mistake-review-stage';
  static const int defaultMaxItems = 10;

  /// Assemble a graded review lesson from [entries].
  ///
  /// [entries] is taken in reverse-chronological order (most recent first) so
  /// the newest mistakes are reviewed first. Entries without a snapshot are
  /// skipped; their position in [entryIds] is `null` only when [entries] is
  /// already filtered — here we skip them entirely, so [entryIds] has no nulls.
  static MistakeReviewAssembly assemble(
    List<MistakeEntry> entries, {
    int maxItems = defaultMaxItems,
  }) {
    // Most recent first (entries is FIFO oldest→newest).
    final sorted = entries.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final items = <Interaction>[];
    final entryIds = <String?>[];

    for (final entry in sorted) {
      if (items.length >= maxItems) break;
      final snapshot = entry.interactionSnapshot;
      if (snapshot == null) continue;
      // Re-id the snapshot so synthetic ids are unique and mappable back to
      // the source mistake. Every interaction variant shares the `id` field.
      items.add(snapshot.copyWith(id: 'mistake-review-${entry.id}'));
      entryIds.add(entry.id);
    }

    final lesson = Lesson(
      id: lessonId,
      name: 'Mistake Review',
      type: LessonType.review,
      template: LessonTemplate.legacy,
      content: LessonContent(
        stages: [Stage(id: stageId, name: 'Mistake Review', items: items)],
      ),
    );

    return MistakeReviewAssembly(lesson: lesson, entryIds: entryIds);
  }
}