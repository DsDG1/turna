import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/policy/presentation_policy.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/domain/anki/adaptation/presentation_decision.dart';

/// [kind] is what the payload encoder needs; [decision] is the typed outcome
/// for gating, diagnostics and the "why this identification" surface.
class CardPresentationResolution {
  const CardPresentationResolution({
    required this.kind,
    required this.decision,
  });

  final OfficialAnkiProjectionKind kind;
  final CardPresentationDecision decision;
}

/// The full per-card outcome of the adaptation chain: the presentation
/// decision plus the **effective** role values the payload encoder must use —
/// plan bindings already applied, i.e. exactly the facts the decision was
/// taken against. Callers never re-merge the plan into the mapping themselves
/// (ADR 0057 §2: the plan is the single configuration carrier).
class OfficialCardPlanResolution {
  const OfficialCardPlanResolution({
    required this.kind,
    required this.decision,
    required this.values,
  });

  final OfficialAnkiProjectionKind kind;
  final CardPresentationDecision decision;
  final OfficialAnkiRoleValues values;
}

/// The single card-level presentation resolver (ADR 0057 §1).
///
/// Every caller — preview summaries, v2 lesson loading, and (in a later
/// increment) formal review — goes through this class so the same card in the
/// same context cannot end up with two different presentations.
///
/// [storedKindName] is the v2 view row's expected kind. It is **advisory**: the
/// fresh decision always wins, and a disagreement is recorded as
/// [PresentationReason.storedKindDrift] instead of being silently obeyed.
class OfficialCardPresentationResolver {
  const OfficialCardPresentationResolver();

  /// Resolve one card through the full adaptation chain (ADR 0057 §1/§4/§5).
  ///
  /// [applied] is the adaptation lookup for THIS card (card override >
  /// cloze-target scope > template scope > none). Everything between "a plan
  /// exists" and "a presentation kind exists" happens here: folding the plan
  /// into the effective mapping, deriving the values against it, and sending
  /// the whole card back to the original face when the plan's layout cannot
  /// be expressed. Callers only fetch data and encode the payload.
  ///
  /// A notetype without a mapping decision resolves to
  /// [NeedsCorrectionDecision]: the recognizer never guesses a structured
  /// face for an unconfirmed group (ADR 0057 §1).
  OfficialCardPlanResolution resolveCard({
    required OfficialAnkiProjectionRow row,
    required OfficialAnkiMappingSuggestion? mapping,
    required AdaptationLookup applied,
    String? storedKindName,
    OfficialAnkiProjectionPayloads payloads =
        const OfficialAnkiProjectionPayloads(),
    List<String> siblingAnswers = const <String>[],
  }) {
    if (mapping == null) {
      // The plan chain is built on the confirmed mapping decision; without
      // one a human must pick the fields first. The card still renders as
      // the original, never as a guessed exercise.
      return OfficialCardPlanResolution(
        kind: OfficialAnkiProjectionKind.canonicalLink,
        decision: const NeedsCorrectionDecision(
          reasons: [PresentationReason.missingMappingDecision],
        ),
        values: payloads.values(row, null, siblingAnswers: siblingAnswers),
      );
    }
    switch (applied) {
      case AdaptationPlanFound(:final plan):
        final effective = applyAdaptationPlan(mapping, plan);
        final values = payloads.values(
          row,
          effective,
          plan: plan,
          siblingAnswers: siblingAnswers,
        );
        if (values.document?.unsupported ?? false) {
          // The plan points at structure the renderer cannot express
          // (scripts / tables / embedded media): the whole card keeps the
          // original face instead of half a layout (ADR 0057 §5).
          return OfficialCardPlanResolution(
            kind: OfficialAnkiProjectionKind.canonicalLink,
            decision: const OriginalCardDecision(
              reasons: [PresentationReason.unsupportedStructure],
            ),
            values: values,
          );
        }
        final resolution = resolve(
          values: values,
          mapping: effective,
          typeAnswerEnabled: effective.enabledKinds.contains('typeAnswer'),
          storedKindName: storedKindName,
        );
        return OfficialCardPlanResolution(
          kind: resolution.kind,
          decision: resolution.decision,
          values: values,
        );
      case AdaptationExplicitlyOriginal():
        // The user pinned this card to the original rendering — a deliberate
        // choice, not a diagnostic state, so no reason is recorded.
        return OfficialCardPlanResolution(
          kind: OfficialAnkiProjectionKind.canonicalLink,
          decision: const OriginalCardDecision(reasons: []),
          values: payloads.values(row, mapping, siblingAnswers: siblingAnswers),
        );
      case AdaptationPlanMissing():
        return OfficialCardPlanResolution(
          kind: OfficialAnkiProjectionKind.canonicalLink,
          decision: const OriginalCardDecision(
            reasons: [PresentationReason.planMissing],
          ),
          values: payloads.values(row, mapping, siblingAnswers: siblingAnswers),
        );
      case AdaptationNoPlan():
        final values =
            payloads.values(row, mapping, siblingAnswers: siblingAnswers);
        final resolution = resolve(
          values: values,
          mapping: mapping,
          typeAnswerEnabled: mapping.enabledKinds.contains('typeAnswer'),
          storedKindName: storedKindName,
        );
        return OfficialCardPlanResolution(
          kind: resolution.kind,
          decision: resolution.decision,
          values: values,
        );
    }
  }

