# Varnamala Future Plan v2：纯净学习框架路线

> 本文档替代 `dreamplan.md` 作为后续开发的事实计划。
> 与 v1 的核心差异：
> 1. **移除**全部社交 / 排行榜 / 联赛 / 好友等交互功能。
> 2. **不再**添加任何新的课程内容（不增 vocab、不增 grammar、不增 lesson、不增 passage、不增 audio asset）。已存在的 JSON 作为唯一内容源，仅做必要的模型 / 渲染器 / 校验 / 数据通路完善。
> 3. 后续所有工作目标：**把已有框架打磨到"任意 Section / Unit / Lesson 在不写新内容的情况下都能正确渲染、复习、统计"**，而不是"做更多内容"。

---

## 1. 总目标与边界

**目标**：把 Varnamala 打造成一个**纯净、本地优先、可承载大量内容**的语言学习框架基底。当前语种以 Swahili 为主目标（vocab.json 仍是 Kannada 占位，这是已知遗留）。

**明确不做**：

- ❌ 任何形式的**新词表 / 新语法点 / 新课程 / 新阅读文 / 新听力稿**。
- ❌ 任何**云端 CMS / 后端 / 增量同步**。
- ❌ 任何**社交 / 排行榜 / 联赛 / 好友 / 私信 / 关注 / 分享奖励链**。
- ❌ 任何**League XP、Leaderboard、Friends 字段、Streak Repair（XP 计数型）、Heart refill 计时**等 Duolingo 风格的"反学习"摩擦。
- ❌ **Patreon 入口、Follow Reward、Share-to-Claim 计数**。
- ❌ **Speaking 题型**（flutter_tts 录制 + 匹配）和 **外部 GUI 编辑器**（Phase 7）。
- ❌ 任何与学习流程无关的 UI 实验（Onboarding 大段宣言页只保留最简 1 页）。

**明确要做**：

- ✅ 让模型层（`SubLesson / ListeningPhase / ReadingPassage / GrammarPoint / Expression / LessonTemplate`）**真正端到端可用**，而不是"有枚举无内容"。
- ✅ 让 4 种 Lesson Template（`intro / practice / review / mastery`）的渲染 / 进度 / 复习链路**有真实 lesson 验证**。
- ✅ Expression 实体的**数据通路**（vocab → SRS → 复习 UI）打通。
- ✅ 离线音频策略**实际生效**（即便只有一个测试音频，路径要通）。
- ✅ Mastery 80% 通过率 / 无限重试**真正判定**。
- ✅ Heats / League / Friends / 排行榜相关代码**清理下架**。
- ✅ 测试覆盖核心 ViewModel / Provider / Renderer 分发。
- ✅ TL 语言码切到 `sw`（或保留 `kn` 但显式标注，不混合）。

---

## 2. 当前资产盘点（保留）

| 模块 | 状态 | 关键文件 |
|---|---|---|
| 课程模型 | ✅ 已扩展 | `domain/course/{section,unit,lesson,stage,interaction,sub_lesson,listening_phase,reading_passage,expression,grammar_point,lesson_word_link,lesson_content,srs_word,mistake_entry}.dart` |
| Interaction 题型 | ✅ 11 种 | ShowWord / MultipleChoice / FillBlank / TranslateSentence / ListenAndPick / TypeTheWord / ListenOnly / ReorderSentence / ReadingMcq / ReadingTrueFalse / ReadingShortAnswer |
| Lesson Template 枚举 | ✅ 6 种 | legacy / intro / practice / listening / reading / review / mastery（**注意：当前 JSON 仅 legacy + listening 有真实 lesson**） |
| 课程加载 | ✅ 完成 | per-section JSON + index + drift SQLite（schemaVersion 4）+ per-section 懒加载 + `loadLessonById` + content-version reseed |
| SRS 引擎 | ✅ 完成 | `application/srs_provider.dart` + `core/sm2.dart` + 闪卡 UI + 首次出现追踪（`LessonLinkStore` 单写者） |
| 语法复习 | ✅ 完成 | `GrammarReviewProvider` + `GrammarReviewPage` + `practiceItems` 复用 InteractionRenderer + 错题 → 语法跨路由 |
| 错题本 | ✅ 完成 | 30 条 FIFO + `interactionSnapshot` + `grammarPointId` 跨路由 + `MistakePracticePage` 重做 + `rewriteCount >= 2` 自动移除 |
| TTS 控制器 | ✅ 完成 | `AudioController` 统一 TTS + 离线音频 + 语速（0.8/1.0/1.2） + 按 `TargetLanguage.ttsLanguageCode` 切码 |
| 主题 / 暗色模式 | ✅ 完成 | `VarnamalaTheme` 语义化颜色 + `ThemeProvider` 持久化 |
| 学习统计 | ✅ 完成 | `StudyLog` + `StudyLogRepository`（90 天日志） + `StudyStatsProvider` + Profile 仪表盘 |
| 课程树 / Section 切换 | ✅ 完成 | `CourseProvider` 懒加载 + `SectionSwitcher` + `UnitCard` 折叠 |
| Render 插件机制 | ✅ 完成 | `@injectable` + GetIt `Set<InteractionRenderer>` + sealed-switch 分发 + `autoAdvance` 旗位 |
| DI / 路由 | ✅ 完成 | GetIt + Injectable + AutoRoute（9 个 route） |

---

## 3. **移除清单**（删除 / 简化 / 标记弃用）

> 下列功能**不直接服务于"单人离线学习"**，全部下架。代码可保留但 UI 入口不暴露，或直接删除以减小攻击面。

### 3.1 League（联赛 / 天梯）

- `GameProvider.bronzeLeague` 常量、`leagueXp` 字段、Profile 页 "Current League" 卡片。
- `Achievement` 颜色档位（amethyst/pearl/ruby/emerald/diamond/...）中带 `league*` 命名的占位。
- 后续不再有"晋级/降级/周奖励"的任何代码路径。

### 3.2 Friends / Leaderboard / 社交

