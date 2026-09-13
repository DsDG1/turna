# ADR 0029: FSRS Relearn Ladder + Local Weight Fitting

## Date
2026-07-29

## Status
Accepted

## Context

ADR 0028 introduced FSRS with **binary** pass/fail scoring. Remaining gaps:

1. Relearn after fail was a flat 10 minutes (plus a crude total-lapse cap).
2. All users shared default FSRS weights; no personalization from
   `review_events` despite having a full local history table.

Four-grade UI remains **out of scope**.

## Decision

### 1. Same-day relearn ladder (rule-based)

Fail streak is **per card per local calendar day** (from
`ReviewHistoryDao.countFailsOnLocalDay`), not lifetime `lapses`:

| Today’s fail # | Next due |
|----------------|----------|
| 1 | +10 min (or +30 min if mature, S≥21) |
| 2 | +30 min |
| 3 | +2 h |
| ≥4 | next local day |

Applied in `FsrsEngine.reviewWithFailContext` after the package scheduler.

### 2. Local weight fitting (lite)

- Persist 21 weights in prefs (`srs.fsrsParameters`); empty = defaults.
- `FsrsLiteOptimizer`: pure Dart projected SGD on binary cross-entropy over
  chronological pass/fail sequences built from `review_events`.
- Minimum **300** reviews; accept only if train loss improves ≥0.5% relative.
- Manual trigger from settings (“根据学习记录优化”); never silent auto-train.
- Not guaranteed to match `fsrs-rs` numerically; prioritizes local-first mobile.

### 3. Binary contract unchanged

pass/fail only; Anki Hard/Easy still collapse to pass.

## Consequences

- Fail spam is less punitive than “always 10 min” and safer than lifetime caps.
- Personalized weights are optional and reversible.
- Optimizer is approximate; heavy users may later migrate to FFI `fsrs-rs`.
