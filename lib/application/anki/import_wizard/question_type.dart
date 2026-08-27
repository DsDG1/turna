// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/import_wizard/notetype_mapping_util.dart';

/// User-facing question types shown as chips during import. The internal
/// [NotetypeMappingType] has seven values (plus legacy aliases) that map onto
/// these six plain-language choices; the distinction the UI hides is either
/// an implementation detail (multiSelect, typeAnswer aliases) or something
/// the app can decide from the cards themselves (cloze vs type-the-answer
/// both surface as 填空题).
enum UserQuestionType { choice, fillBlank, listen, word, sentence, flip }

/// Collapse an internal mapping type to the chip the user sees. Legacy
/// aliases are canonicalized first.
UserQuestionType userQuestionTypeOf(NotetypeMappingType type) {
  switch (canonicalizeMappingType(type)) {
    case NotetypeMappingType.multipleChoice:
      return UserQuestionType.choice;
    case NotetypeMappingType.cloze:
    case NotetypeMappingType.fillBlank:
      return UserQuestionType.fillBlank;
    case NotetypeMappingType.listenPick:
      return UserQuestionType.listen;
    case NotetypeMappingType.wordEntry:
      return UserQuestionType.word;
    case NotetypeMappingType.expression:
      return UserQuestionType.sentence;
    case NotetypeMappingType.ankiCard:
      return UserQuestionType.flip;
    case NotetypeMappingType.multiSelect:
    case NotetypeMappingType.typeAnswer:
      // Unreachable after canonicalize, but the switch must be exhaustive.
      return UserQuestionType.flip;
  }
}

/// Inverse of [userQuestionTypeOf] for writing a chip tap back into a
/// mapping. 填空题 is ambiguous between cloze deletion and type-the-answer:
/// when the notetype carries cloze markers the cloze interaction preserves
/// the deletions; otherwise the back face becomes the typed answer.
NotetypeMappingType resolveMappingType(
  UserQuestionType type, {
  required bool hasClozeMarkers,
}) {
  switch (type) {
    case UserQuestionType.choice:
      return NotetypeMappingType.multipleChoice;
    case UserQuestionType.fillBlank:
      return hasClozeMarkers
          ? NotetypeMappingType.cloze
          : NotetypeMappingType.fillBlank;
    case UserQuestionType.listen:
      return NotetypeMappingType.listenPick;
    case UserQuestionType.word:
      return NotetypeMappingType.wordEntry;
    case UserQuestionType.sentence:
      return NotetypeMappingType.expression;
    case UserQuestionType.flip:
      return NotetypeMappingType.ankiCard;
  }
}

final RegExp _clozeMarkerRe = RegExp(r'\{\{c\d+::');

/// Whether any sampled note of this notetype carries `{{c1::…}}` cloze
/// markers — the evidence that a 填空题 choice should map to the cloze
/// interaction instead of type-the-answer.
bool hasClozeMarkers(AnkiNotetype notetype, List<AnkiNote> notes) {
  if (notetype.isCloze) return true;
  const maxSamples = 10;
  var checked = 0;
  for (final note in notes) {
    if (note.mid != notetype.id) continue;
    if (++checked > maxSamples) break;
    for (final field in note.fields) {
      if (_clozeMarkerRe.hasMatch(field)) return true;
    }
  }
  return false;
}
