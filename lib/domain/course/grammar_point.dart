// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

// Project imports:
import 'package:varnamala/domain/course/interaction.dart';

part 'grammar_point.freezed.dart';
part 'grammar_point.g.dart';

List<Interaction> _practiceItemsFromJson(Object? json) {
  if (json is! List) return const <Interaction>[];
  return json
      .map((e) => Interaction.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}

List<Map<String, dynamic>> _practiceItemsToJson(List<Interaction> items) =>
    items.map((i) => i.toJson()).toList();

/// A grammar rule or pattern taught across one or more lessons.
///
/// Grammar points can enter the review system independently and can be linked
/// to example expressions or sentences. Optional [practiceItems] are short
/// drills shown during grammar review after the explanation card.
@freezed
class GrammarPoint with _$GrammarPoint {
  const factory GrammarPoint({
    required String id,

    /// Short title, e.g. "Present tense -a verb conjugation".
    required String title,

    /// Full explanation shown in lesson and review.
    @Default('') String explanation,

    /// IDs of expressions that exemplify this grammar point.
    @Default(<String>[]) List<String> exampleExpressionIds,

    /// IDs of example sentences (could be stored as expression ids or separate
    /// sentence ids in the future).
    @Default(<String>[]) List<String> exampleSentenceIds,

    /// Short practice drills for the grammar-review screen.
    @JsonKey(fromJson: _practiceItemsFromJson, toJson: _practiceItemsToJson)
    @Default(<Interaction>[])
    List<Interaction> practiceItems,
  }) = _GrammarPoint;

  factory GrammarPoint.fromJson(Map<String, dynamic> json) =>
      _$GrammarPointFromJson(json);
}
