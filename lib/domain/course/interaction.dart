// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'interaction.freezed.dart';
part 'interaction.g.dart';

/// Seven interaction types cover the full exercise taxonomy.
@freezed
sealed class Interaction with _$Interaction {
  /// Show a vocabulary item, optionally with context sentence.
  const factory Interaction.showWord({
    required String wordId,
    String? context,
  }) = ShowWord;

  /// Choose one option out of N.
  const factory Interaction.multipleChoice({
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? imageAsset,
  }) = MultipleChoice;

  /// Fill in the blanked word(s) in a sentence.
  const factory Interaction.fillBlank({
    required String sentence,
    required String answer,
    String? hint,
  }) = FillBlank;

  /// Translate a source sentence into the expected target.
  const factory Interaction.translateSentence({
    required String source,
    required String expected,
    @Default(<String>[]) List<String> hints,
  }) = TranslateSentence;

  /// Listen to [audioAsset], then pick the correct option.
  const factory Interaction.listenAndPick({
    required String audioAsset,
    required String prompt,
    required List<String> options,
    required int correctIndex,
  }) = ListenAndPick;

  /// Listen to [audioAsset], then type the expected word/sentence.
  const factory Interaction.typeTheWord({
    required String audioAsset,
    required String prompt,
    required String expected,
  }) = TypeTheWord;

  /// Reorder scrambled tokens into the canonical sentence.
  const factory Interaction.reorderSentence({
    required List<String> scrambled,
    required List<String> correct,
  }) = ReorderSentence;

  factory Interaction.fromJson(Map<String, dynamic> json) =>
      _$InteractionFromJson(json);
}