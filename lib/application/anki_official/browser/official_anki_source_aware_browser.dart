import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
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
      return _searchOfficial(
        importOrSourceId,
        query: query,
        suspended: suspended,
      );
    }
    return _searchLegacyReadonly(
      importOrSourceId,
      query: query,
      suspended: suspended,
    );
  }

  Future<List<SourceAwareBrowserCard>> _searchOfficial(
    String sourceId, {
    required String query,
    bool? suspended,
  }) async {
    final resolvedId = sources.findById(sourceId)?.sourceId ?? sourceId;
    final catalogCards = sources.listCardsForImport(
      sourceId: resolvedId,
      profileId: OfficialAnkiProductionRouter.defaultProfileId,
    );
    final allowed = {for (final card in catalogCards) card.cardId};
    final byId = {for (final card in catalogCards) card.cardId: card};
    final engine = this.engine;
    if (engine == null) {
      return _catalogFallback(
        resolvedId: resolvedId,
        cards: catalogCards,
        query: query,
        suspended: suspended,
      );
    }

    final search = StringBuffer(query.trim());
    if (suspended == true) {
      if (search.isNotEmpty) search.write(' ');
      search.write('is:suspended');
    } else if (suspended == false) {
      if (search.isNotEmpty) search.write(' ');
      search.write('-is:suspended');
    }
    final page = await engine.searchCardsPage(
      search: search.toString(),
      pageSize: 200,
    );
    final ids = [
      for (final id in page.cardIds)
        if (allowed.contains(id)) id,
    ];
    final out = <SourceAwareBrowserCard>[];
    for (final id in ids) {
      final desc = byId[id];
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
      final isSuspended =
          OfficialAnkiHomeDue.suspendedCardIdsByImport[resolvedId]
                  ?.contains(id) ==
              true;
      out.add(
        SourceAwareBrowserCard(
          sourceId: resolvedId,
          cardId: id,
          noteId: desc?.noteId ?? 0,
          deckId: desc?.deckId ?? 0,
          owner: AnkiEngineKind.official,
          noteGuid: desc?.noteGuid,
          templateOrd: desc?.templateOrd ?? 0,
          frontPreview: front.isEmpty ? 'card #$id' : front,
          backPreview: back,
          suspended: isSuspended || suspended == true,
        ),
      );
    }
    return out;
  }

  List<SourceAwareBrowserCard> _catalogFallback({
    required String resolvedId,
    required List<OfficialAnkiCardDescriptor> cards,
    required String query,
    bool? suspended,
  }) {
    // Catalog has no suspend/bury flags. A suspend filter must not invent
    // Legacy NoteStore truth — return empty rather than unfiltered rows.
    if (suspended != null) return const [];
    final q = query.trim().toLowerCase();
    final out = <SourceAwareBrowserCard>[];
    for (final card in cards) {
      final preview = 'card #${card.cardId} note #${card.noteId}';
      if (q.isNotEmpty &&
          !preview.contains(q) &&
          !(card.noteGuid ?? '').toLowerCase().contains(q) &&
          !card.cardId.toString().contains(q)) {
        continue;
      }
      out.add(
        SourceAwareBrowserCard(
          sourceId: resolvedId,
          cardId: card.cardId,
          noteId: card.noteId,
          deckId: card.deckId,
          owner: AnkiEngineKind.official,
          noteGuid: card.noteGuid,
          templateOrd: card.templateOrd,
          frontPreview: preview,
        ),
      );
    }
    return out;
  }

  /// Writes suspend/restore to the Official engine and the formal-due set.
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
    final current = {
      ...?OfficialAnkiHomeDue.suspendedCardIdsByImport[sourceId],
    };
    if (suspended) {
      current.add(cardId);
    } else {
      current.remove(cardId);
    }
    OfficialAnkiHomeDue.suspendedCardIdsByImport = {
      ...OfficialAnkiHomeDue.suspendedCardIdsByImport,
      sourceId: current,
    };
  }

  Future<List<SourceAwareBrowserCard>> _searchLegacyReadonly(
    String importId, {
    required String query,
    bool? suspended,
  }) async {
    final rows = await legacyNotes.searchNotes(
      importId,
      query,
      suspended: suspended,
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
        ),
    ];
  }
}
