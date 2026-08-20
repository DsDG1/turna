const officialAnkiProjectionPageDefault = 200;
const officialAnkiProjectionPageMax = 500;
const officialAnkiProjectionAlgorithmVersion = 2;
const officialAnkiProjectionItemJsonMaxBytes = 32 * 1024;
const officialAnkiProjectionLessonJsonMaxBytes = 512 * 1024;
const officialAnkiProjectionStaleHeartbeatMillis = 30 * 1000;

/// Stable per-profile writer identity. Must not be per-widget or per-tick.
String officialAnkiProjectionOwnerToken(String profileId) {
  return 'owner-profile-$profileId';
}

class OfficialAnkiSourceCardPage {
  const OfficialAnkiSourceCardPage({
    required this.cardIds,
    required this.lastCardId,
    required this.hasMore,
  });

  final List<int> cardIds;
  final int? lastCardId;
  final bool hasMore;
}
