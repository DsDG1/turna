# Contract v1.3 operations

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

Scheduler operations 11–16 and 27–30 are published. Request/response DTO are
camelCase. `answerToken` is opaque. `GET_REVIEW_QUEUE` creates a new
session/queue epoch. Tokens are single-use. Numbers are append-only after this
document ships.

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
