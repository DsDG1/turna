// Unit tests for the official-path exercise presets: presets must round-trip
// through `enabledKinds`, preserve the suggestion's role mapping, and never
// drop 'canonicalLink' (otherwise unrecognizable cards become
// unimportable).

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_exercise_presets.dart';

void main() {
  test('default suggestion kinds read as the auto preset', () {
    const suggestion = OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.auto,
      candidates: [],
    );
    expect(presetOf(suggestion.enabledKinds), OfficialExercisePreset.auto);
  });

  test('every preset round-trips through presetOf', () {
    for (final preset in OfficialExercisePreset.values) {
      expect(presetOf(presetKinds(preset)), preset,
          reason: 'preset $preset must survive a save/reload cycle');
    }
  });

  test('every preset keeps canonicalLink importable', () {
    for (final preset in OfficialExercisePreset.values) {
      expect(presetKinds(preset), contains('canonicalLink'));
    }
  });

  test('unknown kind combinations fall back to auto', () {
    expect(
      presetOf(const ['flip', 'multipleChoice']),
      OfficialExercisePreset.auto,
    );
  });

  test('withPreset rewrites kinds and keeps roles', () {
    const suggestion = OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.auto,
      candidates: [
        OfficialAnkiFieldCandidate(
          role: FieldRole.prompt,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 0.95,
          evidence: ['rule'],
        ),
      ],
    );
    final next = withPreset(suggestion, OfficialExercisePreset.listen);
    expect(next.enabledKinds, presetKinds(OfficialExercisePreset.listen));
    expect(
      next.role(FieldRole.prompt)?.fieldName,
      'Front',
      reason: 'exercise choice must not touch field roles',
    );
    expect(suggestion.enabledKinds, isNot(next.enabledKinds),
        reason: 'original suggestion stays untouched');
  });
}
