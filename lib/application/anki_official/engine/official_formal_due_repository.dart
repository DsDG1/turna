import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_eligibility.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/srs_word.dart';

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
///
/// Instances stored inside an [OfficialFormalDueSnapshot] are frozen: every
/// set is unmodifiable. Mutations go through
/// [OfficialFormalDueRepository.mutateSource], which still commits a full
/// snapshot.
@immutable
class OfficialFormalDuePerSource {
  OfficialFormalDuePerSource({
    required this.importId,
    required this.knowledge,
    Set<int> schedulerDueCardIds = const {},
    Set<int> activePlacementCardIds = const {},
    Set<int> introducedCardIds = const {},
    Set<int> suspendedCardIds = const {},
    Set<int> buriedCardIds = const {},
    Set<int> retiredCardIds = const {},
  })  : schedulerDueCardIds = Set.unmodifiable(schedulerDueCardIds),
        activePlacementCardIds = Set.unmodifiable(activePlacementCardIds),
        introducedCardIds = Set.unmodifiable(introducedCardIds),
        suspendedCardIds = Set.unmodifiable(suspendedCardIds),
        buriedCardIds = Set.unmodifiable(buriedCardIds),
        retiredCardIds = Set.unmodifiable(retiredCardIds);

  final String importId;
  final FormalDueKnowledge knowledge;
  final Set<int> schedulerDueCardIds;
  final Set<int> activePlacementCardIds;

  /// Introduction set as of the last snapshot commit. The introduction
  /// store publishes change events after persisting; the repository folds
  /// them into new snapshots — there is no getter-time bypass.
  final Set<int> introducedCardIds;
  final Set<int> suspendedCardIds;
  final Set<int> buriedCardIds;
  final Set<int> retiredCardIds;

