# ADR 0034: AI companion hardening

## Status
Accepted

## Context
Companion features (hint stream, free chat, dictionary enrich, diagnosis,
saved explanations, review card explain) shipped in the A–E enrichment plan.
Skeptic review found DI orphans for `AiExplainPrefsStore`, incomplete
learner-context injection, and residual raw error strings.

## Decision
1. **Single prefs store**: Register `AiExplainPrefsStore` (and saved
   explanations) as GetIt singletons in `setupLocator`; resolve via
   `AiExplainPrefsStore.resolve`. No silent orphan stores on production paths.
2. **Engine-only I/O**: Companion providers call only `AiEngine`; never
   `ai_prompt_builder` or course section JSON schema.
3. **Errors**: All user-facing companion errors go through `AiErrorMapper`.
4. **Rate limit**: Local debounce for dictionary enrich; diagnosis keeps ≥60s;
   hint supersede remains uncapped (cancel previous).
5. **Cache**: Changing reply language / depth / inject clears `AiEngine` cache
   so prefs fingerprint changes are not masked by LRU hits.
6. **Export**: Progress export must never include `ai.engineConfig` (API key).

## Consequences
- Settings → explain prefs affect all companion surfaces consistently.
- Tests assert inject-off, schema boundary, and export key exclusion.
- Optional usage counters remain backlog.
