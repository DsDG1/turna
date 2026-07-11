# ADR 0007: DI consolidation and small robustness refactors

- **Status**: Accepted
- **Date**: 2026-07-10
- **Related**: Robustness roadmap Phase 3, ADR 0005, ADR 0006

## Context

Several low-level robustness issues remained after Phases 0–2:

1. `SettingsProvider` was registered manually in `main.dart` (after `setupLocator`) instead of through Injectable. Because it sat outside the Injectable graph, `AudioController` guarded every access with `getIt.isRegistered<SettingsProvider>()` — a defensive pattern that indicates the DI graph was not fully wired.
2. `lib/match_words.dart` (468 lines) and `lib/match_levels.dart` sat at the `lib/` root instead of under a feature folder, mixing page/data files with the application layer.
3. `GameProvider` inlined achievement XP/streak thresholds and gem rewards as hardcoded `if` ladders (`score >= 1000 && achievements.add('xp_1000') gemsReward += 25; ...`), making them hard to adjust or test.
4. Domain models in `lib/domain/study/`, `lib/domain/auth/`, and `lib/domain/achievement.dart` used hand-written `toJson`/`fromJson` instead of Freezed, inconsistent with `lib/domain/course/`. The roadmap proposed migrating them.

## Decision

1. **Move `SettingsProvider` into the Injectable graph**: annotate it `@lazySingleton`, regenerate `injection.config.dart`, and delete the manual registration in `main.dart`. Remove the now-redundant `getIt.isRegistered<SettingsProvider>()` guards in `AudioController` (constructor ttsSpeed read, `_triggerHaptic`, `_playSound`). The DI graph is now fully wired for SettingsProvider; tests that construct `AudioController` register a `SettingsProvider` explicitly.

2. **Keep the `GemsProvider` guards in `GameProvider._applyGemBonus` and `AchievementsProvider`**: these are deliberately-commented test hooks that let unit tests construct the providers without a full DI graph. Removing them would break the `game_provider_test.dart` (Phase 1) and is a real testability pattern, not the SettingsProvider-style fragility. The comment now makes the intent explicit.

3. **Move `match_words.dart` and `match_levels.dart`** from `lib/` root to `lib/views/play/` (the page belongs with the play hub, the data file is game content). Updated the `match_provider.dart` import and regenerated routes so `routing.gr.dart` points at the new path.

4. **Extract `AchievementConfig`** (`lib/core/achievement_config.dart`): a data-driven table of XP/streak milestones (id, threshold, gemReward) with a `gemsForThreshold` helper. `GameProvider._unlockXpAchievements`/`_unlockStreakAchievements` now delegate to it. The ladder values are unchanged — `AchievementConfig` just makes them editable in one place and directly testable (`test/core/achievement_config_test.dart` verifies the table matches the historical ladder and exercises threshold/idempotency behavior).

5. **Do NOT migrate the study/auth domain models to Freezed** (deferred from the roadmap). `DailyStudyStats` serializes its date as a custom `"YYYY-MM-DD"` key via `_dateKey`, not the ISO format Freezed's `json_serializable` would emit by default; `StudyLog` and `LocalUser` likewise have bespoke JSON shapes stored in prefs/DB. Migrating would require custom converters and risks breaking already-persisted data (the 90-day study-log retention, the persisted local user) — the opposite of the robustness goal. These classes keep hand-written serialization; the inconsistency with `domain/course/` is accepted as a deliberate trade-off. `SerializableFirebaseUser` retains its legacy name (a `typedef LocalUser` alias already exists) to avoid a wide rename touching many view/service files with no functional benefit.

## Consequences

- `AudioController` no longer defensively checks `isRegistered<SettingsProvider>`; the DI graph is the source of truth.
- The `lib/` root no longer holds loose game files; `lib/views/play/` groups them.
- Achievement thresholds are centralized, data-driven, and tested; `GameProvider` lost ~17 lines of hardcoded ladders.
- All 205 tests pass; `flutter analyze` clean; `make ci` green.
- Three existing tests (`audio_controller_fallback_test`, `lesson_viewmodel_flow_test`, `mastery_dialog_stats_test`) were updated to register a `SettingsProvider` in their setUp, since they construct `AudioController` subclasses that now resolve SettingsProvider eagerly instead of via the removed guard.
- The domain-model Freezed migration is explicitly deferred with rationale; the roadmap's Phase 3 note "评估迁移" is now resolved as "do not migrate — data-compat risk."


## Phase 18 update (2026-07-11)

### Injected fields over `getIt` direct lookup

When a dependency is already constructor-injected, call sites **must** use the
injected field — never `getIt<T>()` again inside the same class. Phase 18 fixed:

- `AudioController._triggerHaptic` / `_playSound` → `_settingsProvider`
- `MatchProvider.initializeGame` → constructor-injected `AppPrefs` (was
  `getIt<AppPrefs>()`)

`GameProvider._applyGemBonus` / `AchievementsProvider` still keep optional
`getIt.isRegistered` test hooks (see decision #2 above).

### `MatchProvider` encapsulation

Public mutable game fields became private with read-only getters. UI continues
to read the same names; only the provider mutates state. `secondsRemaining` is
private; the app bar already listens to `countdownNotifier`.

### `AppRouter` annotation + route guard skeleton

- `AppRouter` is `@lazySingleton`; the manual
  `getIt.registerLazySingleton<AppRouter>` in `main.dart` is removed.
- `CourseReadyGuard` (`@lazySingleton`) redirects to `SplashRoute` when
  `CourseProvider.isLoaded` is false. Currently attached only to `HomeRoute`
  so splash/settings stay reachable; Phase 22 dictionary routes can reuse it.

### Audio content decoupling

See ADR 0010 (`VocabAudioResolver`).

## Phase 21 update (2026-07-11)

### Repository interfaces (transition)

- `ICourseRepository` / `IStudyLogRepository` live under `lib/domain/repositories/`.
- Concrete `CourseRepository` / `StudyLogRepository` implement them.
- **DI still registers concrete classes** — no `getIt.registerLazySingleton<ICourseRepository>`.
  Call sites and Injectable graph stay on concrete types until a later phase
  needs mockable interface injection.
- Rationale: avoid a wide getIt type churn for zero runtime benefit this phase.

### SRS queue base

See ADR 0013 (`SrsQueueProvider`).

## Phase 23 update (2026-07-11)

### GameProvider split

See ADR 0015. Injectable now wires:

`ScoreProvider` / `StreakProvider` / `LessonProgressProvider` /
`GameMilestoneProvider` → `GameProvider(appPrefs, …)`.

UI still only exposes `GameProvider` via `providers.dart`.