- 任何读取 `friendsCount` / 拉取其他用户 score / 显示 top 30 的代码。
- `achievements.friendly`（"Track shared progress"）条目直接删除。
- `assets/icons/facebook-icon.png`、`google-icon.png` 若无 OAuth 流程则删除。

### 3.3 Hearts（生命 / 红心）

- `HeartsProvider` 不在 `LessonViewModel` 中被消费，目前是"半成品"——直接**删除**或仅保留为"统计今日已开课次数"的轻量本地计数器（不阻塞、不 refill、不消耗 gems）。
- `assets/images/heart*.png` 相关 UI 全部移除；`HeartsDisplay` widget 删除。

### 3.4 XP 乘数 / 每日目标 / Streak Repair（XP 计数型）

- `XPEvent.dailyGoalComplete` / `streakBonus` / `challengeWin` 三类事件**不再发放**。保留 `lessonComplete` / `perfectLesson` / `srsReviewSession` / `grammarReviewSession` 作为唯一的 XP 来源。
- `LocalStateKeys.dailyXpGoal` / `dailyXpEarned` / `lastDailyReset` / `streakRepairRequired` / `streakRepairProgress` / `streakRepairTarget` / `streakBeforeBreak` 字段全部删除（保留 `streak` 字段作为连续学习天数展示，不与"修复"挂钩）。
- Shop 页 "Streak Repair" 卡片删除。

### 3.5 Gems 货币（仅保留"奖励"语义，去掉"购买"语义）

- `GemsProvider` 保留（仍是 SRS / 语法复习的奖励），但**Shop 页不再卖东西**：
  - 删除 Streak Freeze、Wager Weekend Amulet、Outfits、Power-ups 等所有"宝石购买"卡片。
  - 删除 Refill Hearts（已在 3.3 处理）、Gems Refill 等。
  - 保留 "Try Match Madness" 入口（这是导航，不是购买）。
- `localStateKeys.streakFreezes` / `streakFreezeActive` / `streakWasBroken` 删除（与 3.4 合并处理）。

### 3.6 Patreon / Follow Reward / Share Reward

- `PatreonButton` widget + `url_launcher` 跳转入口删除。
- `localStateKeys.followRewardClaimed` / `validatedShareCount` / `claimedShareCount` 删除。
- Shop 页 "Community Rewards" 区域删除。

### 3.7 现有 Shop 页改写

Shop 路由保留（不删），但页面内容**仅保留**：
- 学习统计简表（来自 `StudyStatsProvider`，非社交）。
- "Try Match Madness" 入口（保留已有）。
其他全部删除。如果最终空荡，**直接把 Shop tab 砍掉**，`HomePage.screens` 简化为 3 tab：Learn / Play / Profile。

### 3.8 Onboarding 简化

- 现有 3 页宣言式 Onboarding（"Reclaiming Language Learning" 等）压缩为**最多 1 页**（"Tap to start"），或直接删除让用户进入 `HomeRoute`。

### 3.9 Firebase 残留

- `SerializableFirebaseUser` 类保留（仅作本地用户壳），`firebase_*` 任何真实集成均已无。
- `authUser` Preference 保留以便后续扩展，本期不动。
- `pubspec.yaml` 早已无 firebase 包，保持。

---

## 4. 保留清单（核心学习闭环）

下面这些是**单人离线学习的真正必要功能**，本期及后续全部保留并打磨：

1. **Section / Unit / Lesson 树形浏览**（`CourseProvider` 懒加载 + `CourseTree`）。
2. **课程模板与渲染**（11 种 Interaction + 6 种 Lesson Template + ReadingPassage + ListeningPhase + SubLesson + Stage 五层结构）。
3. **课程数据通路**（per-section JSON → seeder → drift SQLite → `CourseRepository` → runtime domain model）。
4. **SRS 单词复习**（SM-2 + 闪卡 UI + 首次出现追踪 + 语速切换）。
5. **语法复习**（独立 SRS 队列 + Explain / Practice / Rate + 错题跨路由）。
6. **错题本**（30 条 FIFO + 快照重做 + 跨路由到语法）。
7. **TTS 朗读**（按 TL 切语言码 + 0.8/1.0/1.2 语速 + 离线音频 fallback 接口）。
8. **学习统计**（今日 / 7 日 / 总体 XP / 时长 / 准确率 / 课数 / 复习数）。
9. **个人进度**（lesson 完成 / 完美完成、`completedLessonIds` / `perfectLessonIds` 集合，**不与社交挂钩**）。
10. **个人里程碑**（`AchievementsProvider`：Scholar / Sage / Wildfire / Champion / Sharpshooter / Winner，**全是个人计数**，不显示好友进度）。
11. **Match Madness 小游戏**（已有的 match-words，保留作为 Play hub 入口）。
12. **字母 / 字符学习**（`CharacterDrawing` 屏，保留为可选入口，不强制）。
13. **暗色模式 / 主题**（已完成，保留）。
14. **本地用户**（一个匿名 `LocalUser`，不登录、不上传、不同步）。

---

## 5. 后续工作计划（**不包含任何新内容**）

> **重要前置**：本计划任何一条**都不要求**新增词汇、语法、阅读文、听力稿、音频、图标、文案（除少量必要的占位字符串）。

### Phase 7：去社交化清理（清理已有代码，预计 1–2 周）

1. 删除 3.1–3.6 涉及的字段、Provider 方法、UI 卡片、按钮、路由入口。
2. Shop 页按 3.7 改写或下线。
3. Onboarding 按 3.8 简化。
4. 更新 `LocalStateKeys`、移除孤儿字段、跑一遍 `flutter test` 确认未破坏 SRS / 错题 / 复习流程。
5. 更新 `CLAUDE.md` Features 表格：标记 League / Friends / Leaderboard / Hearts / Streak Repair / Patreon / Share Reward 为 ❌ Removed。

### Phase 8：4 种 Lesson Template 真实可用（预计 2–3 周）

> **不写新 lesson**，只验证既有 JSON 的扩展点能正确渲染。

