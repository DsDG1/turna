import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_practice/card_classifier_models.dart';
import 'package:turna/domain/anki/card_presentation.dart';

/// Chooses exactly one active presentation kind for a source card.
///
/// Priority: user-confirmed mapping > explicit structured contract >
/// high-confidence classifier > Flip > Fidelity fallback.
///
/// Ordinary vocabulary cards stay Flip. Sibling answers from the same
/// deck are never enough to mint a formal MCQ.
class CardPresentationPolicy {
  const CardPresentationPolicy();

  OfficialAnkiProjectionKind selectOfficialKind({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
  }) {
    if (values.truncatedRequired) {
      return OfficialAnkiProjectionKind.canonicalLink;
    }

    final classification = values.classification;
    if (mapping == null ||
        mapping.status == OfficialAnkiMappingStatus.needsMapping ||
        mapping.status == OfficialAnkiMappingStatus.needsReview ||
        mapping.status == OfficialAnkiMappingStatus.skipped) {
      if (classification == null ||
          classification.confidence < 0.85 ||
          classification.shape == AnkiPracticeShape.fidelity) {
        return OfficialAnkiProjectionKind.canonicalLink;
      }
    }

    final enabled = mapping?.enabledKinds.toSet() ??
        const <String>{
          'showWord',
          'flip',
          'multipleChoice',
          'multiSelect',
          'listenPick',
          'typeAnswer',
          'fillBlank',
          'translate',
          'canonicalLink',
        };

    if (classification != null) {
      switch (classification.shape) {
        case AnkiPracticeShape.fidelity:
          return OfficialAnkiProjectionKind.canonicalLink;
        case AnkiPracticeShape.cloze:
          return OfficialAnkiProjectionKind.fillBlank;
        case AnkiPracticeShape.quiz:
          if (classification.correctIndices != null &&
              classification.correctIndices!.length >= 2) {
            return OfficialAnkiProjectionKind.multiSelect;
          }
          return OfficialAnkiProjectionKind.multipleChoice;
        case AnkiPracticeShape.listen:
          if (enabled.contains('listenPick') && values.audio != null) {
            return OfficialAnkiProjectionKind.listenPick;
          }
          return OfficialAnkiProjectionKind.flip;
        case AnkiPracticeShape.vocab:
          if (_explicitMcq(values, enabled)) {
            return OfficialAnkiProjectionKind.multipleChoice;
          }
          if (enabled.contains('flip')) {
            return OfficialAnkiProjectionKind.flip;
          }
          if (enabled.contains('showWord')) {
            return OfficialAnkiProjectionKind.showWord;
          }
          return OfficialAnkiProjectionKind.flip;
        case AnkiPracticeShape.expression:
          return OfficialAnkiProjectionKind.fillBlank;
        case AnkiPracticeShape.typeAnswer:
          if (typeAnswerEnabled &&
              enabled.contains('typeAnswer') &&
              values.audio != null &&
              values.audio!.isNotEmpty) {
            return OfficialAnkiProjectionKind.typeAnswer;
          }
          return OfficialAnkiProjectionKind.flip;
        case AnkiPracticeShape.flip:
          return OfficialAnkiProjectionKind.flip;
      }
    }

    if (enabled.contains('flip') &&
        values.target.isNotEmpty &&
        values.native.isNotEmpty) {
      return OfficialAnkiProjectionKind.flip;
    }
    return OfficialAnkiProjectionKind.canonicalLink;
  }

  CardPresentationKind toCardPresentationKind(
    OfficialAnkiProjectionKind kind,
  ) {
    return switch (kind) {
      OfficialAnkiProjectionKind.multipleChoice =>
        CardPresentationKind.multipleChoice,
      OfficialAnkiProjectionKind.multiSelect => CardPresentationKind.multiSelect,
      OfficialAnkiProjectionKind.fillBlank => CardPresentationKind.fillBlank,
      OfficialAnkiProjectionKind.listenPick =>
        CardPresentationKind.listenAndPick,
      OfficialAnkiProjectionKind.typeAnswer => CardPresentationKind.typeAnswer,
      OfficialAnkiProjectionKind.canonicalLink => CardPresentationKind.fidelity,
      OfficialAnkiProjectionKind.flip ||
      OfficialAnkiProjectionKind.showWord ||
      OfficialAnkiProjectionKind.translate =>
        CardPresentationKind.flip,
    };
  }

  bool _explicitMcq(OfficialAnkiRoleValues values, Set<String> enabled) {
    if (!enabled.contains('multipleChoice')) return false;
    if (!values.hasExplicitOptions) return false;
    if (values.target.isEmpty) return false;
    final uniqueDistractors = values.options
        .where((o) => o.toLowerCase() != values.target.toLowerCase())
        .toSet();
    return uniqueDistractors.length >= 2;
  }
}
