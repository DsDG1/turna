// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'anki_models.freezed.dart';
part 'anki_models.g.dart';

/// Intermediate representation of a parsed Anki collection (.apkg).
/// Pure data — no Varnamala domain types. Produced by [AnkiImporter].
@freezed
abstract class AnkiCollection with _$AnkiCollection {
  const factory AnkiCollection({
    /// mid → notetype definition
    required Map<int, AnkiNotetype> notetypes,

    /// did → deck definition
    required Map<int, AnkiDeckInfo> decks,

    required List<AnkiNote> notes,
    required List<AnkiCardData> cards,

    /// Numeric filename → original media filename mapping
    @Default({}) Map<String, String> media,

    /// Path to the extracted media directory (temporary)
    @Default('') String mediaDir,

    /// SHA-256 of the source `.apkg`/`.colpkg` bytes, computed once during
    /// parsing so callers (e.g. the import wizard) can detect re-imports
    /// without re-reading the whole file.
    @Default('') String sourceHash,

    /// Review log entries (rows from the Anki `revlog` table), used to
    /// backfill per-card review history so the memory-curve features have data
    /// immediately after import. Empty when the package has no revlog.
    @Default(<AnkiRevlogEntry>[]) List<AnkiRevlogEntry> revlog,
  }) = _AnkiCollection;
}

/// A single card template of an Anki notetype (one entry in the `tmpls`
/// array). [qfmt] / [afmt] hold the raw question/answer-side HTML templates
/// with `{{Field}}` placeholders, rendered by `AnkiTemplateRenderer`.
@freezed
abstract class AnkiTemplate with _$AnkiTemplate {
  const factory AnkiTemplate({
    required String name,

    /// Question-side HTML template (`qfmt`)
    @Default('') String qfmt,

    /// Answer-side HTML template (`afmt`)
    @Default('') String afmt,
  }) = _AnkiTemplate;

  factory AnkiTemplate.fromJson(Map<String, dynamic> json) =>
      _$AnkiTemplateFromJson(json);
}

/// Anki notetype (model) definition — field names + card templates.
@freezed
abstract class AnkiNotetype with _$AnkiNotetype {
  const factory AnkiNotetype({
    required int id,
    required String name,

    /// Ordered field names (e.g. ["Front", "Back"])
    required List<String> fieldNames,

    /// Card template names (e.g. ["Card 1", "Card 2 (reverse)"])
    @Default(<String>[]) List<String> templateNames,

    /// Full card templates (aligned with [templateNames] by index; a card's
    /// `ord` selects which template renders it). Empty for imports parsed
    /// before template bodies were captured.
    @Default(<AnkiTemplate>[]) List<AnkiTemplate> templates,

    /// Whether this is a Cloze notetype
    @Default(false) bool isCloze,
  }) = _AnkiNotetype;

  factory AnkiNotetype.fromJson(Map<String, dynamic> json) =>
      _$AnkiNotetypeFromJson(json);
}

/// Anki deck metadata.
@freezed
abstract class AnkiDeckInfo with _$AnkiDeckInfo {
  const factory AnkiDeckInfo({
    required int id,
    required String name,

    /// Parent deck id (0 or absent for top-level)
    @Default(0) int parentId,

    /// Number of cards in this deck (computed)
    @Default(0) int cardCount,
  }) = _AnkiDeckInfo;

  factory AnkiDeckInfo.fromJson(Map<String, dynamic> json) =>
      _$AnkiDeckInfoFromJson(json);
}

/// A single Anki note (row in the `notes` table).
@freezed
abstract class AnkiNote with _$AnkiNote {
  const factory AnkiNote({
    /// Anki note id (millisecond timestamp, globally unique)
    required int id,

    /// Global unique id string
    @Default('') String guid,

    /// Notetype model id (references AnkiNotetype.id)
    required int mid,

    /// Modification timestamp (seconds)
    @Default(0) int mod,

    /// Space-separated tags
    @Default('') String tags,

    /// Field values split by \x1f — aligned with notetype fieldNames
    required List<String> fields,

    /// Sort field (first field content, used for duplicate detection)
    @Default('') String sortField,
  }) = _AnkiNote;
}

/// A single Anki card (row in the `cards` table).
/// Named [AnkiCardData] to avoid collision with the Interaction [AnkiCard].
@freezed
abstract class AnkiCardData with _$AnkiCardData {
  const factory AnkiCardData({
    required int id,

    /// Note id this card belongs to
    required int nid,

    /// Deck id
    required int did,

    /// Card template ordinal (which template generated this card)
    @Default(0) int ord,

    /// Card type: 0=new, 1=learning, 2=review, 3=relearning
    @Default(0) int type,

    /// Queue: -2=buried, -1=suspended, 0=new, 1=learning, 2=review, 3=day-learn
    @Default(0) int queue,

    /// Due value — semantics depend on [queue]:
    /// queue=0: position among new cards
    /// queue=1/3: minutes since collection creation
    /// queue=2: days since collection creation
    @Default(0) int due,

    /// Current interval in days
    @Default(0) int ivl,

    /// Ease factor × 1000 (e.g. 2500 = 2.5)
    @Default(2500) int factor,

    /// Number of successful reviews
    @Default(0) int reps,

    /// Number of times forgotten
    @Default(0) int lapses,
  }) = _AnkiCardData;
}

/// A single review-log entry (row in the Anki `revlog` table). Used to
/// backfill per-card review history for the memory-curve features.
@freezed
abstract class AnkiRevlogEntry with _$AnkiRevlogEntry {
  const factory AnkiRevlogEntry({
    /// Review id = epoch milliseconds of the review (the row's primary key).
    required int id,

    /// Card id this review belongs to (references [AnkiCardData.id]).
    required int cid,

    @Default(0) int usn,

    /// Button pressed: 1=again, 2=hard, 3=good, 4=easy (0 for manual/unset).
    @Default(0) int ease,

    /// New interval after this review (days for review cards; negative =
    /// seconds for learning steps).
    @Default(0) int ivl,

    /// Previous interval before this review (same unit rules as [ivl]).
    @Default(0) int lastIvl,

    /// New ease factor × 1000 (e.g. 2500 = 2.5).
    @Default(0) int factor,

    /// Time taken to answer, in milliseconds (not the review timestamp).
    @Default(0) int time,

    /// Review type: 0=learning, 1=review, 2=relearning, 3=cram.
    @Default(0) int type,
  }) = _AnkiRevlogEntry;
}
