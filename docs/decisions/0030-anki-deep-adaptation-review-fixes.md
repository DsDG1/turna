# ADR 0030 — Anki Deep-Adaptation Code-Review Fixes

- **Status:** Accepted
- **Date:** 2026-08-02
- **Round:** Anki deep-adaptation post-merge review

## Context

A `git diff HEAD` review of the Anki deep-adaptation round (1682 files,
~280k lines of which the great majority are wiki + generated-code deletion)
produced 10 findings. Each finding was re-checked against the actual code
before fixing; ground-truth validation matters here because the deep-
adaptation refactor is large and the diff touches many Anki-specific code
paths that were not exercised by the existing test suite at the time of the
review.

This ADR records the validation outcome, the chosen fix scope, and the
callers affected by the public-API changes.

## Validation outcome

| #  | Finding (reviewer claim)                                                                       | Validation                              | Action                  |
|----|-------------------------------------------------------------------------------------------------|-----------------------------------------|-------------------------|
| 1  | ZIP entry path traversal on Windows (`..\..\`) in `_safeArchiveEntryName` / `_safeRelativePath`  | The check already rejects `..` segments | **Skip (false alarm)**  |
| 2  | `_learningDueAt` interprets legacy queue=1 `due` as seconds (should be minutes)                 | Real                                    | **Fix**                 |
| 3  | Race between Undo and in-flight FSRS grade; `_gradesInFlight` is the wrong gate                 | Gate is correct; **real narrower gap**: `LessonViewModel` never captures `previous` for non-Anki lessons and `undoLastInteraction` is sync `bool` with no async SRS rollback | **Fix (narrower than proposed)** |
| 4  | `_asJsonMap` silently drops `col['dconf']` → users lose custom FSRS weights                      | `deckConfigs` field has no downstream consumer (traceability only) | **Skip (false alarm)** |
| 5  | `parseCorrectIndices` accepts `"0"` as option A via 0-based fallback                            | Real                                    | **Fix**                 |
| 6  | `bulkInsertCourseTree` reads `MAX(sort_order)` outside the batch transaction; concurrent imports race | Real                                | **Fix**                 |
| 7  | `markComplete` not invoked on cancellation; partial imports stay `pending` forever               | Real                                    | **Fix**                 |
| 8  | Lazy canonical cards produce blank review sessions                                              | `AnkiCanonicalCardLoader.load` always renders front+back HTML via `AnkiCardHtmlRenderer`; empty-HTML path is unreachable | **Skip (false alarm)** |
| 9  | Notetype field-name vs field-count mismatch silently mis-indexes content                        | Real but narrow (only triggers on malformed `flds`) | **Fix** |
| 10 | `bulkInsertCourseTree` same-id collision across rapid re-imports                                | Mitigated transitively by Fix 6's `DoNothing` | **Skip (covered by Fix 6)** |

## Fix scope

Six code changes, each with a unit test:

### Fix 1 — `lib/application/anki/anki_srs_migrator.dart`

`_learningDueAt` now interprets a legacy queue=1 `due` value
(`< 100000000`) as **minutes relative to import time**. The previous
fallback `collectionCreationTime + due seconds` was always wrong for legacy
decks — it would put a 10-minute learning card back into the queue 10
seconds after import instead of 10 minutes later.

**Test:** `test/anki/anki_srs_migrator_test.dart` — new
`'legacy learning due (queue=1) is interpreted as minutes'`.

### Fix 2 — `lib/application/anki/anki_card_adapter.dart`

`parseCorrectIndices` drops the 0-based fallback that previously accepted
`"0"` as a 0-based option index. Numeric answers are now strictly 1-based
(`"1"` → options[0], `"4"` → options[3]). Out-of-range and `0` produce an
empty `correctIndices` list so the prompt surfaces as failed instead of
silently passing on option A.

**Test:** `test/anki/anki_card_adapter_test.dart` — new
`'parseCorrectIndices does not treat "0" as a 0-based option'`.

### Fix 3 — `lib/data/course_repository.dart`

`bulkInsertCourseTree` now wraps the `MAX(sort_order)` read + batched write
in `database.transaction(...)`. The section-row insert switches from
`DoUpdate` to `DoNothing`: a previous import's section id colliding with a
new import's id now leaves the existing row intact (its vocab + lesson
rows stay valid), instead of silently overwriting the section's name/
level and orphaning the first import's vocab rows. `DoUpdate` is kept on
the units / lessons / contents child tables — they are nested under the
section id and would also be skipped by FK cascade if the parent insert
loses.

**Test:** `test/data/course_repository_test.dart` — new
`bulkInsertCourseTree` group with sequential, duplicate-id, and concurrent
insert coverage.

### Fix 4 — `lib/data/anki_import_dao.dart` + `lib/views/anki/anki_import_screen.dart`

New `AnkiImportDao.markFailed(importId, reason)` writes
`status = 'failed'` + `last_error = ?`. The import screen's existing
cancellation and error handlers now call `markFailed` after rolling back
SRS state and cleaning up the data, so partial imports stop leaving a
`pending` row in `anki_imports` that the lifecycle UI cannot surface.

**Test:** `test/data/anki_import_dao_test.dart` (new file) — covers
`markFailed` happy-path, no-reason variant, idempotent re-mark, and
no-op-on-missing-importId.

### Fix 5 — `lib/application/lesson_viewmodel.dart` + `srs_provider.dart` + `grammar_review_provider.dart`

Three coordinated changes:

1. `LessonViewModel._applySrsOutcome` now captures the pre-grade
   `SrsWord` for every queue the interaction touched (word + expression +
   grammar-point), pushing each onto a private `_srsUndoStack`.
2. `LessonViewModel.undoLastInteraction` is now **`Future<bool>`**. It
   still rewinds the UI counters synchronously, then awaits the SRS
   rollback for every entry on the stack. A `false` return means the
   base-class `_gradesInFlight` gate refused the rollback (an in-flight
   grade) — the entry is pushed back so the next attempt can retry, and
   the UI can leave the undo affordance enabled.
3. `SrsProvider.rollbackWord` / `rollbackExpression` and
   `GrammarReviewProvider.rollbackGrammarPoint` are new public surfaces
   that delegate to `SrsQueueProvider.undoReview`. The
   `previous ?? state[id] ?? SrsWord.fresh(id)` fallback handles
   never-before-seen items captured during the same lesson.

**Migration note for callers:** `LessonViewModel.undoLastInteraction`'s
signature changed from `bool` to `Future<bool>`. `lib/views/anki/anki_review_session_page.dart:_undoLastReview` is the only existing caller; it now `await`s the result and treats `false` as
"leave the snackbar visible, retry on next tap". Any future caller must
do the same.

**Test:** `test/application/lesson_viewmodel_flow_test.dart` — new
`LessonViewModel.undoLastInteraction` group: counter restoration on
non-Anki MCQ items, plus a gate-held undo path using a
`Completer`-gated `ReviewHistoryDao` stub.

### Fix 6 — `lib/application/anki/anki_importer.dart`

`_parseNotetypes` now rejects the entire notetype when **any** field is
malformed or when `flds` is empty, instead of warning-and-continuing with
`fieldNames[i] == ''` and silently shifting subsequent indices. A
malformed export produces zero notetypes for that mid, surfacing as a
clear diagnostic in the import log rather than as mis-paired MCQ prompts.

The test seam `@visibleForTesting static parseNotetypesForTest(String)`
exposes the private parser so unit tests don't need an `.apkg` fixture.

**Test:** `test/anki/anki_importer_test.dart` (new file) — valid
notetype, malformed-field rejection, missing-`name`-key rejection, empty-
`flds` rejection, and a mixed-validity case.

## Deferred findings — rationale

- **Finding 1** — The `_safeArchiveEntryName` check at `lib/application/anki/anki_importer.dart:235-247` already rejects `..` segments after normalizing backslashes to forward slashes. The reviewer was misled by the slash normalization appearing to allow the traversal; the actual `parts.any((p) => p.isEmpty || p == '..')` rejects it. `_safeRelativePath` in `lib/domain/audio/anki_audio_resolver.dart:147-156` has the same check. Both should remain; no code change.
- **Finding 4** — `AnkiCollection.deckConfigs` is read nowhere downstream; the field is a traceability artifact only. Revisit when a deck-config-driven scheduling feature lands.
- **Finding 8** — `AnkiCanonicalCardLoader.load` (`lib/application/anki/anki_canonical_card_loader.dart:25-92`) always renders front+back via `AnkiCardHtmlRenderer.renderFront/renderBack`. The lazy threshold in `AnkiDeckAssembler.assemble` (`liteThreshold = 2000` at line 122) gates how much is preloaded, never whether anything renders. The blank-card scenario the reviewer described is unreachable.
- **Finding 10** — `bulkInsertCourseTree`'s same-id collision is now covered transitively by Fix 6's `DoNothing` (a colliding section id keeps the existing row and skips the new one). Import uniqueness is the importer's responsibility (the `importId` is ms-based and the importer's caller catches collisions before reaching the bulk insert).

## Out of scope

- **`_asJsonMap` warning on `col['dconf']` failures** — field is unused.
- **`_safeRelativePath` symlink check** — no symlink-aware platform code in this codebase.
- **`AnkiReviewAssembler._deckIdFromSectionId` regex hardening** — works for every section id the assembler currently produces.
- **Migrating `anki_review_session_page.dart`'s private `_ReviewUndoEntry` capture helper** — separate code path; the lesson VM now owns the canonical capture, but the review page's page-local `_undoEntry` keeps a richer snapshot (wasNewCard, importId) the VM doesn't need. Migrate in a follow-up once Fix 5 stabilizes.

## Verification

```bash
flutter test test/anki/anki_importer_test.dart \
           test/anki/anki_card_adapter_test.dart \
           test/anki/anki_srs_migrator_test.dart \
           test/data/course_repository_test.dart \
           test/data/anki_import_dao_test.dart \
           test/application/lesson_viewmodel_flow_test.dart
flutter analyze
```

End-to-end smoke (manual, on Android):

1. Import a legacy Anki 2.1 deck with 50 mid-10-min learning cards → verify they appear as due in ~10 min, not 10 sec.
2. Import two `.apkg` files in quick succession → verify the L1 course tree has both with stable ordering across restarts.
3. Cancel a 5k-card import mid-way → verify `anki_imports.status = 'failed'` (DB inspector) and the import manager offers a retry.
4. Submit one correct + one incorrect answer in a non-Anki lesson → tap Undo → verify counters restored + SRS state reverted.
5. Submit while the FSRS gate is held (test-only `_GateHoldingReviewHistoryDao`) → undo returns false; retry after gate release succeeds.
6. Submit `"0"` in a quiz answer → verify it surfaces as failed, not as option A marked correct.