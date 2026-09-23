// Project imports:
import 'package:turna/domain/anki/anki_note_records.dart';

/// Persistence API for the Legacy NoteStore tables (`anki_notetypes`,
/// `anki_notes`, `anki_cards_meta`, schema v9).
///
/// Concrete: `AnkiNoteDao` in `lib/data`.
abstract class IAnkiNoteStore {
  /// Patch mutable card-state columns (`suspended`, `buriedUntil`, `marked`,
  /// `flag`); nulls leave the column untouched.
  Future<void> setCardState(
    String importId,
    int cardId, {
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  });

  /// Card-browser search across the note fields, joined with card meta.
  Future<List<AnkiCardBrowserRecord>> searchNotes(
    String importId,
    String query, {
    int? flag,
    bool? suspended,
    bool? marked,
    int limit = 50,
    int offset = 0,
  });

  /// Remove every note + card-meta row belonging to [importId].
  Future<void> deleteByImport(String importId);
}
