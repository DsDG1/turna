import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/core/html_stripper.dart';
import 'package:turna/data/anki_note_dao.dart';

/// One browser row that either side can render without depending on the
/// other store.
class SourceAwareBrowserCard {
  const SourceAwareBrowserCard({
    required this.sourceId,
    required this.cardId,
    required this.noteId,
    required this.deckId,
    required this.owner,
    this.noteGuid,
    this.templateOrd = 0,
    this.frontPreview = '',
    this.backPreview = '',
    this.suspended = false,
    this.buried = false,
    this.flag = 0,
    this.marked = false,
    this.tags = const <String>[],
  });

  final String sourceId;
  final int cardId;
  final int noteId;
  final int deckId;
  final AnkiEngineKind owner;
  final String? noteGuid;
  final int templateOrd;
  final String frontPreview;
  final String backPreview;
  final bool suspended;
  final bool buried;
  final int flag;
  final bool marked;
  final List<String> tags;
}

class OfficialBrowserFilter {
  const OfficialBrowserFilter({
    this.query = '',
    this.deckId,
    this.tag,
    this.flag,
    this.marked,
    this.suspended,
    this.buried,
  });

  final String query;
  final int? deckId;
  final String? tag;
  final int? flag;
  final bool? marked;
  final bool? suspended;
  final bool? buried;
}

enum OfficialBrowserAvailability { available, sourceMissing, engineUnavailable }

class OfficialBrowserSearchResult {
  const OfficialBrowserSearchResult({
    required this.rows,
    required this.availability,
    this.reason,
  });

  final List<SourceAwareBrowserCard> rows;
  final OfficialBrowserAvailability availability;
  final String? reason;

  bool get available => availability == OfficialBrowserAvailability.available;
}

/// Doc 34 W7: Official sources read from the Official catalog; Legacy stays
/// read-only via [AnkiNoteDao]. Pure Official-first sources never require
/// NoteStore rows.
class OfficialAnkiSourceAwareBrowser {
  const OfficialAnkiSourceAwareBrowser({
    required this.sources,
    required this.legacyNotes,
    this.router = const OfficialAnkiProductionRouter(),
    this.engine,
  });

  final OfficialAnkiSourceDao sources;
  final AnkiNoteDao legacyNotes;
  final OfficialAnkiProductionRouter router;

  /// When set, Official search/suspend go through the Collection. Catalog
  /// rows still bound the source; they are not a substitute for search.
  final OfficialAnkiEngine? engine;

  Future<List<SourceAwareBrowserCard>> search({
    required String importOrSourceId,
    String query = '',
    bool? suspended,
    bool? buried,
    bool? marked,
    int? flag,
    int? deckId,
    String? tag,
    AnkiEngineKind? ownerHint,
    String profileId = OfficialAnkiProductionRouter.defaultProfileId,
  }) async {
    final owner = ownerHint ??
        (sources.findById(importOrSourceId) != null
            ? AnkiEngineKind.official
            : router.engineForImport(
                importId: importOrSourceId,
                sources: sources,
                profileId: profileId,
              ));
    if (owner == AnkiEngineKind.official) {
      return (await searchWithAvailability(
        importOrSourceId: importOrSourceId,
        filter: OfficialBrowserFilter(
          query: query,
          suspended: suspended,
          buried: buried,
          marked: marked,
          flag: flag,
          deckId: deckId,
          tag: tag,
        ),
        ownerHint: owner,
        profileId: profileId,
      ))
          .rows;
    }
    return _searchLegacyReadonly(
      importOrSourceId,
      query: query,
      suspended: suspended,
      marked: marked,
      flag: flag,
    );
  }

