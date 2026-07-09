// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'interaction.dart';
import 'lesson_content.dart';
import 'listening_phase.dart';
import 'stage.dart';
import 'sub_lesson.dart';

part 'lesson.freezed.dart';
part 'lesson.g.dart';

/// Lesson type — drives presentation (icon / color / label in the course
/// tree). Every type shares one [LessonContent] shape; the type tag itself
/// carries no structural difference.
enum LessonType {
  normal,
  listening,
  reading,
  review,
  challenge,
}

/// Lesson template — describes the pedagogical structure of the lesson.
///
/// Unlike [LessonType], which is purely presentational, the template can be
/// used by the loader/renderer to pick the right content shape (e.g. sub-lessons
/// for intro lessons, listening phases for listening lessons).
enum LessonTemplate {
  /// Four sub-lessons introducing new knowledge/vocab/expressions.
  intro,

  /// Three-phase listening lesson.
  listening,

  /// Four sub-lessons practicing prior intro content, harder.
  practice,

  /// Reading passage + comprehension questions.
  reading,

  /// Mixed review sub-lessons.
  review,

  /// Single mastery check with pass threshold.
  mastery,

  /// Fallback for legacy lessons that use a flat stage list.
  legacy,
}

/// A single lesson inside a unit. [content] holds the stages (and, for
/// reading lessons, the passage). All lesson types use the same
/// [LessonContent] model.
@freezed
class Lesson with _$Lesson {
  const factory Lesson({
    required String id,
    required String name,
    @Default('') String description,
    @Default(LessonType.normal) LessonType type,

    /// Pedagogical template. If omitted, the loader/renderer fall back to
    /// a flat stage list for backward compatibility.
    @Default(LessonTemplate.legacy) LessonTemplate template,
    @Default(<String>[]) List<String> prerequisiteLessonIds,
    required LessonContent content,
  }) = _Lesson;

  const Lesson._();

  factory Lesson.fromJson(Map<String, dynamic> json) => _$LessonFromJson(json);

  /// True if this is a mastery-check lesson.
  bool get isMastery => template == LessonTemplate.mastery;

  /// A single flat list of [Stage]s that the lesson renderer can walk.
  ///
  /// The shape is derived from [template]:
  /// - legacy / normal / review / mastery: [content.stages]
  /// - intro / practice: flattened [content.subLessons]
  /// - listening: flattened [content.listeningPhases]
  /// - reading: [content.stages] (questions); [content.readingPassage] is
  ///   rendered separately by the lesson screen.
  List<Stage> get flattenedStages {
    switch (template) {
      case LessonTemplate.legacy:
      case LessonTemplate.review:
      case LessonTemplate.mastery:
        return content.stages;
      case LessonTemplate.intro:
      case LessonTemplate.practice:
        return _flattenSubLessons(content.subLessons);
      case LessonTemplate.listening:
        return _flattenListeningPhases(content.listeningPhases);
      case LessonTemplate.reading:
        return content.stages;
    }
  }

  static List<Stage> _flattenSubLessons(List<SubLesson> subLessons) {
    final result = <Stage>[];
    for (final sub in subLessons) {
      for (final stage in sub.stages) {
        result.add(stage.copyWith(
          id: 'sub-${sub.id}-${stage.id}',
          name: '${sub.name} > ${stage.name}',
        ));
      }
    }
    return result;
  }

  static List<Stage> _flattenListeningPhases(List<ListeningPhase> phases) {
    final result = <Stage>[];
    for (final phase in phases) {
      result.add(Stage(
        id: 'lp-${phase.id}',
        name: phase.name,
        items: phase.type == ListeningPhaseType.summary
            ? _summaryItems(phase)
            : phase.items,
      ));
    }
    return result;
  }

  /// Summary phases may have empty [ListeningPhase.items]; synthesize a
  /// single [ListenOnly] interaction so the lesson walker can finish the
  /// course without a special-cased screen.
  static List<Interaction> _summaryItems(ListeningPhase phase) {
    if (phase.items.isNotEmpty) return phase.items;
    return [
      Interaction.listenOnly(
        id: '${phase.id}-listen',
        audioAsset: phase.audioAsset,
        transcript: phase.transcript,
        prompt: 'Listen to the summary',
      ),
    ];
  }
}