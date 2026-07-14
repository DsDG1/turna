# ADR 0016: Integration and golden test strategy

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 24

## Context

We need regression protection for multi-step learning flows and key screens
without requiring a physical device in every CI job.

## Decision

### Host E2E (`test/integration/`)

- Logical end-to-end tests using real providers + fakes (audio, course).
- Run with `flutter test test/integration/`.
- Device-level `integration_test/` package reserved for Phase 25 smoke if needed.

### Golden tests (`test/golden/`)

- Fixed surface sizes; light + dark via `VarnamalaTheme`.
- PNGs under `test/golden/goldens/` are committed.
- **Update only manually**: `flutter test --update-goldens test/golden/`.
- CI runs goldens without `--update-goldens`; failure blocks merge.

### Coverage targets (Phase 24)

- Flows: lesson completion + progress, SRS review persistence, dictionary + weak words.
- Goldens: play hub, dictionary results, settings reminder, SRS empty state.
- Widget gaps: match words smoke, settings toggles, lesson completion dialog.

## Consequences

- Content PRs (future5) can rely on these paths for behavioral/visual lock.
- Local OS/font differences may require re-generating goldens on the CI OS.
