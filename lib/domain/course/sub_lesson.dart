// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'stage.dart';

part 'sub_lesson.freezed.dart';
part 'sub_lesson.g.dart';

/// A sub-lesson is a self-contained mini-flow inside a [Lesson].
///
/// Used by lesson templates such as "intro" (4 sub-lessons) or "review"
/// (3 sub-lessons), where each sub-lesson introduces or practices a small
/// chunk of content and can be completed independently.
@freezed
class SubLesson with _$SubLesson {
  const factory SubLesson({
    required String id,
    required String name,
    @Default('') String description,

    /// Ordering index within the parent lesson.
    @Default(0) int sortOrder,

    /// The interactions that make up this sub-lesson.
    @Default(<Stage>[]) List<Stage> stages,
  }) = _SubLesson;

  factory SubLesson.fromJson(Map<String, dynamic> json) =>
      _$SubLessonFromJson(json);
}
