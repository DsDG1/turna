// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_question.freezed.dart';
part 'reading_question.g.dart';

/// Three reading-question variants for [LessonContent.reading].
@freezed
sealed class ReadingQuestion with _$ReadingQuestion {
  const factory ReadingQuestion.mcq({
    required String prompt,
    required List<String> options,
    required int correctIndex,
  }) = ReadingMcq;

  const factory ReadingQuestion.trueFalse({
    required String statement,
    required bool answer,
  }) = ReadingTrueFalse;

  const factory ReadingQuestion.shortAnswer({
    required String prompt,
    required String expectedAnswer,
  }) = ReadingShortAnswer;

  factory ReadingQuestion.fromJson(Map<String, dynamic> json) =>
      _$ReadingQuestionFromJson(json);
}