# ADR 0005: Test coverage expansion for robustness

- **Status**: Accepted
- **Date**: 2026-07-10
- **Related**: Robustness roadmap Phase 1, ADR 0004

## Context

Before this phase, several core providers had no dedicated tests: `SrsProvider`, `MistakeProvider`, `GameProvider`, and the `Achievement` domain model. The DI bootstrap (`main.dart` + `setupLocator`) had no test pinning its `SettingsProvider` registration contract. The view layer had only one widget test (`course_tree_test.dart`).

Two latent bugs were surfaced during audit:

1. **`Achievement.getCurrentLevel` off-by-one** (`lib/domain/achievement.dart`): when progress met or exceeded the final target, the method returned `targets.length + 1` — one above `maxLevel` (`targets.length`). The consuming widget (`lib/views/profile/widgets/achievements.dart`) relied on this with `isCompleted = level > maxLevel`, coupling a wrong invariant to another wrong invariant.
2. **`StreamingSharedPreferences` test isolation**: `SharedPreferences.setMockInitialValues({})` does not clear an already-cached `StreamingSharedPreferences` instance, so cross-test state leaked when multiple tests reused the cached instance. This affected every prefs-backed provider test and was not documented anywhere.

## Decision

1. Add unit tests for the high-risk, previously-untested providers:
   - `test/application/srs_provider_test.dart` — SM-2 scheduling, due computation, word/expression dual-track, persistence round-trip, corrupted-JSON degradation.
   - `test/application/mistake_provider_test.dart` — FIFO log, 30-entry cap, rewrite removal, snapshot round-trip, corrupted-JSON degradation.
   - `test/application/game_provider_test.dart` — XP accumulation, lesson completion tracking, reset, streak/XP achievement gem unlocks.
   - `test/domain/achievement_test.dart` — level derivation and target lookup, with a regression guard asserting the cap.
   - `test/service/locator_test.dart` — pins the `SettingsProvider` manual-registration contract for the Phase 3 DI refactor.

2. Fix `Achievement.getCurrentLevel` to cap at `maxLevel` (`targets.length`), and update the consumer to `isCompleted = level >= maxLevel`. This makes the achievement card correctly show completion at the maximum level instead of an out-of-range level.

3. Document the `StreamingSharedPreferences` isolation caveat in each affected test's `setUp`: reset the relevant key explicitly after `setMockInitialValues({})` because the cached instance is not cleared.

## Consequences

- The high-risk providers are now under regression protection before the Phase 2 error-handling refactor touches `LessonViewModel._onLessonCompleted` (which calls into `GameProvider`/`MistakeProvider`).
- The `SettingsProvider` DI contract has a named guard test that must be updated when Phase 3 moves it into the Injectable graph — making that refactor's intent explicit rather than silent.
- The achievement completion bug is fixed and locked by a test.
- View-layer widget tests (e.g. `new_lesson_screen`, `settings_page`) were intentionally deferred: they require heavy platform-channel mocking (AudioPlayer, sherpa_onnx, Drift) for limited robustness return relative to the provider tests. They remain a candidate for a later pass.