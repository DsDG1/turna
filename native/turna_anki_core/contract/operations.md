# Contract v1 operations

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
| 17 | CREATE_BACKUP | yes |
| 18 | SEARCH_CARDS_PAGE | yes |
| 19 | GET_NOTE_CARDS_BATCH | yes |
| 20 | GET_CARD_DESCRIPTORS_BATCH | yes |

Numbers are append-only after this document ships.
