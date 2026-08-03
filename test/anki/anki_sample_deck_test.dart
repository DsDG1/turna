import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_sample_deck.dart';

void main() {
  test('sample deck has stable hash, notes, and cards', () {
    final a = AnkiSampleDeck.build();
    final b = AnkiSampleDeck.build();

    expect(a.sourceHash, AnkiSampleDeck.sourceHash);
    expect(a.sourceHash, b.sourceHash);
    expect(a.notes, isNotEmpty);
    expect(a.cards.length, a.notes.length);
    expect(a.notetypes, isNotEmpty);
    expect(a.decks, isNotEmpty);
    expect(a.media, isEmpty);
    expect(a.revlog, isEmpty);

    for (final note in a.notes) {
      expect(note.fields.length, 2);
      expect(note.fields[0], isNotEmpty);
      expect(note.fields[1], isNotEmpty);
      final cardsForNote = a.cards.where((c) => c.nid == note.id);
      expect(cardsForNote, isNotEmpty);
    }

    // Re-builds use the same note ids (merge-friendly).
    expect(
        a.notes.map((n) => n.id).toList(), b.notes.map((n) => n.id).toList());
  });

  test('sample notetype maps to wordEntry or ankiCard', () {
    final collection = AnkiSampleDeck.build();
    final notetype = collection.notetypes.values.single;
    final mapping = AnkiCardAdapter.inferMapping(notetype);
    expect(
      mapping.type,
      anyOf(
        NotetypeMappingType.wordEntry,
        NotetypeMappingType.ankiCard,
        NotetypeMappingType.multipleChoice,
      ),
    );
  });
}
