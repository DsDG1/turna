// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'interaction.freezed.dart';
part 'interaction.g.dart';

/// Every exercise type in a lesson — both the practice "interactions" and
/// the reading-comprehension questions. Merging them into one sealed union
/// means the [LessonViewModel] iterates a single `List<Interaction>` and the
/// renderer registry dispatches every type the same way (see
/// [InteractionRenderer]).
///
/// Each variant carries a stable [id] (defaulted to `''` for backward
/// compatibility with data authored before ids were added). When [id] is
/// non-empty it is used by [interactionItemId] as the synthetic key for
/// tracking per-item state; an empty id falls back to `legacy-$index`.
///
/// Optional [grammarPointId] links an exercise to a grammar point for
/// mistake → grammar-review cross-routing.
@freezed
sealed class Interaction with _$Interaction {
  /// Show a vocabulary item, optionally with context sentence.
  const factory Interaction.showWord({
    @Default('') String id,
    required String wordId,
    String? context,
    String? grammarPointId,
    String? expressionId,
  }) = ShowWord;

  /// Choose one option out of N.
  const factory Interaction.multipleChoice({
    @Default('') String id,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? imageAsset,
    String? grammarPointId,
  }) = MultipleChoice;

  /// Choose one or more options out of N.
  ///
  /// Used for listening exercises such as "select the 3 words you heard".
  /// [correctIndices] lists the zero-based indices of all correct options.
  /// [minSelections] / [maxSelections] constrain how many options the learner
  /// must pick before submitting.
  const factory Interaction.multiSelect({
    @Default('') String id,
    required String prompt,
    required List<String> options,
    required List<int> correctIndices,
    @Default(1) int minSelections,
    @Default(2147483647) int maxSelections,
    String? imageAsset,
    String? grammarPointId,
  }) = MultiSelect;

  /// Fill in the blanked word(s) in a sentence.
  const factory Interaction.fillBlank({
    @Default('') String id,
    required String sentence,
    required String answer,
    String? hint,
    String? grammarPointId,
  }) = FillBlank;

  /// Translate a source sentence into the expected target.
  const factory Interaction.translateSentence({
    @Default('') String id,
    required String source,
    required String expected,
    @Default(<String>[]) List<String> hints,
    String? grammarPointId,
  }) = TranslateSentence;

  /// Listen to [audioAsset], then pick the correct option.
  const factory Interaction.listenAndPick({
    @Default('') String id,
    required String audioAsset,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? grammarPointId,
  }) = ListenAndPick;

  /// Listen to [audioAsset], then type the expected word/sentence.
  const factory Interaction.typeTheWord({
    @Default('') String id,
    required String audioAsset,
    required String prompt,
    required String expected,
    String? grammarPointId,
  }) = TypeTheWord;

  /// Listen-only card (e.g. listening-lesson summary phase). No grading —
  /// the user plays audio / TTS and continues.
  const factory Interaction.listenOnly({
    @Default('') String id,
    String? audioAsset,
    @Default('') String transcript,
    @Default('Listen to the summary') String prompt,
    String? grammarPointId,
  }) = ListenOnly;

  /// Reorder scrambled tokens into the canonical sentence.
  const factory Interaction.reorderSentence({
    @Default('') String id,
    required List<String> scrambled,
    required List<String> correct,
    String? grammarPointId,
  }) = ReorderSentence;

  /// Reading-comprehension multiple choice. Rendered alongside an optional
  /// lesson-level passage (see [LessonContent.passage]).
  const factory Interaction.readingMcq({
    @Default('') String id,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? grammarPointId,
  }) = ReadingMcq;

  /// Reading-comprehension true / false.
  const factory Interaction.readingTrueFalse({
    @Default('') String id,
    required String statement,
    required bool answer,
    String? grammarPointId,
  }) = ReadingTrueFalse;

  /// Reading-comprehension free-text answer.
  const factory Interaction.readingShortAnswer({
    @Default('') String id,
    required String prompt,
    required String expectedAnswer,
    String? grammarPointId,
  }) = ReadingShortAnswer;

  factory Interaction.fromJson(Map<String, dynamic> json) =>
      _$InteractionFromJson(json);
}

/// Optional grammar-point link on any [Interaction] variant.
String? interactionGrammarPointId(Interaction interaction) {
  return switch (interaction) {
    ShowWord(:final grammarPointId) => grammarPointId,
    MultipleChoice(:final grammarPointId) => grammarPointId,
    MultiSelect(:final grammarPointId) => grammarPointId,
    FillBlank(:final grammarPointId) => grammarPointId,
    TranslateSentence(:final grammarPointId) => grammarPointId,
    ListenAndPick(:final grammarPointId) => grammarPointId,
    TypeTheWord(:final grammarPointId) => grammarPointId,
    ListenOnly(:final grammarPointId) => grammarPointId,
    ReorderSentence(:final grammarPointId) => grammarPointId,
    ReadingMcq(:final grammarPointId) => grammarPointId,
    ReadingTrueFalse(:final grammarPointId) => grammarPointId,
    ReadingShortAnswer(:final grammarPointId) => grammarPointId,
  };
}

/// Canonical correct-answer label for mistake logging / feedback.
String? interactionCorrectAnswerLabel(Interaction interaction) {
  return switch (interaction) {
    ShowWord(:final wordId) => wordId,
    MultipleChoice(:final options, :final correctIndex) =>
      options[correctIndex],
    MultiSelect(:final options, :final correctIndices) =>
      correctIndices.map((i) => options[i]).join(', '),
    FillBlank(:final answer) => answer,
    TranslateSentence(:final expected) => expected,
    ListenAndPick(:final options, :final correctIndex) => options[correctIndex],
    TypeTheWord(:final expected) => expected,
    ListenOnly() => null,
    ReorderSentence(:final correct) => correct.join(' '),
    ReadingMcq(:final options, :final correctIndex) => options[correctIndex],
    ReadingTrueFalse(:final answer) => answer.toString(),
    ReadingShortAnswer(:final expectedAnswer) => expectedAnswer,
  };
}

/// Short prompt label used in lesson-completion summaries to identify a
/// question. Falls back to a generic label when the interaction has no
/// meaningful prompt.
String interactionPromptLabel(Interaction interaction) {
  return switch (interaction) {
    ShowWord(:final wordId) => wordId,
    MultipleChoice(:final prompt) => prompt,
    MultiSelect(:final prompt) => prompt,
    FillBlank(:final sentence) => sentence,
    TranslateSentence(:final source) => source,
    ListenAndPick(:final prompt) => prompt,
    TypeTheWord(:final prompt) => prompt,
    ListenOnly(:final prompt) => prompt,
    ReorderSentence(:final scrambled) => scrambled.join(' '),
    ReadingMcq(:final prompt) => prompt,
    ReadingTrueFalse(:final statement) => statement,
    ReadingShortAnswer(:final prompt) => prompt,
  };
}
