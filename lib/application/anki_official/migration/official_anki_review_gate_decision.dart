import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';

enum OfficialAnkiReviewGateDecision {
  useLegacy,
  openOfficial,
  failClosed,
}

/// Production review split. Official-routed sources never silently
/// fall back to Legacy session.
OfficialAnkiReviewGateDecision decideOfficialReviewGate({
  required bool cutoverEnabled,
  required AnkiEngineKind routedEngine,
  required bool catalogPresent,
  required bool hasReviewTarget,
  required bool canOpenOfficialReview,
}) {
  if (!cutoverEnabled) return OfficialAnkiReviewGateDecision.useLegacy;
  if (routedEngine != AnkiEngineKind.official) {
    return OfficialAnkiReviewGateDecision.useLegacy;
  }
  if (!catalogPresent || !hasReviewTarget || !canOpenOfficialReview) {
    return OfficialAnkiReviewGateDecision.failClosed;
  }
  return OfficialAnkiReviewGateDecision.openOfficial;
}
