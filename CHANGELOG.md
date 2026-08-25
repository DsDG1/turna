# Changelog

Varnamala Plus 的完整更新历程。本文件按时间顺序记录从最初原型到当前
版本的所有重要里程碑,面向用户与贡献者。

更简短的版本摘要 → 应用内 **设置 → 更新日志**。
更详细的工程说明 → [`docs/decisions/`](./docs/decisions/) 与 [`README.md`](./README.md)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；
本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## 0.7.2 Anki 导入与复习体验优化 (2026-08-25)

本节记录 0.7.2 候选版本内容；正式发布仍以最终验收结果为准。

### 改进

- 每个 Anki 来源会作为独立课程显示，多次导入和多牌组管理更清晰。
- “复习全部”可连续覆盖多个 Anki 来源，待复习数量、卡片顺序与实际复习保持一致。
- 课程管理页新增卡片浏览、牌组统计和旧数据迁移入口。
- 优化卡片样式、图片、音频和复杂内容的显示与播放。
- 导入、重新导入、删除和迁移支持更稳妥的中断恢复。

### 修复

- 修复课程切换、牌组定位和删除范围不准确的问题。
- 减少导入或迁移中断后出现重复数据、残留数据和不可见课程的情况。
- 提升备份恢复、存储清理和整体运行稳定性。

---

## 总体时间线

| 阶段 | 时间 | 关键变化 | 关键 commit |
| --- | --- | --- | --- |
| 0. 原型与上游 | 2024-04 → 2024-11 | 西班牙语/卡纳达语 625 词原型,接入 Firebase,加社交化 | `02cf739` … `0cb4ac8` |
| 1. 本地化分叉 | 2026-03 | dsdogs fork,UI overhaul,引入 hearts/leagues/gems | `69c6954` … `14b82ce` |
| 2. 离线优先重写 | 2026-07-07 | Firebase 下线,SQLite + SRS,改卡纳达语 | `f06849b` |
| 3. future1.0 骨架 | 2026-07-09 | Section/Unit/Lesson 层级 + 课型模板 + 表达层 SRS | `0ed58ce` … `0e1f932` |
| 4. future4 框架 | 2026-07-11 | 13 个 phase 框架收尾 | `1766454` … `7ec3371` |
| 5. 1.0.0 土耳其语 | 2026-07-12 | 目标语言改为土耳其语,AI 助手 + 教材导入 | `389f453` … `2119469` |
| 6. 1.1.0 FSRS/AI/Anki | 2026-07-30 | FSRS 连续记忆、AI 引擎重构、Anki 智能化 | `980224e` |
| 7. 维护 | 2026-07-30 → 2026-08-01 | OHOS gitlink 修复、settings 同步 | `f62a727`, `9b5a172` |
| 8. 1.2.0 伴学与内容 | 2026-08-05 | AI 伴学工具链 + 土耳其语八章内容扩充 | `8fb07d9` |
| 9. 1.3.0 Anki渲染与视觉 | 2026-08-15 | Anki 原生渲染与练习解耦 + Turna 吉祥物系统 + 系统健康监控 | （已并入 0.7 系列） |
| 10. 0.7.2 Anki 可靠性 | 2026-08-25 | 多牌组复习、浏览统计、导入与迁移恢复 | （候选版本） |

---

## 0. 原型与上游 Varnamala (2024-04 → 2024-11)

