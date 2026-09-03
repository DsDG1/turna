import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/domain/anki/card_presentation.dart';

import '../recognize/result.dart';

/// L4: the thin archetype × preference table (doc 37 §3.8). The old
/// shape-by-shape switch and its conversion helpers are gone — an
/// archetype maps to exactly one default kind, constrained by the user's
/// enabled kinds, with flip/canonicalLink as the only fallbacks.
class OfficialAnkiPresentationPolicy {
  const OfficialAnkiPresentationPolicy();

  OfficialAnkiProjectionKind selectOfficialKind({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
  }) {
    if (values.truncatedRequired) {
      return OfficialAnkiProjectionKind.canonicalLink;
    }
    // Iron-law downgrade (§3.7): this card violated its notetype's
    // archetype, so it keeps the fidelity rendering.
    if (values.archetypeViolated) {
      return OfficialAnkiProjectionKind.canonicalLink;
    }

    final trusted = mapping != null &&
        mapping.status != OfficialAnkiMappingStatus.review &&
        mapping.status != OfficialAnkiMappingStatus.skipped;
    if (!trusted && values.archetypeConfidence < 0.85) {
      return OfficialAnkiProjectionKind.canonicalLink;
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
    final hasAudio = values.audio != null && values.audio!.isNotEmpty;

    switch (values.archetype) {
      case CardArchetype.richHtml:
        return OfficialAnkiProjectionKind.canonicalLink;
      case CardArchetype.cloze:
        return OfficialAnkiProjectionKind.fillBlank;
      case CardArchetype.choice:
        if (!values.hasExplicitOptions || values.options.isEmpty) {
          // Defensive: a choice archetype with no resolvable options on
          // this card degrades to the pair fallback instead of building a
          // broken MCQ (normally unreachable — validation marks the card
          // violated first).
          return _pairFallback(enabled, values);
        }
        final multi = (values.correctIndices ?? const <int>[]).length >= 2;
        final wanted = multi
            ? OfficialAnkiProjectionKind.multiSelect
            : OfficialAnkiProjectionKind.multipleChoice;
        if (enabled.contains(wanted.name)) return wanted;
        return _pairFallback(enabled, values);
      case CardArchetype.audioFirst:
        if (enabled.contains('listenPick') && hasAudio) {
          return OfficialAnkiProjectionKind.listenPick;
        }
        return _pairFallback(enabled, values);
      case CardArchetype.typeIn:
        if (typeAnswerEnabled &&
            enabled.contains('typeAnswer') &&
            hasAudio) {
          return OfficialAnkiProjectionKind.typeAnswer;
        }
        return _pairFallback(enabled, values);
      case CardArchetype.basicPair:
        return _pairFallback(enabled, values);
    }
  }

  OfficialAnkiProjectionKind _pairFallback(
    Set<String> enabled,
    OfficialAnkiRoleValues values,
  ) {
    if (enabled.contains('flip') &&
        values.target.isNotEmpty &&
        values.native.isNotEmpty) {
      return OfficialAnkiProjectionKind.flip;
    }
    if (enabled.contains('showWord') && values.target.isNotEmpty) {
      return OfficialAnkiProjectionKind.showWord;
    }
    if (values.target.isEmpty && values.native.isEmpty) {
      return OfficialAnkiProjectionKind.canonicalLink;
    }
    return OfficialAnkiProjectionKind.flip;
  }

  /// Domain presentation mapping (kept from the old policy; the study
  /// session host consumes [CardPresentationKind]).
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
}
