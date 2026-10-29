// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'interaction.dart';
import 'lesson_content.dart';
import 'lesson_segment.dart';
import 'listening_phase.dart';
import 'stage.dart';

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
abstract class Lesson with _$Lesson {
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

  /// True when the lesson is authored as several self-contained sub-lessons
  /// ("小课") rather than one flat flow. This is the flag the lesson walker
  /// keys on: segmented lessons pause at each sub-lesson boundary.
  bool get hasSubLessons => content.subLessons.isNotEmpty;

  /// The lesson's playable segments, in order.
  ///
  /// The shape is derived from [template]:
  /// - intro / practice / review / legacy **with sub-lessons**: one segment
  ///   per sub-lesson, each with the sub-lesson's stages.
  /// - listening: one segment holding the phase-flattened stages.
  /// - everything else: one segment holding [content.stages].
  ///
  /// Review previously played only [content.stages], which left a review
  /// lesson authored with sub-lessons alone (the shape the authoring contract
  /// and the AI pipeline both produce) with nothing to play; sub-lessons now
  /// take precedence for every template that allows them.
  List<LessonSegment> get segments {
    final subs = content.subLessons;
    if (subs.isNotEmpty && template != LessonTemplate.listening) {
      if (template == LessonTemplate.intro ||
          template == LessonTemplate.practice ||
          template == LessonTemplate.review ||
          template == LessonTemplate.legacy) {
        return [
          for (final sub in subs)
            LessonSegment(
              subLessonId: sub.id,
              name: sub.name,
              stages: [
                for (final stage in sub.stages)
                  stage.copyWith(
                    id: 'sub-${sub.id}-${stage.id}',
                    name: '${sub.name} > ${stage.name}',
                  ),
              ],
            ),
        ];
      }
    }
    if (template == LessonTemplate.listening) {
      return [
        LessonSegment(
          name: name,
          stages: _flattenListeningPhases(content.listeningPhases),
        ),
      ];
    }
    return [LessonSegment(name: name, stages: content.stages)];
  }

  /// A single flat list of [Stage]s that the lesson renderer can walk: all
  /// segments' stages concatenated.
  List<Stage> get flattenedStages => [
        for (final segment in segments) ...segment.stages,
      ];

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