1. 写一个**最小**的 `s-template-smoke.json`（或在 `s-test.json` 内追加），覆盖：
   - 1 个 `template: intro` 的 lesson（4 个 SubLesson，每 SubLesson 1 个 ShowWord + 1 个 MCQ）。
   - 1 个 `template: practice` 的 lesson（4 个 SubLesson，难度更高）。
   - 1 个 `template: review` 的 lesson（3 个 SubLesson，混合 ShowWord / MCQ / FillBlank）。
   - 1 个 `template: mastery` 的 lesson（1 个 SubLesson，多题型 + 80% 阈值 + 无限重试）。
   - 1 个 `template: reading` 的 lesson（用 `readingPassage` 结构体而非旧 `passage` 字符串）。
2. 实现 Mastery 80% 通过率判定：
   - 在 `LessonViewModel` 中新增 `isMastery` 判断 + `passed` 状态 + `attempts` 计数。
   - 未通过时不进入 `isComplete`，弹出 "Try again" 入口（沿用 `MistakePracticePage` 模式）。
3. 验证 `Lesson.flattenedStages` 对 5 种 template 的 flatten 行为（intro / practice / review / mastery / reading），**不写新 lesson 跑通即可**。
4. 跑测试 + 手工 UI 走查。

### Phase 9：Expression 实体端到端贯通（预计 1–2 周）

> **不新增 Expression 词条**，仅打通通路。

1. 在 `SwahiliCourse` loader / `CourseRepository` 中加 `expressions` 表 / 字段（schemaVersion 5）。
2. `SrsProvider` 增加 `registerExpression` / `reviewExpression` / `getDueExpressions` 接口，复用 SM-2 引擎。
3. `SrsReviewPage` 改为支持 word / expression 双类型卡片。
4. `LessonViewModel._registerSrsWords` 同时注册 `ShowWord` 里的 `expressionId`（如有）。
5. `LessonLinkStore` 的 `LinkType.expression` 已存在，确认 `MistakeEntry.expressionId` 字段已落库。
6. 跑通：现有 s-foundations 里如果出现 `expressionId` 字段（目前没有），即可测试；**否则只做通路，留待真实 Expression 词条出现时立刻可用**。

### Phase 10：TL 语言码与离线音频策略（预计 1 周）

> **不新增任何音频文件**。

1. `LanguageProvider.ttsLanguageCode` 决定返回 `sw` 还是 `kn`：
   - **方案 A**：切到 `sw`，接受 Kannada 词被 TTS 错误朗读（短期可接受，因为 TTS 对未知词会拼读字母）。
   - **方案 B**：保留 `kn`，在 `assets/courses/swahili/vocab.json` 头部加 `language: "kn"` 的注释，并写明 "TTS 用 kn 直到 Swahili 词表上线"。
   - 选定后**二选一**，**禁止混用**。
2. 离线音频策略接口（`AudioController.speakWord`）已存在，**只验证**：
   - 当 `WordEntry.audioAsset` 为空时回退到 TTS。
   - 当 `WordEntry.audioAsset` 非空时播放离线音频。
   - 至少 1 个 example 验证通过。
3. **不**生成任何新音频。

### Phase 11：测试覆盖与构建稳定性（预计 1–2 周）

1. `LessonViewModel` 流程测试：加载 → 答题 → 错题记录 → 完成 → XP 发放 → 统计记录。
2. Renderer 端到端测试（golden 测或 widget 测）：每个 Renderer 至少 1 个 happy-path。
3. `Lesson.flattenedStages` 5 种 template 的单元测。
4. `CourseRepository` + seeder 的 round-trip 测（写入 JSON → seed → 读出 domain model → JSON 序列化回原文）。
5. `drift` schema 迁移测：v1→v4 顺序升级。

### Phase 12：文档与代码卫生（持续）

1. 更新 `CLAUDE.md`：
   - 删除"🔴 Features Needed (Firebase-Based)"整节或大段缩减。
   - 标记"Removed" / "Will Not Do" 项。
2. `dreamplan.md` 标注 "Superseded by future2.md"。
3. 删除 / 归档 `IMPLEMENTATION.md` / `NEXT_VERSION.md` 中已被 future2 覆盖的条目。
4. 清理 `git status` 中 `D assets/screens/*.jpg`、`M assets/course_data.json` 等遗留未提交改动。
5. `lib/courses/languages/kannada*.dart` 文件若决定永远不切到真实 Swahili 词表，**保留**但加注释 "Historical placeholder"；如要切，**单独开一个分支**做内容替换（**不**在本计划范围）。

---

## 6. 施工阶段（Step-by-step）

> **阅读对象**：开发者 / Agent。下面的步骤按依赖顺序排列，**前一步未完成不要跳到下一步**。每一步都给出 ① 动作 ② 涉及文件 ③ 验证 / 交付物。**严禁在执行步骤的过程中添加新词汇、新语法、新 lesson、新音频**。
>
> **每步完成后必须 `git commit`**，commit message 格式：`[phase-N step-M] <一句话说明>`，便于回滚。

### Step 0：施工前准备（半天）

- **0.1** 备份当前 `pubspec.lock` 与 `lib/` 整体（tag：`pre-future2-v0`）。
  - 验证：`git tag` 存在。
- **0.2** 在 `lib/core/logger.dart` 或新建 `lib/core/deprecation.dart`，加一个 `DeprecatedFlag` 静态类，初始为空。
  - 验证：编译通过。
- **0.3** 跑一次 `flutter test` 全量，记录当前通过 / 失败用例数。
  - 验证：基线数字写入 `test/BASELINE.md`。
- **0.4** 跑一次 `flutter build apk --debug`（或 `web`），确保当前可构建。
  - 验证：构建产物存在。

---

### Phase 7 施工步骤（去社交化清理，预计 1–2 周）

#### ✅ Step 1：删除 League 残留（半天）

- **1.1** 删除 `lib/application/game_provider.dart` 中：
  - `static const String bronzeLeague` 常量。
  - `leagueXp` 字段在 `LocalStateKeys`、`_readState`、所有 `awardXP` 分支里的读写。
  - `_unlockXpAchievements` / `_unlockStreakAchievements` 中与 league 相关的判断。
  - 涉及文件：`lib/application/game_provider.dart`、`lib/service/locator.dart`（`LocalStateKeys.leagueXp`）。
  - 验证：`grep -rn "leagueXp\|bronzeLeague" lib/` 返回 0 行。
