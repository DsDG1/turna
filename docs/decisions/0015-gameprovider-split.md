# ADR 0015: GameProvider split (facade)

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 23, ADR 0007

## Context

`GameProvider` (~428 lines) owned score, streak, lesson progress, milestone
unlocks, gems coordination, and four broadcast streams — hard to test and
risky to change.

## Decision

Split into focused `@lazySingleton` providers behind a **stable facade**:

| Provider | Responsibility |
|---|---|
| `ScoreProvider` | XP score prefs |
| `StreakProvider` | streak / last date / app-open check; uses pure `resolveStreakOnPractice` |
| `LessonProgressProvider` | completed/perfect lesson sets + stream |
| `GameMilestoneProvider` | XP/streak unlock ids + gem apply (≠ UI `AchievementsProvider`) |
| `GameProvider` | public API facade; orchestrates `incrementScore` / streams |

- Pure streak logic: `lib/core/streak_resolver.dart`.
- Call sites keep using `GameProvider`; UI MultiProvider list unchanged.
- Tests use `GameProvider.forTesting(prefs)`.
- Stream ownership: lesson progress stream lives on `LessonProgressProvider`;
  aggregated `UserGameState` / score / streak broadcast remain on the facade.

## Migration path

Later phases may inject sub-providers into widgets; not required now.

## Consequences

- Facade ~200 lines of orchestration (still thinner and structured).
- Existing fakes that `implements GameProvider` continue to work.
