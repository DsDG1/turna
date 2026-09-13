# ADR 0013: SRS queue base class

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 21, ADR 0007

## Context

`SrsProvider` and `GrammarReviewProvider` duplicated state load/persist,
SM-2 review, due caching, and lesson-link recording — ~500 lines of near-
isomorphic code with divergent public method names.

## Decision

Introduce `SrsQueueProvider` (`lib/application/srs_queue_provider.dart`):

| Concern | Owner |
|---|---|
| Prefs key / log tag | Subclass abstract getters |
| State load / `persist` / `clear` | Base |
| `registerItem` / `registerAllItems` / `reviewItem` | Base |
| Primary due cache (`getDueItems`) | Base |
| Public API names (`registerWord`, `reviewGrammarPoint`, …) | Subclass wrappers |
| Dual expression due cache (Phase 20) | `SrsProvider` only |
| `markDueNow` | `GrammarReviewProvider` only |

**Not done**: splitting word/expression into two providers (would break
single-blob prefs and public API).

## Consequences

- Subclasses are thin facades; behavior covered by existing unit tests.
- `encodeStateForPersist` lives on the base (benchmarks import base).
- Call sites unchanged.