  /// Exact formal-due keys. Empty when [knowledge] is not [known].
  Set<CanonicalCardKey> get formalDueCardKeys {
    if (knowledge != FormalDueKnowledge.known) return const {};
    return computeFormalDueCardKeysForSource(
      sourceId: importId,
      officialSchedulerDueCardIds: schedulerDueCardIds,
      activePlacementCardIds: activePlacementCardIds,
      introducedCardIds: introducedCardIds,
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

  /// Turna-side due total. Production collectors never write it (Play Hub
  /// computes the aggregate at read time); the field only exists so a
  /// future SrsProvider-owned refresh can carry it atomically.
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

/// Outcome of a [OfficialFormalDueRepository.commit] /
/// [OfficialFormalDueRepository.mutateSource] attempt.
enum OfficialFormalDueCommitResult {
  /// A new complete snapshot landed (generation + 1, one notification).
  committed,

  /// The expected generation no longer matches — a newer snapshot won and
  /// this write was dropped instead of overwriting it.
  stale,

  /// The source is not present in the current snapshot (the mutation had
  /// nothing to transform).
  missingSource,
}

/// The single production writer for Official formal-due state (plan 34 D6,
/// maintainability plan Wave 1).
///
/// Home, Play Hub, Profile, Review All and Stats read [snapshot]; the ONLY
/// way state changes is one atomic [commit] of a complete
/// [OfficialFormalDueUpdate] or a full-snapshot [mutateSource] — never a
/// per-field write. Failed refreshes call [markUnavailable] and keep the
/// last complete snapshot visible.
class OfficialFormalDueRepository extends ChangeNotifier {
  OfficialFormalDueRepository._() {
    _introductionSubscription = CardIntroductionStore.changes.listen(
      _onIntroductionChanged,
    );
  }

  static final OfficialFormalDueRepository instance =
      OfficialFormalDueRepository._();

  OfficialFormalDueSnapshot _snapshot = OfficialFormalDueSnapshot.empty;

  // Kept so a future repository teardown can detach from the introduction
  // store; the singleton lives for the process lifetime (never cancelled).
  // ignore: unused_field, cancel_subscriptions
  StreamSubscription<CardIntroductionChanged>? _introductionSubscription;

  /// Sources whose introduction events could not land because the source
  /// was absent from the snapshot at event time. The next full refresh
  /// rebuilds them from the introduction store.
  final Set<String> pendingIntroductionSources = {};

  /// Optional hook fired when an introduction event races a refresh and
  /// loses; the sync layer may trigger a source-scoped refresh here.
  void Function(String sourceId)? onSourceRefreshNeeded;

  OfficialFormalDueSnapshot get snapshot => _snapshot;
  int get generation => _snapshot.generation;

  /// Whether [commit] with a given generation would be stale. Production
  /// refreshes must consult this (or handle a stale [commit] result)
  /// instead of blind-writing.
  bool isStale(int generation) => generation != _snapshot.generation;

  /// Applies one complete refresh result as the new snapshot: generation
  /// +1, exactly one notification. Generation CAS — a refresh whose base
  /// generation no longer matches returns [OfficialFormalDueCommitResult.stale]
  /// and changes nothing.
  OfficialFormalDueCommitResult commit(
    OfficialFormalDueUpdate update, {
    required int basedOnGeneration,
  }) {
    if (basedOnGeneration != _snapshot.generation) {
      return OfficialFormalDueCommitResult.stale;
    }
    _installSnapshot(
      OfficialFormalDueSnapshot(
        generation: _snapshot.generation + 1,
        byImport: _freezeBySource(update.bySource),
        rawDueByImport: Map.unmodifiable(update.rawDueBySource),
        unintroducedNew: update.unintroducedNew,
        turnaDue: update.turnaDue,
        unavailable: update.unavailable,
        error: update.error,
      ),
    );
    pendingIntroductionSources.clear();
    return OfficialFormalDueCommitResult.committed;
  }

  /// Mutates one source's six sets and commits the result as a full new
  /// snapshot (still one generation bump, one notification). The transform
  /// receives the CURRENT frozen per-source state and returns the next
  /// one; it must not retain references to the input's sets.
  ///
  /// Generation CAS protects against clobbering a refresh that landed
  /// between the caller's read and this mutation.
  OfficialFormalDueCommitResult mutateSource(
    String sourceId, {
    int? expectedGeneration,
    required OfficialFormalDuePerSource Function(OfficialFormalDuePerSource)
        transform,
  }) {
    if (expectedGeneration != null &&
        expectedGeneration != _snapshot.generation) {
      return OfficialFormalDueCommitResult.stale;
    }
    final current = _snapshot.byImport[sourceId];
    if (current == null) return OfficialFormalDueCommitResult.missingSource;
    final next = transform(current);
    _installSnapshot(
      OfficialFormalDueSnapshot(
        generation: _snapshot.generation + 1,
        byImport: Map.unmodifiable({
          ..._snapshot.byImport,
          sourceId: _freezePerSource(next),
        }),
        rawDueByImport: _snapshot.rawDueByImport,
        unintroducedNew: _snapshot.unintroducedNew,
        turnaDue: _snapshot.turnaDue,
        unavailable: false,
      ),
    );
    return OfficialFormalDueCommitResult.committed;
  }

  /// Marks the whole snapshot unavailable after a failed refresh — the
  /// previous complete sets stay visible (stale) instead of being zeroed.
  void markUnavailable(Object error) {
    _installSnapshot(
      OfficialFormalDueSnapshot(
        generation: _snapshot.generation + 1,
        byImport: _snapshot.byImport,
        rawDueByImport: _snapshot.rawDueByImport,
        unintroducedNew: _snapshot.unintroducedNew,
        turnaDue: _snapshot.turnaDue,
        unavailable: true,
        error: error,
      ),
    );
  }

  /// Test-only reset. Production state changes exclusively through
  /// [commit]/[mutateSource]/[markUnavailable].
  void resetForTest() {
    _snapshot = OfficialFormalDueSnapshot.empty;
    pendingIntroductionSources.clear();
    notifyListeners();
  }

  void _installSnapshot(OfficialFormalDueSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }

  void _onIntroductionChanged(CardIntroductionChanged event) {
    final current = _snapshot.byImport[event.sourceId];
    if (current == null) {
      pendingIntroductionSources.add(event.sourceId);
      return;
    }
    OfficialFormalDuePerSource next;
    switch (event.kind) {
      case CardIntroductionChangeKind.introduced:
        if (current.introducedCardIds.contains(event.cardId)) return;
        next = OfficialFormalDuePerSource(
          importId: current.importId,
          knowledge: current.knowledge,
          schedulerDueCardIds: current.schedulerDueCardIds,
          activePlacementCardIds: current.activePlacementCardIds,
          introducedCardIds: {...current.introducedCardIds, event.cardId},
          suspendedCardIds: current.suspendedCardIds,
          buriedCardIds: current.buriedCardIds,
          retiredCardIds: current.retiredCardIds,
        );
      case CardIntroductionChangeKind.retired:
        next = OfficialFormalDuePerSource(
          importId: current.importId,
          knowledge: current.knowledge,
          schedulerDueCardIds: current.schedulerDueCardIds,
          activePlacementCardIds: current.activePlacementCardIds,
          introducedCardIds:
              current.introducedCardIds.difference({event.cardId}),
          suspendedCardIds: current.suspendedCardIds,
          buriedCardIds: current.buriedCardIds,
          retiredCardIds: {...current.retiredCardIds, event.cardId},
        );
    }
    final result = mutateSource(
      event.sourceId,
      transform: (_) => next,
    );
    if (result != OfficialFormalDueCommitResult.committed) {
      // A refresh won the race; ask the sync layer to re-collect this
      // source instead of last-write-wins overwriting newer data.
      pendingIntroductionSources.add(event.sourceId);
      onSourceRefreshNeeded?.call(event.sourceId);
    }
  }

  static Map<String, OfficialFormalDuePerSource> _freezeBySource(
    Map<String, OfficialFormalDuePerSource> bySource,
  ) {
    return Map.unmodifiable({
      for (final entry in bySource.entries) entry.key: _freezePerSource(entry.value),
    });
  }

  static OfficialFormalDuePerSource _freezePerSource(
    OfficialFormalDuePerSource per,
  ) {
    return OfficialFormalDuePerSource(
      importId: per.importId,
      knowledge: per.knowledge,
      schedulerDueCardIds: per.schedulerDueCardIds,
      activePlacementCardIds: per.activePlacementCardIds,
      introducedCardIds: per.introducedCardIds,
      suspendedCardIds: per.suspendedCardIds,
      buriedCardIds: per.buriedCardIds,
      retiredCardIds: per.retiredCardIds,
    );
  }

  // -------------------------------------------------------------------
  // Convenience accessors (read-only views over the snapshot)
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

  // -------------------------------------------------------------------
  // Aggregation helpers shared by Home / Play Hub / Profile
  // -------------------------------------------------------------------

  /// Legacy (Turna SRS) due words that are NOT owned by an Official
  /// source. Never merge Official and Turna stores into one writer.
  int legacyAnkiDueExcludingOfficial(Iterable<SrsWord> dueWords) {
    final intro = CardIntroductionStore.resolve();
    var n = 0;
    for (final word in dueWords) {
      if (!word.wordId.startsWith(LegacyAnkiIdentifiers.ankiPrefix)) continue;
      final importId = LegacyAnkiIdentifiers.importIdFromWordId(word.wordId);
      if (officialImportIds.contains(importId)) continue;
      if (!intro.isFormallyEligibleWord(word)) continue;
      n++;
    }
    return n;
  }

  int aggregatedAnkiDue(Iterable<SrsWord> dueWords) {
    return legacyAnkiDueExcludingOfficial(dueWords) +
        _snapshot.introducedOfficialDue;
  }

  /// Exact formal-due count. Legacy behavior returns 0 for unknown
  /// imports; prefer [formalDueCountForImport] which reports unknown as
  /// null instead of guessing zero.
  int formalOfficialDueForImport(String importId) {
    return formalDueCountForImport(importId) ?? 0;
  }
}
