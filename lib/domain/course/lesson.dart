// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'lesson_content.dart';

part 'lesson.freezed.dart';
part 'lesson.g.dart';

/// Five lesson types map to five [LessonContent] variants.
enum LessonType {
  normal,
  listening,
  reading,
  review,
  challenge,
}

/// A single lesson inside a unit. Content is one of five typed variants.
@freezed
class Lesson with _$Lesson {
  const factory Lesson({
    required String id,
    required String name,
    @Default('') String description,
    @Default(LessonType.normal) LessonType type,
    @Default(<String>[]) List<String> prerequisiteLessonIds,
    required LessonContent content,
  }) = _Lesson;

  factory Lesson.fromJson(Map<String, dynamic> json) => _$LessonFromJson(json);
}