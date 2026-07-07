// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'stage.dart';

part 'lesson_content.freezed.dart';
part 'lesson_content.g.dart';

/// Lesson content variants match [LessonType] one-to-one.
/// Reading lessons hold [ReadingStage]s (typed items), others hold [Stage]s
/// (whose `items` are [Interaction]s).
@freezed
sealed class LessonContent with _$LessonContent {
  const factory LessonContent.normal({
    required List<Stage> stages,
  }) = NormalContent;

  const factory LessonContent.listening({
    required String audioAsset,
    required List<Stage> stages,
  }) = ListeningContent;

  const factory LessonContent.reading({
    required String text,
    required List<ReadingStage> stages,
  }) = ReadingContent;

  const factory LessonContent.review({
    required List<Stage> stages,
  }) = ReviewContent;

  const factory LessonContent.challenge({
    required List<Stage> stages,
  }) = ChallengeContent;

  factory LessonContent.fromJson(Map<String, dynamic> json) =>
      _$LessonContentFromJson(json);
}