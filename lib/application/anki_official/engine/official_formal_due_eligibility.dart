import 'package:turna/domain/anki/canonical_card_key.dart';

/// Exact formal-due membership for Official Anki review.
///
/// Card-key intersection only — never approximate with
/// `min(schedulerDueCount, introducedCount)`.
Set<CanonicalCardKey> computeFormalDueCardKeys({
  required Set<CanonicalCardKey> officialSchedulerDueCardKeys,
  required Set<CanonicalCardKey> activePlacementCardKeys,
  required Set<CanonicalCardKey> introducedCardKeys,
  Set<CanonicalCardKey> suspendedCardKeys = const {},
  Set<CanonicalCardKey> buriedCardKeys = const {},
  Set<CanonicalCardKey> retiredCardKeys = const {},
}) {
  return officialSchedulerDueCardKeys
      .intersection(activePlacementCardKeys)
      .intersection(introducedCardKeys)
      .difference(suspendedCardKeys)
      .difference(buriedCardKeys)
      .difference(retiredCardKeys);
}

/// Same formula over raw Official card ids for one source.
Set<CanonicalCardKey> computeFormalDueCardKeysForSource({
  required String sourceId,
  required Set<int> officialSchedulerDueCardIds,
  required Set<int> activePlacementCardIds,
  required Set<int> introducedCardIds,
  Set<int> suspendedCardIds = const {},
  Set<int> buriedCardIds = const {},
  Set<int> retiredCardIds = const {},
  String profileId = 'profile-default-01',
}) {
  CanonicalCardKey key(int cardId) => CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profileId,
        sourceId: sourceId,
        cardId: cardId,
      );

  return computeFormalDueCardKeys(
    officialSchedulerDueCardKeys: {
      for (final id in officialSchedulerDueCardIds) key(id),
    },
    activePlacementCardKeys: {
      for (final id in activePlacementCardIds) key(id),
    },
    introducedCardKeys: {
      for (final id in introducedCardIds) key(id),
    },
    suspendedCardKeys: {
      for (final id in suspendedCardIds) key(id),
    },
    buriedCardKeys: {
      for (final id in buriedCardIds) key(id),
    },
    retiredCardKeys: {
      for (final id in retiredCardIds) key(id),
    },
  );
}
