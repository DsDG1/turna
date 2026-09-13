# ADR 0028: FSRS Continuous Memory Model for SRS

## Date
2026-07-29

## Status
Accepted

## Context

Varnamala’s SRS core was a tuned **SM-2** (`lib/core/sm2.dart`) with binary
grades (认识 / 不认识). Profile maturity chips labelled cards as
`new / young / mature / leech` based on `intervalDays >= 21`. That UI pattern
reads like a **Leitner-style four-box “graduation”**, but:

1. SM-2 does **not** predict recall probability \(R(t)\).
2. “Mature” is only a workload bucket — not “mastered forever”.
3. Failures still use coarse rules (young → 1 day; mature ×0.2).
4. ADR 0027 already stores per-card `review_events`, so a probabilistic model
   can use real history.

### Research summary

| Source | Role |
|--------|------|
| Ebbinghaus (1885) | Forgetting curve foundation |
| Leitner | Fixed boxes / multi-stage “graduation” — **rejected** as primary scheduler |
| SM-2 (Wozniak, 1987) | Prior implementation; ease + exponential intervals |
| Settles & Meeder, ACL 2016 (Duolingo HLR) | Trainable half-life for L2 vocab; continuous \(h\), not discrete stages |
| Ye et al., KDD 2022 (DHP / FSRS lineage) | DSR model + cost-optimal scheduling under target retention |
| FSRS (open-spaced-repetition; Anki 23.10+) | Production D/S/R scheduler; open benchmark superiority vs Anki SM-2 |

**Product definition of mastery (this ADR):** continuous signals
\(R_{\text{now}}\) and stability \(S\) (days until predicted \(R \approx 0.9\)),
**not** “passed stage 4 / never review again”.

## Decision

1. Introduce `SrsScheduler` abstraction with `review`, `previewIntervalDays`,
   `retrievability`, `masteryScore`.
2. Default implementation: **FSRS** via `package:fsrs` (default weights,
   `desiredRetention = 0.9`, max interval 730d, relearn ~10m).
3. Keep `Sm2Engine` as legacy scheduler for tests/compat; production queue uses FSRS.
4. Extend `SrsWord` + `srs_states` (schema **v8**) with `stability`,
   `difficulty`, `fsrsState`, `learningStep`.
5. **Binary-only scoring (locked):** the only user-facing outcomes are
   **pass / fail** (记住·做对 / 没记住·做错). Mapped to FSRS Again / Good.
   Four-button Again/Hard/Good/Easy UI is **out of scope** (not deferred).
6. Memory curve uses FSRS \(R(t,S)\), not `exp(-Δt / intervalDays)`.
7. Maturity chip copy: 新卡 / 巩固中 / 长期记忆 / 顽固 — no “毕业掌握”.
8. Lesson exercise grades (correct / incorrect) feed the same pass/fail
   pipeline as flashcard self-rates when a word/expression id is known.

## Consequences

- Scheduling optimizes for target retention, not ease-factor heuristics.
- Lapses use post-lapse stability (no hard reset to “stage 1” forever).
- Cards never leave the queue solely by stage count; long intervals still exist.
- One-time migration seeds \(S,D\) from SM-2 `intervalDays`/`ease` when FSRS
  fields are null.
- Anki revlog Hard/Easy collapse to pass on import; UI never exposes four grades.
- Personal weight optimization remains future work (needs large local history).
- Desired retention \(R_{\text{desired}}\) is user-tunable (default 0.9) without
  adding grade buttons.