[rshrc/Varnamala](https://github.com/rshrc/Varnamala) 上游项目最初的 6 个月。
最早一次 commit `02cf739` 在 2024-04-26:"basic app to go through 625 words
in spanish and kannda"。

### 0.1 起步 (2024-04 → 2024-10)

最初的 6 个月,目标是搭一个能跑通西班牙语 / 卡纳达语 625 词的语言学习 App。

#### 初次提交
- `02cf739` basic app to go through 625 words in spanish and kannda — 首个
  可运行版本,直接读 JSON 词表清单。
- `6bae7bb` added extensions — Dart 扩展增强类型推导。
- `0b3998f` added basic animations — 基础动画框架。
- `39a3710` added basic matching game for english - kannada — 配对小游戏雏形。
- `a988234` added tts for kannada transliteration — TTS 卡纳达语转写。
- `6909d51` added some basic audio support — 通用音频接口。

#### 路由 / DI / 资产
- `f7ca83a` 引入 `get_it` 依赖注入(`f7ca83a`、`fd64d73`)。
- `3c768f5` auto_route 接管路由(`42fd3df` 跟进)。
- `a3a3058` setup streaming shared preferences。
- `a3d61d3` 加 `font_awesome_flutter`。
- `6c33c66` UI revamp + 资产重做。
- `18b5ce2` duolingo assets added — 引入 Duolingo 风格视觉资产。
- `9ae6a9e` course tree layout with dynamic json data rendering。
- `a79dc01` lesson page customized — 课程页定制。

#### 游戏化与基础架构
- `5cb288f` gameplay logic implemented — 游戏化逻辑实现。
- `c7e3afc` nullable options increased — 题型可选参数扩展。
- `c354518` more stless widgets — Stateless 化。
- `83d5ae4` fixed basic course data — 课程数据基础修复。
- `1073370` updated course data and made code better。
- `ec9757d` improved gameplay experience — 体验打磨。
- `21c1f73` Added dialog for course completion。
- `88dc9a0` extra pop added for quitting level — 退出关卡二次确认。
- `aa14966` character drawing feature added — 字符画练习。
- `208589a` character drawing 抽到 Provider。
- `1c526ff` handled no lessons screen — 空态处理。
- `f483732` Shuffle options for each question — 题目选项随机化。
- `2a739e0` implement getFormattedTime function — 时间格式化。
- `89b913d` `fd5af06` `4e91b86` add a match words page — Match Madness 配对页。
- `d5ed00a` sounds added to the match madness level — 配对页音效。
- `283c11d` tried adding support for macos — 试加 macOS 平台。
- `ad95939` clean code — 清理。
- `e8edf44` commented out fill_in_the_blanks + INSTRUCTIONS.md — 填空题暂
  关闭 + 文档。
- `753659b` `7d7637b` dart badge / Discord 徽章。
- `d665ebb` Added 2 levels to Introductions chapter。
- `b35b073` Added translation text to specific question types — 题型翻译。

#### 文档与社区
- `c5e33ed` Create CODE_OF_CONDUCT.md。
- `7ab2d31` Create CONTRIBUTING.md。
- `c4d5805` Update issue templates。
- `4a8297f` Create LICENSE (MIT)。

### 0.2 接入 Firebase (2024-11)

#### 引入 Fire 栈
- `b4a4ab2` gitignore 屏蔽 Firebase 配置文件。
- `f832f88` `ad4ae9f` `573d2d4` `b3be381` `6df4165` `e6ed76a` 引入
  Firebase Auth / Firestore / Crashlytics / Analytics + 配置文件 + 配置指南。
- `6b5261b` `54aaf51` `a498542` Supported FirebaseUser serialization +
  analytics。
- `4885d7a` `5bc2692` `8c86292` AccountWidget + ShopPage 接入 Firebase 登出。
- `e7e586c` Splash 检查登录状态自动跳 HomeRoute。
- `4bdd47c` Loader widget。
- `8562cb4` `b3286b9` 用户文档初始化 + 分数自增。
- `e2553b0` `24a8be3` Firestore 集成 streak + score。
- `b197b87` 课程适配用户动态名称。
- `5884b60` Profile 组件重命名 + 重组。
- `5a5e5ac` gitignore 屏蔽 firebase_options.dart / node_modules / serviceAccountKey。

#### 社交化
- `e24137f` `b4bd541` emergency firebase store migration script in js —
  Node.js 端迁移脚本(Firestore 处理用户)。
- `c1e9e02` `722d8bc` 课程内容读用户数据 + 强制清理用户数据本地缓存关闭。
- `03fab03` streak maintenance feature added — 连击维护。
- `3d1668c` _initializeUserDocument 处理 name + profileImage。
- `bf6a20d` `2f6d61a` 加好友 + 好友推荐。
- `e3deda7` 排行榜 XP 排序。
- `6ef2076` `054f7d2` LeaderboardPage 改为常量 + AppBar 修复。
- `e3e2ae4` follow button — 关注按钮。
- `45fd83d` 统计数据动态化。
- `a89a989` `d46373b` `f3f61be` 导出 + 清理 + 插件升级。
- `af12a71` 截图更新。
- `87aed2a` Merge PR #17 user-socialization。

### 0.3 多语言框架 (2024-11)

- `e72ce23` Add TargetLanguage enum + barrel files + 课程数据加载。
- `753262b` 新依赖 `countup` + `flutter_svg`。
- `127ccbd` `376ef19` `eda89a8` `4bac910` `86cd372` CourseProvider +
  GameProvider + LanguageProvider + LessonProvider。
- `ab6eb3c` `b8462ae` `b43dcf6` Language → TargetLanguage 统一 + Kannada /
  Malayalam / Tamil / Telugu 元音辅音映射。
- `d411ddb` Malayalam 课程结构化数据。
- `e83aa40` Tamil + Telugu 课程结构化数据。
- `825ab55` 用户进度跟踪。
- `b16f361` 当前语言偏好持久化。
- `ec95d23` `535c56e` `a36d5fc` CharactersAppBar + 动态语言切换 +
  Kannada / Tamil / Telugu / Malayalam 语言选择。
- `7c72ef9` 移除 ChooseLanguageAppbar 的 StageProgressBar。
- `ee00dff` ContinueButton ChicletAnimatedButton 集成。
- `1802cb1` CourseTree 改走 Provider。
- `777aab6` HomePage 初始化语言设置。
- `afae392` LessonAppBar 退出时重置状态。
- `9f36d79` ListLesson 高度公式简化。
- `674673a` `5dcad83` `b15ab6b` `a0f92e9` `364449d` `17cb8bb` MatchProvider
  抽取 + 状态管理重构。
- `300d679` 多语言支持 + Firestore 缓存。
- `7f57e47` 字符画平滑(笔触点未清)。
- `31cbc25` 字符画与学习页 + Font Awesome。
- `2cef9a9` 字典支持(词条很少)。
- `b30f3ae` Merge PR #27 multilang-support。
- `d6edd7f` 把 `Words625` 改名 **Varnamala**。
- `e7f9887` 修复 base_href。
- `391d593` 修复 Google 登录抖动。
- `79e1f6f` 移除 Duolingo 吉祥物 + 配色更新 + 吉祥物更新。
- `15b9ffa` 图标和 favicon 翻新。
- `13cf431` `appGreen` → `primaryColor` 命名统一。

### 0.4 缺失/待删(预告 2026-07)

这一阶段加入的社交化、付费、Firebase 同步功能在 2026-07-09 (commit
`e060c11`) 一次性全部删除,详见 §2。

---

## 1. 本地化分叉 (2026-03)

2026-03-04 上游仓库存活近 17 个月后,本分叉(dSDogs)导入,创建 `CLAUDE.md`
宣告"再次开发"。

### 改造

- `69c6954` Create CLAUDE.md。
- `1aea3cf` project update。
- `2b4f611` major nonsensical updates — 大型非语义化更新(UI 改版)。
- `804300b` `46928dc` major UI overhaul — 两次 UI 大改版。
- `7b36923` more Game enhancements。
- `720a9eb` more gamification — 更多游戏化。
- `e55626f` achievement section implementation — 成就章节。
- `d3b4796` onboarding 屏幕 + 调试导航 + hearts 提示 + UI 组件细化。
- `50f0dab` more fixes。
- `1490f4a` import fixes。
- `8c1a810` leaderboard fixes。
- `a24b3b9` `14b82ce` `32a1e33` README 大改版。
- `ffd5fe9` linux stuff — Linux 桌面构建支持。

### 引入后又被删除(2026-07-09 `e060c11`)

| 功能 | 原因 |
| --- | --- |
| Google 登录 | 改为本地用户,无后端 |
| 排行榜 / 段位 | 无社交化 |
| 商店 / 冻结 / 道具 | 无付费 |
| XP boost / 每日目标 | 与间隔重复逻辑冲突 |
| 连续冻结 / 周末护符 / 连击修复 | 引导用户持续学习,不应"修复" |
| 心数 / 生命 | 移除学习摩擦 |
| 钻石购买 / 道具 | 无付费 |
| 好友系统 / 社交成就 | 无社交化 |
| 推送通知 | 无后端 |
| 口语题 | TTS 已足够 |
| 外部 GUI 编辑器 | 改回 JSON-first |

---

## 2. 离线优先重写 (2026-07-07)

`f06849b` — Refactor to offline-first Kannada learning with SRS。
这是整个本地优先路线的真正起点。Firebase 全部下线,改为 SQLite + Provider。

### 2.1 数据迁移

- 移除 Firebase Auth / Firestore / Cloud Functions / Firebase 配置文件。
- `firebase_user` 域模型改为 `local_user` 本地用户模型。
- 移除 League provider + 排行榜,改为本地成就。
- 移除 Facebook / 社交登录(只保留核心课程流)。
- 移除多语言字母表,聚焦 **卡纳达语**作为主课程。
- 移除 Node.js 依赖(`package.json` / `package-lock.json`)。
- 更新 Android / iOS 构建配置 + Web `index.html`。

### 2.2 SRS 引擎

- 引入 **SM-2 间隔重复**:
  - `lib/core/sm2.dart` — SM-2 核心算法。
  - `lib/application/srs_provider.dart` — Vocab SRS 队列。
- 引入 `lib/application/grammar_review_provider.dart` — 语法 SRS 队列。
- 引入 `lib/application/srs_queue_provider.dart` — 共享 SRS 队列基类。

### 2.3 课程模型重写

新域模型 `lib/domain/course/`:
- `section.dart` — Section 域模型。
- `unit.dart` — Unit 域模型。
- `lesson.dart` — Lesson 域模型 + LessonTemplate。
- `lesson_content.dart` — Lesson 内容(stages / subLessons / listeningPhases / readingPassage)。
- `stage.dart` — Stage 模型。
- `interaction.dart` — Interaction 模型(13 种交互题型)。
- `sub_lesson.dart` — 子课模型。
- `listening_phase.dart` — 听力阶段模型。
- `expression.dart` — 表达模型。
- `grammar_point.dart` — 语法点模型。
- `reading_passage.dart` — 阅读短文模型。
- `srs_word.dart` — SRS 词条模型。
- `mistake_entry.dart` — 错题记录模型。

支持题型:
- multipleChoice / translate / fillBlank / matchWords / listening /
  speaking / reading-MCQ / readingTrueFalse / readingShortAnswer。

### 2.4 内容存储

- 卡纳达语词表 `lib/courses/languages/kannada_vocab.dart`。
- 引入 `lib/di/renderer_module.dart` 渲染模块 DI。
- 新 Footer `lib/data/course_repository.dart` SQLite 课程仓库。
- `lib/data/study_log_repository.dart` 学习日志仓库。

### 2.5 错误处理

- `b49602b` refactor(errors): unify error handling with Result + global
  boundary — 统一 Result + 全局错误边界。

### 2.6 性能 / 主题

- `ed87f7a` perf+theme: dark-mode adaptive text, TTS background isolate,
  startup/smoothness — 暗色自适应文本 + TTS 后台 isolate + 启动 / 流畅度。
- `dad02dd` section 视觉 + TTS checker + 音频 / 设置打磨。
- `0a34123` perf(phase20): 收敛 `Colors.white` / 硬编码颜色到 `VarnamalaTheme`,
  清理 match_words / profile / settings about / loader / gems 颜色。

### 2.7 课程 / 章节结构

- `0ed58ce` Add Section/Unit/Lesson hierarchy with section switcher:
  - `CourseProvider` 增 `SectionData` + `switchToSection()` + section-aware
    加载。
  - `SectionSwitcher`:树顶左上角下拉芯片。
  - `UnitHeader`:分组标签 + teal 强调条。
  - `CourseTree` 重写:SectionSwitcher 置顶,Section 1 保留旧树,Section 2
    暂空占位。
- `1e9035d` Refactor: restructure lesson and course models:
  - `level_provider` 替换为 `lesson_viewmodel`。
  - 移除旧 course/course 域模型 + courses wrapper。
  - 移除旧 lesson 屏 + 组件。
  - 新 `new_lesson_screen` + 组件。
  - `course_tree` + routing 同步更新。

### 2.8 Phase 7 社交清理

- `e060c11` [phase-7] social/gamification cleanup done — 一次清掉 hearts /
  leagues / friends / 商店 / 推送等 11 项。

### 2.9 Phase 8 课型模板

- `45ca964` [phase-8] 4 lesson templates + mastery 80% done:
  - `intro` / `practice` / `listening` / `reading` 4 模板。
  - `mastery` 80% 通过线。
  - 详见 `docs/authoring/lesson-type-templates.md` 与 4 个模板 JSON
    (`templates/lesson-intro.json` / `lesson-practice.json` /
    `lesson-mastery.json`)。

### 2.10 Phase 9 表达层 SRS

- `4103535` [phase-9 step-16] drift schema v5: add Expressions table:
  - `Expressions` 表 + schema 升级 v5。
- `560297a` [phase-9 step-17] seeder: expressions table + empty JSON asset。
- `8280891` [phase-9 step-18] CourseRepository + SwahiliCourse expression
  loading。
- `5a5088d` [phase-9 step-19] SrsWord type enum + SrsProvider expression API。
- `61be45c` [phase-9 step-20] ShowWord.expressionId + LessonViewModel
  registration。
- `c1f7a97` [phase-9 step-21] SrsReviewPage dual-type flashcards。
- `6bc87fa` [phase-9 step-22] expression entity end-to-end done — 表达式
  端到端数据跑通(词汇 + 整句双类型闪卡)。

### 2.11 Phase 10 TTS 语言码

- `1ff15e5` [phase-10 step-23] tts language code: switch to sw + ADR:
  - TTS 语言码 → `sw`(斯瓦希里语)。
  - 2026-07-30 commit `2b4f611` 的 TTS 配置改为 `tr`(土耳其语)。
- `dbe9b76` [phase-10 step-24] audio controller fallback tests。
- `8d2da98` [phase-10 step-25] tts language + audio fallback verified。

### 2.12 Phase 11 测试覆盖

- `441b02b` [phase-11 step-26] lesson viewmodel flow tests。
- `4401995` [phase-11 step-27] renderer happy-path widget tests。
- `2f0989f` [phase-11 step-28] flattenedStages unit tests。
- `40c8ee0` [phase-11 step-29] seeder round-trip test。
- `fbffd9b` [phase-11 step-30] drift schema migration tests (v3→v5)。
- `0e1f932` [phase-11] test coverage milestone done。

### 2.13 文档收尾

- `85de640` [docs] future2.md: mark Phase 7-11 steps completed per git log。
- `1c541e9` [phase-12] documentation cleanup and archive:
  - 删除 `dreamplan.md` / `future1.md` 等过时路线图(本节合并)。
- `8ffbabc` [fix] await setupLocator before runApp;drop duplicate AppRouter
  registration — 启动时序修复。
- `336d7c1` [phase-12-bugfix] fix user-visible P1 bugs and cosmetic cleanups。
- `5c1641e` [phase-12-bugfix] race-free single-writer for gems / score /
  daily-stats — 单写者互斥,避免并发。
- `50264d1` [docs] README: reflect Phase 12 bug-fix tag, schema v5, current
  test count。
- `e436380` [fix] CourseProvider.load idempotent + eager-loaded at app
  startup — 课程页加载失败时不再白屏。
- `133a495` fix: 课程页加载失败时显示灰色空白(显式 section 加载状态 + 重试
  UI)。
- `e3d8f37` chore: 同步其他本地改动。
- `7e8f605` docs: 在 README 中补充课程树加载状态说明。

---

## 3. future1.0 内容骨架 (2026-07-09)

由 `[phase-7]` → `[phase-11]` 顺次铺好的骨架。

### 3.1 设置 / 音频 / 错题

- `9275194` feat(settings,audio): add SettingsProvider, AudioModule, sound/
  haptic toggles — 设置 Provider + 音频模块 + 音效 / 触感开关。
- `01f0813` feat(settings): redesign SettingsPage and add About Varnamala
  page — 设置页重设计 + 关于页。
- `5aebd9d` fix(course-tree): harden empty-state handling and defensive
  section loads — 课程树空态硬化。
- `1d07193` feat(mistakes,progress): enhance MistakeList and add lesson
  progress reset — 错题清单 + 课程进度重置。
- `d2cb058` docs: remove stale CONTRIBUTING / INSTRUCTIONS / plan and update
  test baseline — 删陈旧文档 + 同步基线。
- `f2003cf` docs: add future3.md roadmap for content production and tooling。
- `a5aa557` docs(audit): Phase 13 content inventory and migration mapping —
  内容清单 + 迁移映射。

### 3.2 内容工具

- `828e597` feat(tools): Phase 14 course content CLI — `tool/course_cli.py`。
- `a975cbe` docs(future3): mark Phase 14 complete。

### 3.3 音频策略

- `b8483eb` feat(audio): Phase 15 audio strategy and generation pipeline。
- `8bb50b0` chore(audio): remove accidentally committed test artifact。
- `6deef19` refactor(audio): finalize Phase 15 strategy — runtime TTS for
  words/expressions — 单词 / 表达式运行时 TTS。

### 3.4 CI / 错误 / DI

- `8a9e305` ci: add Flutter CI workflow and Makefile, fix discord branch —
  全 Flutter CI + Makefile。
- `0026bca` test: cover core providers;fix Achievement.getCurrentLevel
  off-by-one。
- `b49602b` refactor(errors): unify error handling with Result + global
  boundary。
- `3f75783` refactor(di): move SettingsProvider into Injectable;tidy root +
  thresholds。

### 3.5 质量波 + 品牌

- `75b762c` refactor: quality waves A–D, rebrand to varnamala, update
  future3 — 重命名 + 品牌色彩收口。
- `ed87f7a` perf+theme: dark-mode adaptive text, TTS background isolate,
  startup/smoothness。
- `dad02dd` pre-existing section-visuals, TTS checker, audio + settings
  polish。

### 3.6 离线 Swahili TTS + 性能

- `3292248` feat: upgrade offline Swahili TTS and course content。
- `27c97df` perf(build): prune espeak-ng-data to Bantu-only + R8 release
  shrink — 体积裁剪。
- `61a41bb` perf+robust: dueCount caching, startup deferral, rebuild
  scoping, decode guards。
- `c6c4cee` feat: Daily Challenge deck + future4.md roadmap — 每日挑战 +
  future4 路线图。

### 3.7 Phase 16 测试

- `112ea20` test(phase16): SM-2 / repository / link store / schema v3→v5 /
  SRS cache tests。
- `0f7cf25` docs(future4): mark Phase 16 complete and feed gaps into Phase 17。

---

## 4. future4 框架收尾 (2026-07-11)

**future4 框架归档**，一次性完成 13 个 `[phase-N]`。

### 4.1 Phase 17 — 卫生 + 守卫

- `1766454` chore(phase17): hygiene, downgrade guard, app id, content
  update prompt:
  - 卫生清理、版本降级守卫、应用 ID、内容更新提示。

### 4.2 Phase 18 — DI 整合 + 音频 / 内容解耦

`3d6d51e` refactor(phase18): DI consolidation, audio/content decoupling,
router guard:
- `AudioController` 改为注入 `SettingsProvider`,不再直接 import
  `swahili_vocab`。
- `VocabAudioResolver` 抽象多语言音频。
- `MatchProvider` 构造注入 `AppPrefs` + 字段私有化。
- `AppRouter` 注解 + `CourseReadyGuard` 骨架。
- 资产路径规范化从 renderer 移回 `AudioController`。
- `lib/domain/audio/vocab_audio_resolver.dart` + `swahili_vocab_audio_resolver.dart`。
- `lib/routing/course_ready_guard.dart`。
- ADR `0010-audio-content-decoupling.md`。

### 4.3 Phase 19 — 输入性能

`7d001b2` perf(phase19): remove input setState rebuilds, cache stats futures,
clean weak-word source:
- 输入渲染器改用 `ValueListenableBuilder`,避免每次按键 setState 重建。
- `LearningStats` 缓存 future,跨 Tab 切换不重新计算。
- `getWeakWords` 改读 `MistakeProvider` 缓存,不再每次重新解析 prefs。
- 课程树交互渲染器细粒度重建。

### 4.4 Phase 20 — 主题收敛 + 规模 ADR

`0a34123` perf(phase20): srs/study-log scaling ADRs, theme color convergence:
- 新 SRS 持久化规模 ADR + StudyLog append 策略 ADR(0014 / 0015)。
- `Colors.white` / 硬编码颜色 → `VarnamalaTheme` 收敛。
- match_words / profile / settings about / loader / gems 颜色清理。

### 4.5 Phase 21 — SRS 队列基类 + Repository 接口

`7db88d5` refactor(phase21): SRS queue base class, repository interfaces,
Piper completer:
- 抽 `SrsQueueProvider` 基类,`SrsProvider` / `GrammarReviewProvider` 转为
  薄封装。
- `ICourseRepository` + `IStudyLogRepository` 接口 + DB-as-cache。
- Piper Swahili TTS 初始化 `Completer` 替代 busy-wait,可并发。
- Repository + Piper init 测试。

### 4.6 Phase 22 — 字典 / 弱词 / 提醒 / 课程树状态 / 无障碍

`1334551` feat(phase22): dictionary, weak-word review, daily reminder,
course tree state, a11y:
- /dictionary 全课程搜索:vocab / expression / grammar。
- 弱词复习(30 天 / 错 ≥ 2 次)+ `_PlayHubCard`。
- `flutter_local_notifications` 本地每日提醒。
- 课程树 completed / due / weak 状态角标 + `Selector` 重建。
- IconButton 工具提示、MCQ 屏阅读器语义、输入语义标签。

### 4.7 Phase 23 — GameProvider 拆分 + 纯 streak resolver

`78d26c0` refactor(phase23): split GameProvider into focused providers +
pure streak resolver:
- `ScoreProvider` / `StreakProvider` / `LessonProgressProvider` /
  `GameMilestoneProvider` 四件套。
- `GameProvider` 保留为薄 facade,向后兼容。
- `streak_resolver.dart` 纯函数 + 全路径覆盖。
- DI 整合 ADR 终稿。

### 4.8 Phase 24 — 集成测试 + Golden 基线

`d9b336e` test(phase24): integration flows, golden baseline, widget gap
coverage:
- 集成测试:lesson flow / SRS review restart / dictionary + weak words。
- Golden 测试:play hub / dictionary / settings reminder / SRS empty
  (light + dark)。
- match_words / settings sound toggles / 课程完成 / mastery dialog 覆盖。
- SRS 持久化 benchmark。

### 4.9 Phase 25 — 释放流水线

`7ec3371` chore(phase25): release pipeline, versioning, content inventory
v0.4.0-future4:
- `tool/build_release.py` 一键构建 APK / AAB / Web 制品 + 内容清单。
- `test/tool/build_release_test.py` mock subprocess + shutil。
- ADR `0017 release pipeline and versioning strategy`。
- 更新 ADR `0004` 接入 CI 构建冒烟。
- `Makefile` 加 `build-release` + `build-release-smoke` target。
- `flutter_ci.yml` 跑 Python 工具测试 + release build smoke。
- 生成 `docs/content_inventory_v0.4.0-future4.md`。

### 4.10 Phase 26 — 文档收尾

- `65a8964` docs(phase26): future4 completion, CLAUDE.md update, ADR 0018
  handoff — 文档 + CLAUDE.md + ADR 0018 交接。
- `9d9b56a` docs(future4): mark Phases 17-24 complete and update baseline
  — `future4.md` 状态块更新,`BASELINE.md` 收口 372/372。

---

## 5. 1.0.0 土耳其语转向 (2026-07-12)

> 详细迁移背景见 [`docs/project-guide.md`](./docs/project-guide.md) §13 / §15。

### 5.1 一次性土耳其语迁移

`389f453` chore(future4): bulk Turkish pivot and course tree virtualization:
- 目标语言由斯瓦希里语改为 **土耳其语**(assets / TTS / language code /
  course loader)。
- 移除 Swahili 课程内容、Piper 离线模型、Swahili 专属代码。
- 新 Turkish 课程骨架 + 语言绑定。
- `CourseTree` 课程列表扁平化 `SliverList` 虚拟化,支持 100+ 课/单元。
- 测试 + 文档同步。

#### 关键文件变动
- 删除 `assets/courses/swahili/`(8 sections × ~138 行 + vocab + expressions
  + grammar_points)。
- 新增 `assets/courses/turkish/`(8 sections × 43 行 placeholder + 真实
  section1 165 行 + vocab / expressions / grammar_points)。
- 文件重命名 `assets/courses/{swahili => turkish}/index.json`(38 行)。
- 删 `sw_CD-lanfrica-medium.onnx.json`(Piper 模型 493 行)。
- 新 / 更新文档:
  - `docs/authoring/course-layout.md`(112 行)。
  - `docs/authoring/gui-course-editor.md`(216 行)。
  - `docs/authoring/lesson-type-templates.md`(456 行)。
  - `docs/authoring/listening-show-format.md`(332 行)。
  - 4 个模板 `templates/lesson-{intro,practice,mastery}.json` + 模板文档。
- 新 ADR:
  - `0019-section-tree-vs-lesson-body-loading.md`(82 行)。
  - `0020-swahili-to-turkish-pivot.md`(79 行)。
- 删 `dreamplan.md` / `future2.md` / `future3.md` / `future4.md`(迁入
  `docs/decisions/` 与 `docs/function-checklist.md`)。
- 代码层 `lib/application/`、`lib/core/`、`lib/courses/course_loader.dart`、
  `course_validator.dart` 等土耳其语接入。
- `lib/courses/alphabets/swahili.dart` 删除。

### 5.2 课程内容扩充

- `56d0433` Rework s1-l2 Merhaba into 15-card productive intro — Section 1
  问候语单元 15 张 productive intro 卡。
- `ba45561` Remove obsolete top-level docs — 删 `CODE_OF_CONDUCT.md` /
  `Reference.md`。
- `128ab3b` docs & content: update README, Turkish course data, authoring
  templates, docs and listening audio assets — README + Turkish 课程数据
  + authoring 模板 + 文档 + 听力音频资产。
- `6e0c2e0` feat: update app code including lesson VM, providers, routing,
  course tree and AI course generator — 课程 VM / Provider / 路由 / 课程树
  / AI 课程生成器全面更新。
- `2706c3a` build: update Android build config, Linux plugin registrant and
  pubspec dependencies — 构建配置更新。
- `b6bde9c` test & tools: add lesson VM flow test, course CLI updates, GUI
  tools and remove old screenshots — 课程 VM 流程测试 + CLI 更新 + GUI 工具
  + 删旧截图。

### 5.3 AI 助手上线

- `2119469` feat(ai): align in-app AI course generator with GUI (core gen +
  wish mode) — 在 app AI 课程生成器对齐 GUI。
- `8136838` build: commit generated code and pubspec.lock for reproducible
  clones — 生成代码 + lock 入库,首次克隆即可重现。
- `2ed7066` feat(ai): in-lesson AI hint assistant + DeepSeek default config
  — 课内 AI 提示助手 + DeepSeek 默认配置。
- `5424837` chore: commit pre-existing working-tree changes + gitignore
  build/IDE artifacts。
- `9990427` fix(ai): harden AI hint assistant — response parsing, race
  guards, language source — 提示响应解析硬化 + 防抖 + 语言源。
- `4114321` feat(settings): add Settings tab + progress export/import —
  设置 Tab + 进度导出 / 导入。
- `559d1d0` refactor(lesson): code-review round 2 — sentinel parsing, SRS
  latency, AI reasoning config — 哨兵解析 + SRS 延迟 + AI 推理配置。

### 5.4 GUI 工具扩张

- `5f2dda0` feat(tool/gui): textbook import — knowledge merger, import
  strategies, bulk preview, presets/concurrency/usage, perf (bookplan2
  P4-P6) — 教材导入(知识合并 + 导入策略 + 批量预览 + 预设 + 并发 + 性能)。
- `4913978` chore(tool/gui): shared infra + project scaffold — 共享基础设
  施 + 项目脚手架。
- `d4812ce` feat(tool/gui): AI generation overhaul — ai dialog subpackage,
  streaming, fixer, prompt library — AI 生成大改(ai dialog 子包 + 流式
  + 修正器 + 提示库)。
- `a51c218` feat(tool/gui): textbook import P1-P3 — project persistence,
  structured steps, extraction quality — 教材导入 P1-P3(项目持久化 + 结构
  化步骤 + 提取质量)。
- `534e118` feat(tool/gui): textbook import P4-P6 — knowledge merger wiring,
  import strategies, bulk preview, presets, perf, docs — 教材导入 P4-P6
  (知识合并接线 + 导入策略 + 批量预览 + 预设 + 性能 + 文档)。
- `22f90fb` chore(tool/gui): wire app shell + workshop window + update test
  baseline — 主窗 + workshop 窗口接线 + 测试基线更新。
- `8827a3b` chore: Turkish course content updates, AI hint/settings
  refactoring, GUI docs, textbook projects — Turkish 课程内容 + AI 提示
  / 设置重构 + GUI 文档 + 教材项目。
- `a6a27f8` docs(readme): expand GUI textbook import + workshop + AI engine
  sections — README 扩充 GUI 教材导入 + workshop + AI 引擎章节。
- `85a021a` docs: polish README tone, add SLA context for SRS and lesson
  templates — README 语气打磨 + SLA 上下文。
- `6c67411` docs: expand READMEs with linguistics and SLA content — 语言
  学 + SLA 内容扩充。
- `c0ee43f` feat(tool/gui): 教师模式重构 + 功能课向导 + 课程总览 — 教师
  模式 + 功能课向导 + 课程总览。
- `8bdd8e2` refactor(tool/gui): 代码精简 T1+T2 + upgradeplus1 异步加载 +
  数据 / 测试更新。
- `871cafa` refactor(tool/gui): 精简 T3 - 抽 helper 消除跨文件 / 跨方法
  重复。
- `a5ba895` refactor(tool/gui): 精简 T4 - commands.py QUndoCommand 家族抽
  基类。
- `7bbbc81` docs(gui): update tool/gui/README.md with comprehensive guide
  and SLA appendix — GUI README 综合指南 + SLA 附录。
- `58cb3e2` perf(tool/gui): course tree 图标类级缓存 + id->item 索引化。
- `07b3ca9` perf(tool/gui): user_action_filter 连点节流避免反射刷屏。
- `ffe8915` perf(tool/gui): git 库对话框关闭停定时器 + 日志轮询长度短路。
- `4230af9` perf(tool/gui): course_overview 复用常驻 host 避免每次刷新
  重建。
- `8572990` perf(tool/gui): linear_flow options model 按 id 指纹缓存复用。
- `4bce2fd` feat: tool/gui commands + settings + course adapter;Flutter
  accessibility;remove stale ADRs — GUI commands + settings + course
  adapter + Flutter 无障碍 + 删陈旧 ADRs。

### 5.5 内容清单

- `docs/content_inventory_current.md` 持续更新。

---

## 6. 1.1.0 FSRS / AI / Anki 智能化 (2026-07-30)

> 历史实现规范见 [`docs/project-guide.md`](./docs/project-guide.md) §5、§6、§7（原 ADR 0027–0029）。

`980224e` feat(srs,anki,ai): FSRS engine, anki smart organization, AI
engine refresh, app icon & l10n — 368 files changed, 27727 insertions(+),
13991 deletions(-) 是 1.1.0 的核心提交。

### 6.1 间隔重复引擎 — FSRS

- `lib/core/fsrs_engine.dart` — 连续记忆模型 FSRS。
- `lib/core/fsrs_optimizer.dart` — 本地参数优化器。
- `lib/core/fsrs_relearn.dart` — relearn 路径。
- `lib/core/srs_scheduler.dart` — SRS 调度器(替代 / 增强 SM-2)。
- `lib/core/sm2.dart` 刷新(保留作后备)。
- `lib/data/review_history_dao.dart` — 复习历史 DAO。
- `lib/data/srs_state_dao.dart` — SRS 状态 DAO。
- `lib/application/memory_curve_provider.dart` — 记忆曲线。
- `lib/application/review_progress_provider.dart` — 复习进度。
- `lib/application/srs_tutor_provider.dart` — SRS 学习导师。
- Lesson / Course / Mistake / SRS Provider + `srs_queue_provider` 重新调
  校适配 FSRS。

### 6.2 Anki 智能化

- `lib/application/anki/anki_organization_resolver.dart` — 智能牌组归类。
- `lib/application/anki/anki_sample_deck.dart` — 示例牌组。
- `lib/application/anki/anki_template_renderer.dart` — 牌型渲染。
- `anki_review_assembler.dart` / `anki_deck_assembler.dart` /
  `anki_deck_manager.dart` / `anki_importer.dart` /
  `anki_notetype_ai.dart` / `anki_srs_migrator.dart` 全面重构。
- `anki_card_adapter.dart` / `anki_models.dart` 重新生成(freezed +
  json_serializable)。
- 渲染器按交互拆分(`per-interaction` 渲染器)。
- `anki_card_enhancer.dart` 删除(合并到新设计)。
- `anki_import_service.dart` 删除(合并到 resolver + importer)。

### 6.3 AI 引擎重构

`lib/application/ai/engine/` 整目录重构:
- `ai_cache.dart` — 内存 + 磁盘 IO + Web 缓存。
- `ai_cancel_token.dart` — 可取消令牌。
- `ai_engine.dart` — 引擎主类。
- `ai_engine_config.dart` — 引擎配置。
- `ai_engine_config_holder.dart` — 配置持有者。
- `ai_engine_result.dart` — 引擎结果封装。
- `ai_http_client.dart` — 统一 HTTP 客户端。
- `ai_provider_preset.dart` — 提供商预设。
- `ai_recent_tasks_provider.dart` — 最近任务。
- `ai_stream_chunk.dart` — 流式响应块。
- `hint_genres.dart` — 提示类型枚举。
- `textbook_import_plan.dart` + `textbook_presets.dart` — 教材导入计划
  + 预设。
- 全面接入:ai_api_config / ai_course_provider / ai_course_service /
  ai_grounded_resource_provider / ai_hint_provider / ai_lesson_helper_provider
  / ai_wish_provider / knowledge_merger / knowledge_prompt / textbook_import_provider。
- `lib/application/ai/ai_hint_provider.dart` 硬化解析。
- 新视图:
  - `lib/views/ai/ai_hub_page.dart` AI 中心。
  - `lib/views/ai/components/ai_hub_app_bar.dart` AI 中心 AppBar。
  - `lib/views/textbook/textbook_conflict_preview.dart` 教材冲突预览。
  - `lib/views/textbook/textbook_review_panel.dart` 教材审阅面板。
- 新服务:`lib/service/xiaoyi_service.dart` + OHOS `XiaoyiPlugin.ets`。

### 6.4 UI / 屏幕

- **课程**: 新 `course_management_page`;section_picker + 树形可视化更新。
- **课**: 新 `ai_depth_tutor_sheet`、`anki_media_strip`、
  `lesson_practice_card`、`tutor_launch_sheet`。
- **复习**: 新 `retention_curve_chart`、`review_progress_page`;
  `grammar_review` / `mistake` 页刷新。
- **首页**: 新 `streak_broken_dialog`;`bottom_navigator` / profile / stat
  AppBar / `home_page` 刷新。
- **设置**: 新 `changelog_page`、`ai_api_config_sheet`、
  `settings_fun_section`、`settings_xiaoyi_tile`;章节 widget 重制。
- **Profile**: 新 `profile_quick_actions`;achievements / learning_stats /
  share_progress_card / statistics 刷新。
- splash / characters / dictionary / onboarding / play / anki 屏触达。

### 6.5 本地化

- **删除**:`l10n.yaml`、`lib/l10n/app_*.arb`、
  `lib/l10n/app_localizations*.dart`、`lib/application/locale_provider.dart`。
- **新增**:`lib/l10n/app_strings.dart`(手写,无 codegen)。
- `app_strings.dart` 全文中文化 + 配置刷新。

### 6.6 品牌 / 资产

- 应用图标在 Android / iOS / macOS / OHOS / Web / Windows 全面刷新。
- `android/app/src/main/res/mipmap-*/launcher_icon*.png` 全套。
- `web/icons/Icon-192.png` / `Icon-512.png` / `Icon-maskable-*`。
- `windows/runner/resources/app_icon.ico`。
- `web/favicon.png` 555 字节新版。
- 新增资产:
  - `assets/app_logo.png`
  - `assets/app_logo_store_1024.png`
  - `assets/app_logo_store_216.png`
  - `assets/mala/mala_reading.png`
  - `assets/mala/mala_waving.png`
- 新工具 `tools/generate_logo_variants.py`(69 行)。

### 6.7 文档

- 删陈旧 ADR 0021–0026(团队协作 / Git 集成 / 本地编辑器增强,本仓库不走
  那套)。
- 删 `docs/authoring/gui-beginner-guide.md` / `.html`。
- `docs/anki-import-design.md` 与 `docs/功能清单.md` 大幅扩充。

### 6.8 测试

- 新测试文件:
  - `test/anki/anki_organization_resolver_test.dart`
  - `test/anki/anki_sample_deck_test.dart`
  - `test/anki/anki_template_renderer_test.dart`
  - `test/ai/engine/*`(全部)
  - `test/ai/textbook_import_plan_test.dart`
  - `test/ai/knowledge_merger_test.dart`
  - `test/ai/textbook_presets_test.dart`
  - `test/integration/anki_review_assembler_test.dart`
  - `test/course_provider_scope_test.dart`
  - `test/srs/memory_curve_provider_test.dart`
  - `test/srs/review_progress_provider_test.dart`
  - `test/srs/srs_tutor_provider_test.dart`
  - `test/srs/fsrs_engine_test.dart`
  - `test/srs/fsrs_optimizer_test.dart`
  - `test/srs/fsrs_relearn_test.dart`
  - `test/srs/review_outcome_test.dart`
  - `test/data/review_history_dao_test.dart`
  - `test/data/srs_state_dao_test.dart`
  - `test/views/anki_card_renderer_test.dart`
  - `test/views/home/streak_broken_dialog_test.dart`
  - `test/views/settings/settings_account_edit_name_test.dart`
  - `test/views/settings/settings_account_navigate_test.dart`
  - `test/views/settings/settings_category_list_test.dart`
  - `test/views/settings/settings_slider_commit_test.dart`
- 刷新:anki_card_adapter / anki_deck_assembler / anki_srs_migrator /
  ai_course_service / ai_hint_provider / daily_challenge / game_provider /
  grammar_review / learning_stats / lesson_viewmodel / mastery_dialog /
  provider_identity / settings_reminder / srs_provider / sm2 /
  schema_migration / dictionary / play_hub / settings_reminder / srs_review
  golden。
- 集成测试:`lesson_flow_test.dart` / `srs_review_flow_test.dart` /
  `dictionary_and_weak_words_test.dart`。
- 删除 `test/data/course_database_pos_test.dart` / `test/widget_test.dart`。

---

## 7. 维护 (2026-07-30 → 2026-08-01)

### 7.1 settings 同步

- `f62a727` chore: update settings_provider.dart:
  - `lib/application/settings_provider.dart` 增 14 行新配置项。
  - `lib/l10n/app_strings.dart` 增 242 行(中文化)。
  - `lib/main.dart` 16 行变更(主题初始化顺序)。
  - `lib/service/locator.dart` 17 行变更(Locator 调整)。
  - `lib/utils/ohos_file_picker.dart` 86 行变更(OHOS 文件选择器)。
  - `lib/views/ai/ai_hub_page.dart` 581 行变更(AI 中心重构)。
  - `lib/views/anki/anki_import_screen.dart` 405 行变更(Anki 导入屏)。
  - `lib/views/app.dart` 104 行变更(根 widget 调整)。
  - `lib/views/home/components/bottom_navigator.dart` 6 行删除。
  - `lib/views/home/components/stat_app_bar.dart` 17 行变更。
  - `lib/views/home/home_page.dart` 4 行删除。
  - `lib/views/play/components/play_tiles.dart` 523 行新增(play 卡片组件)。
  - `lib/views/play/play_hub_screen.dart` 1097 行大改(play hub 重构)。
  - `lib/views/settings/about_varnamala_page.dart` 1113 行大改(关于页重设)。
  - `lib/views/settings/ai_api_config_sheet.dart` 509 行变更(AI 配置 sheet)。
  - `lib/views/settings/beginner_guide_page.dart` 340 行新增(入门指南页)。
  - `lib/views/settings/settings_page.dart` 33 行变更(设置页)。
  - `lib/views/settings/widgets/settings_about_section.dart` 12 行新增(关于
    section)。
  - `lib/views/theme.dart` 82 行新增(主题助手)。
- `lib/data/rdb_query_executor.dart` 45 行新增(查询执行器抽象)。
- `test/BASELINE.md` 同步。

### 7.2 OHOS gitlink 修复

`9b5a172` chore(git): untrack ohos/.codegenie gitlink, ignore IDE tool dirs:

`ohos/.codegenie` 目录被作为 gitlink(160000)提交,指向一个过期的子 commit。
Git 在每个 gitlink 上递归跑 `git status --porcelain=2`,内部子仓库的损坏
状态导致每次 status 输出 ~650 行致命错误,实质挂起所有 git 操作。

- `git rm --cached ohos/.codegenie`:从索引里删掉 gitlink;
  `ohos/.codegenie/MEMORY.md` 保留在磁盘上不动。
- `.gitignore` 增 `**/.codegenie/` + `**/.hvigor/`,防止 DevEco Studio 下
  次 IDE 启动时再把它们加回来。

验证:`git status --short` 即时返回真实工作树变更。

---

## 8. 1.2.0 伴学与内容扩充 (2026-08-05)

- AI 伴学工具链全面上线：自由问答、学习诊断、讲解收藏、词典扩展与 Anki 问答解析。
- 课内提示支持流式回复，并注入学习者上下文（水平、错题本、讲解偏好）。
- 土耳其语内置课程大幅扩充：A1→B2 八章真实内容（约 148 词 / 18 表达 / 8 语法 / 54 课）。
- 宝石与装扮兑换支持、湿地鹤品牌色板锁定（ADR 0033/0035）。

---

## 9. 1.3.0 Anki 原生渲染、练习解耦与吉祥物升级 (2026-08-15)

### 9.1 Anki 原生渲染与展开式卡面
- **展开式问答卡面**（`AnkiRevealScaffold`）：问题留在上方，答案在下方平滑展开，四档评分（Again/Hard/Good/Easy）固定在底部，彻底移除旧版 300px 3D 翻转卡顿。
- **Flutter 原生 HTML 渲染链**（`AnkiFacePaintEngine` + `AnkiFlutterHtmlView`）：默认走高效 Flutter 原生渲染，仅在复杂 MathJax / JS 脚本时降级 WebView，无 WebView 环境自动文本兜底。
- **卡面预热与元数据**：显示 Deck、Tags、旗标标记，`{{hint:}}` 字段提为可点提示，异步预热下一张 NoteStore 原卡。

### 9.2 复习与练习独立解耦
- **双轨分离**：复习仅走 NoteStore 原卡四档评分，练习独立提供多种交互题型。
- **练习复用题型**：将 Cloze / `{{type:}}` 智能映射为原生填空（`FillBlank` / `TypeTheWord`），支持选择与听选，练习不污染 FSRS 复习调度。

### 9.3 导入体系与容错恢复
- **导入差异规划**（`AnkiImportDiffPlanner`）：支持 merge / forceReplace / appendAsNew 导入策略，提供直观的差异对比预览。
- **操作事务恢复**（`AnkiImportOperationRecovery`）：导入过程全链路事务日志记录，支持失败/取消恢复。
- **字段映射编辑器**（`AnkiImportMappingEditor`）：可视化调整字段与题型映射。

### 9.4 Turna 湿地鹤吉祥物形象系统
- **全新形象**：2D 扁平现代卡通风格，微翘陶土暖红羽冠、湿地青绿羽翼、安纳托利亚信使小邮差包。
- **场景插画全覆盖**：主页动态欢迎（`turna_waving`）、课文阅读（`turna_reading`）、听力沉浸（`turna_listening`）、AI 思考（`turna_thinking`）、通关庆祝（`turna_celebrate`）、错题鼓励（`turna_encourage`）与全新 App 图标（`turna_app_logo`）。
- **交互组件集成**：主页欢迎轮播（`TurnaWelcomes`）与统一轻量提示（`TurnaToast`）。

### 9.5 系统健康与诊断
- **全链路健康监控**（`SystemHealthMonitor`）：提供数据库、文件系统、AI 引擎、Anki 兼容性诊断与可视化诊断页面（`system_health_page.dart`）。
- **AI 伴学证据沉淀**：引入学习证据链记录、会话知识检索与 AI Token 预算管理。

---

## 简版

以下为面向用户的版本摘要，应用内文案见 assets/changelog.md。

### [0.7.2] - 2026-08-25

- Anki 来源现在会作为独立课程显示，多牌组管理更清晰。
- “复习全部”支持连续复习多个 Anki 来源。
- 新增卡片浏览、牌组统计和旧数据迁移入口。
- 优化复杂卡片、图片与音频的显示和播放。
- 导入、重新导入、删除和迁移的中断恢复更可靠。
- 修复课程切换、牌组定位和删除范围不准确的问题。

---

### [0.7.1] - 2026-08-24

- 更新 AI 服务预设，并加入可选的深度思考模式。
- AI 密钥改用系统安全存储，导出时不会携带敏感信息。
- 优化 AI 回复流畅度、取消与重试体验。
- 新增“存储与性能”页面，支持查看占用和清理缓存。
- 修复成就奖励、连续学习统计和备份恢复后的设置刷新。

---

### [0.7] - 2026-08-15

- 改进 Anki 牌组导入、复杂卡片显示和复习体验。
- 大型牌组导入更省内存，并可在中断后恢复。
- 统一课程与复习入口，加入数据导入导出和远程备份。
- 优化个人页、学习统计、成就和 Turna 吉祥物场景。
- 新增学习数据与系统状态检查。

---

### [0.6] - 2026-08-05

- AI 伴学新增自由问答、学习诊断、讲解收藏和词典扩展。
- 课内提示会结合学习水平、错题和讲解偏好回复。
- 土耳其语内置课程扩充为 A1 至 B2 八章。
- 调整 AI 中心分区，并加强导出数据的隐私保护。

---

### [0.5] - 2026-07-30

- 更新个性化记忆复习方式。
- 改进 Anki 牌组识别和复杂卡片显示。
- AI 请求支持取消，回复和错误处理更稳定。
- 重做课程管理、AI 中心和多处界面。
- 新增记忆曲线、复习进度和学习建议。

---

### [0.4] - 2026-07-29

- 界面全面中文化，学习目标语言调整为土耳其语。
- 新增 Anki 导入与复习、课内 AI 提示和教材导入。
- 支持学习进度导入导出。
- 完善主题、提醒、音效、无障碍、词典和学习统计。

---

### [0.3.x] - 2026-07-11

- 支持多种主题、字号、高对比度和阅读辅助选项。
- 加入专注模式、本地学习提醒和课程状态标记。
- 课程内容更新时会提示并可重置进度。
- 移除不再使用的社交、付费和部分游戏化功能。

---

### [0.3.0] - 2026-07-11

- 完成离线优先的课程与学习框架。
- 支持多种课程结构与练习题型。
- 整合学习统计、词典、弱词复习和提醒。

---

### [0.0.1] - 2024-04-26

- 完成最初的西班牙语与卡纳达语词汇学习原型。
- 加入基础练习、动画、语音和配对玩法。
- 建立课程导航与学习数据保存能力。
