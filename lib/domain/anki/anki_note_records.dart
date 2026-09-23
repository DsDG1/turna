/// Plain data classes for the Legacy NoteStore compatibility surface
/// (`anki_notetypes`, `anki_notes`, `anki_cards_meta`, schema v9) — decoupled
/// from the Drift rows so application/view consumers never see data-layer
/// types.
library;

/// Plain data class for an Anki note row (decoupled from the Drift row).
class AnkiNoteRecord {
  final String importId;
  final int noteId;
  final int mid;
  final String tags;
  final List<String> fields;
  final String sfld;
  final String guid;
  final int mod;

  const AnkiNoteRecord({
    required this.importId,
    required this.noteId,
    required this.mid,
    this.tags = '',
    this.fields = const [],
    this.sfld = '',
    this.guid = '',
    this.mod = 0,
  });
}

/// Plain data class for an Anki card-meta row (decoupled from the Drift row).
class AnkiCardMetaRecord {
  final String importId;
  final int cardId;
  final int noteId;
  final int ord;
  final int did;
  final String wordId;
  final String renderMode;
  final String schedulingJson;
  final bool suspended;
  final int? buriedUntil;
  final bool marked;
  final int flag;

  const AnkiCardMetaRecord({
    required this.importId,
    required this.cardId,
    required this.noteId,
    this.ord = 0,
    this.did = 0,
    required this.wordId,
    this.renderMode = 'hybrid',
    this.schedulingJson = '{}',
    this.suspended = false,
    this.buriedUntil,
    this.marked = false,
    this.flag = 0,
  });

  AnkiCardMetaRecord copyWith({
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  }) {
    return AnkiCardMetaRecord(
      importId: importId,
      cardId: cardId,
      noteId: noteId,
      ord: ord,
      did: did,
      wordId: wordId,
      renderMode: renderMode,
      schedulingJson: schedulingJson,
      suspended: suspended ?? this.suspended,
      buriedUntil: buriedUntil ?? this.buriedUntil,
      marked: marked ?? this.marked,
      flag: flag ?? this.flag,
    );
  }
}

/// One card row as the browser sees it: owning note + card meta.
class AnkiCardBrowserRecord {
  final AnkiNoteRecord note;
  final AnkiCardMetaRecord card;

  const AnkiCardBrowserRecord({required this.note, required this.card});
}
