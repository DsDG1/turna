// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'interaction.dart';

part 'stage.freezed.dart';
part 'stage.g.dart';

/// A group of [Interaction]s inside a lesson.
///
/// `makeCollectionsUnmodifiable: false` lets callers mutate `items` if
/// needed; the loader is the only writer in practice.
@Freezed(makeCollectionsUnmodifiable: false)
abstract class Stage with _$Stage {
  const factory Stage({
    required String id,
    required String name,
    @Default('') String description,
    @Default(<String>[]) List<String> prerequisiteStageIds,
    required List<Interaction> items,
  }) = _Stage;

  factory Stage.fromJson(Map<String, dynamic> json) => _$StageFromJson(json);
}
