// Project imports:
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/l10n/app_strings.dart';

/// Builds a small in-memory [AnkiCollection] so users can try the import
/// wizard without picking a real `.apkg` file.
///
/// Content mirrors Section 1 greetings (Turkish → Chinese). Stable ids and
/// [sourceHash] make re-imports merge cleanly.
class AnkiSampleDeck {
  AnkiSampleDeck._();

  /// Stable hash used for re-import detection (not a real file digest).
  static const String sourceHash = 'sample-turkish-greetings-v1';

  /// Pseudo path stored on the import record.
  static const String sourcePath = 'sample://turkish-greetings-v1';

  static const int notetypeId = 1600000000001;
  static const int deckId = 1600000000002;

  /// Front/back pairs: Turkish term → Chinese gloss.
  static const List<(String front, String back)> cards = [
    ('merhaba', '你好'),
    ('günaydın', '早上好'),
    ('teşekkürler', '谢谢'),
    ('hoşça kal', '再见'),
    ('evet', '是'),
    ('hayır', '否'),
    ('nasılsın?', '你好吗？'),
    ('iyiyim', '我很好'),
    ('lütfen', '请'),
    ('rica ederim', '不客气'),
  ];

  /// Produce a complete [AnkiCollection] ready for the import preview step.
  static AnkiCollection build() {
    const mid = notetypeId;
    const did = deckId;

    final notetype = AnkiNotetype(
      id: mid,
      name: 'Basic',
      fieldNames: const ['Front', 'Back'],
      templateNames: const ['Card 1'],
      templates: const [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '{{Front}}',
          afmt: '{{FrontSide}}<hr id=answer>{{Back}}',
        ),
      ],
    );

    final deck = AnkiDeckInfo(
      id: did,
      name: AppStrings.ankiSampleDeckName,
      cardCount: cards.length,
    );

    final notes = <AnkiNote>[];
    final cardRows = <AnkiCardData>[];

    for (var i = 0; i < cards.length; i++) {
      final pair = cards[i];
      // Stable synthetic Anki ids (ms-style timestamps) so re-import merges.
      final noteId = 1700000000000 + i;
      final cardId = 1800000000000 + i;
      notes.add(
        AnkiNote(
          id: noteId,
          guid: 'sample-tr-greet-$i',
          mid: mid,
          tags: 'sample greeting turkish',
          fields: [pair.$1, pair.$2],
          sortField: pair.$1,
        ),
      );
      cardRows.add(
        AnkiCardData(
          id: cardId,
          nid: noteId,
          did: did,
          ord: 0,
          type: 0,
          queue: 0,
          due: i,
        ),
      );
    }

    return AnkiCollection(
      notetypes: {mid: notetype},
      decks: {did: deck},
      notes: notes,
      cards: cardRows,
      media: const {},
      mediaDir: '',
      sourceHash: sourceHash,
      revlog: const [],
    );
  }
}
