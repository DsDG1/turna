import 'package:turna/domain/anki/card_presentation.dart';

/// Why a card ended up on a given presentation path (ADR 0057 §1).
///
/// Reasons are diagnostic and drive the "为什么这么识别" surface; they are
/// never used to re-derive the decision. A decision carries every reason that
/// applied, in the order the rules fired.
enum PresentationReason {
  /// A required field was truncated by the projection budget, so the values
  /// in hand cannot be proven complete.
  truncatedRequired,

  /// The card contradicts its notetype archetype (missing cloze markers,
  /// unalignable options, script/complex markup).
  archetypeViolated,

  /// The archetype was recognised below the auto-accept band and the mapping
  /// was never confirmed by a human.
  lowConfidence,

  /// A choice archetype resolved no option pool on this card.
  missingOptions,

  /// The exercise needs media (prompt audio, prompt image) and none resolved.
  missingMedia,

  /// A card with media whose face could not be proven. Rendering it as a flip
  /// could put answer-side media on the question face, so the card keeps the
  /// original rendering (ADR 0057 §5).
  unknownMediaSide,

  /// Neither prompt nor answer text is present — nothing to present.
  emptyFields,

  /// The stored view kind is not a kind this build knows (older/newer schema).
  unknownStoredKind,

  /// The stored view kind is known but disagrees with the freshly resolved
  /// decision. The fresh decision wins; this records that the view is stale.
  storedKindDrift,

  /// The interaction payload exceeded the projection size limit; the card
  /// falls back to the original-card link instead of disappearing.
  payloadOverflow,

  /// Formal review keeps the original card in phase one (ADR 0057 §8).
  formalReviewOriginalFirst,

  /// An active plan referenced by the manifest is missing or unreadable, so the
  /// card cannot be rendered from it and keeps the original face.
  planMissing,

  /// The content cannot be converted safely: scripts, embedded widgets, or a
  /// layout block pointing at something the renderer cannot express.
  unsupportedStructure,

  /// The notetype has no confirmed mapping decision, so no structured face can
  /// be derived for its cards. A human must confirm the field roles first
  /// (the v1 "needsMapping" state, surfaced as a correction instead of a
  /// silent original card).
  missingMappingDecision,
}

/// Typed outcome of the single presentation resolver (ADR 0057 §1).
///
/// Four outcomes, all of them supported results:
/// - [StructuredCardDecision]: a Flutter-rendered exercise.
/// - [OriginalCardDecision]: render the official card as-is.
/// - [NeedsCorrectionDecision]: a human must fix the plan/fields first.
/// - [UnavailableCardDecision]: nothing can be rendered; the caller must show
///   a per-card reason instead of dropping the card.
sealed class CardPresentationDecision {
  const CardPresentationDecision({
    required this.reasons,
    this.resolverVersion = currentResolverVersion,
  });

  /// Bumped whenever the decision rules change, so persisted derived state can
  /// be re-validated instead of trusted.
  static const int currentResolverVersion = 1;

  final List<PresentationReason> reasons;
  final int resolverVersion;

  /// The structured kind, or null when the outcome is not structured.
  CardPresentationKind? get kind;

  bool get isOriginalCard => this is OriginalCardDecision;
  bool get isStructured => this is StructuredCardDecision;

  bool hasReason(PresentationReason reason) => reasons.contains(reason);
}

final class StructuredCardDecision extends CardPresentationDecision {
  const StructuredCardDecision({
    required this.kind,
    required super.reasons,
    super.resolverVersion,
  });

  @override
  final CardPresentationKind kind;
}

/// The official card is the answer: either it is the supported result of
/// choice, or nothing else can be proven to preserve the visible information.
final class OriginalCardDecision extends CardPresentationDecision {
  const OriginalCardDecision({
    required super.reasons,
    super.resolverVersion,
  });

  @override
  CardPresentationKind? get kind => null;
}

/// The card cannot be presented until a human fixes the binding or the plan.
final class NeedsCorrectionDecision extends CardPresentationDecision {
  const NeedsCorrectionDecision({
    required super.reasons,
    super.resolverVersion,
  });

  @override
  CardPresentationKind? get kind => null;
}

/// Neither a structured presentation nor the original card can be rendered.
/// Callers must surface the reason per card; silently skipping is a loss.
///
/// Produced by the lesson payload encoder (the original-card link itself
/// overflows the projection budget), not by the resolver — the resolver never
/// encodes payloads. [AdaptationBatchSummary] counts it when a caller feeds
/// it encoder-level decisions.
final class UnavailableCardDecision extends CardPresentationDecision {
  const UnavailableCardDecision({
    required super.reasons,
    super.resolverVersion,
  });

  @override
  CardPresentationKind? get kind => null;
}
