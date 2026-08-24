import 'package:flutter/foundation.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_eligibility.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';

/// How much a due number can be trusted (plan 34 D6 / R3-1).
enum FormalDueKnowledge {
  /// The six sets were read successfully — the count is exact.
  known,

  /// This source has never completed a card-id sync. The count is NOT
  /// zero and must not fall back to schedulerDue — show "unknown".
  unknown,

  /// The whole sync failed (engine/collection unavailable). Stale data
  /// stays visible marked unavailable.
  unavailable,
}

/// The six formal-due sets for one Official source (plan 34 §R3):
/// formalDue = schedulerDue ∩ activePlacement ∩ introduced
///             − suspended − buried − retired.
@immutable
class OfficialFormalDuePerSource {
  const OfficialFormalDuePerSource({
    required this.importId,
    required this.knowledge,
    this.schedulerDueCardIds = const {},
    this.activePlacementCardIds = const {},
    this.introducedCardIds = const {},
    this.suspendedCardIds = const {},
    this.buriedCardIds = const {},
    this.retiredCardIds = const {},
    this.resolveIntroducedAtReadTime = true,
  });

  final String importId;
  final FormalDueKnowledge knowledge;
  final Set<int> schedulerDueCardIds;
  final Set<int> activePlacementCardIds;

  /// Seeded introduction set. When [resolveIntroducedAtReadTime] is true
  /// (production default) the introduction store is re-read on every
  /// [formalDueCardKeys] call, because marks happen at review time and a
  /// stored snapshot would go stale within the same session.
  final Set<int> introducedCardIds;
  final Set<int> suspendedCardIds;
  final Set<int> buriedCardIds;
  final Set<int> retiredCardIds;
  final bool resolveIntroducedAtReadTime;

  /// Exact formal-due keys. Empty when [knowledge] is not [known].
  Set<CanonicalCardKey> get formalDueCardKeys {
    if (knowledge != FormalDueKnowledge.known) return const {};
    final introduced = resolveIntroducedAtReadTime
        ? CardIntroductionStore.resolve().introducedCardIdsForSource(importId)
        : introducedCardIds;
    return computeFormalDueCardKeysForSource(
      sourceId: importId,
      officialSchedulerDueCardIds: schedulerDueCardIds,
      activePlacementCardIds: activePlacementCardIds,
      introducedCardIds: introduced,
      suspendedCardIds: suspendedCardIds,
      buriedCardIds: buriedCardIds,
      retiredCardIds: retiredCardIds,
    );
  }

  /// Exact count; `null` when unknown — never a guessed zero and never a
  /// schedulerDue fallback (plan 34 R3-1).
  int? get formalDueCount =>
      knowledge == FormalDueKnowledge.known ? formalDueCardKeys.length : null;
}

/// Immutable snapshot of every source's due state plus sync-level health.
/// Carries a generation so a late async refresh can detect it is stale and
/// drop its result instead of overwriting newer data (plan 34 R3-3).
@immutable
class OfficialFormalDueSnapshot {
  const OfficialFormalDueSnapshot({
    required this.generation,
    required this.byImport,
    this.unavailable = false,
    this.error,
    this.rawDueByImport = const {},
    this.unintroducedNew = 0,
    this.turnaDue = 0,
  });

  final int generation;
  final Map<String, OfficialFormalDuePerSource> byImport;

  /// True when the last sync failed; [byImport] holds the last good data.
  final bool unavailable;
  final Object? error;

  /// Scheduler counts as reported by the engine (pre-eligibility) — used
  /// for the "new/unintroduced" hint, never for formal due.
  final Map<String, int> rawDueByImport;
  final int unintroducedNew;
  final int turnaDue;

  static const OfficialFormalDueSnapshot empty = OfficialFormalDueSnapshot(
    generation: 0,
    byImport: {},
  );

  int? formalDueCountFor(String importId) {
    final per = byImport[importId];
    return per?.formalDueCount;
  }

  /// Total introduced formal due across every KNOWN source. Unknown
  /// sources contribute nothing but keep [isPartial] true.
  int get introducedOfficialDue {
    var total = 0;
    for (final per in byImport.values) {
      total += per.formalDueCount ?? 0;
    }
    return total;
  }

  bool get isPartial => byImport.values.any(
        (per) => per.knowledge != FormalDueKnowledge.known,
      );

  int get unintroducedOfficialDue {
    var raw = 0;
    for (final importId in byImport.keys) {
      raw += rawDueByImport[importId] ?? 0;
    }
    final leftover = raw - introducedOfficialDue;
    return leftover < 0 ? 0 : leftover;
  }
}

/// The single repository for Official formal-due state (plan 34 D6).
///
/// Home, Play Hub, Profile, Review All and Stats read this snapshot; UIs
/// never decrement counts themselves — mutations call [refreshFromMutation]
/// or a full sync. [OfficialAnkiHomeDue] is a thin compatibility facade
/// over this repository.
class OfficialFormalDueRepository extends ChangeNotifier {
  OfficialFormalDueRepository._();

