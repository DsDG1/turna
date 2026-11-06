import 'interaction.dart';

const Set<String> reviewPoolInteractionTypeNames = {
  'multipleChoice',
  'multiSelect',
  'fillBlank',
  'translateSentence',
  'listenAndPick',
  'typeTheWord',
  'reorderSentence',
  'readingMcq',
  'readingTrueFalse',
  'readingShortAnswer',
  'readAloud',
};

bool isReviewPoolInteraction(Interaction interaction) => switch (interaction) {
      MultipleChoice() ||
      MultiSelect() ||
      FillBlank() ||
      TranslateSentence() ||
      ListenAndPick() ||
      TypeTheWord() ||
      ReorderSentence() ||
      ReadingMcq() ||
      ReadingTrueFalse() ||
      ReadingShortAnswer() ||
      ReadAloud() =>
        true,
      ShowWord() ||
      ListenOnly() ||
      AnkiCard() ||
      AnkiHtmlCard() ||
      ImageRecall() ||
      Dictation() =>
        false,
    };

String interactionRuntimeType(Interaction interaction) => switch (interaction) {
      ShowWord() => 'showWord',
      MultipleChoice() => 'multipleChoice',
      MultiSelect() => 'multiSelect',
      FillBlank() => 'fillBlank',
      TranslateSentence() => 'translateSentence',
      ListenAndPick() => 'listenAndPick',
      TypeTheWord() => 'typeTheWord',
      ListenOnly() => 'listenOnly',
      ReorderSentence() => 'reorderSentence',
      ReadingMcq() => 'readingMcq',
      ReadingTrueFalse() => 'readingTrueFalse',
      ReadingShortAnswer() => 'readingShortAnswer',
      AnkiCard() => 'ankiCard',
      AnkiHtmlCard() => 'ankiHtmlCard',
      ImageRecall() => 'imageRecall',
      Dictation() => 'dictation',
      ReadAloud() => 'readAloud',
    };
