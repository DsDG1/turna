import '../config.dart';
import '../facts/card_facts.dart';
import '../facts/notetype_facts.dart';
import '../facts/options_structure.dart';
import '../lexicon/field_roles.dart';
import 'result.dart';

/// Signal layer of a rule. Ties between equal-weight rules break by
/// layer first (structure > binding > content), then by table order.
enum RuleLayer { structure, binding, content }

/// One declarative archetype rule (§3.6). Rules are independent: adding
/// one never changes another's semantics — the defining difference from
/// the old 8-step if-else ladder.
class ArchetypeRule {
  const ArchetypeRule({
    required this.id,
    required this.layer,
    required this.target,
    required this.weight,
    required this.probe,
  });

  final String id;
  final RuleLayer layer;
  final CardArchetype target;
  final double weight;

  /// Returns evidence detail when the rule fires, null when it does not.
  final String? Function(NotetypeFacts facts, Map<FieldRole, FieldBinding> roles)
      probe;
}

/// Inputs a rule probe may need beyond the facts themselves are computed
/// by the recognizer (see [recognizeNotetype]); the table stays pure.

/// The v1 rule table. Order matters only for tie-breaking inside the
/// same layer; weights come from config.dart.
const List<ArchetypeRule> archetypeRules = [
  ArchetypeRule(
    id: 'A1',
    layer: RuleLayer.structure,
    target: CardArchetype.cloze,
    weight: ruleClozeDeclaredWeight,
    probe: _declaredCloze,
  ),
  ArchetypeRule(
    id: 'A2',
    layer: RuleLayer.structure,
    target: CardArchetype.richHtml,
    weight: ruleTemplateRichHtmlWeight,
    probe: _templateRichHtml,
  ),
  ArchetypeRule(
    id: 'A3',
    layer: RuleLayer.structure,
    target: CardArchetype.typeIn,
    weight: ruleTypeInWeight,
    probe: _templateTypeIn,
  ),
  ArchetypeRule(
    id: 'A4',
    layer: RuleLayer.binding,
    target: CardArchetype.choice,
    weight: ruleChoiceBoundWeight,
    probe: _choicePoolBound,
  ),
  ArchetypeRule(
    id: 'A2c-script',
    layer: RuleLayer.content,
    target: CardArchetype.richHtml,
    weight: ruleContentScriptWeight,
    probe: _contentScript,
  ),
  ArchetypeRule(
    id: 'A2c-complex',
    layer: RuleLayer.content,
    target: CardArchetype.richHtml,
    weight: ruleContentComplexHtmlWeight,
    probe: _contentComplexHtml,
  ),
  ArchetypeRule(
    id: 'A6-unparsed',
    layer: RuleLayer.content,
    target: CardArchetype.richHtml,
    weight: ruleEmbeddedOptionsUnparsedWeight,
    probe: _embeddedOptionsUnparsed,
  ),
  ArchetypeRule(
    id: 'A5',
    layer: RuleLayer.content,
    target: CardArchetype.cloze,
    weight: ruleSampleClozeWeight,
    probe: _sampleClozeMarkers,
  ),
  ArchetypeRule(
    id: 'A6',
    layer: RuleLayer.content,
    target: CardArchetype.choice,
    weight: ruleEmbeddedOptionsWeight,
    probe: _embeddedOptions,
  ),
  ArchetypeRule(
    id: 'A6m',
    layer: RuleLayer.content,
    target: CardArchetype.choice,
    weight: ruleEmbeddedOptionsMixedWeight,
    probe: _embeddedOptionsMixed,
  ),
  ArchetypeRule(
    id: 'A7',
    layer: RuleLayer.content,
    target: CardArchetype.audioFirst,
    weight: ruleAudioFirstWeight,
    probe: _audioFirst,
  ),
  ArchetypeRule(
    id: 'A8',
    layer: RuleLayer.content,
    target: CardArchetype.basicPair,
    weight: ruleShortPairWeight,
    probe: _shortPair,
  ),
];

String? _declaredCloze(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  return facts.isClozeKind ? 'kind=cloze' : null;
}

String? _templateRichHtml(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  if (!facts.hasTemplateFacts) return null;
  if (facts.hasTemplateScript) return 'template:script';
  if (facts.hasTemplateComplexHtml) return 'template:complex_html';
  return null;
}

String? _templateTypeIn(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  return facts.hasTypeInFilter ? 'template:{{type:}}' : null;
}

String? _choicePoolBound(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final response = roles[FieldRole.response];

  // 1) Multi-field options check (OptionA..D, A..D, Q_1..Q_4, etc.)
  final multiFieldOptionNames = facts.fieldNames
      .where((name) =>
          EmbeddedOptionsParser.isOptionFieldName(name.toLowerCase()))
      .toList();
  if (multiFieldOptionNames.length >= 2 && response != null) {
    for (final sample in facts.samples) {
      final pool = EmbeddedOptionsParser.extractMultiFieldOptions(
        facts.fieldNames,
        sample,
      );
      if (pool != null && pool.length >= 2) {
        if (response.fieldIndex < sample.length) {
          final ans = sample[response.fieldIndex];
          final correct =
              EmbeddedOptionsParser.parseCorrectIndices(ans, pool);
          if (correct.isNotEmpty) {
            return 'multi_field_pool=${pool.length}, answer=${pool[correct.first]}';
          }
        }
      }
    }
  }

  // 2) Single option-pool field check
  final options = roles[FieldRole.options];
  if (options == null || response == null) return null;
  final pool = CardFacts.of(facts.nonEmptySamplesOf(options.fieldIndex))
      .parseOptionPool();
  if (pool.length < 2) return null;
  final correct = CardFacts.of(facts.nonEmptySamplesOf(response.fieldIndex))
      .parseCorrectIndices(pool);
  if (correct.isEmpty) return null;
  return 'pool=${pool.length}, answer=${pool[correct.first]}';
}

