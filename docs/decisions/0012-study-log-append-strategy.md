# ADR 0012: StudyLog append strategy (recent queue)

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 20, `StudyLogRepository`

## Context

`appendLog` previously read the full 90-day log list, appended one entry,
purged, and wrote the whole list back — O(n) prefs I/O per activity.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **Recent queue** (`study.logs.recent`, cap 200) | Small writes; simple JSON; merge on cap | Need dual-key read merge |
| Ring buffer single key | One key | Harder purge/merge; worse debug |

## Decision

Use an **incremental recent queue**:

- `study.logs` — main 90-day log (unchanged key).
- `study.logs.recent` — pending appends, **cap 200**.
- On `appendLog`: push to recent; purge stale rows from recent; if
  `recent.length >= 200`, merge into main, clear recent, purge 90 days on main.
- On `readLogs`: merge main + recent by id (recent wins), sort by timestamp.
- On `clearAll`: clear both keys + daily stats.
- `_writeChain` serializes all mutations (unchanged).

Daily stats updates stay on the critical path (small map) and are unchanged.

## Consequences

- Append of a typical study session only rewrites a small recent JSON array.
- Full rewrite cost amortizes to every 200 appends (or explicit `flushRecent`).
- Tests cover merge semantics, cap flush, clear, and corruption of recent.
