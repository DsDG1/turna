# ADR 0015 — `GameProvider` 拆分（门面）

> 状态：Accepted ｜ 日期：2026-07-11 ｜ 关联：future4 Phase 23、ADR 0007
## 决策

拆成若干聚焦的 `@lazySingleton` provider，藏在一个**稳定门面**之后：

| Provider | 职责 |
|---|---|
| `ScoreProvider` | XP 分数偏好 |
| `StreakProvider` | 连胜 / 上次日期 / 打开检查；用纯函数 `resolveStreakOnPractice` |
| `LessonProgressProvider` | 已完成 / 完美课时集合 + 流 |
| `GameMilestoneProvider` | XP / 连胜解锁 id 与宝石发放（≠ UI 侧 `AchievementsProvider`） |
| `GameProvider` | 公开 API 门面；编排 `incrementScore` 与各条流 |

- 纯连胜逻辑放 `lib/core/streak_resolver.dart`。
- 调用点继续用 `GameProvider`；UI 的 MultiProvider 列表不变。
- 测试用 `GameProvider.forTesting(prefs)`。
- 流的归属：课时进度流在 `LessonProgressProvider`；聚合的 `UserGameState` / 分数 / 连胜广播仍留在门面上。
### 迁移路径

后续阶段可以把子 provider 直接注入 widget；当前不要求。
## 理由

`GameProvider`（约 428 行）同时负责分数、连胜、课时进度、里程碑解锁、宝石协同与四条广播流——难测且改动风险高。
## 影响与边界

- 门面约 200 行编排代码（仍更薄、更有结构）。
- 既有 `implements GameProvider` 的 fake 继续可用。
