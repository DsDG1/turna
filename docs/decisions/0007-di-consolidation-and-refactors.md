# ADR 0007 — DI consolidation and small robustness refactors

> **Status**: Accepted ｜ **Date**: 2026-07-10 ｜ **Related**: Robustness roadmap Phase 3.
## 决策

1. **Move `SettingsProvider` into the Injectable graph**: annotate it `@lazySingleton`, regenerate `injection.config.dart`, and delete the manual registration in `main.dart`. Remove the now-redundant `getIt.isRegistered<SettingsProvider>()` guards in `AudioController` (constructor ttsSpeed read, `_triggerHaptic`, `_playSound`). The DI graph is now fully wired for SettingsProvider; tests that construct `AudioController` register a `SettingsProvider` explicitly.

2. **Keep the `GemsProvider` guards in `GameProvider._applyGemBonus` and `AchievementsProvider`**: these are deliberately-commented test hooks that let unit tests construct the providers without a full DI graph. Removing them would break `game_provider_test.dart` and is a real testability pattern, not the SettingsProvider-style fragility. The comment now makes the intent explicit.

3. **Move `match_words.dart` and `match_levels.dart`** from `lib/` root to `lib/views/play/` (the page belongs with the play hub, the data file is game content). Updated the `match_provider.dart` import and regenerated routes so `routing.gr.dart` points at the new path.

4. **Extract `AchievementConfig`** (`lib/core/achievement_config.dart`): a data-driven table of XP/streak milestones (id, threshold, gemReward) with a `gemsForThreshold` helper. `GameProvider._unlockXpAchievements` / `_unlockStreakAchievements` now delegate to it. **The ladder values are unchanged** — `AchievementConfig` just makes them editable in one place and directly testable (`test/core/achievement_config_test.dart` verifies the table matches the historical ladder and exercises threshold/idempotency behavior).

5. **Do NOT migrate the study/auth domain models to Freezed** (deferred from the roadmap). `DailyStudyStats` serializes its date as a custom `"YYYY-MM-DD"` key via `_dateKey`, not the ISO format Freezed's `json_serializable` would emit by default; `StudyLog` and `LocalUser` likewise have bespoke JSON shapes stored in prefs/DB. Migrating would require custom converters and risks breaking already-persisted data (the 90-day study-log retention, the persisted local user) — the opposite of the robustness goal. These classes keep hand-written serialization; the inconsistency with `domain/course/` is accepted as a deliberate trade-off. `SerializableFirebaseUser` retains its legacy name (a `typedef LocalUser` alias already exists) to avoid a wide rename touching many view/service files with no functional benefit.
### 后续阶段的补充约定

- **注入字段优先于 `getIt` 直查**：依赖已由构造函数注入时，调用点**必须**用注入字段，不得在同一类内再 `getIt<T>()`。Phase 18 修掉的实例：`AudioController._triggerHaptic` / `_playSound` → `_settingsProvider`；`MatchProvider.initializeGame` → 构造函数注入的 `AppPrefs`（原为 `getIt<AppPrefs>()`）。`GameProvider._applyGemBonus` / `AchievementsProvider` 仍保留可选的 `getIt.isRegistered` 测试钩子（见决策 2）。
- **仓库接口处于过渡态**：`ICourseRepository` / `IStudyLogRepository` 位于 `lib/domain/repositories/`，但 **DI 仍注册具体类**——不引入 `getIt.registerLazySingleton<ICourseRepository>`。调用点与 Injectable 图留在具体类型上，直到某个阶段真的需要可 mock 的接口注入。理由：避免一次零运行时收益的 getIt 类型大改。
- **`MatchProvider` 封装**：公开的可变游戏字段改为私有 + 只读 getter，UI 继续读同名；只有 provider 改状态。`secondsRemaining` 转为私有，app bar 本就监听 `countdownNotifier`。
- **`AppRouter` 注解 + 路由守卫骨架**：`AppRouter` 标 `@lazySingleton`，移除 `main.dart` 里手写的 `getIt.registerLazySingleton<AppRouter>`。`CourseReadyGuard`（`@lazySingleton`）在 `CourseProvider.isLoaded` 为 false 时跳转到 `SplashRoute`；目前只挂在 `HomeRoute` 上，好让 splash / settings 仍可达，Phase 22 的词典路由可以复用它。
- **音频内容解耦**：见 [ADR 0010](./0010-audio-content-decoupling.md)（`VocabAudioResolver`）。
- **SRS 队列基类**：见 [ADR 0013](./0013-srs-queue-base-class.md)（`SrsQueueProvider`）。
- **`GameProvider` 拆分**：见 [ADR 0015](./0015-gameprovider-split.md)。Injectable 现在接的是 `ScoreProvider` / `StreakProvider` / `LessonProgressProvider` / `GameMilestoneProvider` → `GameProvider(appPrefs, …)`；UI 仍只通过 `providers.dart` 暴露 `GameProvider`。
## 理由

Phase 0–2 之后剩下的几处低层健壮性问题：

1. `SettingsProvider` 在 `main.dart` 里手工注册（`setupLocator` 之后），没走 Injectable。正因为它在 Injectable 图之外，`AudioController` 每次访问都要用 `getIt.isRegistered<SettingsProvider>()` 兜一层——这种防御式写法本身就说明 DI 图没有接完整。
2. `lib/match_words.dart`（468 行）与 `lib/match_levels.dart` 落在 `lib/` 根目录，把页面/数据文件与应用层混在一起。
3. `GameProvider` 把成就 XP/streak 阈值与宝石奖励写成硬编码 `if` 阶梯（`score >= 1000 && achievements.add('xp_1000') gemsReward += 25; ...`），难调也难测。
4. `lib/domain/study/`、`lib/domain/auth/` 与 `lib/domain/achievement.dart` 的领域模型用**手写** `toJson`/`fromJson`，与 `lib/domain/course/` 不一致；路线图曾提议迁移。
## 影响与边界

- `AudioController` 不再防御式检查 `isRegistered<SettingsProvider>`；DI 图是唯一真源。
- `lib/` 根目录不再散落游戏文件；它们归到 `lib/views/play/`。
- 成就阈值集中成数据驱动且可测；`GameProvider` 少了约 17 行硬编码阶梯。
- 当时全部 205 个测试通过，`flutter analyze` 干净，`make ci` 全绿。
- 三个既有测试（`audio_controller_fallback_test`、`lesson_viewmodel_flow_test`、`mastery_dialog_stats_test`）在 setUp 里补注册 `SettingsProvider`——它们构造的 `AudioController` 子类不再经已删除的守卫提前解析 SettingsProvider。
- 领域模型的 Freezed 迁移被**显式推迟**并给出理由；路线图 Phase 3 的「评估迁移」就此结案为「不迁移——数据兼容风险」。