  Future<OfficialBrowserSearchResult> searchWithAvailability({
    required String importOrSourceId,
    OfficialBrowserFilter filter = const OfficialBrowserFilter(),
    AnkiEngineKind? ownerHint,
    String profileId = OfficialAnkiProductionRouter.defaultProfileId,
  }) async {
    final owner = ownerHint ??
        (sources.findById(importOrSourceId) != null
            ? AnkiEngineKind.official
            : router.engineForImport(
                importId: importOrSourceId,
                sources: sources,
                profileId: profileId,
              ));
    if (owner != AnkiEngineKind.official) {
      final rows = await _searchLegacyReadonly(
        importOrSourceId,
        query: filter.query,
        suspended: filter.suspended,
        marked: filter.marked,
        flag: filter.flag,
      );
      return OfficialBrowserSearchResult(
        rows: rows,
        availability: OfficialBrowserAvailability.available,
      );
    }
    return _searchOfficial(importOrSourceId, filter: filter);
  }

  Future<OfficialBrowserSearchResult> _searchOfficial(
    String sourceId, {
    required OfficialBrowserFilter filter,
  }) async {
    final source = sources.findById(sourceId);
    if (source == null) {
      return const OfficialBrowserSearchResult(
        rows: [],
        availability: OfficialBrowserAvailability.sourceMissing,
        reason: 'official_source_missing',
      );
    }
    final resolvedId = source.sourceId;
    final catalogCards = sources.listCardsForImport(
      sourceId: resolvedId,
      profileId: OfficialAnkiProductionRouter.defaultProfileId,
    );
    final allowed = {for (final card in catalogCards) card.cardId};
    final byId = {for (final card in catalogCards) card.cardId: card};
    final engine = this.engine;
    if (engine == null) {
      return const OfficialBrowserSearchResult(
        rows: [],
        availability: OfficialBrowserAvailability.engineUnavailable,
        reason: 'official_engine_unavailable',
      );
    }

    final search = _officialSearch(filter);
    final ids = <int>[];
    String? pageToken;
    do {
      final page = await engine.searchCardsPage(
        search: search,
        pageSize: 1000,
        pageToken: pageToken,
      );
      ids.addAll(page.cardIds.where(allowed.contains));
      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    final liveById = <int, OfficialAnkiCardDescriptor>{};
    for (var start = 0; start < ids.length; start += 1000) {
      final end = (start + 1000).clamp(0, ids.length);
      for (final descriptor
          in await engine.getCardDescriptorsBatch(ids.sublist(start, end))) {
        liveById[descriptor.cardId] = descriptor;
      }
    }
    final out = <SourceAwareBrowserCard>[];
    for (final id in ids) {
      final catalog = byId[id];
      final live = liveById[id];
      if (live == null || !_matchesLiveFilter(live, filter)) continue;
      var front = '';
      var back = '';
      try {
        final rendered = await engine.renderCard(cardId: id, browser: true);
        front = stripHtml(rendered.questionDisplayHtml).trim();
        if (front.isEmpty) {
          front = stripHtml(rendered.questionHtml).trim();
        }
        back = stripHtml(rendered.answerDisplayHtml).trim();
        if (back.isEmpty) {
          back = stripHtml(rendered.answerHtml).trim();
        }
      } catch (_) {
        front = 'card #$id';
      }
      out.add(
        SourceAwareBrowserCard(
          sourceId: resolvedId,
          cardId: id,
          noteId: catalog?.noteId ?? live.noteId,
          deckId: catalog?.deckId ?? live.deckId,
          owner: AnkiEngineKind.official,
          noteGuid: catalog?.noteGuid ?? live.noteGuid,
          templateOrd: catalog?.templateOrd ?? live.templateOrd,
          frontPreview: front.isEmpty ? 'card #$id' : front,
          backPreview: back,
          suspended: live.suspended,
          buried: live.buried,
          flag: live.flag,
          marked: live.marked,
          tags: live.tags,
        ),
      );
    }
    return OfficialBrowserSearchResult(
      rows: out,
      availability: OfficialBrowserAvailability.available,
    );
  }

  String _officialSearch(OfficialBrowserFilter filter) {
    final parts = <String>[];
    final query = filter.query.trim();
    if (query.isNotEmpty) parts.add(query);
    if (filter.tag?.trim().isNotEmpty == true) {
      parts.add('tag:${_quoted(filter.tag!.trim())}');
    }
    if (filter.flag != null) parts.add('flag:${filter.flag!.clamp(0, 7)}');
    void booleanTerm(bool? value, String term) {
      if (value == null) return;
      parts.add(value ? term : '-$term');
    }

    booleanTerm(filter.marked, 'tag:marked');
    booleanTerm(filter.suspended, 'is:suspended');
    booleanTerm(filter.buried, 'is:buried');
    return parts.join(' ');
  }

  String _quoted(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  bool _matchesLiveFilter(
    OfficialAnkiCardDescriptor card,
    OfficialBrowserFilter filter,
  ) {
    if (filter.deckId != null && card.deckId != filter.deckId) return false;
    if (filter.flag != null && card.flag != filter.flag) return false;
    if (filter.marked != null && card.marked != filter.marked) return false;
    if (filter.suspended != null && card.suspended != filter.suspended) {
      return false;
    }
    if (filter.buried != null && card.buried != filter.buried) return false;
    final tag = filter.tag?.trim().toLowerCase();
    if (tag != null &&
        tag.isNotEmpty &&
        !card.tags.any((candidate) => candidate.toLowerCase() == tag)) {
      return false;
    }
    return true;
  }

  /// Writes suspend/restore to the Official engine and folds the change
  /// into the formal-due snapshot via one full-snapshot CAS mutation
  /// (maintainability plan §7.4 — no manual static-map spreads).
  Future<void> setOfficialSuspended({
    required String sourceId,
    required int cardId,
    required bool suspended,
  }) async {
    final engine = this.engine;
    if (engine == null) return;
    await engine.buryOrSuspendCards(
      action: suspended
          ? OfficialBuryOrSuspendAction.suspend
          : OfficialBuryOrSuspendAction.restoreCards,
      cardIds: [cardId],
    );
    final repo = OfficialFormalDueRepository.instance;
    final expectedGeneration = repo.generation;

    OfficialFormalDuePerSource transform(OfficialFormalDuePerSource current) {
      return OfficialFormalDuePerSource(
        importId: current.importId,
        knowledge: current.knowledge,
        schedulerDueCardIds: current.schedulerDueCardIds,
        activePlacementCardIds: current.activePlacementCardIds,
        introducedCardIds: current.introducedCardIds,
        suspendedCardIds: suspended
            ? {...current.suspendedCardIds, cardId}
            : current.suspendedCardIds.difference({cardId}),
        buriedCardIds: current.buriedCardIds,
        retiredCardIds: current.retiredCardIds,
      );
    }

    var result = repo.mutateSource(
      sourceId,
      expectedGeneration: expectedGeneration,
      transform: transform,
    );
    if (result == OfficialFormalDueCommitResult.stale) {
      repo.mutateSource(sourceId, transform: transform);
    }
  }

  Future<List<SourceAwareBrowserCard>> _searchLegacyReadonly(
    String importId, {
    required String query,
    bool? suspended,
    bool? marked,
    int? flag,
  }) async {
    final rows = await legacyNotes.searchNotes(
      importId,
      query,
      suspended: suspended,
      marked: marked,
      flag: flag,
    );
    return [
      for (final row in rows)
        SourceAwareBrowserCard(
          sourceId: importId,
          cardId: row.card.cardId,
          noteId: row.note.noteId,
          deckId: 0,
          owner: AnkiEngineKind.legacy,
          frontPreview: row.note.sfld.isNotEmpty
              ? row.note.sfld
              : row.note.fields.join(' / '),
          suspended: row.card.suspended,
          flag: row.card.flag,
          marked: row.card.marked,
        ),
    ];
  }
}
