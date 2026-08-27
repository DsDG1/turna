import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';

/// Matches every card whose imported history proves it was already studied
/// in Anki (`cards.reps >= 1`). The vendored Anki search grammar implements
/// `prop:reps` with `>=` natively, so this rides the existing
/// `searchCardsPage` channel without any ABI change.
const String kImportedHistorySearchQuery = 'prop:reps>=1';

typedef ImportedHistorySearchPage = Future<OfficialAnkiCardPage> Function({
  String search,
  int pageSize,
  String? pageToken,
});

/// Reconciles imported review history into the introduction ledger.
///
/// Two consumers share this: projection publish seeds new imports
/// correctly, and the home due sync adopts (self-healing backfill) ledger
/// rows that were seeded `unintroduced` before the fix (01-due-state.md).
class ImportedHistoryIntroducer {
  const ImportedHistoryIntroducer();

  /// Pages the whole-collection studied-card search into one id set.
  Future<Set<int>> fetchStudiedCardIds({
    required ImportedHistorySearchPage searchPage,
    int pageSize = 500,
  }) async {
    final ids = <int>{};
    String? pageToken;
    while (true) {
      final page = await searchPage(
        search: kImportedHistorySearchQuery,
        pageSize: pageSize,
        pageToken: pageToken,
      );
      ids.addAll(page.cardIds);
      if (page.nextPageToken == null ||
          page.nextPageToken!.isEmpty ||
          page.cardIds.isEmpty) {
        break;
      }
      pageToken = page.nextPageToken;
    }
    return ids;
  }

  /// Upgrades every ledger row whose card has imported history. Only rows
  /// currently `unintroduced` (or missing) change; course-introduced and
  /// retired rows are preserved by the DAO's conditional upsert.
  Future<void> adopt({
    required ImportedHistorySearchPage searchPage,
    required Map<String, Set<int>> cardIdsBySource,
    CardIntroductionStore? store,
    int pageSize = 500,
  }) async {
    if (cardIdsBySource.isEmpty) return;
    final studied = await fetchStudiedCardIds(
      searchPage: searchPage,
      pageSize: pageSize,
    );
    if (studied.isEmpty) return;
    final resolved = store ?? CardIntroductionStore.resolve();
    for (final entry in cardIdsBySource.entries) {
      final adopted = entry.value.intersection(studied);
      if (adopted.isEmpty) continue;
      await resolved.adoptImportedHistory(
        sourceId: entry.key,
        cardIds: adopted,
      );
    }
  }
}
