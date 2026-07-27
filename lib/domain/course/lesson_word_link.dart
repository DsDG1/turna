// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'lesson_word_link.freezed.dart';
part 'lesson_word_link.g.dart';

/// The kind of learning item that was linked to a lesson.
enum LinkType {
  word,
  expression,
  grammarPoint,
}

/// Records where a word, expression, or grammar point was first encountered.
@freezed
abstract class LessonWordLink with _$LessonWordLink {
  const factory LessonWordLink({
    required String wordId,
    required String lessonId,
    required String lessonName,
    @Default(LinkType.word) LinkType type,
    required DateTime firstSeenAt,
  }) = _LessonWordLink;

  factory LessonWordLink.fromJson(Map<String, dynamic> json) =>
      _$LessonWordLinkFromJson(json);
}
