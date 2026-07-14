// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'reading_passage.freezed.dart';
part 'reading_passage.g.dart';

/// A structured reading passage used by reading lessons.
@freezed
class ReadingPassage with _$ReadingPassage {
  const factory ReadingPassage({
    /// Passage title.
    required String title,

    /// Paragraphs of the passage.
    @Default(<String>[]) List<String> paragraphs,

    /// Approximate CEFR difficulty: 1=A1, 2=A2, 3=B1, 4=B2, etc.
    @Default(1) int difficulty,

    /// IDs of words introduced or highlighted in this passage.
    @Default(<String>[]) List<String> linkedWordIds,

    /// IDs of expressions highlighted in this passage.
    @Default(<String>[]) List<String> linkedExpressionIds,
  }) = _ReadingPassage;

  factory ReadingPassage.fromJson(Map<String, dynamic> json) =>
      _$ReadingPassageFromJson(json);
}
