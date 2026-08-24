import 'package:flutter/foundation.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Dual-source home due. Never merge Official and Turna stores into one writer.
///
/// Thin facade (plan 34 D6): all storage lives in
/// [OfficialFormalDueRepository]; these static accessors keep legacy call
/// sites compiling while new code reads the repository snapshot directly.
/// New consumers MUST NOT be added — read
/// `OfficialFormalDueRepository.instance.snapshot` instead.
class OfficialAnkiHomeDue extends ChangeNotifier {
  OfficialAnkiHomeDue._();

  static final OfficialAnkiHomeDue instance = OfficialAnkiHomeDue._();

  static OfficialFormalDueRepository get _repo =>
      OfficialFormalDueRepository.instance;

  static int get officialDue => _repo.snapshot.introducedOfficialDue;

  /// Compatibility no-op: [officialDue] is DERIVED from the six sets and
  /// must never be written directly (plan 34 D6). Legacy router paths still
  /// assign it; the assignment has no effect.
  // ignore: avoid_setters_without_parameters
  static set officialDue(int v) {}

  static int get turnaDue => _repo.snapshot.turnaDue;

  static Set<String> get officialImportIds => _repo.officialImportIds;

  static Map<String, int> get officialDueByImport =>
      _repo.snapshot.rawDueByImport;

  static Map<String, Set<int>> get officialSchedulerDueCardIdsByImport => {
        for (final entry in _repo.snapshot.byImport.values)
          entry.importId: entry.schedulerDueCardIds,
      };

  static Map<String, Set<int>> get activePlacementCardIdsByImport => {
        for (final entry in _repo.snapshot.byImport.values)
          entry.importId: entry.activePlacementCardIds,
      };

  static Map<String, Set<int>> get suspendedCardIdsByImport => {
        for (final entry in _repo.snapshot.byImport.values)
          entry.importId: entry.suspendedCardIds,
      };

  static Map<String, Set<int>> get buriedCardIdsByImport => {
        for (final entry in _repo.snapshot.byImport.values)
          entry.importId: entry.buriedCardIds,
      };

  static Map<String, Set<int>> get retiredCardIdsByImport => {
        for (final entry in _repo.snapshot.byImport.values)
          entry.importId: entry.retiredCardIds,
      };

  static bool get officialDueUnavailable => _repo.snapshot.unavailable;

  static int get unintroducedNew => _repo.snapshot.unintroducedNew;

  // -------------------------------------------------------------------
  // Setter compatibility: route legacy writers into the repository so
  // every consumer sees one fact source. Each write is a full snapshot
  // application — partial per-field writes still land consistently.
  // -------------------------------------------------------------------

  static set turnaDue(int v) => _applyWith(turnaDue: v);

  static set officialImportIds(Set<String> v) => _applyWith(importIds: v);

  static set officialDueByImport(Map<String, int> v) => _applyWith(rawDue: v);

  static set officialSchedulerDueCardIdsByImport(Map<String, Set<int>> v) =>
      _applyWith(schedulerDue: v);

  static set activePlacementCardIdsByImport(Map<String, Set<int>> v) =>
      _applyWith(placement: v);

  static set suspendedCardIdsByImport(Map<String, Set<int>> v) =>
      _applyWith(suspended: v);

  static set buriedCardIdsByImport(Map<String, Set<int>> v) =>
      _applyWith(buried: v);

  static set retiredCardIdsByImport(Map<String, Set<int>> v) =>
      _applyWith(retired: v);

  static set officialDueUnavailable(bool v) {
    if (v) {
      _repo.markUnavailable(StateError('official due unavailable'));
    } else {
      _applyWith(clearUnavailable: true);
    }
  }

  static set unintroducedNew(int v) => _applyWith(unintroducedNew: v);

  static void _applyWith({
    Set<String>? importIds,
    Map<String, int>? rawDue,
    Map<String, Set<int>>? schedulerDue,
    Map<String, Set<int>>? placement,
    Map<String, Set<int>>? suspended,
    Map<String, Set<int>>? buried,
    Map<String, Set<int>>? retired,
    int? turnaDue,
    int? unintroducedNew,
    bool clearUnavailable = false,
  }) {
    final snap = _repo.snapshot;
    // Merge the written field into the current per-source state. Imports
    // carried by the WRITTEN maps join the snapshot even when they were
    // not registered before — a write is evidence the source exists.
    final imports = <String>{
      ...?importIds,
      ...snap.byImport.keys,
      ...?schedulerDue?.keys,
      ...?placement?.keys,
      ...?suspended?.keys,
      ...?buried?.keys,
      ...?retired?.keys,
    };
    final merged = <String, OfficialFormalDuePerSource>{};
    for (final importId in imports) {
      final current = snap.byImport[importId];
      // A scheduler-due write means the card-id sync covered this import —
      // its six sets are known. Otherwise preserve the current knowledge
      // (or unknown for brand-new entries).
      final schedulerSynced = (schedulerDue ?? const {}).containsKey(importId);
      merged[importId] = OfficialFormalDuePerSource(
        importId: importId,
        knowledge: schedulerSynced
            ? FormalDueKnowledge.known
            : current?.knowledge ?? FormalDueKnowledge.unknown,
        schedulerDueCardIds:
            schedulerDue?[importId] ?? current?.schedulerDueCardIds ?? const {},
        activePlacementCardIds:
            placement?[importId] ?? current?.activePlacementCardIds ?? const {},
        introducedCardIds: current?.introducedCardIds ?? const {},
        suspendedCardIds:
            suspended?[importId] ?? current?.suspendedCardIds ?? const {},
        buriedCardIds: buried?[importId] ?? current?.buriedCardIds ?? const {},
        retiredCardIds:
            retired?[importId] ?? current?.retiredCardIds ?? const {},
      );
    }
    _repo.apply(
      byImport: merged,
      rawDueByImport: rawDue ?? snap.rawDueByImport,
      unintroducedNew: unintroducedNew ?? snap.unintroducedNew,
      turnaDue: turnaDue ?? snap.turnaDue,
      unavailable: clearUnavailable ? false : snap.unavailable,
    );
    instance.notifyListeners();
  }

  static void reset() {
    _repo.reset();
    instance.notifyListeners();
  }

  // -------------------------------------------------------------------
  // Legacy computation helpers — now read the repository snapshot.
  // -------------------------------------------------------------------

  static int legacyAnkiDueExcludingOfficial(Iterable<SrsWord> dueWords) {
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

  static int aggregatedAnkiDue(Iterable<SrsWord> dueWords) {
    return legacyAnkiDueExcludingOfficial(dueWords) + introducedOfficialDue;
  }

  static int get introducedOfficialDue => _repo.snapshot.introducedOfficialDue;

  /// Exact formal-due count. Legacy behavior returns 0 for unknown
  /// imports; prefer [OfficialFormalDueRepository.formalDueCountForImport]
  /// which reports unknown as null instead of guessing zero.
  static int formalOfficialDueForImport(String importId) {
    return _repo.formalDueCountForImport(importId) ?? 0;
  }

  /// Exact formal-due keys for one Official import/source.
  static Set<CanonicalCardKey> formalDueCardKeysForImport(String importId) {
    return _repo.formalDueCardKeysForImport(importId);
  }

  static int get unintroducedOfficialDue =>
      _repo.snapshot.unintroducedOfficialDue;
}
