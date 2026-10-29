import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/domain/anki/adaptation/presentation_decision.dart';
import 'package:turna/domain/anki/card_presentation.dart';

import '../facts/text_metrics.dart';
import '../recognize/result.dart';

/// One decision plus the reasons it fired (ADR 0057 §1). The kind is the
/// application-level projection kind; the reasons are the shared diagnosis.
typedef OfficialKindDecision = ({
  OfficialAnkiProjectionKind kind,
  List<PresentationReason> reasons,
});

/// L4: the thin archetype × preference table (doc 37 §3.8). The old
/// shape-by-shape switch and its conversion helpers are gone — an
/// archetype maps to exactly one default kind, constrained by the user's
/// enabled kinds, with flip/canonicalLink as the only fallbacks.
///
/// This is the **single** card-level decision (ADR 0057). [resolve] is the
/// entry point; [selectOfficialKind] is a thin projection of it kept for the
/// existing callers. Nothing else in the app may re-derive a kind from an
/// archetype table.
class OfficialAnkiPresentationPolicy {
  const OfficialAnkiPresentationPolicy();

  /// Decide this card's kind and why.
  ///
  /// [storedKindName] is the v2 view row's expected kind, used only to detect
  /// drift (the view is outdated); it never decides the outcome.
  OfficialKindDecision resolve({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
    bool formalReview = false,
  }) {
    return _guardUnprovenMedia(
      _decide(
        values: values,
        mapping: mapping,
        typeAnswerEnabled: typeAnswerEnabled,
        formalReview: formalReview,
      ),
      values,
    );
  }

  /// A flip face renders media per side. If any occurrence's face could not be
  /// proven, guessing would risk putting an answer clip in front of the
  /// learner, so the card keeps the original rendering instead (ADR 0057 §5,
  /// plan §8.3: 无法证明完整时走原卡).
  OfficialKindDecision _guardUnprovenMedia(
    OfficialKindDecision decided,
    OfficialAnkiRoleValues values,
  ) {
    if (decided.kind != OfficialAnkiProjectionKind.flip) return decided;
    if (!values.hasUnprovenMediaSide) return decided;
    return (
      kind: OfficialAnkiProjectionKind.canonicalLink,
      reasons: <PresentationReason>[
        ...decided.reasons,
        PresentationReason.unknownMediaSide,
      ],
    );
  }

