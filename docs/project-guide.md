# Turna 项目指南（详尽版）

> 本文是 README 的深度补充。README 给出概览与快速上手，本文给出每个子系统的设计、实现要点与决策依据。阅读顺序建议：先读 README，再按需查阅本文相应章节。
>
> 所有信息以代码现状为准（schemaVersion 21、课程内容版本 12、`flutter test --exclude-tags golden` 1852 passed / 0 failed，另 golden 4/4、native 68/68，截至 2026-08-28；完整基线见 `test/BASELINE.md`）。
>
> **近期重要变更**：Legacy Anki 复刻层已于 2026-08-27 由 [doc 35](./official-anki-migration/35-duplicate-legacy-layer-cleanup-plan.md) L0–L3 物理删除（`lib/application/anki/` 目录清空）。原 §6 中描述 legacy 解析/装配/映射/Full-Lite 的段落已改为删除说明，勿再按旧描述实现。

---

## 目录

1. [项目定位与设计哲学](#1-项目定位与设计哲学)
2. [教学法与二语习得基础](#2-教学法与二语习得基础)
3. [架构总览](#3-架构总览)
4. [课程引擎](#4-课程引擎)
5. [复习系统：FSRS、记忆曲线与错题](#5-复习系统fsrs记忆曲线与错题)
6. [Anki 深度集成](#6-anki-深度集成)
7. [AI 引擎层与 AI 功能](#7-ai-引擎层与-ai-功能)
8. [音频、TTS 与智能朗读](#8-音频tts-与智能朗读)
9. [主题与可访问性](#9-主题与可访问性)
10. [平台与构建](#10-平台与构建)
11. [GUI 课程编辑器（作者工具）](#11-gui-课程编辑器作者工具)
12. [听力音频生成流水线](#12-听力音频生成流水线)
13. [课程数据格式与 Authoring](#13-课程数据格式与-authoring)
14. [测试与质量基线](#14-测试与质量基线)
15. [已明确不做（含教学法依据）](#15-已明确不做含教学法依据)
16. [文档索引](#16-文档索引)
17. [下一轮计划与致谢](#17-下一轮计划与致谢)

---

## 1. 项目定位与设计哲学

**Turna** 是基于上游 [Varnamala](https://github.com/rshrc/Varnamala) 的本地优先（local-first）、离线 Flutter 语言学习框架，当前目标语为 **Turkish（土耳其语）**。它在上游 Section/Unit/Lesson/SRS/错题本骨架之上，持续做三件事：

- **深化复习引擎**：从 SM-2 升级到 **FSRS**（Free Spaced Repetition Scheduler），并加入记忆曲线可视化与复习历史持久化。
- **打通 Anki 生态**：可直接导入 `.apkg` 牌组，按 notetype 智能映射为课程结构，复杂牌组以 WebView 高保真渲染，并与本应用 SRS/错题/统计流水线双向打通。
- **统一 AI 能力**：以单一 AI 引擎层收敛所有 LLM 流量（流式、缓存、取消、JSON schema），并提供 AI Hub 作为集中入口。

### 设计原则

| 原则 | 含义 |
|---|---|
| **本地优先** | SQLite（drift）为存储，无云后端、无推送、无登录；数据隐私与离线可用性优先。 |
| **单人离线** | 无好友、排行榜、联赛、心数、宝石等社交/ monetization 机制。 |
| **JSON 为真理源** | 课程内容以 JSON 存储，可版本化、可 diff、可脚本批处理；GUI 编辑器只是 JSON 的可视化前端。 |
| **DB 作为派生缓存** | 首次启动从 bundle JSON seed `course.db`，之后复用；按内容版本号自动 reseed。 |
| **教学法驱动** | 功能取舍以二语习得研究为依据（见第 2 节），而非单纯工程简化。 |

> 本仓库非上游官方版本；纯原版功能请访问 [rshrc/Turna](https://github.com/rshrc/Varnamala)。

---

## 2. 教学与二语习得基础

本项目的课程设计与复习机制建立在二语习得（SLA）与认知心理学研究之上。以下给出贯穿全局的核心概念与本项目对应的工程实现。

### 2.1 可理解输入与 i+1 原则

Stephen Krashen 的**输入假说**（Input Hypothesis）认为，语言习得发生在学习者接触到略高于当前水平的**可理解输入**（comprehensible input）时——即 "i+1"，其中 i 为学习者当前水平。本项目的 CEFR 分级 Section（A1→B2）与 inter-section 前置依赖即是对该原则的工程化：学习者必须在较低等级课程中达到一定掌握程度后，才能解锁下一等级。

### 2.2 间隔重复与遗忘曲线

Hermann Ebbinghaus（1885）描述了**遗忘曲线**：新记忆形成后迅速衰减，但每次**主动检索**都能显著减缓衰减。**间隔重复**（spaced repetition）将复习安排在遗忘临界点附近，以最少复习次数达成最长记忆保持；这在词汇习得中被认为是实证基础最牢固的策略之一（Nation, 2013）。

本项目复习引擎采用 **FSRS**（见第 5 节），以**目标保持率**（desired retention，默认 0.9）驱动下次复习间隔计算，比传统 SM-2 更贴近真实遗忘曲线。SM-2 作为后备调度器保留在 `lib/core/sm2.dart`。

### 2.3 检索练习与测试效应

**测试效应**（testing effect）：相对于被动重读，主动从记忆中提取信息（"自我测试"）能显著增强长期保持（Roediger & Karpicke, 2006）。本项目的填空、翻译、听写、选择等题型本质上都是不同形式的检索练习，而非单纯"考核"。

### 2.4 技能习得理论

**Skill Acquisition Theory**（DeKeyser, 2007）描述了从**陈述性知识**（declarative knowledge，"知道规则"）到**程序性知识**（procedural knowledge，"自动运用"）的转化路径。本项目的语法复习采用 **Explain → Practice → Rate** 三段流：先呈现语法规则（显性知识输入），再通过练习转化为程序性技能，最后自我评估掌握程度。

### 2.5 交错练习

相比集中练习单一类型，**交错练习**（interleaved practice）在训练阶段感觉更吃力，但长期保持效果显著更优（Rohrer & Taylor, 2007）。本项目的"每日挑战"从课程树随机抽取真实题项合成挑战课，实现跨题型、跨单元的交错出题。

### 2.6 错误分析与中介语

**错误分析**（error analysis）是 SLA 中理解**中介语**（interlanguage）发展轨迹的核心手段——学习者的错误并非随机，而是反映其当前的中介语规则系统（Corder, 1967）。本项目错题本保留原始 interaction 快照（题干、正答、用户错答），支持重做与跳转对应语法点复习，使错误本身成为可分析的学习数据。

### 2.7 多技能整合

应用语言学将语言能力分解为**接受性技能**（听、读）与**产出性技能**（说、写），以及词汇、语法、语音等**语言知识**维度。本项目的 6 种 Lesson Template（intro / practice / listening / reading / review / mastery）与 14 种 Interaction 题型覆盖了从词汇呈现到听读输入再到可控产出的完整闭环，避免孤立训练单一技能。

### 2.8 关于土耳其语

Turkish 属于**突厥语系**，是一种**黏着语**（agglutinative language）：语法关系通过向词根依次附加词缀表达，一个词可承载相当于英语一整句的信息（如 *evlerinizdekilerden* = "from those at your houses"）。核心特征：

- **元音和谐**（vowel harmony）：词缀元音须与词根元音在舌位前后与唇形圆展上一致。
- **SOV 语序**：主-宾-动，与汉语/英语（SVO）显著不同。
- **无语法性别**：无冠词、无名词类别，代词无性别区分。
- **浅层正字法**（shallow orthography）：拼写-发音对应高度规则，对初学者的音位意识训练较友好。

这些特征使 Turkish 对汉语母语者既有门槛（语序、黏着形态），也有便利（无性别、拼读规则）。本项目据此设计了渐进式语法复习与丰富的词形变化练习；`listenOnly` 纯听阶段让学习者专注音位解码而不受文字干扰，`typeTheWord` 则将音位解码与拼写产出结合，双向强化形-音映射。

---

## 3. 架构总览

Clean Architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route。

```
lib/
├── application/        # Providers（状态管理）+ 应用服务
│   ├── ai/             # AI 能力：engine/ + companion/ + textbook/
│   │   └── engine/     # 统一 AI 引擎层（单一 LLM 流量出入口）
│   ├── anki_import/    # Anki 导入向导 controller / flow / 完成协调
│   ├── anki_import/recognition/  # 证据驱动识别器（doc 37：词典绑定 / 原型规则 / 薄 policy，纯函数）
├── anki_official/  # 官方 Anki Core（rslib FFI）引擎/导入/渲染/投影/迁移（ADR 0036）
│   ├── srs_provider.dart          # 单词 SRS 队列（SrsQueueProvider 子类）
│   ├── grammar_review_provider.dart  # 语法 SRS 队列
│   ├── srs_queue_provider.dart    # SRS 队列共享基类（FSRS 调度）
│   ├── srs_tutor_provider.dart    # AI SRS 导师（据错题/弱词生成复习课）
│   ├── mistake_provider.dart      # FIFO 错题本
│   ├── study_stats_provider.dart  # 学习统计聚合
│   ├── memory_curve_provider.dart # 记忆曲线模型与预测
│   ├── review_progress_provider.dart
│   ├── score_provider.dart        # XP / 分数
│   ├── streak_provider.dart       # 连续学习天数
│   ├── lesson_progress_provider.dart
│   ├── gems_provider.dart         # 宝石账本
│   ├── game_provider.dart         # 薄 facade，转发到上述各 provider
│   ├── weak_word_quiz_assembler.dart
│   ├── audio_controller.dart      # TTS / 音效统一接管
│   ├── smart_speech.dart          # 智能朗读：语言检测 + 自动朗读
│   ├── accessibility_provider.dart # 6 项可访问性偏好
│   ├── settings_provider.dart     # 含每课程 TTS 设置
│   └── ...
├── core/               # 纯逻辑：FSRS / SM-2 / 语言检测 / HTML / streak / logger
│   ├── fsrs_engine.dart           # FSRS-backed SrsScheduler
│   ├── fsrs_optimizer.dart        # FSRS 参数优化
│   ├── fsrs_relearn.dart          # 失败后当日重学阶梯
│   ├── sm2.dart                   # SM-2 后备调度器
│   ├── srs_scheduler.dart         # SrsScheduler 接口
│   ├── language_detector.dart     # 按脚本推断 BCP-47 语言码
│   ├── html_stripper.dart         # Anki HTML 卡片朗读前去标签
│   └── streak_resolver.dart       # 纯 streak 解析
├── courses/            # 字母 + 语种 loader/validator（目标 Turkish）
├── data/               # drift CourseDatabase + Seeder + Repository 实现
│   ├── course_database.dart       # schemaVersion 21（15 张 drift Table 类 + 约 17 张原生 SQL 管理表）
│   ├── anki_note_dao.dart         # Anki NoteStore 数据访问
│   ├── srs_state_dao.dart         # SRS 状态持久化
│   ├── review_history_dao.dart    # 复习历史事件
│   └── ...
├── di/                 # GetIt + Injectable（renderer_module / audio_module）
├── domain/             # 领域模型 + Repository 接口
│   ├── course/         # section/unit/lesson/stage/interaction/sub_lesson/
│   │                   # listening_phase/reading_passage/expression/grammar_point/
│   │                   # srs_word/mistake_entry/word_entry
│   ├── audio/          # VocabAudioResolver / AnkiAudioResolver 抽象
│   └── repositories/   # ICourseRepository, IStudyLogRepository
├── routing/            # Auto Route + CourseReadyGuard
├── service/            # AppPrefs / locator / TTS / 本地提醒
└── views/              # courses / dictionary / home / lesson / play / profile /
                        # review / ai / anki / anki_official / settings / theme.dart
```

### 关键模式

- **状态管理**：Provider + ChangeNotifier。Provider 既是 DI 容器也是状态广播。
- **DI**：GetIt + Injectable，`@injectable` / `@lazySingleton` 注解，`build_runner` 生成 `injection.config.dart`。
- **路由（导航合同，详见 `docs/platform-adaptive-page-transition-unification-plan.md`）**：Auto Route + 代码生成（`.gr.dart`）+ `CourseReadyGuard`（DB seed 完成前重定向到 splash）。全屏页面一律走 AutoRoute，全局 `AppRouter.defaultRouteType = RouteType.adaptive(enablePredictiveBackGesture: true)`——Android 用 Material 路由（含预测返回，manifest 已加 `enableOnBackInvokedCallback`），iOS/macOS 用真实 Cupertino 路由（边缘返回），Web 无转场。禁止：全局强制单一平台路由、`PageRouteBuilder`/`transitionsBuilder` 自定义转场、调用点直接构造 `MaterialPageRoute`/`CupertinoPageRoute`、覆盖 `ThemeData.pageTransitionsTheme`。唯一例外：`lib/routing/platform_page_route.dart` 的官方路由类选择器，仅供运行时组装、无稳定页面身份的内部页使用。底部主 Tab 是 `IndexedStack` 即时切换（非 push/pop）；Dialog/BottomSheet 保持弹层语义。以上契约由 `test/routing/routing_policy_contract_test.dart` 与 `test/routing/adaptive_route_semantics_test.dart` 在 CI 强制。
- **模型**：Freezed 不可变 + `@JsonSerializable`；Interaction 变体由 `runtimeType` 区分。
- **Repository**：接口（`domain/repositories/`）+ 实现（`data/`）；DB 作为派生缓存，JSON 为真理源。
- **渲染器插件化**：14 种 Interaction 各有 `@injectable` 渲染器，由 `di/renderer_module.dart` 收集成 `Set<InteractionRenderer>` 注册到 GetIt。分发走 `lookupRenderer()`，它先用 `_handlesTypeFor()` 把实例映射到 **freezed 公开接口类型**再匹配——**不能直接用 `runtimeType`**，因为 freezed 生成的是私有的 `_$FooImpl`，永远不等于渲染器声明的 `handlesType`。新增题型：写渲染器 → 在 module 登记 → 重跑 `build_runner`，无需改动任何分发逻辑。

---

## 4. 课程引擎

### 4.1 层级模型

```
Section -> Unit -> Lesson -> SubLesson / ListeningPhase / ReadingPassage -> Stage -> Interaction
```

全部为 Freezed 不可变类 + JSON 序列化。`Lesson.flattenedStages` 将嵌套内容展平为渲染器可遍历的 `List<Stage>`。

### 4.2 Interaction 题型（14 种）

按语言技能维度分类，均 `@injectable` 注册到 GetIt：

| 维度 | 题型 | 说明 |
|---|---|---|
| 词汇呈现 | `showWord` | 形式 + 意义 + 音频 |
| 接受性词汇 | `multipleChoice` | 识词选义 |
| 接受性词汇 | `multiSelect` | 多选 |
| 产出性词汇/句法 | `fillBlank` | 完形填空 |
| 产出性词汇/句法 | `translateSentence` | 翻译 |
| 产出性词汇/句法 | `reorderSentence` | 乱序组句 |
| 产出性词汇/句法 | `typeTheWord` | 听音拼写 |
| 听力 | `listenAndPick` | 听后选择 |
| 听力 | `listenOnly` | 纯听输入 |
| 阅读 | `readingMcq` | 篇章选择 |
| 阅读 | `readingTrueFalse` | 篇章判断 |
| 阅读 | `readingShortAnswer` | 篇章简答 |
| Anki 官方 | `ankiCard` | Flutter 渲染的官方 Anki 卡片（`allowJs=false` 的卡默认走此轨，见第 6 节） |
| Anki 保真 | `ankiHtmlCard` | 仅 Official 复习路径经 WebView 渲染原 notetype HTML；lesson 体/错题重放中的存量卡降级为占位卡（`AnkiHtmlCardRetiredRenderer`，见第 6 节） |

### 4.3 Lesson Template（6 + 1）

| 模板 | 教学定位 |
|---|---|
| **intro**（认识新词） | `showWord` 呈现形式与意义，配合简单选择题建立 form-meaning mapping。 |
| **practice**（巩固练习） | 受控语境中反复操练——填空、翻译、组句——陈述性知识向程序性技能转化。 |
| **listening**（听力训练） | `listenAndPick` / `typeTheWord` / `listenOnly`，训练自下而上语音解码。`ListeningPhase` 支持 debut→main→fin 三段式音频，可叠加 BGM。 |
| **reading**（阅读理解） | 短文 + `readingMcq` / `readingTrueFalse` / `readingShortAnswer` 三道递进题，训练自上而下篇章理解。 |
| **review**（复习） | 跨单元回顾，交错出题避免集中练习效应。 |
| **mastery**（综合测验） | 混合题型限时完成，模拟多技能并行需求。 |
| `legacy` | 兜底模板，兼容旧版课程数据。 |

### 4.4 按需加载与缓存

- `index.json` + per-section JSON + drift SQLite 缓存（**schemaVersion 21**）。
- 按内容版本号（`index.json` 的 `version`，当前 12）自动 reseed；bump version 或清空 app data 可强制 reseed。
- `expressions` 表支持表达级 SRS。

### 4.5 当前内容状态

8 个 CEFR 分级 Section（A1->B2），含 inter-section 前置依赖；**全部 8 节均已填充真实内容**——共 148 词汇 / 18 表达 / 8 语法点 / 54 课时，每节含听力与阅读练习，无占位。Section 1（A1）为问候入门（`s1-l2`：8 词 + 2 表达，3 subLessons）。完整清单见 [`docs/content_inventory_current.md`](./content_inventory_current.md)。

---

## 5. 复习系统：FSRS、记忆曲线与错题

### 5.1 FSRS 引擎

`lib/core/fsrs_engine.dart` 实现 `SrsScheduler` 接口，基于 [`fsrs`](https://pub.dev/packages/fsrs) 包。核心参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `desiredRetention` | 0.9 | 目标回忆概率，驱动下次间隔计算。 |
| `maximumIntervalDays` | 730 | 间隔硬上限（天）。 |
| `enableFuzzing` | true | 是否施加间隔抖动（预览时关闭以保证确定性）。 |
| `maxSameDayFails` | 4 | 当日失败次数达此值后将 due 推迟到次日。 |
| `parameters` | FSRS 默认 21 权重 | 可选个性化权重（见 5.2 优化器）。 |

**评分语义**：练习题用二元 pass→Good / fail→Again；导入的 Anki 卡片可传四档 Again/Hard/Good/Easy。失败路径走**当日重学阶梯**（`fsrs_relearn.dart`，10 分钟学习步 + 重学步）。

**SM-2 后备**：`lib/core/sm2.dart` 仍保留，作为可选调度器。

### 5.2 FSRS 参数优化

`lib/core/fsrs_optimizer.dart` 基于学习者的复习历史（`ReviewEvents`）拟合个性化 FSRS 权重，使调度更贴合个人遗忘曲线。

### 5.3 SRS 状态与复习历史持久化

- **`SrsStates` 表**（schema v7）：wordId PK，queue / dueAt / intervalDays / ease / reps / lapses / isLeech / type / lastReviewedAt。`SrsQueueProvider` 改为同步内存缓存 + write-through 持久化，启动时 `ensureLoaded()` 从 SQLite 水合；自带从旧 prefs blob 的一次性迁移。
- **`ReviewEvents` 表**（schema v7）：自增，cardId / queue / reviewedAt / quality / prev-next intervalDays / prev-nextEase / reps / lapses / type，带 `@TableIndex`（cardId + reviewedAt）。`reviewItem` 每次写一条 `ReviewEventRecord`。
- **`SrsWord`** 增加 `lastReviewedAt`，无需 DB join 即可算遗忘曲线。

### 5.4 记忆曲线

`MemoryCurveProvider.snapshot()` 计算：

- **currentRetention**：已复习卡片的平均保持率 R = exp(-Δt/S)。
- **forecast**：dueToday / due7Days / due30Days。
- **maturity**：new / young / mature / leech 分布。
- **retention-by-interval**：按 prevIntervalDays 分桶（[1,4,7,14,21,30,60,90,180]）的经验回忆率曲线。

`lib/views/review/components/retention_curve_chart.dart` 的 `RetentionCurveChart` 用 `fl_chart` LineChart 可视化保持率曲线，复习进度页（`review_progress_page.dart` 的 `_CurveCard`，数据经 `ReviewProgressProvider` 聚合）与 Anki 牌组统计页（`MemoryCurveProvider.snapshotForImportId`）复用；预测 dueToday / due7Days 在复习进度页以 KPI 卡展示。

### 5.5 错题本

30 条 FIFO 队列，保留原始 interaction 快照（题干、正答、用户错答）。支持重做清除与跳转对应语法点复习。

### 5.6 语法复习

Explain → Practice → Rate 三段流（见 2.4 Skill Acquisition Theory）。

### 5.7 每日挑战

从课程树随机抽取真实题项合成挑战课，实现交错练习（见 2.5）。

### 5.8 弱词复习

近 30 天内错误 ≥2 次的词汇自动汇聚为 10 题迷你 quiz，针对性检索练习。Anki 保真/MCQ 快照在弱词 quiz 中被跳过（仅 AnkiCard 结构化卡参与）。

### 5.9 Match Madness

限时单词配对小游戏，通过速度压力强化形式-意义连接自动化，降低实际交流中的认知负荷。

### 5.10 撤销与并发

`undoReview` 与在途 `reviewItem` 通过 `_gradesInFlight` 集合防竞态：评分写入期间拒绝撤销，完成后重试。

### 5.11 练习页（Play Hub，2026-08 焕新）

`lib/views/play/play_hub_screen.dart`——复习流的总入口，信息架构自上而下：

- **Playground Hero**（仅语言课程，Anki scope 下整体消失）。
- **队列按 `CourseScope` 切开**（[ADR 0037](./decisions/0037-anki-course-review-unification.md)）：语言课只显示错题 / 单词 / 语法；导入 Anki 只显示 Anki 复习（并隐藏薄弱单词）。「开始今日复习」与个人页快捷入口同一套隔离。
- **AI 助手行**：单行卡 + 引擎就绪/未配置状态 chip → AI Hub。
- **练习工具**：语言课为薄弱单词 / 词典 / 复习进度；Anki 课为词典 / 复习进度。

**长按浮窗交互契约**（`info_popup.dart` + `play_info_panels.dart`）：短按一律直接进入页面；长按在**有数据可看**的入口上生效（主卡、四个队列、薄弱单词、复习进度、AI 助手；词典与 Playground 不参与）。浮窗挂根 Overlay、锚定在被按卡片旁（下方空间不足自动翻到上方），打开 = 自锚点方向缩放 + 逐行 stagger 滑入（`easeOutBack`），关闭反向；`reducedMotion`/系统禁用动画退化为纯淡入淡出；打开触发 medium 触感（`sensoryReduce` 跳过）；卡片带 `Semantics(onLongPress)` 长按语义。**注意**：浮窗内容位于页面 Provider 树之上，面板组件一律通过构造注入数据（`PlayQueueSnapshot` / `AiEngineConfig` / `StudyStatsProvider` 实例），不得在面板 build 内做 inherited provider 查找。

---

## 6. Anki 深度集成

> **官方 Core 现状（Official Anki 迁移中）**：Android 生产新导入 / 正式复习 / 课程投影走官方 Anki Core（rslib FFI，`lib/application/anki_official/`）。生产 bundle 为 `OfficialAnkiFeatureFlags.productionAndroid`（不再用 10 个能力 dart-define 自由组合）。收口与 Legacy 退役以 [`docs/official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md) 为准；OHOS 产品支持已 EOL（[ADR 0041](./decisions/0041-ohos-product-eol.md)）。详见 [`docs/official-anki-migration/README.md`](./official-anki-migration/README.md) 与 [ADR 0036](./decisions/0036-official-anki-core-migration.md)、[ADR 0037](./decisions/0037-anki-course-review-unification.md)。

本应用可导入 Anki `.apkg` 牌组作为课程树的一个 Section。产品合同与评分口径以 [ADR 0037](./decisions/0037-anki-course-review-unification.md) 为准。

### 6.1 导入流水线

**生产（Android Official-first）**：选 `.apkg` → 一次计算 `AnkiImportExecutionPlan` → `OfficialAnkiOfficialFirstService` 写入 Official Collection → 投影课程树 → 以 `sourceId` 进入课程 scope。不写 Legacy NoteStore / Turna Anki SRS。`.colpkg` 与内存 sample 生产 fail-closed。

**执行计划三态**：`AnkiImportExecutionPlan.planFor` 只产出 `officialFirst` / `failClosed` / `unsupported`——`legacyOnly`、`allowLegacyOnly`、`AnkiImportOwner.legacy`、`AnkiImportDecision.legacy`、`LegacyAnkiImportFacade` 均已删除。

> **Legacy 解析/装配管线已物理删除（2026-08-27，doc 35 L0–L3 施工完毕）**
>
> 原先的 5 步 legacy 管线（`.apkg` 解析 → NoteStore 三表持久化 → deck 装配 → 媒体拷贝 → revlog→FSRS 迁移）连同 `anki_importer.dart`、`anki_deck_assembler.dart`、`anki_srs_migrator.dart` 已全部删除，`lib/application/anki/` 目录清空（guard test 有终态断言）。连带删除：智能组织、Notetype 映射编辑器、Full/Lite 装配、`{{type:}}` 输入桥。迁移细节与差异实录见 [`official-anki-migration/35-duplicate-legacy-layer-cleanup-plan.md`](./official-anki-migration/35-duplicate-legacy-layer-cleanup-plan.md) §10。
>
> **存量数据（仍需注意）**：DB 里旧导入的 lesson 体与错题快照仍携带已删类型。`AnkiHtmlCard` 因此保留类型本体，在 lesson body / 错题重放中由 `anki_html_card_retired_renderer` 降级为「确认即过」占位卡（指向「设置 → 旧版与兼容性」），避免 `lookupRenderer` 对未注册类型抛 `StateError`。注意它**不是**保真渲染——官方保真复习仍活跃，见 §6.3。

### 6.2 智能组织 / Notetype 映射 / Full-Lite 模式（均已随 legacy 层删除）

以下三项均为 legacy 装配管线的配套能力，**已随 doc 35 L1 一并删除**，此处仅作历史记录，勿再按此实现：

- **智能组织**：`AnkiOrganizationResolver` 从 notetype 字段名/标签抽取 unit/lesson 键，配合 `assemble(smartGrouping:)` 分卡。类已 0 引用。
- **Notetype 映射编辑器**：把 note 映射为 9 种结构化类型（含 `_NotetypeMappingEditor` 与 `AnkiNotetypeAI.identifyAll`）。**替代实现**：官方映射页 `views/anki_official/official_anki_mapping_page.dart`，用自有 `OfficialAnkiMappingSuggestion` 体系，不依赖旧 `NotetypeMapping`。
- **Full / Lite 模式**：按牌组规模（`liteThreshold` 默认 2000）选择完整课程树或 shell Section。装配器已删；`anki.liteThreshold` 设置键、旧版页滑块与备份清单条目亦已删除（旧备份中该键按 unknownKey 跳过）。

### 6.3 保真渲染（Fidelity HTML）

复杂 notetype（含自定义 HTML/CSS/JS）无法干净映射为结构化题型时走保真路径，以 `AnkiHtmlCard` Interaction 承载原 notetype HTML。

> **现状澄清（doc 35 L2 后）**：`AnkiRenderPolicy` 与 NoteStore 侧的逐卡 `render_mode` 判定已随 legacy 层删除。保真渲染**仅服务于 Official 复习路径**，调用链为：
> `official_formal_review_coordinator` → `application/study_session/anki_review_content.dart`（`fidelityInteractions: Map<String, AnkiHtmlCard>`）→ `views/review/components/official_template_webview_body.dart` → `AnkiHtmlCardView`。
> 与之区分：lesson body / 错题重放中的 `AnkiHtmlCard` 走 §6.1 所述的 retired 降级卡，**不**渲染 HTML。

- `AnkiHtmlCardView`（`webview_flutter`，唯一 WebView 使用点）渲染原 notetype HTML + CSS，模板 `{{field}}` 替换、cloze 挖空。
- **平台门控**：仅 Android/iOS 有 WebView 实现；桌面/Web 降级为文本兜底（决策 4），不实例化 `WebViewController`。
- **暗色 CSS**：app 暗色主题时注入暗色 CSS（阶段 6）。
- **JS 与网络隔离**：notetype `allowJs` 默认关；联网默认完全离线。离线/询问策略通过 CSP 实际阻断 `fetch`、XHR、WebSocket 和外部资源，不只拦页面跳转。

### 6.4 智能去解密（Pre-render Cache）—— 已放弃

部分牌组（如加密考研牌组）曾在 notetype CSS 中含混淆的解密 JS。原设计：首次复习时 `AnkiHtmlCardView` 在 WebView 中跑一次 JS，延迟捕获 `document.body.innerHTML`，去 `<script>`，缓存到 `anki_prerendered_html`（schema v10）；后续复习直接服缓存纯 HTML。

> 该路径已于 schema v22 `DROP TABLE IF EXISTS anki_prerendered_html` 收口（writer 随 doc 35 Legacy 层删除后表保证为空）。DAO `prerendered()` / `upsertPrerenderedFace`、存储清单统计、旧版页「智能去解密 / 抓取延时」文案均已删除。不接回 `onCaptured`。加密牌组若需脚本，走官方保真 WebView + `ankiForceDisableJs`。

高级页提供渲染/网络与单牌组覆盖、失败降级、媒体与导入性能、三种排程继承、同胞卡与难卡规则、FSRS 实验室、存储维护、脱敏报告和实验功能中心。系统健康监控在启动时直接监听 `LogCapture`，用指纹、60 秒去重和分数阈值生成本机告警；详见 [`advanced-settings-system-health.md`](advanced-settings-system-health.md)。

### 6.5 复习入口与浏览

- **复习**：`FormalReviewLauncher` → 共享 `AnkiReviewSessionRoute`。正式资格 = 官方到期搜索（`did:<deck> (is:due OR is:learn OR is:new)`，分页，不受复习队列 100 张上限约束）∩ placement ∩ **已解锁** ∩ 未暂停/搁置/退役。已解锁 = **该投影 Lesson 已完成**，或导入历史 `reps ≥ 1`。第一遍课内只解锁、不写官方 scheduler、不记错题本；新卡第一次 Again/Good 发生在 Anki 复习。第一遍下课对该课所在牌组抬高**当天**新卡名额（`ENSURE_TODAY_NEW_QUOTA` / `extend_new`），使剩余 ≥ 本课张数，不改牌组 `new_per_day` 预设。**重做已完成课**在下课 flush 官方 Again/Good（`ANSWER_AHEAD_CARDS` 临时 filtered deck）；今日已 `rated:1` 的卡跳过；flush 失败在完成摘要中可见。Official 不可用 fail-closed，不降级 Turna SRS。**无 Official 源时不再有 Legacy assembler 兜底**：`formal_review_source_coordinator.fromCatalog` 直接跳过 legacy-only 源，recorded-legacy 源进入页面后显示 `FormalReviewLauncher.failClosedMessage` 错误面，不静默换语义。
- **卡片浏览器 / 牌组统计**：Official 源有 engine 时读 Collection / scheduler；无 engine 时 catalog 回退，stats 不得把 catalog 总数标成已证明。
- **示例牌组**：内存 sample 生产 fail-closed；入口已从导入页与课程管理隐藏。`startWithSample` 仅测试 haemostasis。

### 6.6 已延期（二期/远期）

错题快照瘦身（存 noteId 引用而非全 HTML）、WebView 池化。（官方 FFI 后端已由 ADR 0036 落地，见第 6 节开头。OHOS 产品支持已退役，不再评估 OHOS WebView。）`{{type:}}` 输入桥（`anki_type_answer.dart`）已随 doc 35 L1 删除，不再作为已交付项列出。

---

## 7. AI 引擎层与 AI 功能

### 7.1 统一 AI 引擎层

`lib/application/ai/engine/` 是全应用唯一的 LLM 流量出入口，从 `tool/gui/src/backend/ai/` 移植并重构。文件：

| 文件 | 职责 |
|---|---|
| `ai_engine.dart` | `@lazySingleton` facade：`chat()` + `requestJson()` + 缓存接线 |
| `ai_engine_config.dart` | `AiEngineConfig`：双模型（modelChat / modelJson）+ `StrictSchemaMode` + reasoning 支持 |
| `ai_engine_config_holder.dart` | `@lazySingleton ChangeNotifier`，单一配置真理源，**持久化到本地**（配置含 API key 序列化到 `StreamingSharedPreferences`，设备上为明文、用户显式选择；写入绕过日志） |
| `ai_http_client.dart` | `postJson` / `postStream` / `probeConnection`；json_schema→json_object 自动回退；`AiCancelToken` 协作式取消 |
| `ai_cache.dart` | SHA-256 LRU + 磁盘镜像（条件编译 web/io）；key 不含 API key |
| `ai_provider_preset.dart` | 预设：deepseek（默认 `deepseek-v4-flash`）/ openai / moonshot / ollama / custom |
| `ai_recent_tasks_provider.dart` | 最近任务环（max 20，FIFO），AI Hub Continue 区数据源 |

**设计要点**：引擎领域无关（只暴露 `chat` + `requestJson`），领域方法、prompt 构建、`parseCompletion` 留在 `AiCourseService` 以避免 engine↔service 循环依赖。所有 5 个 AI provider + Anki 直调 `AiEngine`（流式 + 取消 + 缓存），绕过旧 shim。

### 7.2 AI Hub

`lib/views/ai/ai_hub_page.dart`——集中 AI 入口（从 Play Hub 进入），四区：

- **Hero**：preset / modelChat / modelJson / 脱敏 key 芯片 + 重新配置按钮 + 配置不完整告警。
- **Continue**：最近 3 个任务（`AiRecentTasksProvider`），空态提示，点击跳转对应路由。
- **Start**：5 个入口——许愿生成 / 教材导入 / 据错题导师 / 据弱词导师 / 深度讲解（带上下文门控）。
- **Tools**：测试连接（`probeConnection` + 延时）/ 清缓存 / 查看 API 配置。

### 7.3 AI 功能清单

| 功能 | 入口 | 说明 |
|---|---|---|
| **AI 提示助手** | 课程内聊天面板 | 按当前题目上下文提供提示与解释。 |
| **深度讲解** | 课程内 sheet / AI Hub | 4 种 genre：语法讲解 / 近义词辨析 / 句子拆解 / 错因分析（`hint_genres.dart`，typed 解析 + 容错 fromJson）。 |
| **SRS 导师** | 课程内 sheet / AI Hub | 据错题 + 弱词 + 近期复习构建 prompt，AI 生成复习课并写入课程树（`srs_tutor_provider.dart`）。 |
| **许愿生成** | `AiWishChatPage` / AI Hub | 多轮对话对齐需求 + 附件 → "滑动确认"生成 section JSON + 通俗解释。Genre 标签批量生成多种模板。 |
| **教材导入** | `TextbookImportRoute` / AI Hub | 从 PDF/Word/图片/文本提取词汇/表达/语法点，多阶段向导导入课程树。 |
| **课程生成** | AI Hub | 普通/许愿模式；`ai_fixer` 生成后自动修复 id 冲突/引用断裂/schema 不符。 |
| **Lesson 助手** | 课程内 | `AiLessonHelperProvider`。 |

> 注：旧的实验性页面 `AiCourseGeneratorPage` 已删除；课程生成现经许愿聊天页 + AI Hub。

### 7.4 安全姿态

- API key/base URL/model 可持久化到本地（用户可选）；写入绕过日志避免泄密。
- 「不保存到本地」横幅在配置页提示安全立场。
- 附件用临时文件。

---

## 8. 音频、TTS 与智能朗读

### 8.1 AudioController

`lib/application/audio_controller.dart` 统一接管 TTS（`flutter_tts`，语言码 `tr`）与音效。`speak` / `speakWithResult` 支持可选 `languageCode`：null 用目标语（保持原行为），非 null 用指定语言，解析失败回退目标语。`AccessibilityProvider` 注入：`sensoryReduce` 开时音效/触觉反馈早退。

### 8.2 智能朗读（Smart Speech）

`lib/core/language_detector.dart`（纯逻辑）按脚本检测返回 BCP-47 基础码：

| 脚本 | 语言 |
|---|---|
| Han | zh |
| Kana | ja |
| Hangul | ko |
| Cyrillic | ru |
| Arabic | ar |
| Thai | th |
| Devanagari | hi |
| Greek | el |
| Hebrew | he |
| Turkish 特有字符（ğ ı ş İ；ç ö ü 不算，因法德共用） | tr |
| 纯 Latin | per-course native 回退 |

`inferOptionLanguage` / `detectOption` 用 prompt 方向推断 MCQ 选项语言（解决 "merhaba" 这类无变音符土耳其词的歧义）；`detectCardPair` 用 Anki 正反面之一的土耳其信号推断另一面。`lib/core/html_stripper.dart` 在朗读 Anki HTML 卡片前去标签。`smart_speech.dart`（`currentSpeechLanguages` / `detectSpeakLanguage` / `autoReadOnTapForActiveCourse`）封装策略，getIt + 失败回退 tr/en。

### 8.3 每课程设置

`settings_provider.dart` + `LocalStateKeys`：`autoReadOnTapFor(scope)`（默认 true）/ `nativeLanguageCodeFor(scope)`（默认 'en'），key 编码 courseScope。Course 管理页每课程行有齿轮 → 底部 sheet（自动朗读 Switch + 母语语言 Dropdown 14 项）。

### 8.4 接线点

- MCQ 选项 tap（受 toggle 控制按推断语言朗读）。
- Anki 翻牌（卡出现读正面、翻开读背面，受 toggle 控制 + 每面手动朗读钮）。
- 词典自由文本（`detectSpeakLanguage`）。
- 已知目标语调用点（vocab term / 听力 transcript / ShowWord / SRS term）走 `speak`（target）不变。

### 8.5 离线 TTS

系统/Google TTS（`tr`），Android 优先 `com.google.android.tts`。Piper Swahili 模型 + `sherpa_onnx` 已移除。预录 `audioAsset` 预留给听力练习。

---

## 9. 主题与可访问性

### 9.1 TurnaTheme

`lib/views/theme.dart` 提供 `lightTheme` / `darkTheme` / `highContrastLightTheme` / `highContrastDarkTheme`，及一组按 `Brightness` 自适应的语义化颜色 helper（`cardBg` / `scaffoldBg` / `textHintColor` / `inputFillColor` / `bottomNavBg` / `glassSurface` 等）。Play Hub 用轻量 `SoftCard`（`TurnaTheme.softTint` / `softBorder`，毛玻璃栈已移除）。

调色板（Turna「湿地鹤」ADR 0033 方案 A — 主色锁 `#1F727E`；无 peacock API）：

```dart
const brandNavy      = Color(0xFF19324A);
const primaryColor   = Color(0xFF1F727E);  // Brand Teal (locked)
const primaryLight   = Color(0xFF2F7F8E);
const primaryDark    = Color(0xFF145A64);  // brandTealDark ≡ GUI BRAND_TEAL_DARK
const brandSky       = Color(0xFF4A95A8);
const brandReed      = Color(0xFF5FB8C4);
const secondary      = Color(0xFFB85C3F);  // anatolianClay — warm accent only
const secondaryLight = Color(0xFFEAD9B8);  // warmSand
const error   = Color(0xFFE74C3C);
const success = Color(0xFFFFD93D);
const warning = Color(0xFFFF9F43);
```

主 CTA 渐变：`brandTeal → brandTealLight`（关键路径用 `TurnaTheme.primaryCtaDecoration`）。Clay 用于完成/完美角标、成就向指标、About 品牌条、Play Hub 至多一处次要 soft tint。**角色边界：** success 黄=答题反馈；clay=进度/成就；streak 橙=连胜 chip（不同控件）；高对比 secondary 可偏离 clay。**Android 状态栏/导航栏** 对齐 AppBar 表面（非 teal 铺条）：`colors.xml` + `TurnaTheme.systemUiOverlayFor`。真源：`lib/views/theme.dart` 与 `tool/gui/src/theme_tokens.py`（ADR 0033）。

`ThemeProvider`（`light / dark / system`）持久化到 `StreamingSharedPreferences`，Profile 页可切换。

### 9.2 AccessibilityProvider

`lib/application/accessibility_provider.dart`，6 项持久化偏好：

| 偏好 | 作用 |
|---|---|
| `textScale` | 文本缩放 100–200% |
| `reducedMotion` | 减少动画（`MediaQuery` disableAnimations） |
| `highContrast` | 切换高对比主题（纯黑白表面 + 强边框 + 最大对比文本） |
| `dyslexiaFont` | 文本主题换 Lexend 字体 |
| `sensoryReduce` | 静音音效与触觉反馈 |
| `focusMode` | 关闭 splash 旋转图计时器等分心元素 |

`app.dart` 的 `_AppShell` 监听 ThemeProvider + AccessibilityProvider，选 light/dark/high-contrast 变体，注入根 `MediaQuery` 覆盖（textScaler + accessibleNavigation）。Settings 7 大类（Account / Learning / Audio & Haptics / Accessibility / AI Tools / Data / About）。

---

## 10. 平台与构建

### 10.1 支持平台

| 平台 | 状态 | 备注 |
|---|---|---|
| **Android** | ✅ 主力 | 发布产物 APK/AAB；Anki Official Core 首发平台。 |
| **iOS** | ✅ 应用保留 | WebView 保真可用；Anki Official Core 暂不承诺。 |
| **Web** | ⚠️ 有限 | 无 WebView 保真（文本兜底）；`build_release.py --skip-web` 可跳过。 |
| **HarmonyOS (OHOS)** | ❌ EOL | 产品支持已退役（[ADR 0041](./decisions/0041-ohos-product-eol.md)）；数据出口见 `turna-migration-v1`。 |

### 10.2 官方 Flutter / Android

本项目使用**官方 Flutter SDK**（非 OpenHarmony fork）。Android 构建需 **JDK 17**。详见 [`docs/android-build-setup.md`](./android-build-setup.md)。

### 10.3 构建命令

```bash
flutter pub get        # 生成代码已提交，无需 build_runner
flutter run            # 运行

# 修改 @freezed / @JsonSerializable / @AutoRoute / @injectable 后才需重新生成
flutter pub run build_runner build --delete-conflicting-outputs   # 或 make gen

# 发布（APK/AAB/可选 web + 内容清单）
python tool/build_release.py --version 0.4.0-future4
# 或
make build-release VERSION=0.4.0-future4
```

### 10.4 Makefile

```bash
make gen                # 生成代码
make test               # Dart 测试
make test-python        # Python 工具测试
make analyze            # 静态分析
make ci                 # analyze + test + test-python + build-release-smoke
```

环境要求：官方 Flutter SDK `>=3.2.3 <4.0.0` + JDK 17（Android）。

---

## 11. GUI 课程编辑器（作者工具）

位于 [`tool/gui/`](../tool/gui/)，基于 **PySide6**，复用 `tool/course_cli.py` 校验/归一化逻辑。JSON 仍是唯一真理源。运行：`pip install PySide6 && python tool/gui/src/main.py`。

### 11.1 定位与视图

- 打开 `assets/courses/<lang>/` 目录，三栏树（Section → Unit → Lesson）+ 右侧 detail 面板。detail 按 lesson `template` 切换可用字段，非法结构在 UI 层不可构造。
- **教师视图**：线性三层次（课 → 环节 → 步骤 → 题目），含 `LessonWizard`、`QuestionCards`、`TemplateEditors`、`VocabTable`、`ErrorMapper`、`LessonBlueprint`（卡片流蓝图，只读预览 + 命令化就地编辑）。
- **传统视图**：`CourseTree` + `LessonEditor` + `ResourceEditor` + `DetailPanel`。

### 11.2 教材导入（Textbook Import）

从外部教材（PDF/Word/图片/文本）提取语言教学内容，多阶段向导：

1. **选材**：拖入文件，自动识别类型抽文本（PDF PyPDF2 / Word python-docx / 图片 base64 入 vision API）。
2. **提取**：AI 逐章识别词汇/表达/语法点/对话/练习，`KnowledgeExtractor` 按 `KnowledgeSchema` 产出结构化条目。
3. **合并**：`KnowledgeMerger` 跨章节去重合并，处理多次出现、释义冲突、例句归并。
4. **预览**：`BulkImportPreviewPanel` 逐条确认/编辑/排除，按资源类型分 tab。
5. **导入**：写入 `vocab.json` / `expressions.json` / `grammar_points.json` 并生成 lesson。

配套：`extraction_quality.py`（提取质量控制）、`import_strategy.py`（保守/激进/交互式三策略）、`textbook_presets.py`（教材预设）、`markdown_chopper.py`（大文件分段 + 断点续传）、项目持久化到 `tool/var/textbooks/`（支持中断恢复）。

### 11.3 Workshop 窗口

独立于课程树的 **Workshop 窗口**（`workshop_window.py`），与 App Shell 松耦合，共享项目上下文。集中管理批量操作：教材导入任务列表、AI 批量生成队列、跨 section 内容迁移、操作日志。支持多任务并行，后台执行不阻塞主编辑器。

### 11.4 AI 生成引擎（GUI 端）

| 模块 | 职责 |
|---|---|
| `ai_generator.py` | 普通模式 + 许愿模式生成调度 |
| `ai_stream.py` | SSE 流式响应处理 |
| `ai_fixer.py` | 生成后自动修复：id 冲突、引用断裂、schema 不符 |
| `ai_prompt_library.py` | 可复用 prompt 模板库 |
| `ai_genre.py` | Genre 标签映射，多模板批量生成编排 |
| `ai_usage.py` | Token 用量追踪 |

支持普通模式（表单 → 生成 → 预览 → 导入）、许愿模式（多轮对话 + 附件 → 生成 + 解释）、Genre 批量生成（`[intro]`/`[practice]`/`[listening]`/`[reading]`/`[review]`/`[mastery]` 标签）、流式输出 + 中途取消、自动修复。

### 11.5 护栏

| 护栏 | 实现 |
|---|---|
| id 全局唯一 | id 只读；rename 只改 name；validate 兜底查重；导入冲突弹窗 |
| scale ceiling | `MAX_UNITS_PER_SECTION=60` / `MAX_LESSONS_PER_UNIT=40` |
| 引用完整性 | `wordId`/`expressionId`/`grammarPointId` 从已加载资源下拉选 |
| 保存前校验 | `validate --format json` 失败 → 禁用保存 + 高亮问题节点 |
| 密钥不落盘 | API key/base URL/model 仅存内存；附件用临时文件 |

### 11.6 打包与测试

```bash
pip install pyinstaller
python tool/gui/build_gui.py              # onefile -> dist/turna-gui.exe
python tool/gui/build_gui.py --onedir

python -m pytest tool/gui/tests/                 # GUI 单元测试
python -m pytest test/tool/gui_round_trip_test.py  # GUI ↔ CLI round-trip
```

---

## 12. 听力音频生成流水线

`listening` template 的 `listeningPhases[].audioAsset` 指向预生成 MP3。两步流水线离线生成，不在运行时调云端 TTS。

### 12.1 第一步：TTS 合成

[`tool/generate_audio.py`](../tool/generate_audio.py) 调 **MiniMax T2A v2 REST API** 批量合成。

```bash
export MINIMAX_API_KEY="sk-..."
export MINIMAX_GROUP_ID="..."        # 部分账号需要

python tool/generate_audio.py all                        # 全部 listening 资产
python tool/generate_audio.py all --voice-id male-qn-jingying --speed 0.9
python tool/generate_audio.py speak "Merhaba, nasılsın?" out.mp3
python tool/generate_audio.py all --force                 # 强制重生成
```

### 12.2 第二步：混音

[`tool/mix_listening_a1.py`](../tool/mix_listening_a1.py) 用 **pydub** 混音（需 ffmpeg）。

```bash
pip install pydub
python tool/mix_listening_a1.py all \
    --main-dir  assets/sounds/turkish/listening/raw_a1 \
    --debut-dir assets/sounds/turkish/listening/debut \
    --fin-dir   assets/sounds/turkish/listening/fin \
    --bgm-dir   assets/sounds/turkish/listening/bgm \
    --mapping   tool/mappings/a1_show_mapping.csv \
    --output-dir assets/sounds/turkish/listening/mixed_a1
```

混音结构：`debut + [主内容 + BGM(降 18dB)] + fin`，结尾 BGM 淡出 800ms。每节课映射到 A/B/C variant（不同 debut/fin/bgm 组合），CSV mapping 指定；未映射默认 A。

### 12.3 人工录音替换

人工录音可替换 TTS 文件，规范见 [`docs/audio-recording-guidelines.md`](./audio-recording-guidelines.md)。文件名与 `audioAsset` 一致，放入 `assets/sounds/turkish/listening/`。

### 12.4 资产清单校验

```bash
python tool/course_cli.py audio-manifest --output manifest.csv
```

---

## 13. 课程数据格式与 Authoring

JSON 位于 `assets/courses/turkish/`，由 `CourseLoader` 加载、`DatabaseSeeder` seed 到 SQLite。最小 `index.json`：

```json
{
  "version": 12,
  "language": "tr",
  "displayName": "Turkish",
  "sections": [
    { "id": "section1", "name": "Section 1", "level": "A1",
      "prerequisiteSectionIds": [], "file": "sections/section1.json" }
  ]
}
```

每个 section 含 `units -> lessons -> content`（stages / subLessons / listeningPhases / readingPassage）。Interaction 变体由 `runtimeType` 区分。完整 authoring 契约见：

- [`docs/authoring/course-layout.md`](./authoring/course-layout.md)
- [`docs/authoring/lesson-type-templates.md`](./authoring/lesson-type-templates.md)
- [`docs/authoring/listening-show-format.md`](./authoring/listening-show-format.md)
- [`docs/authoring/textbook-import.md`](./authoring/textbook-import.md)
- [`docs/authoring/teacher-guide.md`](./authoring/teacher-guide.md)

---

## 14. 测试与质量基线

```bash
flutter test --exclude-tags golden           # 1852 passed / 0 failed（最新数字见 test/BASELINE.md）
python -m unittest discover -s test -p "*_test.py"            # Python 工具测试
python -m unittest discover -s tool/gui/tests -p "test_*.py"  # GUI 1276 项（上次记录）
```

- `flutter analyze`：改动文件 0 error / 0 warning（仅历史 info 级 lint）。
- `tool/course_cli.py --course-dir assets/courses/turkish validate` 通过。
- 2 个历史环境敏感测试（`anki_review_fidelity_test` 缺 path_provider mock；一个 `anki_note_dao_test` 在并发 `ensureSqliteLibForTestHost` 下偶发）隔离运行可通过。
- 最新基线与各轮改动记录见 [`test/BASELINE.md`](../test/BASELINE.md)。

---

## 15. 已明确不做（含教学法依据）

以下"游戏化"机制的移除是经过考量的教学法决策：

- ❌ **League / 天梯 / 好友 / 排行榜 / 分享**。社会比较虽短期能提升参与度，但对语言习得的内在动机存在抑制作用（Deci & Ryan, 1985 自我决定理论）。本项目选择内容驱动而非竞争驱动。
- ❌ **Hearts / Streak Repair / 商店道具**。惩罚机制（答错扣心）与"失败恐惧"相关，可能导致学习者回避高难度内容——而高难度内容恰是 i+1 原则所要求的习得关键区间。
- ❌ **Speaking 录音匹配**。自动语音评分在非主流语种（含 Turkish）上可靠性与效度不足，且本项目以 TTS + 听力路径覆盖语音输入训练。
- ❌ **云端 CMS / Firebase / 推送通知**。本地优先架构保证离线可用性与数据隐私，避免服务端依赖的持续维护成本。
- ❌ **GUI 替代 JSON 作为真理源**。GUI 是 JSON 的可视化前端，JSON 始终是唯一权威存储，确保可版本化、可 diff、可脚本批处理。
- ❌ **XP 倍率 / 每日 XP 目标 / 宝石购买 / 道具 / 社交成就**。同上，去除摩擦与 monetization。

---

## 16. 文档索引

| 文档 | 说明 |
|---|---|
| [`README.md`](../README.md) | 项目概览与快速上手 |
| [`CLAUDE.md`](../CLAUDE.md) | AI Agent 架构总览 |
| [`docs/content_inventory_current.md`](./content_inventory_current.md) | Turkish 内容清单 |
| [`docs/ai_companion_implementation.md`](./ai_companion_implementation.md) | AI companion 实现边界 |
| [`docs/advanced-settings-system-health.md`](./advanced-settings-system-health.md) | 高级设置与系统健康 |
| [`docs/decisions/`](./decisions/) | 架构决策记录（ADR 0030–0041） |
| [`docs/official-anki-migration/`](./official-anki-migration/README.md) | 官方 Anki Core 迁移文档索引；活跃收口入口为 doc 34 |
| [`docs/android-build-setup.md`](./android-build-setup.md) | Android / 官方 Flutter 构建配置 |
| [`docs/analysis/project-framework-analysis.md`](./analysis/project-framework-analysis.md) | 项目框架分析 |
| [`docs/authoring/`](./authoring/) | Authoring 契约与教师指南 |
| [`docs/audio-recording-guidelines.md`](./audio-recording-guidelines.md) | 人工录音提交规范 |
| [`test/BASELINE.md`](../test/BASELINE.md) | 测试基线与改动记录 |

---

## 17. 下一轮计划与致谢

### 下一轮

- **内容深化**：全部 8 节已填充真实内容（148 词 / 18 表达 / 8 语法点）；后续按以下优先级持续扩充深度与覆盖度：
  1. **高频词汇优先**：以 Turkish National Corpus 词频数据为指导，优先覆盖前 2000 词族（覆盖日常文本约 85%）。
  2. **语法渐进**：A1 集中于现在时、格标记（主/宾/与/属/方位/离格）、简单句；A2 引入过去时与将来时；B1 引入关系从句与名物化；B2 涉及语篇衔接与语体变化。
  3. **语用真实性**：表达与对话应反映目标语真实使用场景（如 `Buyurun` 的多重语用功能），避免翻译腔。
- **Anki 生产收口**：按 [doc 34](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md) §1.1a。W0–W7 路径已接线；下一刀是向导再瘦、W8 真实用户库 owner 切换、真机观察与 W9 分波物理删除（HOLD 已于 2026-08-27 由负责人决策解除）。不得写「迁移完成」。
- **已交付计划的遗留尾项**（来源：Plan 1 / Plan 2+3 两轮已压缩为 stub，正文在 Git 历史）：
  1. 真机性能基线：Android 中低端机型 + profile 构建，采 Plan 2+3 §24 性能预算的 before 数据；
  2. 宝石 UI 钱包快照（`LocalStateKeys.gems`）到 `GemLedgerDao` 账本投影的完全切换；
  3. WebView 渲染真机矩阵（6 设备形态 × 11 卡型），随 doc 34 真机会话执行（[34-remaining §18.3 第 7 项](./official-anki-migration/34-remaining-construction-plan.md)）。
- 活跃施工计划（未交付，勿删）：[Playground P2–P4](./language-playground-implementation-plan.md)、[GUI 与 App Schema 对齐](./tool-gui-app-schema-sync-plan.md)。
- 持续完善可访问性与统计指标。

### 致谢

- 原始框架：[Turna](https://github.com/rshrc/Varnamala) — Section/Unit/Lesson 树 + Provider + Drift + Freezed + auto_route 骨架。
- 复习算法：[fsrs](https://pub.dev/packages/fsrs)（FSRS）、SM-2（SuperMemo 2）。
- TTS：[flutter_tts](https://pub.dev/packages/flutter_tts)。
- 持久化：[drift](https://pub.dev/packages/drift) + [streaming_shared_preferences](https://pub.dev/packages/streaming_shared_preferences)。
- DI / 路由：[get_it](https://pub.dev/packages/get_it) + [injectable](https://pub.dev/packages/injectable) + [auto_route](https://pub.dev/packages/auto_route)。
- Anki 保真：[webview_flutter](https://pub.dev/packages/webview_flutter)。

### License

见 [`LICENSE`](../LICENSE)。
