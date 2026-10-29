import 'package:turna/application/anki_import/adaptation/card_presentation_resolver.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/domain/anki/adaptation/presentation_decision.dart';

/// What the single resolver would do with one notetype's samples (ADR 0057
/// §1, plan §13.1): every sample is resolved exactly like a lesson card and
/// the outcomes aggregate into an [AdaptationBatchSummary]. The preview shows
/// these counts instead of re-deriving modes from a second, divergent table.
class NotetypePresentationPreview {
  const NotetypePresentationPreview({
    required this.summary,
    required this.structuredKinds,
    required this.dominantKind,
  });

  final AdaptationBatchSummary summary;

  /// Every structured kind that appeared on at least one sample.
  final Set<OfficialAnkiProjectionKind> structuredKinds;

  /// The most frequent structured kind, or null when no sample stayed
  /// structured (all original / needs correction / no samples).
  final OfficialAnkiProjectionKind? dominantKind;

  /// Every structured outcome is a flip-family face, so the group reads as a
  /// classic flip group. True for an empty group only via [hasSamples]
  /// callers' own fallback.
  bool get flipOnly => structuredKinds.isEmpty
      ? true
      : structuredKinds.every(_isFlipFamily);

  bool get hasSamples => summary.total > 0;

  static bool _isFlipFamily(OfficialAnkiProjectionKind kind) =>
      kind == OfficialAnkiProjectionKind.flip ||
      kind == OfficialAnkiProjectionKind.showWord ||
      kind == OfficialAnkiProjectionKind.translate;
}

/// Resolve every (sample × template ordinal) of [schema] through the single
/// resolver and aggregate the outcome counts.
///
/// The samples are the projection's preview slice, not the whole group
/// (stratified sampling needs Rust-side support, docs/status.md §4), but the
/// decision path is byte-for-byte the lesson's: same values derivation, same
/// policy, same reasons. When no samples have been loaded yet the summary is
/// empty and callers fall back to the enabledKinds-only heuristic.
NotetypePresentationPreview resolveNotetypePresentationPreview({
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion? suggestion,
}) {
  return _resolve(
    schema: schema,
    suggestion: suggestion,
    applied: const AdaptationNoPlan(),
  );
}

/// Sample-level outcome of applying a candidate [plan] (ADR 0057 §7): every
/// sample goes through the full plan chain — bindings folded into the
/// effective mapping, layout built, unsupported structures falling back to
/// the original card — so activation can be gated on "this plan renders
/// something structured" before it is staged.
AdaptationBatchSummary resolvePlanSampleSummary({
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion? suggestion,
  required CardAdaptationPlan plan,
}) {
  return _resolve(
    schema: schema,
    suggestion: suggestion,
    applied: AdaptationPlanFound(plan, fromCardOverride: false),
  ).summary;
}

NotetypePresentationPreview _resolve({
  required OfficialAnkiProjectionSchema schema,
  required OfficialAnkiMappingSuggestion? suggestion,
  required AdaptationLookup applied,
}) {
  const resolver = OfficialCardPresentationResolver();
  const payloads = OfficialAnkiProjectionPayloads();
  final ordinals = <int>{
    for (final template
        in schema.templateFacts?.templates ?? const <OfficialAnkiTemplateFact>[])
      template.ord,
  };
  if (ordinals.isEmpty) ordinals.add(0);

  final decisions = <CardPresentationDecision>[];
  final kindCounts = <OfficialAnkiProjectionKind, int>{};
  for (final sample in schema.samples) {
    for (final ordinal in ordinals) {
      final row = OfficialAnkiProjectionRow(
        cardId: sample.noteId,
        noteId: sample.noteId,
        noteGuid: '',
        notetypeId: schema.notetypeId,
        deckId: 0,
        deckPath: const <String>[],
        templateOrdinal: ordinal,
        tags: const <String>[],
        fields: sample.fields,
        sourceFingerprint: schema.schemaFingerprint,
        truncated: sample.truncated,
      );
      final resolution = resolver.resolveCard(
        row: row,
        mapping: suggestion,
        applied: applied,
        payloads: payloads,
      );
      decisions.add(resolution.decision);
      if (resolution.decision.isStructured) {
        kindCounts[resolution.kind] = (kindCounts[resolution.kind] ?? 0) + 1;
      }
    }
  }

  OfficialAnkiProjectionKind? dominant;
  var best = 0;
  for (final entry in kindCounts.entries) {
    if (entry.value > best) {
      best = entry.value;
      dominant = entry.key;
    }
  }
  return NotetypePresentationPreview(
    summary: AdaptationBatchSummary.of(decisions),
    structuredKinds: Set.unmodifiable(kindCounts.keys),
    dominantKind: dominant,
  );
}
