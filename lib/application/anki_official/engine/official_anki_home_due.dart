import 'package:flutter/foundation.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_eligibility.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Dual-source home due. Never merge Official and Turna stores into one writer.
class OfficialAnkiHomeDue extends ChangeNotifier {
  OfficialAnkiHomeDue._();

  static final OfficialAnkiHomeDue instance = OfficialAnkiHomeDue._();

  static var _officialDue = 0;
  static var _turnaDue = 0;
  static Set<String> _officialImportIds = {};
  static Map<String, int> _officialDueByImport = {};
  /// Exact scheduler-due card ids when known (preferred over count approx).
  static Map<String, Set<int>> _officialSchedulerDueCardIdsByImport = {};
  static Map<String, Set<int>> _activePlacementCardIdsByImport = {};
  static Map<String, Set<int>> _suspendedCardIdsByImport = {};
  static Map<String, Set<int>> _buriedCardIdsByImport = {};
  static Map<String, Set<int>> _retiredCardIdsByImport = {};
  static bool _officialDueUnavailable = false;
  static var _unintroducedNew = 0;

  static int get officialDue => _officialDue;
  static set officialDue(int v) {
    _officialDue = v;
    instance.notifyListeners();
  }

  static int get turnaDue => _turnaDue;
  static set turnaDue(int v) {
    _turnaDue = v;
    instance.notifyListeners();
  }

  static Set<String> get officialImportIds => _officialImportIds;
  static set officialImportIds(Set<String> v) {
    _officialImportIds = v;
    instance.notifyListeners();
  }

  static Map<String, int> get officialDueByImport => _officialDueByImport;
  static set officialDueByImport(Map<String, int> v) {
    _officialDueByImport = v;
    instance.notifyListeners();
  }

  static Map<String, Set<int>> get officialSchedulerDueCardIdsByImport =>
      _officialSchedulerDueCardIdsByImport;
  static set officialSchedulerDueCardIdsByImport(Map<String, Set<int>> v) {
    _officialSchedulerDueCardIdsByImport = v;
    instance.notifyListeners();
  }

  static Map<String, Set<int>> get activePlacementCardIdsByImport =>
      _activePlacementCardIdsByImport;
  static set activePlacementCardIdsByImport(Map<String, Set<int>> v) {
    _activePlacementCardIdsByImport = v;
    instance.notifyListeners();
  }

  static Map<String, Set<int>> get suspendedCardIdsByImport =>
      _suspendedCardIdsByImport;
  static set suspendedCardIdsByImport(Map<String, Set<int>> v) {
    _suspendedCardIdsByImport = v;
    instance.notifyListeners();
  }

  static Map<String, Set<int>> get buriedCardIdsByImport =>
      _buriedCardIdsByImport;
  static set buriedCardIdsByImport(Map<String, Set<int>> v) {
    _buriedCardIdsByImport = v;
    instance.notifyListeners();
  }

  static Map<String, Set<int>> get retiredCardIdsByImport =>
      _retiredCardIdsByImport;
  static set retiredCardIdsByImport(Map<String, Set<int>> v) {
    _retiredCardIdsByImport = v;
    instance.notifyListeners();
  }

  static bool get officialDueUnavailable => _officialDueUnavailable;
  static set officialDueUnavailable(bool v) {
    _officialDueUnavailable = v;
    instance.notifyListeners();
  }

  static int get unintroducedNew => _unintroducedNew;
  static set unintroducedNew(int v) {
    _unintroducedNew = v;
    instance.notifyListeners();
  }

  static void reset() {
    _officialDue = 0;
    _turnaDue = 0;
    _officialImportIds = {};
    _officialDueByImport = {};
    _officialSchedulerDueCardIdsByImport = {};
    _activePlacementCardIdsByImport = {};
    _suspendedCardIdsByImport = {};
    _buriedCardIdsByImport = {};
    _retiredCardIdsByImport = {};
    _officialDueUnavailable = false;
    _unintroducedNew = 0;
    instance.notifyListeners();
  }

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

  static int get introducedOfficialDue {
    var total = 0;
    for (final importId in officialImportIds) {
      total += formalOfficialDueForImport(importId);
    }
    return total;
  }

  static int formalOfficialDueForImport(String importId) {
    // Exact card-id intersection only. Before the first successful ID sync
    // this import is unknown — do not approximate with min(counts).
    if (!officialSchedulerDueCardIdsByImport.containsKey(importId)) {
      return 0;
    }
    return formalDueCardKeysForImport(importId).length;
  }

  /// Exact formal-due keys for one Official import/source.
  static Set<CanonicalCardKey> formalDueCardKeysForImport(String importId) {
    final dueIds = officialSchedulerDueCardIdsByImport[importId] ?? const {};
    final intro = CardIntroductionStore.resolve();
    final introducedIds = intro.introducedCardIdsForSource(importId);
    final placements = activePlacementCardIdsByImport[importId] ?? dueIds;
    return computeFormalDueCardKeysForSource(
      sourceId: importId,
      officialSchedulerDueCardIds: dueIds,
      activePlacementCardIds: placements,
      introducedCardIds: introducedIds,
      suspendedCardIds: suspendedCardIdsByImport[importId] ?? const {},
      buriedCardIds: buriedCardIdsByImport[importId] ?? const {},
      retiredCardIds: retiredCardIdsByImport[importId] ?? const {},
    );
  }

  static int get unintroducedOfficialDue {
    var raw = 0;
    for (final importId in officialImportIds) {
      raw += officialDueByImport[importId] ?? 0;
    }
    final introduced = introducedOfficialDue;
    final leftover = raw - introduced;
    return leftover < 0 ? 0 : leftover;
  }
}
