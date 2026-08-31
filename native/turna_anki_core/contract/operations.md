# Contract v1.12 operations

Wire format is versioned JSON. `turna_anki_spike.proto` is archived and is not
the codec.

| Number | Name | Collection required |
|---:|---|---|
| 1 | ENGINE_INFO | no |
| 2 | OPEN_COLLECTION | no |
| 3 | CLOSE_COLLECTION | yes |
| 4 | CHECK_COLLECTION | yes |
| 5 | IMPORT_PACKAGE | yes |
| 6 | LATEST_PROGRESS | no |
| 7 | CANCEL_OPERATION | no |
| 8 | LIST_DECK_TREE | yes |
| 9 | ~~SEARCH_CARDS~~ | **retired in v1.10** (doc 38 P1-E; unbounded full-collection dump. The number is never reused.) |
| 10 | RENDER_CARD | yes |
| 11 | SET_CURRENT_DECK | yes |
| 12 | GET_REVIEW_QUEUE | yes |
| 13 | DESCRIBE_NEXT_STATES | yes |
| 14 | ANSWER_CARD | yes |
| 15 | GET_UNDO_STATUS | yes |
| 16 | UNDO | yes |
| 17 | CREATE_BACKUP | yes |
| 18 | SEARCH_CARDS_PAGE | yes |
| 19 | GET_NOTE_CARDS_BATCH | yes |
| 20 | GET_CARD_DESCRIPTORS_BATCH | yes |
| 21 | RESTORE_BACKUP | yes |
| 22 | COMPARE_TYPED_ANSWER | yes |
| 23 | EXTRACT_CLOZE_FOR_TYPING | yes |
| 24 | GET_PROJECTION_SCHEMAS | yes |
| 25 | BEGIN_PROJECTION_READ | yes |
| 26 | GET_PROJECTION_ROWS_BATCH | yes |
| 27 | REDO | yes |
| 28 | BURY_OR_SUSPEND_CARDS | yes |
| 29 | COUNTS_FOR_DECK_TODAY | yes |
| 30 | CONGRATS_INFO | yes |
| 31 | DELETE_NOTES | yes |
| 32 | DELETE_CARDS | yes |
| 33 | STATS_FOR_CARDS_BATCH | yes |
| 34 | SCHEDULE_CARDS_AS_NEW | yes |
| 35 | ANSWER_AHEAD_CARDS | yes |
| 36 | ENSURE_TODAY_NEW_QUOTA | yes |
| 37 | GC_UNUSED_MEDIA | yes |
| 38 | PRUNE_EMPTY_METADATA | yes |
| 39 | COMPACT_COLLECTION | yes |
| 40 | DIFF_COLLECTION_CHECKPOINT | yes |
| 41 | GET_CONFIG | yes |
| 42 | SET_CONFIG | yes |

Scheduler operations 11–16 and 27–36 are published. Request/response DTO are
camelCase, with four load-bearing snake-case compat keys kept on the wire:
import log (`new_note_ids` & co), deck tree (`deck_id`/`new_count`/
`learn_count`/`review_count`), undo status (`can_undo`/`can_redo`) and
LATEST_PROGRESS (`operation_kind`/`can_cancel`/`want_abort`). `answerToken` is opaque. `GET_REVIEW_QUEUE` creates a new
session/queue epoch. Tokens are single-use. Numbers are append-only after this
document ships.

`DELETE_NOTES` accepts `{ noteIds: [nid, …] }` (1..10_000 per call, callers
batch) and removes those notes and every card that uses them from the
Collection. It exists for hard source uninstall: note-scoped so decks shared
with other sources (default deck, same-named merged decks) keep the cards they
own. The response is `{ ok, removedCards, queueEpoch }`.

`DELETE_CARDS` is the exact-source uninstall primitive. It removes only the
listed cards and deletes a note only after its final card is gone.

`STATS_FOR_CARDS_BATCH` returns source-scoped scheduler/revlog statistics for
at most 200 exact card IDs. `SCHEDULE_CARDS_AS_NEW` is the explicit W8 reset
policy primitive and resets at most 10,000 exact card IDs per call.

`ANSWER_AHEAD_CARDS` rates cards that may not be in today's due queue
(lesson redo / 提前复习). Request `{ answers: [{ cardId, rating, millisecondsTaken }] }`
(1..100). Cards already rated today are skipped inside the op (host-side
idempotency scans are obsolete). The engine builds a temporary Official
filtered deck over `(<cid terms>) -rated:1`, answers through the scheduler,
then empties and removes the deck. Response
`{ answeredCards, skippedRatedToday }`. Missing capability is fail-closed.

`ENSURE_TODAY_NEW_QUOTA` raises today's remaining new-card quota for one
deck so remaining ≥ `neededNew`. Request `{ deckId, neededNew }`
(`neededNew` 0..9999). Native reads today's studied new count, the preset
`new_per_day`, and current `extend_new`; if remaining is already enough it
is a no-op. Otherwise it applies Official Custom Study `NewLimitDelta`
(sets `extend_new`, does not permanently change `new_per_day`). Response
`{ extendedBy }`. Missing capability is fail-closed.

