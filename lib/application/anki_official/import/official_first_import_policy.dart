import '../official_anki_feature_flags.dart';

/// P5F-1 gate: whether the import wizard runs the official Anki saga BEFORE
/// any Turna-side write (official-first sequencing).
///
/// Requires the opt-in [OfficialAnkiFeatureFlags.officialFirstImport] flag on
/// top of the facade's official decision ([officialCapable]), a real package
/// file (the sample deck is synthetic) and an `.apkg` extension — the
/// official saga rejects `.colpkg`, so those stay on the legacy order.
bool officialFirstImportEligible({
  required bool isSample,
  required bool officialCapable,
  required OfficialAnkiFeatureFlags flags,
  required String filePath,
}) {
  if (isSample) return false;
  if (!officialCapable) return false;
  if (!flags.allowsOfficialFirstImport) return false;
  return filePath.toLowerCase().endsWith('.apkg');
}
