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
    id: 'A6b',
    layer: RuleLayer.content,
    target: CardArchetype.choice,
    weight: ruleBackFaceOptionsWeight,
    probe: _embeddedOptionsOnBack,
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

String _pct(double rate) => '${(rate * 100).round()}%';

String? _choicePoolBound(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final response = roles[FieldRole.response];
  if (response == null) return null;

  // 1) Multi-field options (OptionA..D, A..D, Q_1..Q_4, etc.): a binding
  // signal strong enough for the auto band, so the answer must align on
  // most pool rows — not just on one lucky sample.
  final multiFieldOptionNames = facts.fieldNames
      .where((name) =>
          EmbeddedOptionsParser.isOptionFieldName(name.toLowerCase()))
      .toList();
  if (multiFieldOptionNames.length >= 2) {
    var poolRows = 0;
    var alignedRows = 0;
    for (final row in facts.samples) {
      final pool = EmbeddedOptionsParser.extractMultiFieldOptions(
        facts.fieldNames,
        row,
      );
      if (pool == null || pool.length < 2) continue;
      poolRows++;
      final answer =
          response.fieldIndex < row.length ? row[response.fieldIndex] : '';
      if (EmbeddedOptionsParser.parseCorrectIndices(answer, pool).isNotEmpty) {
        alignedRows++;
      }
    }
    final stats = ChoiceRowStats(
      totalRows: facts.samples.length,
      parseRows: poolRows,
      alignedRows: alignedRows,
    );
    if (stats.parseRate >= sampleRateThreshold &&
        stats.alignRate >= choiceAlignRateThreshold) {
      return 'multi_field_pool=${multiFieldOptionNames.length}, '
          'parse=${_pct(stats.parseRate)}, align=${_pct(stats.alignRate)}';
    }
  }

  // 2) Single option-pool field: each row aligns against its own pool
  // (pools are frequently per-row, so one global pool would misalign).
  final options = roles[FieldRole.options];
  if (options == null) return null;
  var total = 0;
  var poolRows = 0;
  var alignedRows = 0;
  for (final values in facts.samples) {
    final poolRaw =
        options.fieldIndex < values.length ? values[options.fieldIndex] : '';
    if (poolRaw.trim().isEmpty) continue;
    total++;
    final pool = EmbeddedOptionsParser.parseOptionPool(poolRaw);
    if (pool.length < 2) continue;
    poolRows++;
    final answer =
        response.fieldIndex < values.length ? values[response.fieldIndex] : '';
    if (EmbeddedOptionsParser.parseCorrectIndices(answer, pool).isNotEmpty) {
      alignedRows++;
    }
  }
  final stats = ChoiceRowStats(
    totalRows: total,
    parseRows: poolRows,
    alignedRows: alignedRows,
  );
  if (stats.parseRate >= sampleRateThreshold &&
      stats.alignRate >= choiceAlignRateThreshold) {
    return 'pool_rows=$poolRows, '
        'parse=${_pct(stats.parseRate)}, align=${_pct(stats.alignRate)}';
  }
  return null;
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
  // Iron law: option-looking fronts whose answers never align keep
  // fidelity. The floor is deliberately low — a partially choice-looking
  // deck must not silently become a flip deck.
  final prompt = roles[FieldRole.prompt];
  if (prompt == null) return null;
  final response = roles[FieldRole.response];
  final front = CardFacts.of(facts.nonEmptySamplesOf(prompt.fieldIndex));
  final likeRate = front.looksLikeOptionsRate;
  if (response == null) {
    return likeRate >= embeddedOptionsIronLawFloor ? 'answer_missing' : null;
  }
  final stats = measureChoiceRows(
    facts.pairedSamplesOf(prompt.fieldIndex, response.fieldIndex),
  );
  if (stats.alignRate >= choiceAlignRateThreshold) return null;
  final signal = likeRate > stats.parseRate ? likeRate : stats.parseRate;
  if (signal < embeddedOptionsIronLawFloor) return null;
  if (stats.parseRate < embeddedOptionsIronLawFloor) {
    return 'options_unparsed';
  }
  return 'answer_not_aligned '
      'parse=${_pct(stats.parseRate)}, align=${_pct(stats.alignRate)}';
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
  final stats = measureChoiceRows(
    facts.pairedSamplesOf(prompt.fieldIndex, response.fieldIndex),
  );
  if (stats.parseRate < sampleRateThreshold) return null;
  if (stats.alignRate < choiceAlignRateThreshold) {
    return null; // the unparsed twin owns unaligned decks
  }
  return 'parse=${_pct(stats.parseRate)}, align=${_pct(stats.alignRate)}';
}

/// Mixed deck: only part of the samples look like choice questions. The
/// floor sits below A6's rate on purpose — sparse mixed decks still get
/// recognized — and the alignment gate keeps ungradeable decks out.
String? _embeddedOptionsMixed(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final prompt = roles[FieldRole.prompt];
  final response = roles[FieldRole.response];
  if (prompt == null || response == null) return null;
  final stats = measureChoiceRows(
    facts.pairedSamplesOf(prompt.fieldIndex, response.fieldIndex),
  );
  if (stats.parseRate < embeddedOptionsMixedFloor ||
      stats.parseRate >= sampleRateThreshold) {
    return null; // A6 owns the full-rate case
  }
  if (stats.alignRate < choiceAlignRateThreshold) return null;
  return 'mixed parse=${_pct(stats.parseRate)}, align=${_pct(stats.alignRate)}';
}

/// Options-on-back layout: the front carries the stem, the back carries
/// both the options and an explicit answer marker (`答案：B`). A6/A6m own
/// fronts that carry their own options, so this only competes on the
/// rest; review-band weight — a newer pattern, proven before promoted.
String? _embeddedOptionsOnBack(
  NotetypeFacts facts,
  Map<FieldRole, FieldBinding> roles,
) {
  final prompt = roles[FieldRole.prompt];
  final response = roles[FieldRole.response];
  if (prompt == null || response == null) return null;
  var total = 0;
  var parsed = 0;
  for (final values in facts.samples) {
    final back =
        response.fieldIndex < values.length ? values[response.fieldIndex] : '';
    if (back.trim().isEmpty) continue;
    total++;
    if (EmbeddedOptionsParser.extractBackFaceChoice(back) != null) parsed++;
  }
  if (total == 0) return null;
  final rate = parsed / total;
  return rate >= backFaceOptionsParseFloor
      ? 'back_options parse=${_pct(rate)}'
      : null;
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