  static final OfficialFormalDueRepository instance =
      OfficialFormalDueRepository._();

  OfficialFormalDueSnapshot _snapshot = OfficialFormalDueSnapshot.empty;
  OfficialFormalDueSnapshot? _rollbackSnapshot;

  OfficialFormalDueSnapshot get snapshot => _snapshot;
  int get generation => _snapshot.generation;

  /// Whether [apply] with a given generation would be stale.
  bool isStale(int generation) => generation != _snapshot.generation;

  /// Applies a fresh sync result as the new snapshot. Bumps the
  /// generation so older in-flight results become detectably stale.
  void apply({
    Map<String, OfficialFormalDuePerSource> byImport = const {},
    Map<String, int> rawDueByImport = const {},
    int unintroducedNew = 0,
    int turnaDue = 0,
    bool unavailable = false,
    Object? error,
  }) {
    _snapshot = OfficialFormalDueSnapshot(
      generation: _snapshot.generation + 1,
      byImport: Map.unmodifiable(byImport),
      rawDueByImport: Map.unmodifiable(rawDueByImport),
      unintroducedNew: unintroducedNew,
      turnaDue: turnaDue,
      unavailable: unavailable,
      error: error,
    );
    notifyListeners();
  }

  /// Saves the current snapshot for a later [rollback].
  void saveForRollback() {
    _rollbackSnapshot = _snapshot;
  }

  /// Restores the saved snapshot as a NEW generation (so listeners and
  /// stale checks behave normally) — used when a mutation's optimistic
  /// refresh fails and the six sets must return to their last good state.
  void rollback() {
    final saved = _rollbackSnapshot;
    if (saved == null) return;
    _snapshot = OfficialFormalDueSnapshot(
      generation: _snapshot.generation + 1,
      byImport: saved.byImport,
      rawDueByImport: saved.rawDueByImport,
      unintroducedNew: saved.unintroducedNew,
      turnaDue: saved.turnaDue,
      unavailable: saved.unavailable,
      error: saved.error,
    );
    _rollbackSnapshot = null;
    notifyListeners();
  }

  /// Marks the whole snapshot unavailable after a failed refresh — the
  /// previous sets stay visible (stale) instead of being zeroed.
  void markUnavailable(Object error) {
    _snapshot = OfficialFormalDueSnapshot(
      generation: _snapshot.generation + 1,
      byImport: _snapshot.byImport,
      rawDueByImport: _snapshot.rawDueByImport,
      unintroducedNew: _snapshot.unintroducedNew,
      turnaDue: _snapshot.turnaDue,
      unavailable: true,
      error: error,
    );
    notifyListeners();
  }

  void reset() {
    _snapshot = OfficialFormalDueSnapshot.empty;
    _rollbackSnapshot = null;
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Convenience accessors (facade-compatible views over the snapshot)
  // -------------------------------------------------------------------

  Set<String> get officialImportIds => _snapshot.byImport.keys.toSet();

  int? formalDueCountForImport(String importId) =>
      _snapshot.formalDueCountFor(importId);

  Set<CanonicalCardKey> formalDueCardKeysForImport(String importId) =>
      _snapshot.byImport[importId]?.formalDueCardKeys ?? const {};

  FormalDueKnowledge knowledgeFor(String importId) =>
      _snapshot.byImport[importId]?.knowledge ?? FormalDueKnowledge.unknown;

  Set<int> schedulerDueCardIdsFor(String importId) =>
      _snapshot.byImport[importId]?.schedulerDueCardIds ?? const {};

  Set<int> activePlacementCardIdsFor(String importId) =>
      _snapshot.byImport[importId]?.activePlacementCardIds ?? const {};

  Set<int> suspendedCardIdsFor(String importId) =>
      _snapshot.byImport[importId]?.suspendedCardIds ?? const {};

  Set<int> buriedCardIdsFor(String importId) =>
      _snapshot.byImport[importId]?.buriedCardIds ?? const {};

  Set<int> retiredCardIdsFor(String importId) =>
      _snapshot.byImport[importId]?.retiredCardIds ?? const {};
}

/// Computes the per-source six-set view used by the repository, resolving
/// the introduced set through the introduction store.
OfficialFormalDuePerSource buildFormalDuePerSource({
  required String importId,
  required Set<int> schedulerDueCardIds,
  required bool schedulerDueSynced,
  required Set<int> activePlacementCardIds,
  required Set<int> suspendedCardIds,
  required Set<int> buriedCardIds,
  required Set<int> retiredCardIds,
}) {
  return OfficialFormalDuePerSource(
    importId: importId,
    knowledge: schedulerDueSynced
        ? FormalDueKnowledge.known
        : FormalDueKnowledge.unknown,
    schedulerDueCardIds: schedulerDueCardIds,
    activePlacementCardIds: activePlacementCardIds,
    introducedCardIds:
        CardIntroductionStore.resolve().introducedCardIdsForSource(importId),
    suspendedCardIds: suspendedCardIds,
    buriedCardIds: buriedCardIds,
    retiredCardIds: retiredCardIds,
  );
}
