# Contract v1.9 operations

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
| 9 | SEARCH_CARDS | yes (host/spike only; not production) |
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

Scheduler operations 11–16 and 27–36 are published. Request/response DTO are
camelCase. `answerToken` is opaque. `GET_REVIEW_QUEUE` creates a new
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
(1..100). The engine builds a temporary Official filtered deck, answers
through the scheduler, then empties and removes the deck. Response
`{ answeredCards }`. Missing capability is fail-closed.

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
