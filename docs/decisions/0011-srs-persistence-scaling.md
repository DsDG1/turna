# ADR 0011: SRS persistence scaling (sharding threshold)

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 20, `SrsProvider._persist`

## Context

Every SRS review currently re-encodes the entire `Map<String, SrsWord>` to a
single prefs key (`srs.state`). That is O(n) JSON work per review. At large
vocab sizes this could become a jank source.

## Decision

1. **Measure first** via `SrsProvider.encodeStateForPersist` and
   `test/application/srs_persist_benchmark_test.dart` (500 / 2000 / 10000 rows).
2. **Shard threshold** (from future4): if encode at **n > 2000** takes
   **> 5 ms** on a representative host, implement `srs.state.shard.<i>` and
   rewrite only the affected shard on review.
3. **Phase 20 outcome**: baseline tests land; **sharding is deferred**. On
   typical developer Linux / CI hosts, full-map encode at 10k entries is well
   under 5 ms (often sub-millisecond for 2k). Current course scale is far below
   2k SRS items.
4. Production path remains a **single blob** key `LocalStateKeys.srsState`.
   Revisit when real Swahili content (future5) or user history approaches the
   measured threshold.

## Consequences

- No migration of existing prefs.
- Benchmark test documents scale without flaky wall-clock assertions.
- If future profiling exceeds the threshold, implement sharding without
   changing the public `SrsProvider` API.
