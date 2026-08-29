import 'package:turna/domain/anki/canonical_card_key.dart';

/// Exact formal-due membership for Official Anki review.
///
/// P1: the scheduler is the gate. Unintroduced course cards stay suspended
/// (the lock reconciler enforces it), so the queue a session serves never
/// contains them.
///
/// The `suspended`/`buried` subtraction terms are load-bearing, not
/// informational: Anki matches `is:new` and `is:learn` on the card TYPE,
/// and suspending/burying only rewrites the queue — a suspended new card
/// still answers `is:new`, so a search-collected schedulerDue does carry
/// the suspended backlog. Without the subtraction the due badge counts the
/// whole unintroduced deck. There is deliberately no `introduced` term: it
/// read a fragile in-memory mirror whose cold-start emptiness filtered out
/// every due card.
Set<CanonicalCardKey> computeFormalDueCardKeys({
  required Set<CanonicalCardKey> officialSchedulerDueCardKeys,
  required Set<CanonicalCardKey> activePlacementCardKeys,
  Set<CanonicalCardKey> suspendedCardKeys = const {},
  Set<CanonicalCardKey> buriedCardKeys = const {},
  Set<CanonicalCardKey> retiredCardKeys = const {},
}) {
  return officialSchedulerDueCardKeys
      .intersection(activePlacementCardKeys)
      .difference(suspendedCardKeys)
      .difference(buriedCardKeys)
      .difference(retiredCardKeys);
}

/// Same formula over raw Official card ids for one source.
Set<CanonicalCardKey> computeFormalDueCardKeysForSource({
  required String sourceId,
  required Set<int> officialSchedulerDueCardIds,
  required Set<int> activePlacementCardIds,
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
