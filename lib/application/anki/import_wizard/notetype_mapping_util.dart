import 'package:turna/application/anki/anki_card_adapter.dart';

/// Collapse legacy aliases so dropdown [initialValue] always matches an
/// item. Shared by the recognition preview and the mapping editor
/// (maintainability plan Wave 4 extraction).
NotetypeMappingType canonicalizeMappingType(NotetypeMappingType type) {
  switch (type) {
    case NotetypeMappingType.multiSelect:
      return NotetypeMappingType.multipleChoice;
    case NotetypeMappingType.typeAnswer:
      return NotetypeMappingType.fillBlank;
    case NotetypeMappingType.ankiCard:
    case NotetypeMappingType.wordEntry:
    case NotetypeMappingType.expression:
    case NotetypeMappingType.cloze:
    case NotetypeMappingType.multipleChoice:
    case NotetypeMappingType.fillBlank:
    case NotetypeMappingType.listenPick:
      return type;
  }
}

NotetypeMapping canonicalizeMapping(NotetypeMapping m) {
  final canonical = canonicalizeMappingType(m.type);
  return canonical == m.type ? m : m.copyWith(type: canonical);
}

bool mappingUsesFrontBackFields(NotetypeMappingType type) {
  switch (canonicalizeMappingType(type)) {
    case NotetypeMappingType.ankiCard:
    case NotetypeMappingType.wordEntry:
    case NotetypeMappingType.expression:
    case NotetypeMappingType.fillBlank:
    case NotetypeMappingType.typeAnswer:
    case NotetypeMappingType.listenPick:
      return true;
    case NotetypeMappingType.cloze:
    case NotetypeMappingType.multipleChoice:
    case NotetypeMappingType.multiSelect:
      return false;
  }
}