String? _contentScript(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final probe = CardFacts.of(facts.samples.expand((v) => v).toList());
  return probe.anyContainsScript ? 'sample:script' : null;
}

String? _contentComplexHtml(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final probe = CardFacts.of(facts.samples.expand((v) => v).toList());
  return probe.anyContainsComplexHtml ? 'sample:complex_html' : null;
}

String? _embeddedOptionsUnparsed(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  // Iron law: the front face looks like an options list but the answer
  // never aligns → the notetype is untrustworthy, keep fidelity.
  final prompt = roles[FieldRole.prompt];
  final response = roles[FieldRole.response];
  if (prompt == null) return null;
  final front = CardFacts.of(facts.nonEmptySamplesOf(prompt.fieldIndex));
  if (front.looksLikeOptionsRate < sampleRateThreshold) return null;
  final embedded = front.extractEmbeddedOptions();
  if (embedded == null) return 'options_unparsed';
  if (response == null) return 'answer_missing';
  final aligned = CardFacts.of(facts.nonEmptySamplesOf(response.fieldIndex))
      .parseCorrectIndices(embedded.options);
  return aligned.isEmpty ? 'answer_not_aligned' : null;
}

String? _sampleClozeMarkers(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  if (facts.isClozeKind) return null; // A1 already owns declared cloze
  final probe = CardFacts.of(facts.samples.expand((v) => v).toList());
  final rate = probe.clozeMarkerRate;
  return rate >= sampleRateThreshold
      ? 'cloze_markers=${(rate * 100).round()}%'
      : null;
}

String? _embeddedOptions(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final prompt = roles[FieldRole.prompt];
  final response = roles[FieldRole.response];
  if (prompt == null || response == null) return null;
  final front = CardFacts.of(facts.nonEmptySamplesOf(prompt.fieldIndex));
  if (front.looksLikeOptionsRate < sampleRateThreshold) return null;
  final embedded = front.extractEmbeddedOptions();
  if (embedded == null) return null; // the unparsed twin already fired
  final aligned = CardFacts.of(facts.nonEmptySamplesOf(response.fieldIndex))
      .parseCorrectIndices(embedded.options);
  return aligned.isEmpty ? null : '${embedded.options.length} options';
}

/// Mixed deck: only part of the samples look like choice questions. Fires
/// below the A6 rate threshold but still requires answer alignment, and its
/// lower weight keeps the result in the review band for user confirmation.
String? _embeddedOptionsMixed(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final prompt = roles[FieldRole.prompt];
  final response = roles[FieldRole.response];
  if (prompt == null || response == null) return null;
  final front = CardFacts.of(facts.nonEmptySamplesOf(prompt.fieldIndex));
  final rate = front.looksLikeOptionsRate;
  if (rate < embeddedOptionsReviewRate || rate >= sampleRateThreshold) {
    return null; // A6 owns the full-rate case
  }
  final embedded = front.extractEmbeddedOptions();
  if (embedded == null) return null;
  final aligned = CardFacts.of(facts.nonEmptySamplesOf(response.fieldIndex))
      .parseCorrectIndices(embedded.options);
  return aligned.isEmpty
      ? null
      : 'mixed ${embedded.options.length} options';
}

String? _audioFirst(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final audio = roles[FieldRole.audio];
  final response = roles[FieldRole.response];
  if (audio == null || response == null) return null;
  // Structure: the audio field renders on a front template; content:
  // sound markers live in the prompt-bound field's samples.
  final audioOnFront = facts.hasTemplateFacts &&
      facts.frontFieldOrds.contains(audio.fieldIndex);
  final prompt = roles[FieldRole.prompt];
  final promptHasSound = prompt != null &&
      CardFacts.of(facts.nonEmptySamplesOf(prompt.fieldIndex)).anyContainsSound;
  if (!audioOnFront && !promptHasSound) return null;
  final answerShort = CardFacts.of(facts.nonEmptySamplesOf(response.fieldIndex))
      .shortRate;
  return answerShort >= sampleRateThreshold
      ? 'front_audio+short_answer=${(answerShort * 100).round()}%'
      : null;
}

String? _shortPair(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final prompt = roles[FieldRole.prompt];
  final response = roles[FieldRole.response];
  if (prompt == null || response == null) return null;
  final front = CardFacts.of(facts.nonEmptySamplesOf(prompt.fieldIndex));
  final back = CardFacts.of(facts.nonEmptySamplesOf(response.fieldIndex));
  if (front.isEmpty || back.isEmpty) return null;
  final bothShort = front.shortRate < back.shortRate
      ? front.shortRate
      : back.shortRate;
  final frontSentence = front.sentenceRate;
  final backSentence = back.sentenceRate;
  final nonSentence = frontSentence < backSentence
      ? 1 - backSentence
      : 1 - frontSentence;
  return (bothShort >= sampleRateThreshold &&
          nonSentence >= sampleRateThreshold)
      ? 'short_pair'
      : null;
}