  /// 生效方案把这一组的练习范围收窄到「默认练习 + 可选练习 + 兜底」。
  ///
  /// 展示仍逐卡重判：方案能说「这组做成听写」，但不能保证每张卡都满足听写
  /// 前提（正面音频已证）；不满足的卡照旧回落，而不是硬造一个残缺练习。
  static OfficialAnkiMappingSuggestion applyAdaptationPlan(
    OfficialAnkiMappingSuggestion mapping,
    CardAdaptationPlan plan,
  ) {
    return _withPlanBindings(_withPlanKinds(mapping, plan), plan);
  }

  static OfficialAnkiMappingSuggestion _withPlanKinds(
    OfficialAnkiMappingSuggestion mapping,
    CardAdaptationPlan plan,
  ) {
    final kinds = <String>{
      plan.defaultExercise,
      ...plan.optionalExercises,
      'flip',
      'canonicalLink',
    };
    return mapping.copyWith(enabledKinds: kinds.toList()..sort());
  }

  /// 方案里的字段绑定覆盖识别结果（ADR 0057 §7.1）。
  ///
  /// 校验器已经保证绑定角色与字段序号合法；这里只是让它在读面上生效，
  /// 否则 `bindings` 就只是一份没人用的装饰。没被方案绑定的角色继续用识别
  /// 结果，二者可以共存。
  static OfficialAnkiMappingSuggestion _withPlanBindings(
    OfficialAnkiMappingSuggestion mapping,
    CardAdaptationPlan plan,
  ) {
    if (plan.bindings.isEmpty) return mapping;
    const rolesByBinding = <String, FieldRole>{
      'prompt': FieldRole.prompt,
      'answer': FieldRole.response,
      'pronunciation': FieldRole.pronunciation,
      'example': FieldRole.example,
      'audio': FieldRole.audio,
      'image': FieldRole.image,
      'options': FieldRole.options,
    };

    final boundRoles = <FieldRole>{};
    final candidates = <OfficialAnkiFieldCandidate>[];
    for (final entry in plan.bindings.entries) {
      final role = rolesByBinding[entry.key];
      if (role == null) continue;
      boundRoles.add(role);
      candidates.add(
        OfficialAnkiFieldCandidate(
          role: role,
          fieldIndex: entry.value,
          fieldName: mapping.role(role)?.fieldName ?? '',
          // Confidence 1 + explicit evidence: the user/AI-confirmed plan wins
          // over the recognizer's own guess for the same role.
          confidence: 1,
          evidence: const ['plan'],
        ),
      );
    }
    if (boundRoles.isEmpty) return mapping;

    return mapping.copyWith(
      candidates: [
        ...candidates,
        for (final candidate in mapping.candidates)
          if (!boundRoles.contains(candidate.role)) candidate,
      ],
    );
  }

  CardPresentationResolution resolve({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    bool typeAnswerEnabled = true,
    String? storedKindName,
    bool formalReview = false,
  }) {
    const policy = OfficialAnkiPresentationPolicy();
    final decided = policy.resolve(
      values: values,
      mapping: mapping,
      typeAnswerEnabled: typeAnswerEnabled,
      formalReview: formalReview,
    );

    final reasons = <PresentationReason>[...decided.reasons];
    if (storedKindName != null) {
      final stored = _kindFromName(storedKindName);
      if (stored == null) {
        reasons.add(PresentationReason.unknownStoredKind);
      } else if (stored != decided.kind) {
        reasons.add(PresentationReason.storedKindDrift);
      }
    }
    final frozen = List<PresentationReason>.unmodifiable(reasons);

    final decision = decided.kind == OfficialAnkiProjectionKind.canonicalLink
        ? OriginalCardDecision(reasons: frozen)
        : StructuredCardDecision(
            kind: policy.toCardPresentationKind(decided.kind),
            reasons: frozen,
          );
    return CardPresentationResolution(kind: decided.kind, decision: decision);
  }

  /// Resolve a stored kind name, or null when this build does not know it.
  /// Unknown kinds are never coerced to flip: they are re-decided from the
  /// card's own facts (ADR 0057 §1).
  static OfficialAnkiProjectionKind? _kindFromName(String name) {
    for (final kind in OfficialAnkiProjectionKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// Outcome counts for a whole structural group (plan §11.2 step 6).
///
/// The preview must show how many cards stay structured and how many fall back,
/// not just the prettiest sample (plan §13.1).
class AdaptationBatchSummary {
  const AdaptationBatchSummary({
    required this.structured,
    required this.originalCard,
    required this.needsCorrection,
    required this.unavailable,
  });

  factory AdaptationBatchSummary.of(
    Iterable<CardPresentationDecision> decisions,
  ) {
    var structured = 0;
    var original = 0;
    var correction = 0;
    var unavailable = 0;
    for (final decision in decisions) {
      switch (decision) {
        case StructuredCardDecision():
          structured++;
        case OriginalCardDecision():
          original++;
        case NeedsCorrectionDecision():
          correction++;
        case UnavailableCardDecision():
          unavailable++;
      }
    }
    return AdaptationBatchSummary(
      structured: structured,
      originalCard: original,
      needsCorrection: correction,
      unavailable: unavailable,
    );
  }

  final int structured;
  final int originalCard;
  final int needsCorrection;
  final int unavailable;

  int get total => structured + originalCard + needsCorrection + unavailable;

  /// Share of cards the plan keeps on a structured face. Zero for an empty
  /// group — an empty group is not "100% adapted".
  double get structuredShare => total == 0 ? 0 : structured / total;
}
