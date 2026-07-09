# Varnamala Plus

> 🚧 **正在施工中** — 框架重整 + 唯一目标语 Swahili，AI 协作（vibecoding）迭代中。

## 起源

本仓库是一个**二次开发分支**，底层框架来自 GitHub 开源项目 **[Varnamala](https://github.com/rshrc/Varnamala)**（同一仓库名）。我们借用了它的 Section / Unit / Lesson / SRS / 错题本 / 暗色主题 / 学习统计等核心骨架，将目标聚焦到**单一目标语 Swahili** 上，并按 `future2.md` 路线图做"减法"——去社交化、去除 Duolingo 风格的 friction、收紧范围。

本仓库并非原项目官方版本；如需纯原版功能，请直接访问上游 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)。

## 当前定位

- **唯一目标语**：Swahili（当前 vocab 仍为 Kannada 占位词表，待替换为真实 Swahili 内容）。
- **本地优先**：纯本地 SQLite 缓存，**不**接入任何云后端 / 推送 / 登录。
- **单人 / 离线**：无好友、无排行榜、无联赛、无心数、无宝石购买——一切"反学习"摩擦都已被剔除。
- **AI 协作开发（vibecoding）**：本项目通过与 AI 协作迭代，每一步有文档化的施工步骤（见 `future2.md` §6），并由 git commit 串成可回放的时间线。

## 框架已完成的能力

- **课程引擎**：`Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction`（freezed 模型 + JSON 序列化）。
- **11 种 Interaction 题型**：`showWord` / `multipleChoice` / `fillBlank` / `translateSentence` / `listenAndPick` / `typeTheWord` / `listenOnly` / `reorderSentence` / `readingMcq` / `readingTrueFalse` / `readingShortAnswer`，每个作为 `@injectable` 插件注册到 GetIt。
- **6 种 Lesson Template**：`intro` / `practice` / `listening` / `reading` / `review` / `mastery`（+ `legacy` 兜底），`Lesson.flattenedStages` 把所有形态展平为渲染器可遍历的 `List<Stage>`。
- **按需加载**：`index.json` + per-section JSON + drift SQLite 缓存（schemaVersion 4），按内容版本号自动 reseed。
- **SRS 复习**：基于 SM-2 算法的单词 SRS + 独立语法点 SRS 队列；闪卡显示"Learned in: <lesson>"。
- **错题本**：30 条 FIFO，错题含原始 interaction 快照，支持重做清除 + 跨路由到语法复习。
- **语法复习**：Explain → Practice → Rate 三段流，练习题直接复用 Interaction 渲染器。
- **TTS 引擎**：`AudioController` 统一接管 TTS 调用，按 `TargetLanguage.ttsLanguageCode` 切语言；离线音频 fallback 接口已就位。
- **暗色 / 亮色主题**：`VarnamalaTheme` 语义化颜色 + `ThemeProvider` 持久化。
- **学习统计仪表盘**：90 天 `StudyLog` 滚动 + 7 日 XP 趋势 + 总时长 / 准确率 / 课数 / 复习数。
- **Match Madness 单词配对小游戏**。

## 已明确**不**做的事（防 scope creep）

- 任何形式的 League / 天梯 / 好友 / 排行榜 / 分享奖励 / Patreon。
- Hearts（生命限制）/ Streak Repair（XP 计数型）/ 商店道具。
- Speaking 录音匹配题型。
- 云端 CMS / Firebase / 推送通知。
- 任何**新内容**（新词 / 新语法 / 新 lesson / 新阅读 / 新音频）—— 内容替换是另一条独立分支的事，不在本仓库范围。

详细列表见 `future2.md` §6 / §7。

## 项目结构

```
lib/
├── application/   # Providers：Course / Lesson / SRS / Mistake / Grammar / Game / Study …
├── core/          # enums, sm2, spacing, text styles, logger
├── courses/       # 字母 + 语种 loader（生产 Swahili，Kannada 占位词表）
├── data/          # drift CourseDatabase + Seeder + Repository
├── di/            # GetIt + Injectable（renderer_module 收集所有 InteractionRenderer）
├── domain/        # section / unit / lesson / stage / interaction / sub_lesson /
│                  # listening_phase / reading_passage / expression / grammar_point /
│                  # lesson_word_link / srs_word / mistake_entry / lesson_content
├── routing/       # auto_route 配置
├── service/       # AppPrefs（StreamingSharedPreferences）+ locator
└── views/         # UI：courses / lesson / play / review / profile / splash / onboarding …
```

## 构建与运行

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed / json_serializable / drift / injectable
flutter run                                                # 设备或模拟器
```

首次启动时，课程数据库 `course.swahili.db` 从 bundle 的 JSON assets seed；之后会复用缓存。如需强制 reseed，bump `assets/courses/swahili/index.json` 的 `version` 即可（自动），或清空 app data。

## 测试

```bash
flutter test
```

`future2.md` Phase 11 的覆盖率目标：**`lib/application` ≥ 70 %，`lib/views/lesson` ≥ 50 %**。

## 文档

- [`future2.md`](./future2.md) — **唯一路线图**，38 个施工步骤（Phase 7–12），明确边界与不做项。
- [`dreamplan.md`](./dreamplan.md) — 旧版 v1 计划，仅作历史参考。
- [`CLAUDE.md`](./CLAUDE.md) — 面向 AI Agent 的架构说明。
- [`IMPLEMENTATION.md`](./IMPLEMENTATION.md) / [`NEXT_VERSION.md`](./NEXT_VERSION.md) / [`plan.md`](./plan.md) — 历史，部分已被 `future2.md` 取代。

## 致谢

- 原始框架：[Varnamala](https://github.com/rshrc/Varnamala) — 提供 Section/Unit/Lesson 树、Provider + Drift + Freezed + auto_route 的整套骨架。
- TTS：[flutter_tts](https://pub.dev/packages/flutter_tts)
- 持久化：[drift](https://pub.dev/packages/drift) + [streaming_shared_preferences](https://pub.dev/packages/streaming_shared_preferences)
- DI / 路由：[get_it](https://pub.dev/packages/get_it) + [injectable](https://pub.dev/packages/injectable) + [auto_route](https://pub.dev/packages/auto_route)

## 截图

| Home | Lesson | Profile | Alphabets |
|:---:|:---:|:---:|:---:|
| ![Home](screenshots/screenshot0.png) | ![Lesson](screenshots/screenshot1.png) | ![Profile](screenshots/screenshot2.png) | ![Alphabets](screenshots/screenshot3.png) |

| Writing | Socials | Leagues and Leaderboard | Games |
|:---:|:---:|:---:|:---:|
| ![Writing](screenshots/screenshot4.png) | ![Socials](screenshots/screenshot5.png) | ![Leagues and Leaderboard](screenshots/screenshot6.png) | ![Games](screenshots/screenshot7.png) |

> 截图后两列（`Socials`、`Leagues and Leaderboard`）展示的是上游原版功能，**本仓库已按 `future2.md` 移除**，仅作历史视觉对比。
