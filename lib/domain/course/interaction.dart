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
///
/// `@Freezed(fromJson/toJson: true)` is required (not just `@freezed`):
/// freezed 2.x only auto-enables json generation when the `fromJson` factory
/// has an expression body, and ours intentionally uses a block body (the
/// try/catch below that degrades unknown runtimeTypes to a sentinel ShowWord
/// instead of throwing).
@Freezed(fromJson: true, toJson: true)
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
  ///
  /// [audioAssets] holds optional prompt-side audio references (e.g.
  /// `anki://<importId>/<file>` from imported Anki decks); the renderer shows
  /// a play button for each.
  const factory Interaction.multipleChoice({
    @Default('') String id,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? imageAsset,
    @Default(<String>[]) List<String> audioAssets,
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
  ///
  /// [audioAssets] / [imageAssets] hold optional prompt-side media references
  /// (e.g. `anki://<importId>/<file>` from imported Anki decks).
  const factory Interaction.fillBlank({
    @Default('') String id,
    required String sentence,
    required String answer,
    String? hint,
    @Default(<String>[]) List<String> audioAssets,
    @Default(<String>[]) List<String> imageAssets,
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

  /// Anki-style flip card: show [front], user reveals [back], then grades
  /// with two buttons (Don't know / Know it, mapped to SM-2 quality by the
  /// renderer).
  ///
  /// Unlike vocabulary-driven variants, the front/back carry no language
  /// semantics — they are generic card faces from an imported Anki deck, so
  /// they are deliberately kept out of the dictionary index. [sourceNoteId]
  /// traces back to the originating Anki note.
  const factory Interaction.ankiCard({
    @Default('') String id,
    required String front,
    required String back,
    @Default(<String>[]) List<String> audioAssets,
    @Default(<String>[]) List<String> imageAssets,
    String? hint,
    String? sourceNoteId,
  }) = AnkiCard;

  factory Interaction.fromJson(Map<String, dynamic> json) {
    try {
      return _$InteractionFromJson(json);
    } catch (e) {
      // Unknown runtimeType from a newer content version (or a corrupted
      // blob) would otherwise throw CheckedFromJsonException and — at the
      // runtime read path — get swallowed by CourseRepository._toLesson's
      // catch, silently emptying the whole lesson. Degrade to a benign
      // ShowWord carrying the offending type so the lesson still loads; the
      // wordId is prefixed with [unknownInteractionWordIdPrefix] so consumers
      // (SRS registration, the ShowWord renderer) can recognize the sentinel
      // and treat it as a load-time failure rather than a real vocab id.
      final rt = json['runtimeType']?.toString() ?? 'unknown';
      return Interaction.showWord(
        wordId: '$unknownInteractionWordIdPrefix$rt',
      );
    }
  }
}

/// Prefix [Interaction.fromJson] emits on the `ShowWord` it returns when the
/// `runtimeType` is unknown/corrupted. Consumers use this to recognize the
/// sentinel as a load-time parse failure (skip SRS registration, render a
/// placeholder) instead of treating it as a real vocabulary id.
const String unknownInteractionWordIdPrefix = 'unknown-interaction:';

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
    AnkiCard() => null,
  };
}

/// Whether an interaction has a text prompt worth explaining, so the
/// in-lesson AI hint assistant should offer itself. Audio-driven types
/// (no text prompt to explain) opt out here, as does [ShowWord] — it is a
/// display-only card whose word/expression is already shown, so there is
/// nothing to "hint" at. Add a `false` arm for any future audio-only type
/// so the lesson screen doesn't need to grow an `is!` exclusion list.
bool interactionAiHintEligible(Interaction interaction) {
  return switch (interaction) {
    ListenAndPick() => false,
    TypeTheWord() => false,
    ListenOnly() => false,
    ShowWord() => false,
    MultipleChoice() => true,
    MultiSelect() => true,
    FillBlank() => true,
    TranslateSentence() => true,
    ReorderSentence() => true,
    ReadingMcq() => true,
    ReadingTrueFalse() => true,
    ReadingShortAnswer() => true,
    AnkiCard() => true,
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
    AnkiCard(:final back) => back,
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
    AnkiCard(:final front) => front,
  };
}

/// A short English label naming the interaction type, for display in the
/// in-lesson AI hint assistant and other UI surfaces.
String interactionTypeLabel(Interaction interaction) {
  return switch (interaction) {
    ShowWord() => 'Vocab Display',
    MultipleChoice() => 'Multiple Choice',
    MultiSelect() => 'Multi-Select',
    FillBlank() => 'Fill-in-the-blank',
    TranslateSentence() => 'Translation',
    ListenAndPick() => 'Listen & Pick',
    TypeTheWord() => 'Dictation',
    ListenOnly() => 'Listening-only',
    ReorderSentence() => 'Sentence Order',
    ReadingMcq() => 'Reading MCQ',
    ReadingTrueFalse() => 'Reading True/False',
    ReadingShortAnswer() => 'Reading Short Answer',
    AnkiCard() => 'Flip Card',
  };
}

/// A human-readable list of the interaction's selectable items, when it has
/// any (options for choice types, scrambled tokens for reorder). Returns
/// `null` for interactions with no notion of options (ShowWord, FillBlank,
/// TranslateSentence, ListenOnly, ReadingTrueFalse, ReadingShortAnswer) so
/// callers can skip rendering an options block.
String? interactionOptionsLabel(Interaction interaction) {
  return switch (interaction) {
    MultipleChoice(:final options) => options.join(' / '),
    MultiSelect(:final options) => options.join(' / '),
    ListenAndPick(:final options) => options.join(' / '),
    ReorderSentence(:final scrambled) => scrambled.join(' / '),
    ReadingMcq(:final options) => options.join(' / '),
    ShowWord() => null,
    FillBlank() => null,
    TranslateSentence() => null,
    TypeTheWord() => null,
    ListenOnly() => null,
    ReadingTrueFalse() => null,
    ReadingShortAnswer() => null,
    AnkiCard() => null,
  };
}