- **1.2** 删除 `lib/views/profile/widgets/statistics.dart` 中的 `_StatCard(...label: 'Current League')` 卡片。
  - 验证：Profile 页 4 卡变 3 卡。
- **1.3** `Assets.images.badge_*` League 徽章资源如有引用，**保留**但 UI 不展示。
  - 验证：`grep -rn "badge_amethyst\|badge_ruby\|badge_emerald" lib/` 仅在 `theme.dart` 颜色定义中存在。
- **1.4** `flutter test` 跑 SRS / 错题 / 复习 / 统计四套 → 全绿。
  - 验证：基线用例数 ±0。

#### ✅ Step 2：删除 Friends / Leaderboard / 社交（半天）

- **2.1** `grep -rn "friendsCount\|leaderboard\|Leaderboard" lib/` 列出所有引用。
- **2.2** 删除 `lib/application/achievements_provider.dart` 中的 `Achievement(id: 'friendly', ...)` 整条。
- **2.3** 删除 `lib/views/profile/widgets/`、`lib/views/shop/`、`lib/views/home/` 中任何 `friendsCount` / "Top 30" 类的引用。
- **2.4** 删除 `lib/service/locator.dart` 中 `LocalStateKeys.friendsCount`。
- **2.5** 确认 `lib/application/achievements_provider.dart::checkLeagueAchievement` 是 no-op，**直接删除**整个方法。
  - 验证：grep 返回 0 行涉及 friends / leaderboard。

#### ✅ Step 3：删除 Hearts 整条线（半天）

- **3.1** 删除 `lib/application/hearts_provider.dart` 整个文件。
- **3.2** 删除 `lib/views/widgets/hearts_display.dart` 整个文件。
- **3.3** 从 `lib/application/providers.dart` 移除 `HeartsProvider` 注册。
- **3.4** 从 `lib/views/home/home_page.dart::initSession` 移除 `heartsProvider.refillHeart()` 调用。
- **3.5** 从 `lib/di/injection.config.dart` 移除（由 build_runner 重生）。
- **3.6** `LocalStateKeys.hearts` / `heartsRefillAt` 字段**保留**（以防数据迁移），但 Provider 已无消费者。
  - 验证：`grep -rn "HeartsProvider\|heartsProvider" lib/` 返回 0 行。

#### ✅ Step 4：删除 XP 乘数 / Streak Repair（半天）

- **4.1** `lib/application/game_provider.dart` 中删除：
  - `LocalStateKeys.dailyXpGoal` / `dailyXpEarned` / `lastDailyReset` 的读写。
  - `LocalStateKeys.streakRepairRequired` / `streakRepairProgress` / `streakRepairTarget` / `streakBeforeBreak` / `streakWasBroken` 的读写。
  - `XPEvent.dailyGoalComplete` / `streakBonus` 枚举值。
  - `_checkStreakOnAppOpen` / `awardXP` 中相关分支。
- **4.2** 保留：`streak` 字段（连续学习天数显示）、`XPEvent.lessonComplete` / `perfectLesson` / `srsReviewSession` / `grammarReviewSession`。
- **4.3** `lib/views/shop/shop_screen.dart` 删除 "Streak Repair" 卡片（`_SectionTitle(title: 'Learn To Repair')` 整段）。
  - 验证：`grep -rn "streakRepair\|dailyGoalComplete" lib/` 返回 0 行。

#### ✅ Step 5：清理 Gems 购买语义（半天）

- **5.1** 保留 `GemsProvider` 的 `earnGems`（SRS / 语法奖励来源）。
- **5.2** `lib/views/shop/shop_screen.dart` 删除：
  - Streak Freeze 卡片（如有）。
  - Outfits / Power-ups 卡片（如有）。
  - Weekend Amulet 卡片（如有）。
  - Refill Hearts 卡片（已随 Step 3 失效，确认 UI 没了）。
- **5.3** 删除 `LocalStateKeys.streakFreezes` / `streakFreezeActive` 字段。
- **5.4** Shop 页只保留："Try Match Madness" 按钮（`MatchWordsRoute`） + 学习统计简表（如决定保留 Shop 入口）。
  - 验证：Shop 页面只有 ≤2 张卡片。

#### ✅ Step 6：清理 Patreon / Follow / Share（半天）

- **6.1** 删除 `lib/views/widgets/patreon_button.dart` 整个文件。
- **6.2** `lib/views/home/components/stat_app_bar.dart` 移除 `PatreonButton` 引用。
- **6.3** `lib/views/shop/shop_screen.dart` 删除 "Community Rewards" 整段。
- **6.4** 删除 `LocalStateKeys.followRewardClaimed` / `validatedShareCount` / `claimedShareCount`。
- **6.5** `lib/views/home/home_page.dart` 移除任何 `url_launcher` 调用。
- **6.6** 评估 `lib/views/profile/widgets/account_app_bar.dart` 中的分享按钮（若有），删除。
  - 验证：`grep -rn "url_launcher\|PatreonButton\|followReward\|validatedShare" lib/` 返回 0 行。

#### ✅ Step 7：Shop 路由去留决定（半天）

- **7.1** 若 Shop 页 ≤1 张卡片有意义 → **下线 Shop tab**：
  - `lib/views/home/home_page.dart` 移除 `const ShopPage()`，screens 数组长度变 3。
  - `BottomNavigator` 移除 Shop 项，currentIndex 取值范围变 0–2。
  - `lib/routing/routing.dart` 删除 `ShopRoute`（如有独立路由）。
  - `lib/views/shop/` 整个目录删除。
- **7.2** 若保留 Shop（用于 Match Madness 入口）→ 保留路由与 tab，但页面只剩 1 个按钮。
- **7.3** 选定后只走 7.1 或 7.2 其中一条。
  - 验证：Bottom tab 数量 = 3（Learn / Play / Profile）或 4（…/ Shop 仅剩 Match Madness 按钮）。

#### ✅ Step 8：Onboarding 简化（半天）

