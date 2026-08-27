// Project imports:
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';

/// User-facing exercise presets for the official mapping page. Each preset
/// writes a concrete `enabledKinds` list onto the suggestion;
/// [CardPresentationPolicy] still combines it with the per-card classifier
/// shape, so a preset never forces an unsupported kind onto a card — it
/// constrains what may be picked, with flip/canonicalLink as fallbacks.
enum OfficialExercisePreset { auto, choice, fillBlank, listen, flip }

/// The kind whitelist a preset maps to. Order matches the policy's fallback
/// chain; every preset keeps 'canonicalLink' so unrecognizable cards stay
/// importable as fidelity links.
const Map<OfficialExercisePreset, List<String>> _presetKinds = {
  OfficialExercisePreset.auto: [
    'showWord',
    'flip',
    'multipleChoice',
    'multiSelect',
    'listenPick',
    'typeAnswer',
    'fillBlank',
    'canonicalLink',
  ],
  OfficialExercisePreset.choice: [
    'multipleChoice',
    'multiSelect',
    'flip',
    'canonicalLink',
  ],
  OfficialExercisePreset.fillBlank: ['fillBlank', 'flip', 'canonicalLink'],
  OfficialExercisePreset.listen: ['listenPick', 'flip', 'canonicalLink'],
  OfficialExercisePreset.flip: ['flip', 'showWord', 'canonicalLink'],
};

List<String> presetKinds(OfficialExercisePreset preset) =>
    _presetKinds[preset]!;

/// Reverse of [presetKinds] for restoring the chip state from a stored
/// suggestion: an exact set match recovers the preset, anything else
/// (including the default full list with 'typeAnswer' variations) reads as
/// [OfficialExercisePreset.auto].
OfficialExercisePreset presetOf(List<String> enabledKinds) {
  final set = enabledKinds.toSet();
  for (final entry in _presetKinds.entries) {
    if (set.length == entry.value.length &&
        set.containsAll(entry.value)) {
      return entry.key;
    }
  }
  return OfficialExercisePreset.auto;
}

/// Apply a preset to a suggestion, leaving roles/status untouched.
OfficialAnkiMappingSuggestion withPreset(
  OfficialAnkiMappingSuggestion suggestion,
  OfficialExercisePreset preset,
) {
  return suggestion.copyWith(enabledKinds: presetKinds(preset));
}
