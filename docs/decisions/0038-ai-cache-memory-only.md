# ADR 0038: AI response cache is memory-only

## Status

Accepted

## Context

The AI cache exposed an optional synchronous file mirror, but production never
attached it. Keeping the dormant API and disk-write counters implied durability
that the product did not provide, while synchronous file operations could block
the UI isolate if enabled later.

## Decision

`AiCache` is a bounded, process-local LRU and is the only AI response cache.
There is no disk attachment API, disk statistic, or cold-start promotion path.
The storage diagnostics surface reports entries as memory keys and does not
convert that count into bytes.

Any future persistent cache must be designed as a new component. It must use
asynchronous/isolate I/O, enforce byte and TTL limits, record `createdAt` and
`lastAccess`, include cache schema and prompt versions in invalidation, and
provide an explicit regenerable-data clearing contract. The removed synchronous
implementation must not be restored.

## Consequences

- Restarting the app intentionally drops cached AI responses.
- “Clear AI cache” clears only bounded in-memory entries.
- Cache diagnostics match production behavior and cannot suggest disk usage.