- **8.1** `lib/views/onboarding/onboarding_screen.dart` 简化为单页："Tap to start" + 跳 Home。
  - 保留 1 个 `PageController`、1 页 `_OnboardingPageData`、1 个 `GetStartedButton`。
  - 删除其他 2 页（"Real Communication"、"Cooperative Mission"）。
- **8.2** 不动 Splash 页。
  - 验证：Onboarding 仅 1 页可滑动 / 跳过。

#### ✅ Step 9：CLAUDE.md 同步（半天）

- **9.1** `CLAUDE.md` 的 "🔴 Features Needed (Firebase-Based)" 整节删除或改为 "Removed by future2.md"。
- **9.2** Features 表格中将 League / Friends / Leaderboard / Hearts / Streak Repair / Patreon / Share Reward / Speaking 标 ❌ Removed / Will Not Do。
- **9.3** 在 `CLAUDE.md` 顶部加一行：> 后续开发以 [`future2.md`](./future2.md) 为准。
  - 验证：`grep -n "future2.md" CLAUDE.md` 有 1 行。

#### ✅ Step 10：Phase 7 收尾验证（半天）

- **10.1** `flutter test` 全量。
  - 验证：与 Step 0.3 基线数字偏差 ≤ 5 个（允许因 Provider 删除连带调整测试）。
- **10.2** `flutter analyze` 0 error。
- **10.3** `flutter build apk --debug` 成功。
- **10.4** 手工走一遍：开 App → Learn → 进 lesson → 完成 → 看 Profile 统计。
  - 验证：无 League / Friends / Hearts / Shop 道具 / Patreon / Streak Repair 任何 UI 痕迹。
- **10.5** `git commit`：`[phase-7] social/gamification cleanup done`。

---

### Phase 8 施工步骤（4 种 Lesson Template 真实可用，预计 2–3 周）

> **绝对不写新 lesson**。仅在 `s-test.json` **追加** 5 个最小 smoke lesson（或新建 `s-template-smoke.json`），不替代既有 lesson。

#### ✅ Step 11：设计 smoke lesson 清单（半天）

- **11.1** 在纸上（或本文件注释里）列出 5 个 smoke lesson 的 `id / template / subLessons / 题型组合`：
  - `l-tpl-intro-smoke`：`template: intro`，4 个 SubLesson，每 SubLesson 1 ShowWord + 1 MCQ。
  - `l-tpl-practice-smoke`：`template: practice`，4 个 SubLesson，MCQ + FillBlank。
  - `l-tpl-review-smoke`：`template: review`，3 个 SubLesson，ShowWord + MCQ + FillBlank 混合。
  - `l-tpl-mastery-smoke`：`template: mastery`，1 个 SubLesson，4 MCQ（用于 80% 阈值测试）。
  - `l-tpl-reading-smoke`：`template: reading`，`readingPassage: ReadingPassage(...)` + 1 ReadingMcq + 1 ReadingTrueFalse。
- **11.2** 复用 `s-test.json` 已有的 35 个 vocab id，不引入新 wordId。
  - 验证：smoke lesson 引用的 `wordId` 全部在 `vocab.json` 中存在（用 grep 确认）。

#### ✅ Step 12：写入 smoke lesson JSON（半天）

- **12.1** 编辑 `assets/courses/swahili/sections/s-test.json` 追加 5 个 lesson（用现有 unit `u-test-1` 或新增 `u-test-templates`）。
- **12.2** `content` 字段严格遵循 `LessonContent` freezed 形状：`subLessons` / `readingPassage` / `linkedGrammarPointIds`。
- **12.3** 跑 `validateSection(s-test.json, vocabIds)` 离线校验（已有 `course_validator.dart`）。
  - 验证：5 个 lesson 全部通过校验。
- **12.4** 在 `assets/courses/swahili/sections/index.json` 中 `version` 字段 +1（**只是版本号变更**，不增 section）。
  - 验证：`index.json` 中 sections 数量不变，version 从 2 升到 3。

#### ✅ Step 13：Mastery 80% 判定实现（1–2 天）

- **13.1** `lib/domain/course/lesson.dart` 中 `Lesson` 加一个派生 `bool get isMastery => template == LessonTemplate.mastery;`。
- **13.2** `lib/application/lesson_viewmodel.dart`：
  - 新增字段 `int _masteryAttempts = 0;`、`bool _masteryPassed = false;`、`int _correctCount = 0;`（如果还没有）。
  - 每次 `_onLessonCompleted` 触发时（**仅当 `lesson.isMastery`**）：
    - 计算通过率 = `_correctCount / _totalItemCount`。
    - `>= 0.8` → `_masteryPassed = true`，照常完成。
    - `< 0.8` → `_masteryPassed = false`，**不**进入 `_isComplete`，弹"Try again"对话框。
  - 新增 `void retryMastery()` 重置进度但保留 `_masteryAttempts += 1`。
  - 新增 getter `bool get isMastery => _lesson?.isMastery ?? false;`、`int get masteryAttempts => _masteryAttempts;`、`bool get masteryPassed => _masteryPassed;`。
- **13.3** `lib/views/lesson/new_lesson_screen.dart`：
  - 完成对话框：若 `vm.isMastery && !vm.masteryPassed` → 显示 "Not yet — accuracy 65% (need 80%)" + "Try Again" 按钮（调用 `vm.retryMastery()`）+ "Back" 按钮。
  - 若 `vm.masteryPassed` → 显示 "Mastery Achieved!" + 继续按钮。
- **13.4** 写 `test/application/mastery_lesson_test.dart`：
  - 场景 A：6 题对 5 题 → passed。
  - 场景 B：6 题对 4 题 → not passed，可重试，重试后对 5 题 → passed。
  - 验证：测试通过。

#### ✅ Step 14：LessonViewModel 不污染非 Mastery lesson（半天）

- **14.1** 确认 `loadLesson` 时若 `lesson.isMastery == false`，`_masteryPassed = true`（默认通过，普通 lesson 不受影响）。
- **14.2** 跑 `flutter test` 全量。
  - 验证：所有现有 lesson 行为不变。

#### ✅ Step 15：手工 UI 验证（半天）

