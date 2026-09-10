import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import '../config.dart';
import '../facts/card_facts.dart';
import '../facts/notetype_facts.dart';
import '../lexicon/field_roles.dart';
import 'archetypes.dart';
import 'binding.dart';
import 'result.dart';

/// L2 entry: recognize one notetype from its declared structure, sample
/// values, and derived template facts. Runs once per notetype — never per
/// card (doc 37 §3.1), so cost scales with notetype count, not card count.
class CardRecognizer {
  const CardRecognizer({this.bindingSolver = const RoleBindingSolver()});

  final RoleBindingSolver bindingSolver;

  RecognitionResult recognizeNotetype(OfficialAnkiProjectionSchema schema) {
    return recognizeFacts(NotetypeFacts.fromSchema(schema));
  }

  RecognitionResult recognizeFacts(NotetypeFacts facts) {
    final roles = bindingSolver.bind(facts);
    final evidence = <RecognitionEvidence>[];

    // Evaluate every rule independently; collect fired evidence.
    ArchetypeRule? winner;
    for (final rule in archetypeRules) {
      final detail = rule.probe(facts, roles);
      if (detail == null) continue;
      evidence.add(RecognitionEvidence(
        signal: '${rule.id}:$detail',
        weight: rule.weight,
        detail: detail,
        target: rule.target,
      ));
      if (winner == null) {
        winner = rule;
        continue;
      }
      final byWeight = rule.weight.compareTo(winner.weight);
      if (byWeight > 0) {
        winner = rule;
      } else if (byWeight == 0 &&
          _layerRank(rule.layer) < _layerRank(winner.layer)) {
        winner = rule;
      }
    }

    CardArchetype archetype;
    var confidence = 0.0;
    if (winner != null) {
      archetype = winner.target;
      confidence =
          winner.weight + _corroboration(winner, facts, roles, archetype);
    } else {
      // A9 default: the universal pair, stronger when a prompt side is
      // bound at all (a response or a single-field layout both count).
      archetype = CardArchetype.basicPair;
      final promptBound = roles.containsKey(FieldRole.prompt);
      final pairBound = promptBound &&
          (roles.containsKey(FieldRole.response) || facts.fieldNames.length <= 1);
      confidence = pairBound
          ? ruleDefaultPairedWeight
          : ruleDefaultBareWeight;
      evidence.add(RecognitionEvidence(
        signal: 'A9:default',
        weight: confidence,
        detail: pairBound ? 'pair_bound' : 'no_pair',
        target: CardArchetype.basicPair,
      ));
    }
    if (confidence > 1.0) confidence = 1.0;

    return RecognitionResult(
      archetype: archetype,
      confidence: confidence,
      evidence: evidence,
      roles: roles,
      fieldCount: facts.fieldNames.length,
      templateFactsHash: facts.templateFactsHash,
    );
  }

  /// Corroboration raises a winning content rule when an independent
  /// binding-level fact agrees (§3.6 bands make the difference between
  /// "auto" and "review", so the bonus is deliberate and small). A6/A7
  /// probes already verify answer alignment / audio binding internally;
  /// the bonus recognizes that built-in consistency check. A basicPair
  /// win is corroborated when the prompt/response bindings themselves
  /// carry strong agreement — lexicon + structure, or (R1) template
  /// faces backing both sides when the lexicon does not know the names.
  double _corroboration(
    ArchetypeRule winner,
    NotetypeFacts facts,
    Map<FieldRole, FieldBinding> roles,
    CardArchetype archetype,
  ) {
    if (winner.id == 'A6' || winner.id == 'A7') {
      return corroboratedContentBonus;
    }
    if (archetype == CardArchetype.basicPair) {
      final prompt = roles[FieldRole.prompt];
      final response = roles[FieldRole.response];
      if (prompt == null || response == null) return 0;
      // Unresolved choice signal: option-looking content that no choice
      // rule could verify. Corroborating a silent auto flip over it is
      // exactly how mixed decks used to become flip cards without a
      // review — the deck belongs in the review band instead.
      for (final binding in [prompt, response]) {
        final rate = CardFacts.of(
          facts.nonEmptySamplesOf(binding.fieldIndex),
        ).looksLikeOptionsRate;
        if (rate >= unresolvedOptionSignalFloor) return 0;
      }
      final strongScores = prompt.confidence >= bandAutoMin &&
          response.confidence >= bandAutoMin;
      bool hasSignal(FieldBinding binding, String signal) =>
          binding.evidence.any((item) => item.signal == signal);
      final structureBacked = facts.hasTemplateFacts &&
          hasSignal(prompt, 'structure:front_template') &&
          hasSignal(response, 'structure:back_template');
      return (strongScores || structureBacked) ? corroboratedPairBonus : 0;
    }
    return 0;
  }
}

int _layerRank(RuleLayer layer) {
  return switch (layer) {
    RuleLayer.structure => 0,
    RuleLayer.binding => 1,
    RuleLayer.content => 2,
  };
}
