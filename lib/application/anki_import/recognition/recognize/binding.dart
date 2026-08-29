import '../config.dart';
import '../facts/card_facts.dart';
import '../facts/notetype_facts.dart';
import '../lexicon/field_roles.dart';
import 'result.dart';

/// L1: assigns each field its best role from accumulated evidence
/// (lexicon + structure + positional priors + value shapes), then a
/// global greedy pass resolves conflicts. Fields number 2–10 typically;
/// greedy is within noise of optimal at that size (§3.5).
class RoleBindingSolver {
  const RoleBindingSolver();

  Map<FieldRole, FieldBinding> bind(NotetypeFacts facts) {
    final scores = <_FieldScore>[];
    final frontOrds = facts.frontFieldOrds;
    final backOnlyOrds = facts.backOnlyFieldOrds;
    final ttsFields = facts.ttsFieldNames;

    for (var index = 0; index < facts.fieldNames.length; index++) {
      final name = facts.fieldNames[index];
      final samples = CardFacts.of(facts.nonEmptySamplesOf(index));
      final signals = <_Signal>[];

      void add(FieldRole role, double weight, String signal, [String detail = '']) {
        signals.add(_Signal(role, weight, signal, detail));
      }

      final exact = exactRoleFor(name);
      if (exact != null) {
        add(exact, lexiconExactWeight, 'lexicon:exact', name);
      }
      for (final role in containsRolesFor(name)) {
        add(role, lexiconContainsWeight, 'lexicon:contains', name);
      }
      if (frontOrds.contains(index)) {
        add(FieldRole.prompt, structuralFrontWeight, 'structure:front_template');
      }
      if (backOnlyOrds.contains(index)) {
        add(FieldRole.response, structuralBackWeight, 'structure:back_template');
      }
      if (index == 0) {
        add(FieldRole.prompt, positionalFrontWeight, 'positional:first_field');
      }
      if (index == 1) {
        add(FieldRole.response, positionalBackWeight, 'positional:second_field');
      }
      if (samples.anyContainsSound) {
        add(FieldRole.audio, sampleAudioWeight, 'sample:sound_ref');
      }
      if (samples.anyContainsImage) {
        add(FieldRole.image, sampleImageWeight, 'sample:image_ref');
      }
      if (ttsFields.contains(name)) {
        add(FieldRole.audio, templateTtsWeight, 'structure:tts_filter');
      }
      if (samples.plainShortRate > 0) {
        add(FieldRole.prompt, sampleShortTextWeight, 'sample:plain_text');
        add(FieldRole.response, sampleShortTextWeight, 'sample:plain_text');
      }

      scores.add(_FieldScore(index, name, samples, signals));
    }

    // Greedy global assignment: strongest (field, role) claims first.
    final claims = <_Claim>[];
    for (final field in scores) {
      final byRole = <FieldRole, double>{};
      for (final signal in field.signals) {
        byRole[signal.role] = (byRole[signal.role] ?? 0) + signal.weight;
      }
      byRole.updateAll(
        (_, value) => value.clamp(0, bindingScoreCap).toDouble(),
      );
      final ordered = byRole.entries.toList()
        ..sort((a, b) {
          final byScore = b.value.compareTo(a.value);
          if (byScore != 0) return byScore;
          return fieldRolePriority(a.key).compareTo(fieldRolePriority(b.key));
        });
      field.rankedRoles = ordered;
      for (final entry in ordered) {
        claims.add(_Claim(field, entry.key, entry.value));
      }
    }
    claims.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byPriority =
          fieldRolePriority(a.role).compareTo(fieldRolePriority(b.role));
      if (byPriority != 0) return byPriority;
      return a.field.index.compareTo(b.field.index);
    });

    final assignedFields = <int>{};
    final assignedRoles = <FieldRole>{};
    final bindings = <FieldRole, FieldBinding>{};
    for (final claim in claims) {
      if (claim.score <= 0) continue;
      if (assignedFields.contains(claim.field.index)) continue;
      if (claim.role == FieldRole.ignored) continue;
      if (assignedRoles.contains(claim.role)) continue;
      final evidence = [
        for (final signal in claim.field.signals)
          if (signal.role == claim.role)
            RecognitionEvidence(
              signal: signal.signal,
              weight: signal.weight,
              detail: signal.detail,
            ),
      ];
      bindings[claim.role] = FieldBinding(
        role: claim.role,
        fieldIndex: claim.field.index,
        fieldName: claim.field.name,
        confidence: claim.score,
        evidence: evidence,
      );
      assignedFields.add(claim.field.index);
      assignedRoles.add(claim.role);
    }

    // Fallback pass mirrors the old positional fallback: a notetype
    // without prompt/response bindings still gets the best remaining
    // non-media fields so projection always has a plan.
    _fallbackBind(
      facts,
      bindings,
      assignedFields,
      scores,
      FieldRole.prompt,
      'positional:front',
    );
    _fallbackBind(
      facts,
      bindings,
      assignedFields,
      scores,
      FieldRole.response,
      'positional:back',
    );

    return bindings;
  }

  void _fallbackBind(
    NotetypeFacts facts,
    Map<FieldRole, FieldBinding> bindings,
    Set<int> assignedFields,
    List<_FieldScore> scores,
    FieldRole role,
    String signal,
  ) {
    if (bindings.containsKey(role)) return;
    if (role == FieldRole.response) {
      // Single-field and cloze-declared notetypes have no back side.
      if (facts.isClozeKind || facts.fieldNames.length <= 1) return;
    }
    for (final field in scores) {
      if (assignedFields.contains(field.index)) continue;
      final isMedia = field.rankedRoles.any((entry) =>
          entry.key == FieldRole.audio || entry.key == FieldRole.image);
      if (isMedia) continue;
      bindings[role] = FieldBinding(
        role: role,
        fieldIndex: field.index,
        fieldName: field.name,
        confidence: positionalFallbackConfidence,
        evidence: [
          RecognitionEvidence(
            signal: signal,
            weight: positionalFallbackConfidence,
          ),
        ],
      );
      assignedFields.add(field.index);
      return;
    }
  }
}

class _Signal {
  const _Signal(this.role, this.weight, this.signal, this.detail);

  final FieldRole role;
  final double weight;
  final String signal;
  final String detail;
}

class _FieldScore {
  _FieldScore(this.index, this.name, this.samples, this.signals);

  final int index;
  final String name;
  final CardFacts samples;
  final List<_Signal> signals;
  List<MapEntry<FieldRole, double>> rankedRoles = const [];
}

class _Claim {
  const _Claim(this.field, this.role, this.score);

  final _FieldScore field;
  final FieldRole role;
  final double score;
}
