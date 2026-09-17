import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

enum OfficialAnkiSourceKind { official, legacy, turnaExercise }

enum OfficialAnkiReviewTarget {
  officialReviewer,
  legacyRenderer,
  flutterExercise,
  error
}

/// Source-kind routing. Official cards never enter the Legacy renderer.
class OfficialAnkiReviewerRouter {
  static OfficialAnkiReviewTarget resolve({
    required OfficialAnkiSourceKind kind,
    OfficialAnkiFeatureFlags? flags,
    bool rendererAvailable = true,
  }) {
    final resolved = flags ?? OfficialAnkiFeatureFlags.current;
    switch (kind) {
      case OfficialAnkiSourceKind.legacy:
        return OfficialAnkiReviewTarget.legacyRenderer;
      case OfficialAnkiSourceKind.turnaExercise:
        return OfficialAnkiReviewTarget.flutterExercise;
      case OfficialAnkiSourceKind.official:
        if (!resolved.allowsOfficialRenderer || !rendererAvailable) {
          return OfficialAnkiReviewTarget.error;
        }
        return OfficialAnkiReviewTarget.officialReviewer;
    }
  }

  /// Architectural invariant (ADR 0036 / doc 35 L2): Official cards must never
  /// route to the Legacy renderer under any circumstances.
  static bool officialMayUseLegacyRenderer(OfficialAnkiSourceKind kind) {
    if (kind != OfficialAnkiSourceKind.official) return false;
    return resolve(kind: kind) == OfficialAnkiReviewTarget.legacyRenderer;
  }
}
