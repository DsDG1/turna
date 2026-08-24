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
  if (routedEngine != AnkiEngineKind.official) {
    return OfficialAnkiReviewGateDecision.useLegacy;
  }
  // Recorded Official owner stays Official (doc 34 W0-06). Cutover pause or
  // missing capability is fail-closed, never a Legacy assembler.
  if (!cutoverEnabled ||
      !catalogPresent ||
      !hasReviewTarget ||
      !canOpenOfficialReview) {
    return OfficialAnkiReviewGateDecision.failClosed;
  }
  return OfficialAnkiReviewGateDecision.openOfficial;
}
