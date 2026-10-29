import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// What the plan is being validated against: the structural facts of the group
/// it claims to cover.
class AdaptationFacts {
  const AdaptationFacts({
    required this.sourceId,
    required this.notetypeId,
    required this.fieldCount,
    this.templateOrdinals = const <int>[],
    this.frontFieldOrds = const <int>{},
    this.backFieldOrds = const <int>{},
  });

  final String sourceId;
  final int notetypeId;
  final int fieldCount;

  /// Template ordinals that actually exist in this notetype. Empty means
  /// "unknown", not "none".
  final List<int> templateOrdinals;

  /// Fields rendered on the front face of the template the plan targets.
  final Set<int> frontFieldOrds;

  /// Fields rendered on the back face of the template the plan targets.
  final Set<int> backFieldOrds;
}

/// Every way a plan can be rejected locally. The AI never gets to bypass these:
/// strict JSON Schema is not semantic correctness (ADR 0057 §7).
enum AdaptationIssue {
  schemaVersion,
  scopeSource,
  scopeNotetype,
  scopeTemplate,
  unknownBlockKind,
  unknownSelection,
  fieldOutOfRange,
  unknownExercise,
  unknownDefaultExercise,
  unknownBindingRole,
  unknownFallback,
  emptyFront,
  answerOnFront,
  backOnlyFieldOnFront,

  /// The plan renders nothing structured on any available sample (every
  /// layout hits unsupported structure), so activating it would pin the whole
  /// group to the original card. Produced by the sample-level check next to
  /// the validator, not by [AdaptationPlanValidator.validate] itself — the
  /// validator sees no card content.
  allSamplesUnsupported,
}

class AdaptationValidation {
  const AdaptationValidation(this.issues);

  static const AdaptationValidation valid = AdaptationValidation(<AdaptationIssue>[]);

  final List<AdaptationIssue> issues;

  bool get ok => issues.isEmpty;

  @override
  String toString() => 'AdaptationValidation(${issues.join(', ')})';
}

/// Local, semantic validation of an AI-proposed plan (ADR 0057 §7).
///
/// Order of checks mirrors the plan's validation ladder: envelope → scope →
/// vocabulary → field references → information leak. Anything that cannot be
/// proven safe is rejected rather than repaired silently.
abstract final class AdaptationPlanValidator {
  static AdaptationValidation validate(
    CardAdaptationPlan plan, {
    required AdaptationFacts facts,
  }) {
    final issues = <AdaptationIssue>[];

    if (plan.schemaVersion != AdaptationVocabulary.schemaVersion) {
      issues.add(AdaptationIssue.schemaVersion);
    }
    if (plan.scope.sourceId != facts.sourceId) {
      issues.add(AdaptationIssue.scopeSource);
    }
    if (plan.scope.notetypeId != facts.notetypeId) {
      issues.add(AdaptationIssue.scopeNotetype);
    }
    if (facts.templateOrdinals.isNotEmpty &&
        !facts.templateOrdinals.contains(plan.scope.templateOrdinal)) {
      issues.add(AdaptationIssue.scopeTemplate);
    }
    if (plan.fallback.isEmpty ||
        !AdaptationVocabulary.fallbacks.contains(plan.fallback)) {
      issues.add(AdaptationIssue.unknownFallback);
    }
    if (plan.front.isEmpty) {
      issues.add(AdaptationIssue.emptyFront);
    }

    for (final entry in plan.bindings.entries) {
      if (!AdaptationVocabulary.bindingRoles.contains(entry.key)) {
        issues.add(AdaptationIssue.unknownBindingRole);
      }
    }

    for (final exercise in plan.optionalExercises) {
      if (!AdaptationVocabulary.exerciseKinds.contains(exercise)) {
        issues.add(AdaptationIssue.unknownExercise);
      }
    }

    if (!AdaptationVocabulary.exerciseKinds.contains(plan.defaultExercise)) {
      issues.add(AdaptationIssue.unknownDefaultExercise);
    }

    for (final block in [...plan.front, ...plan.back]) {
      if (!AdaptationVocabulary.blockKinds.contains(block.kind)) {
        issues.add(AdaptationIssue.unknownBlockKind);
      }
      if (!AdaptationVocabulary.selections.contains(block.selection)) {
        issues.add(AdaptationIssue.unknownSelection);
      }
      if (block.fieldIndex < 0 || block.fieldIndex >= facts.fieldCount) {
        issues.add(AdaptationIssue.fieldOutOfRange);
      }
    }

    // Information leaks. The answer field on the question face is the worst
    // failure mode this whole feature can produce, so both the explicit
    // binding and the template's own back-only fields are checked.
    final answerField = plan.bindings['answer'];
    if (answerField != null) {
      for (final block in plan.front) {
        if (block.fieldIndex == answerField) {
          issues.add(AdaptationIssue.answerOnFront);
          break;
        }
      }
    }
    if (facts.backFieldOrds.isNotEmpty) {
      for (final block in plan.front) {
        if (facts.backFieldOrds.contains(block.fieldIndex) &&
            !facts.frontFieldOrds.contains(block.fieldIndex)) {
          issues.add(AdaptationIssue.backOnlyFieldOnFront);
          break;
        }
      }
    }

    return issues.isEmpty
        ? AdaptationValidation.valid
        : AdaptationValidation(List<AdaptationIssue>.unmodifiable(issues));
  }
}