  OfficialKindDecision _decide({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
    required bool formalReview,
  }) {
    // Formal review keeps the original card in phase one: changing the prompt
    // direction or adding hints changes recall difficulty (ADR 0057 §8).
    if (formalReview) {
      return (
        kind: OfficialAnkiProjectionKind.canonicalLink,
        reasons: const <PresentationReason>[
          PresentationReason.formalReviewOriginalFirst,
        ],
      );
    }
    if (values.truncatedRequired) {
      return (
        kind: OfficialAnkiProjectionKind.canonicalLink,
        reasons: const <PresentationReason>[PresentationReason.truncatedRequired],
      );
    }
    // Iron-law downgrade (§3.7): this card violated its notetype's
    // archetype. For choice questions, only a genuinely short pair
    // degrades to flip — a long stem or an explanation-sized back keeps
    // fidelity rendering (mixed decks: the non-choice minority used to
    // land here as raw flip cards). Other complex cards keep fidelity.
    if (values.archetypeViolated) {
      if (values.archetype == CardArchetype.choice) {
        final pairLike = CardText.isShortAnswer(values.target) &&
            CardText.isShortAnswer(values.native);
        if (pairLike) {
          final enabled = mapping?.enabledKinds.toSet() ??
              const <String>{'flip', 'canonicalLink'};
          final kind = _pairFallback(enabled, values);
          return (
            kind: kind,
            reasons: <PresentationReason>[
              PresentationReason.archetypeViolated,
              if (kind == OfficialAnkiProjectionKind.canonicalLink)
                PresentationReason.missingOptions,
            ],
          );
        }
      }
      return (
        kind: OfficialAnkiProjectionKind.canonicalLink,
        reasons: const <PresentationReason>[
          PresentationReason.archetypeViolated,
        ],
      );
    }

    final trusted = mapping != null &&
        mapping.status != OfficialAnkiMappingStatus.review &&
        mapping.status != OfficialAnkiMappingStatus.skipped;
    if (!trusted && values.archetypeConfidence < 0.85) {
      return (
        kind: OfficialAnkiProjectionKind.canonicalLink,
        reasons: const <PresentationReason>[PresentationReason.lowConfidence],
      );
    }

    final enabled = mapping?.enabledKinds.toSet() ??
        const <String>{
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

    // Opt-in presentations (ADR 0057 §4). They are never a default: the user's
    // preset has to enable the kind and this card has to prove the prerequisite.
    // Failing either check falls through to the archetype rules below, so a
    // half-eligible card still gets a supported presentation.
    if (enabled.contains('imageRecall') &&
        values.frontImages.isNotEmpty &&
        values.target.isNotEmpty &&
        !values.hasUnprovenMediaSide) {
      return (
        kind: OfficialAnkiProjectionKind.imageRecall,
        reasons: const <PresentationReason>[],
      );
    }
    if (enabled.contains('dictation') &&
        values.frontAudio.isNotEmpty &&
        CardText.isShortAnswer(values.target) &&
        !values.hasUnprovenMediaSide) {
      return (
        kind: OfficialAnkiProjectionKind.dictation,
        reasons: const <PresentationReason>[],
      );
    }

    switch (values.archetype) {
      case CardArchetype.richHtml:
        return (
          kind: OfficialAnkiProjectionKind.canonicalLink,
          reasons: const <PresentationReason>[],
        );
      case CardArchetype.cloze:
        return (
          kind: OfficialAnkiProjectionKind.fillBlank,
          reasons: const <PresentationReason>[],
        );
      case CardArchetype.choice:
        if (!values.hasExplicitOptions || values.options.isEmpty) {
          // Defensive: a choice archetype with no resolvable options on
          // this card degrades to the pair fallback instead of building a
          // broken MCQ (normally unreachable — validation marks the card
          // violated first).
          return (
            kind: _pairFallback(enabled, values),
            reasons: const <PresentationReason>[
              PresentationReason.missingOptions,
            ],
          );
        }
        final multi = (values.correctIndices ?? const <int>[]).length >= 2;
        final wanted = multi
            ? OfficialAnkiProjectionKind.multiSelect
            : OfficialAnkiProjectionKind.multipleChoice;
        if (enabled.contains(wanted.name)) {
          return (
            kind: wanted,
            reasons: const <PresentationReason>[],
          );
        }
        return (
          kind: _pairFallback(enabled, values),
          reasons: const <PresentationReason>[PresentationReason.missingOptions],
        );
      case CardArchetype.audioFirst:
        if (enabled.contains('listenPick') && hasAudio) {
          return (
            kind: OfficialAnkiProjectionKind.listenPick,
            reasons: const <PresentationReason>[],
          );
        }
        return (
          kind: _pairFallback(enabled, values),
          reasons: <PresentationReason>[
            if (!hasAudio) PresentationReason.missingMedia,
          ],
        );
      case CardArchetype.typeIn:
        if (typeAnswerEnabled && enabled.contains('typeAnswer') && hasAudio) {
          return (
            kind: OfficialAnkiProjectionKind.typeAnswer,
            reasons: const <PresentationReason>[],
          );
        }
        return (
          kind: _pairFallback(enabled, values),
          reasons: <PresentationReason>[
            if (!hasAudio) PresentationReason.missingMedia,
          ],
        );
      case CardArchetype.basicPair:
        final kind = _pairFallback(enabled, values);
        return (
          kind: kind,
          reasons: <PresentationReason>[
            if (kind == OfficialAnkiProjectionKind.canonicalLink)
              PresentationReason.emptyFields,
          ],
        );
    }
  }

  /// The kind alone — callers that do not need the diagnosis.
  OfficialAnkiProjectionKind selectOfficialKind({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
  }) {
    return resolve(
      values: values,
      mapping: mapping,
      typeAnswerEnabled: typeAnswerEnabled,
    ).kind;
  }

  /// Notetype-level expected kind: what this notetype is expected to become
  /// before any card-level fact is known.
  ///
  /// The v2 view stores this as a **hint only**; the resolver re-decides per
  /// card at load time (ADR 0057 §1). Kept here so the view rebuilder and the
  /// card-level rules cannot drift into two tables.
  static OfficialAnkiProjectionKind expectedKindForArchetype(
    CardArchetype archetype,
    Set<String> enabledKinds,
  ) {
    bool has(String kind) => enabledKinds.contains(kind);
    return switch (archetype) {
      CardArchetype.choice => has('multipleChoice')
          ? OfficialAnkiProjectionKind.multipleChoice
          : (has('multiSelect')
              ? OfficialAnkiProjectionKind.multiSelect
              : (has('flip')
                  ? OfficialAnkiProjectionKind.flip
                  : OfficialAnkiProjectionKind.canonicalLink)),
      CardArchetype.cloze => has('fillBlank')
          ? OfficialAnkiProjectionKind.fillBlank
          : OfficialAnkiProjectionKind.canonicalLink,
      CardArchetype.audioFirst => has('listenPick')
          ? OfficialAnkiProjectionKind.listenPick
          : (has('flip')
              ? OfficialAnkiProjectionKind.flip
              : OfficialAnkiProjectionKind.canonicalLink),
      CardArchetype.typeIn => has('typeAnswer')
          ? OfficialAnkiProjectionKind.typeAnswer
          : (has('flip')
              ? OfficialAnkiProjectionKind.flip
              : OfficialAnkiProjectionKind.canonicalLink),
      CardArchetype.richHtml => OfficialAnkiProjectionKind.canonicalLink,
      CardArchetype.basicPair => has('flip')
          ? OfficialAnkiProjectionKind.flip
          : (has('showWord')
              ? OfficialAnkiProjectionKind.showWord
              : OfficialAnkiProjectionKind.canonicalLink),
    };
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
      OfficialAnkiProjectionKind.multiSelect =>
        CardPresentationKind.multiSelect,
      OfficialAnkiProjectionKind.fillBlank => CardPresentationKind.fillBlank,
      OfficialAnkiProjectionKind.listenPick =>
        CardPresentationKind.listenAndPick,
      OfficialAnkiProjectionKind.typeAnswer => CardPresentationKind.typeAnswer,
      OfficialAnkiProjectionKind.imageRecall =>
        CardPresentationKind.imageRecall,
      OfficialAnkiProjectionKind.dictation => CardPresentationKind.dictation,
      OfficialAnkiProjectionKind.canonicalLink => CardPresentationKind.fidelity,
      OfficialAnkiProjectionKind.flip ||
      OfficialAnkiProjectionKind.showWord ||
      OfficialAnkiProjectionKind.translate =>
        CardPresentationKind.flip,
    };
  }
}