- **15.1** `flutter run` 启动 App。
- **15.2** 打开 `l-tpl-intro-smoke` → 看到 4 个 SubLesson 标题 / 进度正确 / flatten 行为正确。
- **15.3** 打开 `l-tpl-reading-smoke` → 看到 `ReadingPassage` 标题 + 段落 + 阅读题。
- **15.4** 打开 `l-tpl-mastery-smoke` → 故意答错 ≥ 2 题 → 看到 "Try Again" 对话框 → 重试 → 答对 ≥ 5/6 → 看到 "Mastery Achieved!"。
- **15.5** `git commit`：`[phase-8] 4 lesson templates + mastery 80% done`。

---

### Phase 9 施工步骤（Expression 实体端到端贯通，预计 1–2 周）

#### ✅ Step 16：Drift schema 升级到 v5（半天）

- **16.1** `lib/data/course_database.dart`：
  - 加新表 `Expressions extends Table { id text PK; term text; translation text; pronunciation text nullable; audioAsset text nullable; tags text default '[]'; }`。
  - `@DriftDatabase(tables: [..., Expressions])` 注册。
  - `schemaVersion => 5`。
  - `onUpgrade`：`if (from < 5) await m.createTable(expressions);`。
- **16.2** 跑 `dart run build_runner build --delete-conflicting-outputs`。
  - 验证：`course_database.g.dart` 中出现 `Expressions` 类。

#### ✅ Step 17：Seeder 写 expressions 表（半天）

- **17.1** 新建 `assets/courses/swahili/expressions.json`（**空数组**或仅有 schema 示例，**不写新表达**）：
  ```json
  { "version": 1, "language": "kn", "expressions": [] }
  ```
- **17.2** `lib/courses/course_loader.dart`：
  - 加 `static const String expressionsAsset = '$baseDir/expressions.json';`。
- **17.3** `lib/data/course_database_seeder.dart`：
  - 加 `_seedExpressions()` 方法（与 `_seedGrammarPoints` 同模式）。
  - 在 `_seed({seedSections: true, seedGrammar: true, seedExpressions: true})` 注册。
- **17.4** 跑一次 seeder 验证空表写入无错。
  - 验证：DB 中 `expressions` 表存在，行数 = 0。

#### ✅ Step 18：CourseRepository 读 expressions（半天）

- **18.1** `lib/data/course_repository.dart`：
  - 加 `Future<List<Expression>> expressions()` 与 `Future<Expression?> expressionById(String id)`。
  - `SwahiliCourse` 加 `expressions` / `expressionsById` 字段。
  - `lib/courses/languages/expressions.dart`（新建）：导出 `loadSwahiliExpressions()` 与 `swahiliExpressionsById` 全局 map（与 `kannada_vocab.dart` 同模式）。
- **18.2** `lib/service/locator.dart::setupLocator` 中加 `await loadSwahiliExpressions();`。
  - 验证：编译通过，App 启动正常。

#### ✅ Step 19：SrsProvider 支持 expression（半天）

- **19.1** `lib/domain/course/srs_word.dart`：加 `enum SrsItemType { word, expression }` 与 `SrsWord` 新字段 `@Default(SrsItemType.word) SrsItemType type;`。
- **19.2** `lib/application/srs_provider.dart`：
  - 加 `registerExpression(String id)` / `reviewExpression(id, quality)` / `getDueExpressions()` 接口（与 word 完全对称，**复用 Sm2Engine**）。
  - `registerAll` 接受 `SrsItemType` 参数。
  - `state` 缓存结构不变（仍 `Map<String, SrsWord>`，靠 `type` 字段区分）。
- **19.3** 跑测试：现有 SRS 测试不应破坏。
  - 验证：基线用例数偏差 = 0。

#### ✅ Step 20：LessonViewModel 注册 expression（半天）

- **20.1** `lib/domain/course/interaction.dart`：
  - `ShowWord` 加可选字段 `String? expressionId;`（**默认 null**，与现有数据兼容）。
- **20.2** `lib/application/lesson_viewmodel.dart::_registerSrsWords`：
  - 检测 `ShowWord.expressionId`，有则 `srsProvider.registerExpression(id)`。
  - `LessonLinkStore.upsertFirstSeen(type: LinkType.expression, ...)`。
- **20.3** `lib/data/course_repository.dart` / seeder：现有 `ShowWord` JSON 都不带 `expressionId`，**不**强制字段 → 无破坏。
  - 验证：现有 s-test / s-foundations / s-daily / s-world lesson 仍能正常 load。

#### ✅ Step 21：SrsReviewPage 双类型支持（半天）

- **21.1** `lib/views/review/srs_review_screen.dart`：
  - `_FlashCard` 改为根据 `word.type` 查 `swahiliVocabById` 或 `swahiliExpressionsById`。
  - 若 expression 缺 term / translation（当前都是空），显示 wordId 占位。
- **21.2** 跑通：当前没有 expression 词条，UI 应不显示任何 expression 卡片（word 卡片照常工作）。
  - 验证：现有 SRS 复习行为不变。

#### ✅ Step 22：Phase 9 收尾验证（半天）

- **22.1** `flutter test` 全量。
- **22.2** `flutter analyze` 0 error。
- **22.3** 手工：开 lesson 含 ShowWord → 关闭 → 进 Play → Review → 闪卡仍显示。
- **22.4** `git commit`：`[phase-9] expression entity end-to-end done`。

---

### Phase 10 施工步骤（TL 语言码与离线音频，预计 1 周）

#### ✅ Step 23：选定 TL 方案（半天）

- **23.1** 在 TTS 语言码方案中二选一（**A 切 sw / B 保留 kn**），写入决策记录：
  - 文件：`lib/core/enums.dart` 或新建 `docs/decisions/0001-tts-language-code.md`。
- **23.2** **方案 A**（选 A 时执行）：
  - `lib/application/language_provider.dart::ttsLanguageCode` 返回 `'sw'`。
  - `assets/courses/swahili/vocab.json` `language` 字段改 `"sw"`。
  - `assets/courses/swahili/index.json` `language` 已是 `"sw"`，不动。
  - `lib/courses/alphabets/resource.dart` 中 `getLanguageSounds` 保持现状（**字母页与 TTS 是两条路**）。
