// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'expression.freezed.dart';
part 'expression.g.dart';

/// A multi-word expression or phrase in the target language.
///
/// Expressions are tracked separately from single [WordEntry]s because they
/// need their own SRS state, origin-lesson tracking, and TTS playback.
@freezed
class Expression with _$Expression {
  const factory Expression({
    required String id,

    /// The expression in the target language, e.g. "habari za asubuhi".
    required String term,

    /// English translation, e.g. "good morning".
    required String translation,

    /// Optional pronunciation hint.
    String? pronunciation,

    /// Optional pre-recorded audio asset; falls back to TTS if absent.
    String? audioAsset,

    /// Optional tags for grouping/filtering (e.g. "greeting", "travel").
    @Default(<String>[]) List<String> tags,
  }) = _Expression;

  factory Expression.fromJson(Map<String, dynamic> json) =>
      _$ExpressionFromJson(json);
}