`RENDER_CARD` requests are camelCase `{ cardId, browser, includeAvTags }`.
Production reviewer always sends `browser=false`. Rust forces
`partial_render=false`. The response is camelCase and includes both raw
`questionHtml`/`answerHtml` and AV-extracted `questionDisplayHtml` /
`answerDisplayHtml`. After AV extraction, display HTML is passed through
official `encode_iri_paths()` plus `%`/`?` protection and a CSS `url()`
encoder. Raw `questionHtml`/`answerHtml` stay unencoded goldens. UI may only
display the `*DisplayHtml` fields.

Optional additive fields (contract 1.1 compatible): `templateOrdinal` (0-based)
and `bodyClass` (for example `card card1`). Native does not emit Desktop
`isWin`/`isMac`/`isLin`. Night classes are added by the UI only.

`COMPARE_TYPED_ANSWER` accepts `{ cardId, marker, provided }` and returns
`{ comparisonHtml, hasExpected }`. Expected text is resolved from the open
Collection; Dart must not parse `{{cN::...}}`.

## v1.9 additions (additive)

`GET_PROJECTION_SCHEMAS` responses now carry a derived `templateFacts` object
per notetype: `{ hash, templates: [{ ord, name, frontFields, backFields,
filters: { typeIn, tts, hint, script, complexHtml } }], reqs: [{ cardOrd,
kind: NONE|ANY|ALL, fieldOrds }] }`. `frontFields`/`backFields` are field
ordinals computed with rslib `ParsedTemplate::requirements` (identical logic
to the stored `config.reqs`, applied per face). `filters` are derived
booleans/field-name lists; no raw template text (`qfmt`/`afmt`/CSS) ever
leaves the engine. The `sampleLimit` clamp rose from 10 to 30 (default stays
3). Old Dart minors ignore the new keys; old engines simply omit them.

## v1.11 additions (additive)

`GC_UNUSED_MEDIA` runs rslib `check_media` then optionally `trash_media_files`
+ `empty_trash`. Request `{ mode: "dryRun"|"trashAndDelete" }`. Response
counts/bytes only — no filename lists on the production envelope.

`PRUNE_EMPTY_METADATA` deletes candidate notetype/deck IDs after re-checking
use counts. Stock notetype id 1 and Default deck id 1 are never removed.

`COMPACT_COLLECTION` vacuums the Collection file after a space/lock check and
returns before/after bytes plus a skip reason.

`DIFF_COLLECTION_CHECKPOINT` is best-effort: when a restorable checkpoint
file is available it returns `{ cardIds }` added since that snapshot; otherwise
an empty list.

`GET_CARD_DESCRIPTORS_BATCH` now includes optional `notetypeId` (notes.mid).

## v1.12 additions (additive, ADR 0043 D2)

`GET_CONFIG` (41) reads one Collection config entry. Request `{ key }`
(non-empty, ≤128 bytes, any key — Anki-native keys included, for
diagnostics). Response `{ found, value? }`. A missing key — or a blob that
no longer parses as JSON, matching rslib `get_config_optional` semantics —
reports `found: false` with no `value` field.

`SET_CONFIG` (42) writes one config entry inside a single Collection
transaction (rslib `set_config_json`, not undoable), so a mid-op kill
leaves no half-written key (ADR 0043 K10). Request `{ key, value }`;
response `{ ok, removed }`. Gates:

- `key` must start with `turna.` — the bridge can never clobber Anki's own
  config entries (`schedVer`, `curDeck` & co). Violations are
  `INVALID_ARGUMENT`.
- `value` must be a JSON object (decisions are structured), ≤256 KiB
  serialized.
- A missing or explicit `null` value **deletes** the key (single-statement
  atomic SQL; deleting a missing key succeeds — idempotent), and the
  response reports `removed: true`.
- Every write/delete advances the content generation: config decisions are
  projection input (ADR 0043 D3), so stale projection snapshots must not
  be considered fresh.

## v1.10 changes

- **Retired op 9 `SEARCH_CARDS`.** It never appeared in `capabilities` and
  no production Dart path called it; its handler dumped every note of the
  whole collection per call. The dispatch arm, handler and name→id mapping
  are removed; the number 9 is permanently retired and never reused.
  Bridge tests now page through `SEARCH_CARDS_PAGE` (18).
- **`BEGIN_PROJECTION_READ.collectionGeneration` is now the content
  generation** (doc 38 P2): it advances only on content-changing
  operations (`IMPORT_PACKAGE`, `DELETE_NOTES`, `DELETE_CARDS`, `UNDO`,
  `REDO`, `RESTORE_BACKUP`, collection reopen) and survives
  scheduling-only mutations such as `ANSWER_CARD` or
  `BURY_OR_SUSPEND_CARDS`. A projection snapshot therefore stays usable
  across answers; paging tokens keep their own `page_generation` counter
  that advances on every mutating op.