- **23.3** **方案 B**（选 B 时执行）：
  - 保持 `'kn'`。
  - `assets/courses/swahili/vocab.json` 头部加 `"_comment": "TTS uses 'kn' until real Swahili vocabulary replaces Kannada placeholder data."`。
  - `CLAUDE.md` 与 `future2.md` 都注明"current TTS language is kn"。
- **23.4** **禁止**两个语言码同时出现在 `ttsLanguageCode` 任何分支。
  - 验证：`grep -n "case TargetLanguage" lib/application/language_provider.dart` 仅 1 个 case。

#### ✅ Step 24：离线音频 fallback 验证（半天）

- **24.1** 写 `test/application/audio_controller_fallback_test.dart`：
  - mock `WordEntry.audioAsset == null` → 走 TTS。
  - mock `WordEntry.audioAsset == 'assets/audio/swahili/test.mp3'` → 走离线（但因无文件，**只需验证走对分支**，不验证实际播放）。
- **24.2** `lib/application/audio_controller.dart` 不改逻辑，只跑通既有 `speakWord` 路径。
  - 验证：测试通过。

#### ✅ Step 25：Phase 10 收尾（半天）

- **25.1** `flutter test` + `flutter analyze`。
- **25.2** `git commit`：`[phase-10] tts language + audio fallback verified`。

---

### Phase 11 施工步骤（测试覆盖，预计 1–2 周）

#### ✅ Step 26：LessonViewModel 流程测（1 天）

- **26.1** `test/application/lesson_viewmodel_flow_test.dart`：
  - 场景 A：加载 legacy lesson → 答对 1 题 → advance → 答错 1 题 → 错题进入 `MistakeProvider` → 完成 lesson → XPEvent.lessonComplete 发放。
  - 场景 B：加载 mastery lesson → 答对 < 80% → 不 complete，`masteryPassed = false`。
  - 场景 C：加载 mastery lesson → 答对 ≥ 80% → complete，`masteryPassed = true`。
  - 场景 D：lesson.linkedGrammarPointIds 非空 → `GrammarReviewProvider` 注册成功。
- **26.2** 用 `in_memory_course_db.dart` helper 注入 mock DB。
  - 验证：测试 4 个全过。

#### ✅ Step 27：Renderer 端到端 widget 测（1–2 天）

- **27.1** 每个 Renderer 1 个 happy-path widget test：
  - `test/views/lesson/renderers/show_word_test.dart`
  - `test/views/lesson/renderers/multiple_choice_test.dart`
  - `test/views/lesson/renderers/fill_blank_test.dart`
  - `test/views/lesson/renderers/listen_and_pick_test.dart`
  - `test/views/lesson/renderers/type_the_word_test.dart`
  - `test/views/lesson/renderers/listen_only_test.dart`
  - `test/views/lesson/renderers/reorder_sentence_test.dart`
  - `test/views/lesson/renderers/translate_sentence_test.dart`
  - `test/views/lesson/renderers/reading_mcq_test.dart`
  - `test/views/lesson/renderers/reading_true_false_test.dart`
  - `test/views/lesson/renderers/reading_short_answer_test.dart`
- **27.2** 每个测试只验 3 件事：① build 不抛错 ② 点击正确答案触发 `onSubmit(true)` ③ 点击错误答案触发 `onSubmit(false)`。
  - 验证：11 个 renderer test 全过。

#### ✅ Step 28：Lesson.flattenedStages 单元测（半天）

- **28.1** `test/domain/lesson_flatten_test.dart`：
  - legacy → 直接返回 content.stages。
  - intro → 4 subLessons × N stages 展平，id 加前缀 `sub-`。
  - practice → 同 intro。
  - review → 直接返回 content.stages（template 与 legacy 行为相同）。
  - mastery → 直接返回 content.stages。
  - listening → 3 phases 展平，summary phase 合成 ListenOnly。
  - reading → content.stages（passage 单独走 UI）。
- **28.2** 验证：5 种 template 行为与 `Lesson.flattenedStages` switch 一致。

#### ✅ Step 29：Seeder round-trip 测（半天）

- **29.1** `test/courses/seeder_round_trip_test.dart`：
  - 取 `assets/courses/swahili/sections/s-test.json` 原始字符串。
  - parse → seed 进 in-memory DB → 读出 → 序列化回 JSON。
  - 比对关键字段（id / name / lessonId / contentJson 结构）一致。
- **29.2** 验证：JSON → DB → JSON 无字段丢失。

#### ✅ Step 30：drift schema 迁移测（半天）

- **30.1** `test/data/schema_migration_test.dart`：
  - 准备 v1 → v4 各阶段 schema 的 in-memory DB。
  - 从 v1 DB 启动 app，触发 `onUpgrade`，验证 v2 (grammarPoints 表) / v3 (practiceItems 列) / v4 (courseMeta 表) 顺利升级。
- **30.2** 验证：迁移无错，旧数据不丢。

#### ✅ Step 31：Phase 11 收尾（半天）

- **31.1** `flutter test --coverage` → 覆盖率报告。
  - 目标：lib/application 覆盖率 ≥ 70%，lib/views/lesson 覆盖率 ≥ 50%。
  - 验证：报告数字。
- **31.2** `git commit`：`[phase-11] test coverage milestone done`。

> **施工状态（按 git 记录）**：Phase 7–11 已全部完成（2026-07-09）。当前只剩 Phase 12 文档与代码卫生工作。

---

### Phase 12 施工步骤（文档与代码卫生，持续）

#### Step 32：CLAUDE.md 同步（1 天）

- **32.1** 删 "🔴 Features Needed (Firebase-Based)" 整节。
- **32.2** "Duolingo Features - Implementation Status" 表中：
  - 删 / 标 ❌：Leagues / Friends / Leaderboard / Hearts / Gems purchase / Patreon / Share / Speaking。
  - 标 ✅：SRS / 错题本 / 语法复习 / Lesson Template / ReadingPassage / ListeningPhase / Expression / SubLesson / SQLite / Dark mode / Stats dashboard。
