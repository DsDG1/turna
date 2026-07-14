// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

// Project imports:
import 'package:varnamala/domain/course/interaction.dart';

part 'mistake_entry.freezed.dart';
part 'mistake_entry.g.dart';

Interaction? _interactionSnapshotFromJson(Object? json) {
  if (json == null) return null;
  return Interaction.fromJson(Map<String, dynamic>.from(json as Map));
}

Object? _interactionSnapshotToJson(Interaction? interaction) =>
    interaction?.toJson();

/// A recorded wrong answer that the user can later revisit.
@freezed
class MistakeEntry with _$MistakeEntry {
  const factory MistakeEntry({
    required String id,

    /// The lesson this mistake happened in.
    required String lessonId,

    /// The stage id within the lesson (or sub-lesson id if applicable).
    required String stageId,

    /// The interaction id within the stage.
    required String interactionId,

    /// Related word id, if this mistake was tied to a vocabulary word.
    String? wordId,

    /// Related expression id, if this mistake was tied to an expression.
    String? expressionId,

    /// Related grammar point id for cross-routing into grammar review.
    String? grammarPointId,

    /// A snapshot of the interaction that produced this mistake, used to
    /// recreate it for practice.
    @JsonKey(
      fromJson: _interactionSnapshotFromJson,
      toJson: _interactionSnapshotToJson,
    )
    Interaction? interactionSnapshot,

    /// What the user answered.
    @Default('') String userAnswer,

    /// The correct answer.
    @Default('') String correctAnswer,

    /// When the mistake was made.
    required DateTime timestamp,

    /// How many times the user has rewritten this mistake correctly.
    @Default(0) int rewriteCount,
  }) = _MistakeEntry;

  factory MistakeEntry.fromJson(Map<String, dynamic> json) =>
      _$MistakeEntryFromJson(json);
}
