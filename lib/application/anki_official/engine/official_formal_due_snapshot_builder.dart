import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';

/// Explicit input for one source's six sets (maintainability plan §7.1).
///
/// Every field distinguishes "known empty" (the default — the sync read the
/// collection and found nothing) from "unknown / not fetched"
/// ([schedulerDueSynced] false, which fails the whole source closed to
/// [FormalDueKnowledge.unknown]). Preserving a previous value is NOT
/// expressible here: that is a repository mutation, never a refresh input.
@immutable
class OfficialFormalDueSourceInput {
  const OfficialFormalDueSourceInput({
    required this.importId,
    required this.schedulerDueCardIds,
    required this.schedulerDueSynced,
    this.activePlacementCardIds = const {},
    this.suspendedCardIds = const {},
    this.buriedCardIds = const {},
    this.retiredCardIds = const {},
  });

  final String importId;
  final Set<int> schedulerDueCardIds;
  final bool schedulerDueSynced;
  final Set<int> activePlacementCardIds;
  final Set<int> suspendedCardIds;
  final Set<int> buriedCardIds;
  final Set<int> retiredCardIds;
}

/// Collects every source's six sets plus sync-level counters into ONE
/// [OfficialFormalDueUpdate]. The repository never sees partial data: the
/// builder is the only place a refresh's raw collection results turn into a
/// commit payload.
class OfficialFormalDueSnapshotBuilder {
  const OfficialFormalDueSnapshotBuilder();

  OfficialFormalDueUpdate build({
    required Iterable<OfficialFormalDueSourceInput> sources,
    Map<String, int> rawDueBySource = const {},
    int turnaDue = 0,
    int unintroducedNew = 0,
    bool unavailable = false,
    Object? error,
  }) {
    final bySource = <String, OfficialFormalDuePerSource>{};
    for (final input in sources) {
      bySource[input.importId] = OfficialFormalDuePerSource(
        importId: input.importId,
        knowledge: input.schedulerDueSynced
            ? FormalDueKnowledge.known
            : FormalDueKnowledge.unknown,
        schedulerDueCardIds: input.schedulerDueCardIds,
        activePlacementCardIds: input.activePlacementCardIds,
        introducedCardIds:
            CardIntroductionStore.resolve().introducedCardIdsForSource(
          input.importId,
        ),
        suspendedCardIds: input.suspendedCardIds,
        buriedCardIds: input.buriedCardIds,
        retiredCardIds: input.retiredCardIds,
      );
    }
    return OfficialFormalDueUpdate(
      bySource: bySource,
      rawDueBySource: rawDueBySource,
      turnaDue: turnaDue,
      unintroducedNew: unintroducedNew,
      unavailable: unavailable,
      error: error,
    );
  }
}

/// Computes the per-source six-set view used by the repository, seeding the
/// introduced set through the introduction store at build time.
OfficialFormalDuePerSource buildFormalDuePerSource({
  required String importId,
  required Set<int> schedulerDueCardIds,
  required bool schedulerDueSynced,
  required Set<int> activePlacementCardIds,
  required Set<int> suspendedCardIds,
  required Set<int> buriedCardIds,
  required Set<int> retiredCardIds,
}) {
  return const OfficialFormalDueSnapshotBuilder().build(
    sources: [
      OfficialFormalDueSourceInput(
        importId: importId,
        schedulerDueCardIds: schedulerDueCardIds,
        schedulerDueSynced: schedulerDueSynced,
        activePlacementCardIds: activePlacementCardIds,
        suspendedCardIds: suspendedCardIds,
        buriedCardIds: buriedCardIds,
        retiredCardIds: retiredCardIds,
      ),
    ],
  ).bySource[importId]!;
}