- **32.3** 顶部加 "> 后续开发以 [`future2.md`](./future2.md) 为准，本文件仅作架构总览"。
  - 验证：CLAUDE.md 中无 Firebase 字样在 Features 章节。

#### Step 33：dreamplan.md 标注过期（半天）

- **33.1** `dreamplan.md` 第 1 行下方加：
  > ⚠️ **本文件已被 [`future2.md`](./future2.md) 取代**（2026-07-09）。本文保留作为历史参考，不再更新。
  - 验证：`head -3 dreamplan.md` 包含 "future2.md"。

#### Step 34：清理 git 遗留（半天）

- **34.1** `git status` 检查 `D assets/screens/*.jpg`、`M assets/course_data.json`、`M assets/courses/...` 等。
- **34.2** 决策每项：
  - `D assets/screens/*.jpg` → **提交删除**（这些图片在 `lib/` 已无引用）。
  - `M assets/course_data.json` → 若仍有引用则保留，否则删除整个文件。
  - `lib/match_words.dart` 仍在 `lib/` 根目录 → 决定保留（已有路由）还是迁移到 `lib/views/play/`。
- **34.3** `git add -p` 选择性提交。
  - 验证：`git status` 干净（除 future2.md 本身）。

#### Step 35：归档过期文档（半天）

- **35.1** `IMPLEMENTATION.md` / `NEXT_VERSION.md` / `plan.md`：
  - 若内容已被 future2 覆盖 → 移动到 `docs/archive/`。
  - 若仍有信息 → 顶部加"已部分被 future2.md 取代"横幅。
- **35.2** 创建 `docs/decisions/` 目录存放 ADR（如 Step 23 的 TTS 语言码决策）。
  - 验证：docs/ 目录结构清晰。

#### Step 36：README.md 简化（半天）

- **36.1** `README.md` 顶部加 "Roadmap: see `future2.md`"。
- **36.2** 删 Firebase 相关的快速开始指引（既然已无 Firebase）。
  - 验证：README.md 中无 cloud / firestore / firebase 启动说明。

#### Step 37：Phase 12 收尾（半天）

- **37.1** `flutter test` + `flutter analyze` + `flutter build` 三连全绿。
- **37.2** `git tag` 当前 commit 为 `future2-phase-12-done`。
- **37.3** 在 `future2.md` 顶部"文档创建日期"下方加 "Phase 7–12 施工完成日期：____"。
  - 验证：tag 存在。

---

## 7. 已确认**不做**的事（防止 scope creep）

| 项目 | 原因 |
|---|---|
| League / 天梯 / 周奖励 | 社交化、单人离线无意义 |
| Friends / 关注 / 私信 | 同上 |
| Leaderboard / Top 30 / 全球排名 | 同上 |
| Hearts（生命限制） | 妨碍学习节奏，与"开放教育"目标冲突 |
| Streak Repair（XP 计数型） | 移除社交化后失去意义，保留纯 `streak` 连续天数显示 |
| 宝石购买道具 | 单人离线无交易 |
| Patreon / Follow Reward / Share Reward | 同上 |
| Speaking 题型 | 录音 / 匹配准确率瓶颈，TTS 路线已够 |
| 外部 GUI 编辑器（Phase 7 v1） | v2 范围内**不做**；如未来需要，应基于 schema 校验自动生成，而不是手工 JSON |
| 新增任何课程内容 | 已在本文 §1 明确 |
| 云端 CMS / Firebase 内容后端 / 增量同步 | 本地优先 |
| 移动端原生 push 通知 | 单设备本地闹钟已够 |

---

## 8. 总时间表（粗估）

| Phase | 步骤 | 估计工时 | 累计 |
|---|---|---|---|
| 0 | 准备 | 0.5 天 | 0.5 d |
| 7 | Step 1–10 | 5–6 天 | ~6 d |
| 8 | Step 11–15 | 4–6 天 | ~12 d |
| 9 | Step 16–22 | 4–6 天 | ~18 d |
| 10 | Step 23–25 | 1.5–2 天 | ~20 d |
| 11 | Step 26–31 | 4–6 天 | ~26 d |
| 12 | Step 32–37 | 2–3 天 | ~29 d |

**总计约 5–6 周**（一人全职）。**全程零新增内容**。

---

## 9. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 清理 Phase 7 时误删错字段 | 跑 `flutter test` 全量；SRS / 错题 / 复习 / 统计四套测试必须全绿。 |
| Mastery 80% 判定与 `LessonViewModel.isComplete` 耦合混乱 | 拆 `isMasteryPassed` / `isComplete` 两个独立状态，UI 层根据二者分别展示。 |
| `SrsReviewPage` 同时支持 word / expression 需要新卡片布局 | 复用 `_FlashCard` 框架，仅 term / translation 来源切换；不重写 UI。 |
| TL 语言码切换影响 TTS 表现 | 选定后写 `ttsLanguageCode` 单测；TTS 不可用时回退到静默 + 显示词义。 |
| `assets/course_data.json` 遗留 | 决定保留或删除；若不再用，删之。 |
| Smoke lesson 引入"新内容"被误判 | 严格只用 `vocab.json` 已有的 35 个 wordId；用 `grep` 校验每个 wordId 在 vocab 中存在。 |
| Step 之间漏 commit | 强制每步一 commit；CI 加 commit message 格式校验（可选）。 |

---

## 10. 文档更新责任

- 本文档 (`future2.md`) 是后续开发的**唯一事实来源**。
- `dreamplan.md` 顶部加一行：> ⚠️ **本文件已被 [`future2.md`](./future2.md) 取代**，仅作历史参考。
- `CLAUDE.md` 的 Features 表格按 Phase 7 步骤同步更新。
- 任何对功能范围（增 / 删）的变更**必须**先在本文件追加条目，再写代码。

---

*文档创建日期：2026-07-09*
*Phase 7–11 施工完成日期：2026-07-09*
*替代：dreamplan.md（v1）*
*核心原则：单人 / 本地 / 纯净 / 不生产内容 / 不做社交*
