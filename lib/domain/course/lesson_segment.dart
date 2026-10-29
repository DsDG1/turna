// Project imports:
import 'package:turna/domain/course/stage.dart';

/// One playable segment of a [Lesson].
///
/// A lesson authored with sub-lessons splits into one segment per sub-lesson:
/// each is a self-contained mini-lesson ("小课") with the volume of a classic
/// lesson, and finishing one is a pause point — the walker reports its result
/// and waits for the player to continue. Every other lesson shape (flat
/// stages, listening phases, reading) is a single segment spanning the whole
/// lesson, so the segmented and flat paths share one walker.
///
/// Derived by [Lesson.segments]; never serialized, so this is a plain
/// immutable class rather than a freezed model.
final class LessonSegment {
  const LessonSegment({
    required this.name,
    required this.stages,
    this.subLessonId,
  });

  /// The [SubLesson.id] this segment plays, or null when the segment is the
  /// whole lesson. Sub-lesson completion is persisted under this id.
  final String? subLessonId;

  /// Display name shown while the segment plays and on its result dialog.
  final String name;

  /// The segment's stages, already flattened from their source shape (the
  /// sub-lesson's stage ids carry the `sub-` prefix, same as the legacy
  /// [Lesson.flattenedStages] composition).
  final List<Stage> stages;

  bool get isSubLesson => subLessonId != null;
}
