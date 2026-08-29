import 'package:turna/domain/anki/canonical_card_key.dart';

/// Exact formal-due membership for Official Anki review.
///
/// P1: the scheduler is the gate. Unintroduced course cards stay suspended
/// (the lock reconciler enforces it), and `(is:due OR is:learn OR is:new)`
/// queue/search/counts already exclude suspended and buried cards — so the
/// only remaining Dart-side terms are placement (which cards this source
/// owns) and retired (uninstall remnants the collector may still report).
/// There is deliberately no `introduced` term anymore: it read a fragile
/// in-memory mirror whose cold-start emptiness filtered out every due card.
Set<CanonicalCardKey> computeFormalDueCardKeys({
  required Set<CanonicalCardKey> officialSchedulerDueCardKeys,
  required Set<CanonicalCardKey> activePlacementCardKeys,
  Set<CanonicalCardKey> retiredCardKeys = const {},
}) {
  return officialSchedulerDueCardKeys
      .intersection(activePlacementCardKeys)
      .difference(retiredCardKeys);
}

/// Same formula over raw Official card ids for one source.
Set<CanonicalCardKey> computeFormalDueCardKeysForSource({
  required String sourceId,
  required Set<int> officialSchedulerDueCardIds,
  required Set<int> activePlacementCardIds,
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
    retiredCardKeys: {
      for (final id in retiredCardIds) key(id),
    },
  );
}
