import 'package:injectable/injectable.dart';
import 'package:turna/domain/repositories/i_anki_note_store.dart';
import 'package:turna/domain/anki/anki_note_records.dart';

// Re-exported so legacy-browsing UIs can consume the raw record shape
// without importing the data layer directly.
export 'package:turna/domain/anki/anki_note_records.dart'
    show AnkiCardBrowserRecord;

/// Legacy deck browsing facade (doc 34 W7): the card browser page renders
/// full note fields and diagnostics, so it consumes [AnkiCardBrowserRecord]
/// directly. All legacy reads/writes route through here so views never touch
/// the data layer.
@lazySingleton
class LegacyAnkiCardBrowser {
  LegacyAnkiCardBrowser(this.notes);

  /// The underlying DAO, exposed only to wire
  /// `OfficialAnkiSourceAwareBrowser.legacyNotes` on the same instance.
  final IAnkiNoteStore notes;

  /// Search raw note fields within one imported deck. The JSON column is
  /// intentionally searched as text; the browser strips HTML only for display.
  Future<List<AnkiCardBrowserRecord>> search(
    String importId,
    String query, {
    int? flag,
    bool? suspended,
    bool? marked,
    int limit = 50,
    int offset = 0,
  }) =>
      notes.searchNotes(
        importId,
        query,
        flag: flag,
        suspended: suspended,
        marked: marked,
        limit: limit,
        offset: offset,
      );

  /// Suspend/mark/flag one legacy card.
  Future<void> setCardState(
    String importId,
    int cardId, {
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  }) =>
      notes.setCardState(
        importId,
        cardId,
        suspended: suspended,
        buriedUntil: buriedUntil,
        marked: marked,
        flag: flag,
      );
}
