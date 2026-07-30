# ADR 0027: Anki Smart Organization + SRS SQLite (Memory-Curve Round)

## Date
2026-07-28

## Status
Accepted

## Context
Two gaps motivated this round:

1. **Anki import was structure-blind.** `anki_deck_assembler` chunked every
   imported deck into flat 20-card lessons, ignoring any unit/lesson metadata
   the deck author encoded in notetype fields or tags. A user importing a
   structured deck lost its organization and got an arbitrary card count.

2. **SRS state was a prefs JSON blob with no per-card review history.** The SM-2
   queue lived in `StreamingSharedPreferences` as one serialized map. That meant
   no queryable review log (so no empirical forgetting curve, no real
   accuracy signal), and the SRS review screen reported session accuracy as
   `correctCount: reviewedCount, incorrectCount: 0` — always 100%.

The user asked for "智能化地对接 Anki 卡片" (intelligently connect Anki cards,
auto-mapping unit settings) and "完善记忆曲线" (improve the memory-curve
feature). Per scope decisions, the Anki side maps into **Anki's own structure**
(not the app's built-in course tree), and the memory-curve side takes the
**full model**: SRS state → SQLite + per-card review history + forgetting-curve
visualization.

## Decision

### 1. SRS state → SQLite (schema v6 → v7, part 1)
- New `SrsStates` table (wordId PK, queue, dueAt, intervalDays, ease, reps,
  lapses, isLeech, type, lastReviewedAt) in `course_database.dart`.
- `SrsStateDao` (`@lazySingleton`, plain DTO over `final CourseDatabase _db` —
  not `@DriftAccessor`, matching the existing DAO pattern): `loadQueue`,
  `upsert`, `upsertBatch`, `delete`, `deleteByPrefix` (LIKE `'$prefix%'`),
  `clearQueue`.
- `SrsQueueProvider` rewritten to hold a **synchronous in-memory cache**
  hydrated from SQLite via `ensureLoaded()` and written through on every
  `persist`/`importStates`/`removeItemsByPrefix`/`clear`. This preserves the
  synchronous contract of `state`, `dueCount`, and `getDueWords()` that ~25
  call sites depend on, avoiding an async refactor of all consumers.
- **Self-migration** in `ensureLoaded()`: on an empty table plus an unset
  `srs.migratedToSqlite.$queueId` flag, parse the old prefs blob once,
  backfill the DB, set the flag, and never read prefs again.
- `SrsWord` gained `lastReviewedAt` so the forgetting curve can be computed
  from the cached state without a DB join.

### 2. Review history + accuracy fix (schema v7, part 2)
- New `ReviewEvents` table (autoincrement id, cardId, queue, reviewedAt,
  quality, prevIntervalDays, nextIntervalDays, prevEase, nextEase, reps,
  lapses, type) with `@TableIndex` on `cardId` and `reviewedAt`.
- `ReviewHistoryDao` (`@lazySingleton`): `insertEvent`, `insertBatch`,
  `eventsForCard` (oldest first), `recentEvents({limit})`, `allEvents`,
  `count`, `deleteByCardPrefix`. `ReviewEventRecord` DTO with
  `bool get recalled => quality >= 3`.
- `reviewItem` sets `lastReviewedAt = DateTime.now()` and writes one
  `ReviewEventRecord` per review. The DAO is resolved **lazily** via
  `GetIt.instance<ReviewHistoryDao>()` with a `@visibleForTesting` setter, so
  the SRS base class's constructor signature only changed for the
  already-injected `SrsStateDao` — no churn across the ~25 test call sites.
- **Accuracy bug fixed**: `srs_review_screen._grantSessionRewards` now takes
  real `{reviewedCount, correctCount, incorrectCount}` (tracked via
  `_sessionCorrect`/`_sessionIncorrect` on grade == known) instead of the
  hard-coded `correctCount: reviewedCount, incorrectCount: 0`.

### 3. Memory-curve model + visualization
- `MemoryCurveProvider` (`@lazySingleton`): `snapshot()` computes
  - `currentRetention` = mean of `R = exp(-Δt / S)` over reviewed cards
    (FSRS-inspired forgetting curve; S ≈ intervalDays, Δt = days since
    `lastReviewedAt`);
  - `forecast` (dueToday / due7Days / due30Days);
  - `maturity` (new / young / mature / leech);
  - `retentionByInterval` — empirical recall rate bucketed by
    `prevIntervalDays` into [1,4,7,14,21,30,60,90,180].
- `learning_stats.dart` gained a `_MemoryCurveCard` (fl_chart `LineChart`
  with gradient + `BarAreaData`, a forecast mini-stat row, and maturity chips)
  rendered via `FutureBuilder`. `MemoryCurveProvider` is **optional** in the
  widget tree — `context.read` is wrapped in try/catch and the card is omitted
  if the provider is absent (keeps existing widget/golden tests green).
- `sm2.dart` gained `previewIntervalDays(word, quality)` (deterministic,
  no fuzz) for the review-screen "known → N days" preview chip.

### 4. Anki smart organization (zero-regression fallback)
- `AnkiOrganizationResolver.resolve(note, notetype)` extracts `unitKey` /
  `lessonKey`:
  - first from **notetype field names** matching unit/chapter/section/单元/章
    (unit) and lesson/topic/subunit/课/节 (lesson);
  - falling back to **tags** with prefixes `unit::`/`unit:`/`chapter::`/
    `chapter:`/`单元::`/`单元:` (unit) and `lesson::`/`lesson:`/`课::`/`课:`
    (lesson);
  - field value takes priority over tag; HTML stripped from field values.
- `anki_deck_assembler.assemble(smartGrouping:)` groups cards into Units →
  Lessons by those keys (deck name as the unit fallback). Multi-chunk (>20)
  lessons are named `"$lessonKey #N"`.
- **Zero-regression**: when no unit/lesson metadata is present, behavior is
  byte-identical to the old 20-card chunking — the existing assembler tests
  pass unchanged. The import screen shows a preview (distinct unit/lesson
  counts + resolved-card count) and a smart-grouping switch (default on).

### 5. Anki revlog parse + migrate
- `AnkiRevlogEntry` freezed model (id, cid, usn, ease, ivl, lastIvl, factor,
  time, type) added to `AnkiCollection`.
- `AnkiImporter._parseRevlog` — paginated (LIMIT/OFFSET 500), table-missing-safe
  (try/catch on COUNT, returns empty), best-effort (never blocks import).
- `AnkiSrsMigrator.migrate()` now takes `revlog` + optional
  `ReviewHistoryDao` and backfills `ReviewEventRecord`s. revlog ease maps to
  quality 1→1 (again), 2→3 (hard), 3→4 (good), 4→5 (easy); unknown cids are
  skipped. When no DAO is supplied, revlog is ignored (no crash).

## Consequences
- SRS state is queryable and survives provider reconstruction from SQLite;
  the prefs blob is a one-time migration source only.
- Per-card review history powers an empirical forgetting curve and an
  accuracy signal grounded in real recall data, not a 100% placeholder.
- Anki imports preserve the deck author's unit/lesson structure when present,
  and degrade gracefully to the previous flat chunking when absent — no
  behavior change for unstructured decks.
- Revlog migration means an Anki user's prior review history seeds the
  memory curve from day one.
- Schema is at v7; downgrade wipes `srs_states` and `review_events`.
- New tests: `srs_state_dao_test` (8), `review_history_dao_test` (9),
  `memory_curve_provider_test` (5), `anki_organization_resolver_test` (10),
  plus updates to srs_provider / grammar_review / srs_review_flow /
  anki_srs_migrator / anki_deck_assembler / sm2 / schema_migration /
  provider_identity / golden / learning_stats. Suite: 484 → 528 all pass.
