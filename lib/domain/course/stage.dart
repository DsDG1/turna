// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'interaction.dart';
import 'reading_question.dart';

part 'stage.freezed.dart';
part 'stage.g.dart';

/// Stage of [Interaction]s inside a lesson. Used by NormalContent,
/// ListeningContent, ReviewContent, and ChallengeContent.
///
/// Freezed doesn't support generics, so we use a concrete type that holds
/// [Interaction] items. Reading lessons use [ReadingStage] instead.
@Freezed(makeCollectionsUnmodifiable: false)
class Stage with _$Stage {
  const factory Stage({
    required String id,
    required String name,
    @Default('') String description,
    @Default(<String>[]) List<String> prerequisiteStageIds,
    required List<Interaction> items,
  }) = _Stage;

  factory Stage.fromJson(Map<String, dynamic> json) => _$StageFromJson(json);
}

/// Reading-specific stage typed to [ReadingQuestion].
@freezed
class ReadingStage with _$ReadingStage {
  const factory ReadingStage({
    required String id,
    required String name,
    @Default('') String description,
    @Default(<String>[]) List<String> prerequisiteStageIds,
    required List<ReadingQuestion> items,
  }) = _ReadingStage;

  factory ReadingStage.fromJson(Map<String, dynamic> json) =>
      _$ReadingStageFromJson(json);
}