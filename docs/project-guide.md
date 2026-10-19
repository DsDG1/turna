# Turna 项目指南（详尽版）

> README 给概览和快速上手，本文给每个子系统的设计、实现要点与决策依据。阅读顺序建议：先读 README，再按需查本文对应章节。
>
> **本文只写还在的代码。** 已经删掉或被取代的实现不占篇幅；要看它们当初怎么做的，去 Git 历史。状态数字（schema 版本、测试计数）一律现场查证，不写死在本文：schema 版本看 `lib/data/course_database.dart` 的 `kSchemaVersion`，内容版本看 `assets/courses/turkish/index.json` 的 `version`，测试计数看 `test/BASELINE.md` 顶条。
>
> **本文是架构与设计叙述的真源**，但**不覆盖**另外两类文档：[`AGENTS.md`](../AGENTS.md) 回答「改什么落在哪、必须怎么做、绝对不许怎么做」（行为规范），[`docs/official-anki-migration/34-cutover-receipt.md`](./official-anki-migration/34-cutover-receipt.md) 是 Anki 内核迁移的唯一状态真源。

## 现状速览

| 子系统 | 状态 | 主要代码位置 |
|---|---|---|
| 课程内容 | 8 节（ A1→B2 ）全部真实内容 | `assets/courses/turkish/`、`lib/courses/` |
| 复习调度 | FSRS 在用，SM-2 保留为后备 | `lib/core/fsrs_engine.dart` |
| 错题本 / 弱词 / 每日挑战 / 记忆曲线 | 全部在用 | `lib/application/*_provider.dart` |
| Anki 内核 | 官方内核（Rust/rslib）已接入 Android、iOS、鸿蒙伴生版 | `lib/application/anki_official/`、`native/turna_anki_core/` |
| AI 能力 | 统一引擎层在用（聊天 / JSON 请求 / 缓存 / 取消） | `lib/application/ai/engine/` |
| 语音 | 系统 TTS + 预录音频，智能朗读按语言猜测 | `lib/application/audio_controller.dart` |
| 主题 / 无障碍 | 4 套主题 + 6 项无障碍偏好 | `lib/core/theme.dart`、`lib/application/accessibility_provider.dart` |
| 课程编辑器 | PySide6 桌面工具，独立工程 | `tool/gui/` |
| 鸿蒙 | 伴生轻量版，不进主交付 | `ohos/` |

---

## 目录

1. [项目定位与设计哲学](#1-项目定位与设计哲学)
2. [教学与二语习得基础](#2-教学与二语习得基础)
3. [架构总览](#3-架构总览)
4. [课程引擎](#4-课程引擎)
5. [复习系统：FSRS、记忆曲线与错题](#5-复习系统fsrs-记忆曲线与错题)
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

**Turna** 是一个本地优先、离线的语言学习应用，当前目标语是 **土耳其语（Turkish）**。骨架来自开源项目 [Varnamala](https://github.com/rshrc/Varnamala)，本仓库在它之上做三件事：

- **把复习做准**：用 **FSRS**（Free Spaced Repetition Scheduler）替代 SM-2，加记忆曲线可视化和复习历史持久化。
- **接上 Anki 生态**：`.apkg` 牌组直接导入，用 Anki 官方的排期内核排期和评分，牌组同时投影成课程目录。
- **把 AI 收成一层**：所有大模型调用走同一个引擎层（流式、缓存、取消、结构化输出），入口集中在 AI Hub。

### 设计原则

| 原则 | 含义 |
|---|---|
| **本地优先** | SQLite（drift）存数据，没有云后端、没有推送、没有登录；离线可用性和数据隐私优先。 |
| **单人离线** | 没有好友、排行榜、联赛这类社交设计，也没有活力值和内购（宝石只能靠学习赚，不能买）。 |
| **JSON 是真理源** | 课程内容是 JSON，可版本化、可 diff、可脚本批处理；桌面编辑器只是 JSON 的可视化前端。 |
| **数据库是派生缓存** | 首次启动从包内 JSON 播种进 `course.db`，之后复用；内容版本号变了就重新播种。 |
| **教学法驱动** | 功能取舍以二语习得研究为依据（见第 2 节），不是单纯图省事。 |

### 目标用户与使用场景

| 维度 | 描述 |
|---|---|
| **核心用户** | 自学土耳其语（或后续扩展语言）的成人 / 青年学习者，偏好无干扰、离线可用的移动学习。 |
| **使用场景** | 通勤、睡前 10–15 分钟的碎片化学习；靠连续学习和成就维持动力。 |
| **用户痛点** | 不想注册账号、反感广告和内购与体力系统、需要听力输入和错题复习、希望导入自有的 Anki 牌组。 |
| **价值主张** | "打开即学，学完即走，离线也能保持进度；能导入 Anki 牌组，也能让 AI 帮着生成内容。" |

### 已知取舍

- **优势**：体验干净、没有付费压力、留存不依赖「错失恐惧」；适合教育公益、隐私敏感和不想折腾账号的用户。
- **劣势**：没有社交激励、没有订阅变现、不能跨设备同步，对「成就驱动型」用户吸引力有限。
- **如果要商业化**，需要补上其中几件：云同步 + 账号、付费课程包或订阅、家庭 / 教师账户；或者保持免费，靠课程授权或内容合作变现。

> 本仓库不是上游官方版本，纯原版功能请访问 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)。

---

## 2. 教学与二语习得基础

课程设计和复习机制建立在二语习得（SLA）与认知心理学之上。下面是贯穿全局的核心概念，以及本项目对应的工程实现。

### 2.1 可理解输入与 i+1 原则

Stephen Krashen 的**输入假说**认为，语言习得发生在学习者接触到略高于当前水平的**可理解输入**（comprehensible input）时，即 "i+1"，i 是当前水平。本项目的 CEFR 分级课程（ A1→B2 ）和课程之间的前置依赖就是这条原则的工程化：要在 A1 达到一定掌握程度，才能解锁 A2。

### 2.2 间隔重复与遗忘曲线

Hermann Ebbinghaus（1885）描述了**遗忘曲线**：新记忆形成后迅速衰减，但每次**主动回想**都能显著减缓衰减。**间隔重复**把复习安排在遗忘临界点附近，用最少的复习次数换来最长的记忆保持（Nation, 2013）。

本项目的复习引擎用 **FSRS**（见第 5 节），以**目标保持率**（desired retention，默认 0.9）驱动下次间隔计算，比传统 SM-2 更贴近真实遗忘曲线。SM-2 作为后备调度器保留在 `lib/core/sm2.dart`。

### 2.3 检索练习与测试效应

**测试效应**（testing effect）：相对被动重读，主动从记忆里提取信息（"自我测试"）能显著增强长期保持（Roediger & Karpicke, 2006）。本项目的填空、翻译、听写、选择题本质上都是不同形式的检索练习，不是单纯的"考核"。

### 2.4 技能习得理论

**技能习得理论**（DeKeyser, 2007）描述了从**陈述性知识**（"知道规则"）到**程序性知识**（"自动运用"）的转化路径。本项目的语法复习采用 **Explain → Practice → Rate** 三段流：先呈现语法规则，再通过练习转化为技能，最后自评掌握程度。

### 2.5 交错练习

相比集中练单一类型，**交错练习**（interleaved practice）在训练阶段更吃力，但长期保持效果显著更好（Rohrer & Taylor, 2007）。本项目的"每日挑战"从课程树随机抽真实题项合成挑战课，实现跨题型、跨单元的交错出题。

### 2.6 错误分析与中介语

**错误分析**是理解学习者**中介语**（interlanguage）发展轨迹的核心手段：学习者的错误不是随机的，反映的是当前的中介语规则系统（Corder, 1967）。本项目的错题本保留原始题目快照（题干、正答、用户错答），支持重做和跳转到对应语法点，让错误本身变成可分析的学习数据。

### 2.7 多技能整合

应用语言学把语言能力拆成**接受性技能**（听、读）、**产出性技能**（说、写），以及词汇、语法、语音等知识维度。本项目的 6 种教学模板（intro / practice / listening / reading / review / mastery）和 14 种题型覆盖了从词汇呈现到听读输入再到可控产出的完整闭环，避免孤立训练单一技能。

### 2.8 关于土耳其语

Turkish 属于**突厥语系**，是**黏着语**（agglutinative language）：语法关系通过往词根上依次加词缀表达，一个词能承载相当于英语一整句的信息（如 *evlerinizdekilerden* = "from those at your houses"）。核心特征：

- **元音和谐**（vowel harmony）：词缀元音要和词根在舌位前后、唇形圆展上一致。
- **SOV 语序**：主-宾-动，和汉语、英语（SVO）差别很大。
- **无语法性别**：没有冠词、没有名词类别，代词不分性别。
- **浅层正字法**（shallow orthography）：拼写和发音对应高度规则，对初学者的音位意识训练比较友好。

这些特征让 Turkish 对汉语母语者既有门槛（语序、黏着形态）也有便利（无性别、拼读规则）。本项目据此设计渐进式语法复习和丰富的词形变化练习：`listenOnly` 纯听阶段让学习者专注音位解码，`typeTheWord` 把音位解码和拼写产出结合起来。

**课时打字判分不能用 Dart 默认的 `toLowerCase()`**：`'İ'` 会被拆成 `i` + 组合上点，学习者输入看起来完全正确的 `iyi` 会被判错。比较统一走 `lib/core/turkish_text.dart` 的 `foldTurkish`（剥组合附加符，İ/I/ı 对称折成 `i`），填空 / 听写 / 短答 / 翻译四个渲染器两侧用同一个函数。词典查找走 `LanguageCodes.lookupFoldKey` 的语言学校准 `I → ı`，与判分用的对称折叠是两件事。

---

## 3. 架构总览

Clean Architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route。

```
lib/
├── application/        # 门面层：Provider（状态管理）+ 应用服务，编排 domain 契约
│   ├── ai/             # AI 能力：engine/（统一引擎层）+ textbook/
│   ├── anki_import/    # 导入向导 controller / flow / 完成协调
│   │   └── recognition/ # 证据驱动识别器（词典绑定 / 原型规则 / 薄 policy，纯函数）
│   ├── anki_official/  # 官方 Anki 内核（rslib FFI）引擎 / 导入 / 渲染 / 投影 / 迁移
│   ├── review/         # 统一复习会话 controller
│   ├── study_session/  # 会话结算
│   └── ...             # 各子系统 provider（srs / grammar / mistake / stats / curve ...）
├── core/               # 纯逻辑：FSRS / SM-2 / 语言检测 / HTML 剥离 / streak / 日志 / 主题
├── courses/            # 字母 + 语种 loader / validator
├── data/               # drift CourseDatabase + Seeder + Repository 实现
├── di/                 # GetIt + Injectable 装配（renderer_module / audio_module / service_module）
├── domain/             # 领域模型 + Repository 接口（repositories/ 目录是接口清单）
├── gen/                # freezed / json_serializable 生成物
├── l10n/               # 国际化
├── routing/            # Auto Route 路由表 + 守卫
├── service/            # AppPrefs / locator / TTS / 本地提醒
└── views/              # 页面：courses / dictionary / home / lesson / play / profile /
                        # review / ai / anki / anki_official / settings / widgets /
                        # <feature>/components/
```

### 分层规矩

依赖方向只能从上往下：

| 层 | 职责 | 不许做 |
|---|---|---|
| `views/` | 页面与组件，只渲染和交互 | 不 import `lib/data/` |
| `application/` | 门面：编排 domain 契约和仓储接口 | 不 import `lib/data/` |
| `domain/` | 实体、状态模型、仓储**接口** | 不反向依赖 `application` / `data` |
| `data/` | drift 库、DAO、仓储实现 | 不对 `views` / `application` 暴露 |
| `core/` | 跨层公共设施 | 不依赖 `views` |
| `di/` | 装配代码（唯一豁免跨层禁则的位置） | — |

规则由 `test/architecture/layering_guard_test.dart` 逐文件强制，失败即层边界已破。豁免白名单是双向校验的：既拦未授权导入，也报「已豁免但不再导入，去删豁免项」。

### 关键模式

- **状态管理**：Provider + ChangeNotifier。Provider 既是依赖注入容器也是状态广播器。
- **依赖注入**：GetIt + Injectable，`@injectable` / `@lazySingleton` 注解，`build_runner` 生成 `injection.config.dart`。
- **路由（导航合同，CI 强制）**：Auto Route + 代码生成（`.gr.dart`）+ `CourseReadyGuard`（数据库播种完成前重定向到 splash）。全屏页面一律走 AutoRoute，全局 `AppRouter.defaultRouteType = RouteType.adaptive(enablePredictiveBackGesture: true)`——Android 用 Material 路由（含预测返回，manifest 已加 `enableOnBackInvokedCallback`），iOS/macOS 用真实 Cupertino 路由（边缘返回），Web 无转场。禁止：全局强制单一平台路由、`PageRouteBuilder` / `transitionsBuilder` 自定义转场、调用点直接构造 `MaterialPageRoute` / `CupertinoPageRoute`、覆盖 `ThemeData.pageTransitionsTheme`。唯一例外是 `lib/routing/platform_page_route.dart` 的官方路由类选择器，只供运行时组装、没有稳定页面身份的内部页使用。底部主 Tab 是 `IndexedStack` 即时切换，不是 push/pop；Dialog / BottomSheet 保持弹层语义。由 `test/routing/routing_policy_contract_test.dart` 与 `test/routing/adaptive_route_semantics_test.dart` 在 CI 强制。
- **模型**：Freezed 不可变类 + `@JsonSerializable`。Interaction 的变体由 `runtimeType` 区分。
- **Repository**：接口在 `domain/repositories/`，实现在 `data/`。数据库是派生缓存，JSON 是真理源。application 层只消费接口（GetIt 以 `@LazySingleton(as: …)` 绑定实现）。
- **渲染器插件化**：14 种 Interaction 各有一个 `@injectable` 渲染器，由 `di/renderer_module.dart` 收集成 `Set<InteractionRenderer>` 注册到 GetIt。分发走 `lookupRenderer()`，它先用 `_handlesTypeFor()` 把实例映射到 **freezed 公开接口类型**再匹配——**不能直接用 `runtimeType`**，因为 freezed 生成的是私有的 `_$FooImpl`，永远不等于渲染器声明的 `handlesType`。新增题型：写渲染器 → 在 module 登记 → 重跑 `build_runner`，不用改任何分发逻辑。

---

## 4. 课程引擎

### 4.1 层级模型

```
Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction
```

全部是 Freezed 不可变类 + JSON 序列化。`Lesson.flattenedStages` 把嵌套内容展平成渲染器可遍历的 `List<Stage>`。

### 4.2 Interaction 题型（14 种）

按语言技能维度分类，均 `@injectable` 注册到 GetIt：

| 维度 | 题型 | 说明 |
|---|---|---|
| 词汇呈现 | `showWord` | 形式 + 意义 + 音频 |
| 接受性词汇 | `multipleChoice` | 识词选义 |
| 接受性词汇 | `multiSelect` | 多选 |
| 产出性词汇/句法 | `fillBlank` | 完形填空（打字比对走 `foldTurkish`） |
| 产出性词汇/句法 | `translateSentence` | 翻译 |
| 产出性词汇/句法 | `reorderSentence` | 乱序组句 |
| 产出性词汇/句法 | `typeTheWord` | 听音拼写 |
| 听力 | `listenAndPick` | 听后选择 |
| 听力 | `listenOnly` | 纯听输入 |
| 阅读 | `readingMcq` | 篇章选择 |
| 阅读 | `readingTrueFalse` | 篇章判断 |
| 阅读 | `readingShortAnswer` | 篇章简答 |
| Anki 官方 | `ankiCard` | Flutter 渲染的官方 Anki 卡片 |
| Anki 保真 | `ankiHtmlCard` | 官方复习路径用 WebView 渲染原 notetype HTML；lesson 体和错题重放里的存量卡降级为占位卡（`AnkiHtmlCardRetiredRenderer`，见第 6 节） |

渲染器实现在 `lib/views/lesson/components/interactions/`。

### 4.3 Lesson Template（6 种教学模板 + 1 种兜底）

| 模板 | 教学定位 |
|---|---|
| **intro**（认识新词） | `showWord` 呈现形式与意义，配简单选择题建立形式-意义对应。 |
| **practice**（巩固练习） | 受控语境里反复操练——填空、翻译、组句——把陈述性知识转成程序性技能。 |
| **listening**（听力训练） | `listenAndPick` / `typeTheWord` / `listenOnly`，训练自下而上的语音解码。`ListeningPhase` 支持 debut→main→fin 三段式音频，可叠 BGM。 |
| **reading**（阅读理解） | 短文 + `readingMcq` / `readingTrueFalse` / `readingShortAnswer` 三道递进题，训练自上而下的篇章理解。 |
| **review**（复习） | 跨单元回顾，交错出题避免集中练习效应。 |
| **mastery**（综合测验） | 混合题型限时完成，模拟多技能并行需求。 |
| `legacy` | 兜底模板，兼容旧版课程数据，不是教学模板。 |

> 写课时内容的完整契约见 [`authoring/lesson-type-templates.md`](./authoring/lesson-type-templates.md)（14 种题型的字段与写法）、[`authoring/course-layout.md`](./authoring/course-layout.md)（Section / Unit / Lesson 层级与文件布局）、[`authoring/listening-show-format.md`](./authoring/listening-show-format.md)（听力课的广播式音频结构）。

### 4.4 按需加载与缓存

- `index.json` + 每节一个 JSON + drift SQLite 缓存。
- 按内容版本号（`index.json` 的 `version`）自动重新播种；改版本号或清空应用数据可以强制重新播种。
- `expressions` 表支持表达级的间隔重复。

### 4.5 当前内容状态

8 个 CEFR 分级课程（A1→B2），课程之间有前置依赖，**8 节全部是真实内容**——共 148 个词 / 18 个表达 / 8 个语法点 / 54 课时 / 11 个单元，每节都有听力和阅读练习，没有占位。完整清单见 [`docs/content_inventory_current.md`](./content_inventory_current.md)（自动生成，勿手改）。

### 4.6 切换语言与备份互斥

**切换语言的三段式失败语义**（`lib/application/course_provider.dart` 的 `setScope`）：先**加载目标语言的内容**（`LanguageContentStore.of(nextCode).ensureLoaded()`），成功后才提交 scope 并级联同步练习语言；任何后续失败（级联、持久化）都整体**回滚到上一个语言**，然后抛 `CourseScopeSwitchException` 给调用方（课程管理页接这个错并提示）。加载失败则**拒绝切换**，scope、内容存储和所有练习过滤条件都留在原语言，零状态变更。连续快速切换会串行化——一次切换完整生效（或完整回滚）之后才开始下一次。

**学习和备份互斥**（`lib/service/remote_backup/remote_backup_busy_gate.dart` 的 `StudyActivityGate`）：导入向导的解析与提交、正式复习页、课时页、每日挑战 / 弱词 / 错题复习三个练习页都在学习活动作用域内；`RemoteBackupService.backupNow` 在整个快照期间持锁并在各阶段之间复查，学习活动中途出现就中止并清理暂存目录；上传读的是**不可变的暂存副本**，媒体复制进副本后再从副本校验和上传，避免上传过程中被学习写入改脏。

---

## 5. 复习系统：FSRS、记忆曲线与错题

### 5.1 FSRS 引擎

`lib/core/fsrs_engine.dart` 实现 `SrsScheduler` 接口，基于 [`fsrs`](https://pub.dev/packages/fsrs) 包。核心参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `desiredRetention` | 0.9 | 目标回忆概率，驱动下次间隔计算；实际会夹在 0.8–0.95。 |
| `maximumIntervalDays` | 730 | 间隔硬上限（天）。 |
| `enableFuzzing` | true | 是否给间隔加随机抖动（预览时关掉，保证确定性）。 |
| `maxSameDayFails` | 4 | 当天失败次数到这个数，下次到期时间推迟到第二天。 |
| `parameters` | FSRS 默认 21 个权重 | 可用个性化权重（见 5.2）。 |

**评分语义**：练习题用二元 pass→Good / fail→Again；导入的 Anki 卡片可以传四档 Again / Hard / Good / Easy。失败路径走**当日重学阶梯**（`lib/core/fsrs_relearn.dart`，10 分钟学习步 + 重学步）。

**SM-2 后备**：`lib/core/sm2.dart` 保留着，作为可选调度器。

### 5.2 FSRS 参数优化

`lib/core/fsrs_optimizer.dart` 根据学习者的复习历史（`ReviewEvents`）拟合个性化 FSRS 权重，让调度更贴合个人遗忘曲线。

### 5.3 复习状态与历史的持久化

- **`SrsStates` 表**：`wordId` 主键，存 queue / dueAt / intervalDays / ease / reps / lapses / isLeech / type / lastReviewedAt。`SrsQueueProvider` 是同步内存缓存 + 写入即持久化，启动时 `ensureLoaded()` 从 SQLite 装载；自带从旧偏好项迁移的一次性逻辑。
- **`ReviewEvents` 表**：自增主键，存 cardId / queue / reviewedAt / quality / 前后 intervalDays / 前后 ease / reps / lapses / type，带 `@TableIndex`（cardId + reviewedAt）。每评一张卡写一条 `ReviewEventRecord`。
- **`SrsWord`** 加了 `lastReviewedAt`，算遗忘曲线不用再 join 数据库。

### 5.4 记忆曲线

`MemoryCurveProvider.snapshot()` 算出：

- **currentRetention**：已复习卡片的平均保持率 R = exp(-Δt/S)。
- **forecast**：今天到期 / 7 天内到期 / 30 天内到期。
- **maturity**：new / young / mature / leech 的分布。
- **retention-by-interval**：按上一次间隔分桶（[1, 4, 7, 14, 21, 30, 60, 90, 180]）的经验回忆率曲线。

`lib/views/review/components/retention_curve_chart.dart` 的 `RetentionCurveChart` 用 `fl_chart` 的 LineChart 画这条曲线，复习进度页和 Anki 牌组统计页共用。

### 5.5 错题本

30 条 FIFO 队列，保留原始题目快照（题干、正答、用户错答）。支持重做清除和跳转到对应语法点复习。列表和仪表盘下拉刷新走 `reloadFromPrefs()`：先丢内存缓存再 `ensureLoaded()`，避免仓库还没加载时把 `entries` 当成空列表。

### 5.6 语法复习

Explain → Practice → Rate 三段流（见 2.4）。

### 5.7 每日挑战

从课程树随机抽真实题项合成挑战课，实现交错练习（见 2.5）。

### 5.8 弱词复习

近 30 天里错 2 次以上的词自动汇成 10 题迷你测验，做针对性检索练习。Anki 保真卡和选择题快照不参与（只有结构化的 AnkiCard 进）。

### 5.9 Match Madness

限时单词配对小游戏，用时间压力强化形式-意义对应的自动化，降低真实交流中的认知负荷。

### 5.10 撤销与并发

`undoReview` 和在途的 `reviewItem` 用 `_gradesInFlight` 集合防竞态：评分写入期间拒绝撤销，写完再重试。统一复习会话（`ReviewSessionController`）评分后先推进界面，数据库后台写；`isPersisting` 为真时禁用撤销。完成页可以撤销最后一张。语法复习走独立页面，评分后可一步撤销（`rollbackGrammarPoint`）；本场奖励发出后不再撤销。

### 5.11 统一复习会话

`lib/views/review/unified_review_page.dart` + `ReviewSessionController`：

- 中途退出有 `PopScope` 确认，已答部分按比例结算（`SessionSettlementService.settle`）。
- 每场默认 25 张（设置里可选 20 / 25 / 30）；完成页显示还剩多少到期卡，可以直接「继续复习」。
- `previewError` 不锁评分键；只有 `writeError` 会禁用并提示重试。
- 新卡按课程设置自动朗读（`maybeAutoSpeak`）；官方模板卡提供角落朗读按钮（读正面文本快照）。

### 5.12 练习页（Play Hub）

`lib/views/play/play_hub_screen.dart` 是复习流的总入口，信息架构自上而下：

- **队列按 `CourseScope` 切开**（[ADR 0037](./decisions/0037-anki-course-review-unification.md)）：语言课只显示错题 / 单词 / 语法；导入的 Anki 只显示 Anki 复习，并隐藏薄弱单词。「开始今日复习」和个人页快捷入口用的是同一套隔离。
- **AI 助手行**：单行卡 + 引擎就绪/未配置状态 chip，通往 AI Hub。
- **练习工具**：语言课是薄弱单词 / 词典 / 复习进度；Anki 课只保留复习进度（导入的牌组没有内置词表，词典入口一并隐藏）。

**长按浮窗交互契约**（`info_popup.dart` + `play_info_panels.dart`）：短按一律直接进页面；长按只在**有数据可看**的入口生效（主卡、四个队列、薄弱单词、复习进度、AI 助手；词典不参与）。浮窗挂在根 Overlay 上、锚定在被按的卡片旁（下方空间不够就翻到上方），打开时从锚点方向缩放 + 逐行滑入（`easeOutBack`），关闭反向；`reducedMotion` 或系统关掉动画时退化成纯淡入淡出；打开时给一次 medium 触感（`sensoryReduce` 打开则跳过）；卡片带 `Semantics(onLongPress)` 长按语义。**注意**：浮窗内容在页面的 Provider 树之上，面板组件一律通过构造注入数据（`PlayQueueSnapshot` / `AiEngineConfig` / `StudyStatsProvider` 实例），不能在面板的 build 里查 inherited provider。

---

## 6. Anki 深度集成

> **状态口径**：Anki 内核迁移的状态只认 [`docs/official-anki-migration/34-cutover-receipt.md`](./official-anki-migration/34-cutover-receipt.md)。本文只写架构和机制，不写进度和验收结论。

本应用可以导入 Anki `.apkg` 牌组，作为课程目录里的一个 Section。产品合同和评分口径见 [ADR 0037](./decisions/0037-anki-course-review-unification.md)。

### 6.1 导入流水线

**生产路径（Android / iOS / 鸿蒙伴生版）**：选 `.apkg` → 算一次 `AnkiImportExecutionPlan` → `OfficialAnkiOfficialFirstService` 写进官方 Collection → 投影成课程树 → 以 `sourceId` 进入课程 scope。**不**写 Turna 自己的 Anki 笔记表，也**不**写 Turna 的间隔重复队列。`.colpkg` 和内存样例牌组在生产环境直接拒绝。

**执行计划只有三种结果**：`officialFirst` / `failClosed` / `unsupported`。官方内核不可用时一律 fail-closed，**不会**降级到别的实现。

> 早期有一套自己解析 `.apkg` 的 Legacy 装配管线（解析 → 笔记表持久化 → 牌组装配 → 媒体拷贝 → 复习历史迁移），已在 2026-08-27 物理删除，代码、目录和配套的智能组织、Notetype 映射编辑器、Full/Lite 模式一并没了。存量数据里旧导入的课时正文和错题快照还带着已删的题型类型，所以 `AnkiHtmlCard` 保留了类型本体，在课时正文和错题重放里降级成「确认即过」的占位卡（指向「设置 → 旧版与兼容性」），避免分发器对未注册类型抛错。**它不是保真渲染**——保真渲染见 6.3。

### 6.2 牌组到课程的映射

复杂的 notetype（含自定义 HTML/CSS/JS）没法干净映射成结构化题型时，走保真路径。映射编辑器在 `lib/views/anki_official/official_anki_mapping_page.dart`，用自有的 `OfficialAnkiMappingSuggestion` 体系，不依赖旧的 Notetype 映射表。

### 6.3 保真渲染（Fidelity HTML）

`AnkiHtmlCard` 承载原 notetype HTML，渲染链路：

```
official_formal_review_coordinator
  → application/study_session/anki_review_content.dart   (fidelityInteractions)
  → views/review/components/official_template_webview_body.dart
  → AnkiHtmlCardView
```

- `AnkiHtmlCardView`（`webview_flutter`，全项目唯一的 WebView 使用点）渲染原 notetype 的 HTML + CSS，替换 `{{field}}` 模板变量，处理 cloze 挖空。
- **平台门控**：只有 Android / iOS 有 WebView 实现；桌面和 Web 降级成文本兜底，不实例化 `WebViewController`。
- **暗色 CSS**：应用切到暗色主题时注入暗色样式。
- **JS 和网络隔离**：notetype 的 `allowJs` 默认关；联网默认完全离线。离线和询问策略通过 CSP 真正挡掉 `fetch`、XHR、WebSocket 和外部资源，不只是拦页面跳转。
- **卡面缩放（可选，2026-08-28 修订）**：只有用户把「卡面文字大小」（`settings.cardTextScale`）调到 100% 以上才注入缩放；**默认 100% 一个字节都不注入**，不碰作者自己的字体和字号。三条轨道共用这一个设置项，实现路径不同：
  - **Dart WebView 轨道**（`AnkiHtmlCardView`）→ 注入 `html{zoom:N}`；
  - **Android 原生复习器轨道** → `WebSettings.textZoom`；
  - **iOS 原生复习器轨道**（WKWebView 没有 `textZoom`，走独立链路）→ `official_anki_reviewer_stage.dart` 读 `cardTextScaleOf(context)`，经 MethodChannel `setTextZoom` 下发（Swift 侧夹在 100–200），由 `WKUserScript` 注入，`assets/anki_reviewer/reviewer.js` 的 `OfficialReviewer.setTextZoom` 再向内层 iframe 派发 `turnaTextZoom`，最后 `card-frame.js` 校验 nonce 后写 `webkitTextSizeAdjust`。

### 6.4 复习入口与浏览

- **复习**：`FormalReviewLauncher` → 共用 `AnkiReviewSessionRoute`。正式资格 = 官方到期搜索（`did:<deck> (is:due OR is:learn OR is:new)`，分页，不受复习队列 100 张上限约束）∩ 课程位置 ∩ **已解锁** ∩ 未暂停/搁置/退役。已解锁 = **该投影课时已完成**，或导入历史里 `reps ≥ 1`。第一遍课内只解锁，不写官方排期、不记错题本；新卡第一次 Again/Good 发生在 Anki 复习页。第一遍下课会给该课所在牌组抬高**当天**的新卡名额（`ENSURE_TODAY_NEW_QUOTA` / `extend_new`），让剩余名额不少于本课张数，不改牌组的 `new_per_day` 预设。重做已完成的课时，会在下课 flush 官方的 Again/Good（`ANSWER_AHEAD_CARDS` 临时 filtered deck）；今天已经 `rated:1` 的卡跳过；flush 失败在完成摘要里看得见。官方内核不可用时 fail-closed，**不**降级到 Turna 自己的间隔重复。
- **卡片浏览器 / 牌组统计**：有官方内核时读 Collection 和 scheduler；没有时回退到 catalog，但统计**不能**把 catalog 总数标成已验证的数字。
- **页面侧数据访问门面**：`application/anki_official/official_anki_catalog_service.dart` 的 `OfficialAnkiCatalogService` 统一承接页面侧的 catalog / source 列表与按 id 读取、待导入任务取消、maintenance job 读写、完整性检查、repair 快照和复习选路规则（并 re-export `OfficialAnkiSourceRow`）。**页面不许 import DAO 文件、不许自己 new `*Dao(`**，由 `test/architecture/layering_guard_test.dart` 强制。
- **示例牌组**：生产环境 fail-closed，入口已从导入页和课程管理隐藏。

### 6.5 高级设置里的 Anki 相关项

高级页提供渲染/网络策略和单牌组覆盖、失败降级、媒体与导入性能、三种排程继承、同胞卡与难卡规则、FSRS 实验室、存储维护、脱敏报告和实验功能中心。系统健康在启动时直接监听 `LogCapture`，按 [ADR 0040](./decisions/0040-system-health-state-machine.md) 的**状态机**生成本机告警：分数只是聚合输入（按严重度排序），**界面上没有任何扣分入口**，也不存在「-40 分确定」这类按钮；恢复来自系统证据（自检通过），陈旧事件按 24 小时活跃窗口衰减、7 天自动过期，`fatal` 组在窗口内把结果钉在 critical。达到 10/40 阈值时以**非阻断横幅**呈现，不锁页。详见 [`advanced-settings-system-health.md`](./advanced-settings-system-health.md)。

---

## 7. AI 引擎层与 AI 功能

### 7.1 统一 AI 引擎层

`lib/application/ai/engine/` 是全应用唯一的模型调用出入口，从 `tool/gui/src/backend/ai/` 移植并重构。文件：

| 文件 | 职责 |
|---|---|
| `ai_engine.dart` | `@lazySingleton` 门面：`chat()` + `requestJson()` + 缓存接线 |
| `ai_engine_config.dart` | `AiEngineConfig`：双模型（modelChat / modelJson）+ `StrictSchemaMode` + reasoning 支持 |
| `ai_engine_config_holder.dart` | `@lazySingleton` ChangeNotifier，配置的唯一真理源，**持久化到本地**（配置含 API key，设备上是明文、由用户显式选择；写入绕过日志） |
| `ai_http_client.dart` | `postJson` / `postStream` / `probeConnection`；json_schema → json_object 自动回退；`AiCancelToken` 协作式取消 |
| `ai_cache.dart` | SHA-256 LRU + 磁盘镜像（条件编译 web/io）；key 里不含 API key |
| `ai_provider_preset.dart` | 预设：deepseek（默认 `deepseek-v4-flash`）/ openai / moonshot / ollama / custom |
| `ai_recent_tasks_provider.dart` | 最近任务环（最多 20 条，FIFO），AI Hub「继续」区的数据源 |

**设计要点**：引擎层不关心业务领域（只暴露 `chat` + `requestJson`），领域方法、prompt 构建、`parseCompletion` 留在 `AiCourseService`，避免 engine ↔ service 循环依赖。所有 provider 和 Anki 直调都走 `AiEngine`（流式 + 取消 + 缓存），不绕旧 shim。

### 7.2 AI Hub

`lib/views/ai/ai_hub_page.dart` 是集中的 AI 入口（从 Play Hub 进），四个区：

- **Hero**：preset / modelChat / modelJson / 脱敏 key 芯片 + 重新配置按钮 + 配置不完整的告警。
- **Continue**：最近 3 个**可恢复**的任务（`AiRecentTasksProvider` 过滤掉 wish / textbook；`tutorChat` 只在偏好项里已有会话时才恢复）。空态给提示，点击跳对应路由。
- **Start**：5 个入口——许愿生成 / 教材导入 / 据错题导师 / 据弱词导师 / 深度讲解（带上下文门控）。
- **Tools**：测试连接（`probeConnection` + 延时）/ 清缓存 / 查看 API 配置。

### 7.3 AI 功能清单

| 功能 | 入口 | 说明 |
|---|---|---|
| **AI 提示助手** | 课程内聊天面板 | 按当前题目上下文给提示和解释。 |
| **深度讲解** | 课程内 sheet / AI Hub | 4 种类型：语法讲解 / 近义词辨析 / 句子拆解 / 错因分析（`hint_genres.dart`，typed 解析 + 容错 `fromJson`）。 |
| **间隔重复导师** | 课程内 sheet / AI Hub | 根据错题 + 弱词 + 近期复习构建 prompt，AI 生成复习课写进课程树（`srs_tutor_provider.dart`）。 |
| **许愿生成** | `AiWishChatPage` / AI Hub | 多轮对话对齐需求 + 附件 → "滑动确认"生成 section JSON + 通俗解释。类型标签支持批量生成多种模板。 |
| **教材导入** | `TextbookImportRoute` / AI Hub | 从 PDF / Word / 图片 / 文本提取词汇、表达、语法点，多阶段向导导入课程树。 |
| **课程生成** | AI Hub | 普通模式和许愿模式；`ai_fixer` 在生成后自动修 id 冲突、引用断裂、schema 不符。 |
| **课时助手** | 课程内 | `AiLessonHelperProvider`。 |

> 旧的实验性页面 `AiCourseGeneratorPage` 已删除；课程生成现在走许愿聊天页 + AI Hub。

### 7.4 已落地的伴学闭环

这一块的功能边界（`lib/application/ai/` 下）：

1. 学习者知识笔记：`AiSavedExplanationsStore`（`ai_saved_explanations.dart`）保存、检索、删除收藏正文和时间，随 hint 流程写入。
2. 资源接地：`AiGroundedResourceProvider`（`ai_grounded_resource_provider.dart`）把已有课程资源格式化成 prompt 片段，并返回全部已加载资源 ID 供 prompt 约束引用。**Top-K 检索和来源白名单校验没有实现。**
3. 导师会话：`AiTutorChatSession`（`ai_tutor_chat_session.dart`）是 JSON 序列化的内存模型；角色扮演以 `AiTutorChatMode.roleplay` 存在（`ai_tutor_chat_provider.dart`），页面提供 4 个场景 chip（用餐 / 问路 / 自我介绍 / 购物）。**难度选择、纠错节奏、成功条件、结束复盘和 TTS 朗读没有实现；会话持久化从未接线。**
4. 请求节流：`CompanionRateLimiter`（`companion_rate_limiter.dart`）做本地最小间隔去抖，防连点烧 token。**每日软/硬预算没有实现。**

### 7.5 安全姿态

- API key / base URL / model 可以持久化到本地（用户可选）；写入绕过日志避免泄密。
- 「不保存到本地」的横幅在配置页提示安全立场。
- 附件用临时文件。
- API key 不写进普通偏好、配置 JSON、日志、导出或缓存；旧明文 key 要等验证迁移成功后才删除（`lib/service/secure_credential_store.dart` + `AiEngineConfigHolder` 的迁移阶段机）。
- 设置页提供「清除凭据」；**独立的「清除 AI 学习数据」入口没有实现**。
- 请求带功能名、prompt 版本、超时（`ai_engine.dart` 默认 60s / 120s）和一次安全重试（服务端以 400 拒绝 `json_schema` 时降级成 `json_object` 重发一次，只在 `StrictSchemaMode.auto` 下触发）。**幂等键没有实现。**

**平台边界**：Android / iOS / macOS / Windows / Linux 用 `flutter_secure_storage` 的可用实现，API key 存在系统钥匙串里；Web 和缺原生安全存储插件的平台只在会话内保留 key，并在设置页提示。Web 启动路径本身不提供 drift 课程库，所以课程检索按现有平台能力降级。语音转文字、OCR 和图片场景任务还属于计划中的后续平台试验；文本伴学和 TTS 不依赖这些能力。不提供没有可靠评分模型支撑的口音或音素分数。

---

## 8. 音频、TTS 与智能朗读

### 8.1 AudioController

`lib/application/audio_controller.dart` 统一接管 TTS（`flutter_tts`，土耳其语 `tr`）和音效。`speak` / `speakWithResult` 支持可选的 `languageCode`：null 用目标语，非 null 用指定语言，解析失败回退目标语。`AccessibilityProvider` 注入：`sensoryReduce` 打开时音效和触觉反馈直接返回。

### 8.2 智能朗读（Smart Speech）

`lib/core/language_detector.dart`（纯逻辑）按文字脚本返回 BCP-47 基础码：

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
| 土耳其语特有字符（ğ ı ş İ；ç ö ü 不算，因为法德共用） | tr |
| 纯拉丁字母 | 回退到该课程的母语 |

`inferOptionLanguage` / `detectOption` 用提示方向推断选择题选项的语言（解决 "merhaba" 这种没有变音符号的土耳其词歧义）；`detectCardPair` 用 Anki 正反面之一的土耳其信号推断另一面。`lib/core/html_stripper.dart` 在朗读 Anki HTML 卡片前去标签。`lib/application/smart_speech.dart` 封装策略（`currentSpeechLanguages` / `detectSpeakLanguage` / `autoReadOnTapForActiveCourse`），走 get_it，失败回退 tr/en。

### 8.3 每课程设置

`settings_provider.dart` + `LocalStateKeys`：`autoReadOnTapFor(scope)`（默认 true）/ `nativeLanguageCodeFor(scope)`（默认 'en'），key 按 courseScope 编码。课程管理页每行有齿轮按钮，弹出底部面板（自动朗读开关 + 母语下拉 14 项）。

### 8.4 接线点

- 选择题选项点击（受开关控制，按推断语言朗读）。
- Anki 翻牌（卡出现读正面、翻开读背面，受开关控制 + 每面有手动朗读钮）。
- 词典自由文本（`detectSpeakLanguage`）。
- 已知目标语的调用点（词条 / 听力原文 / ShowWord / 间隔重复词条）走 `speak`（target），行为不变。
- 课时听力题（`listenAndPick` / `typeTheWord` / `listenOnly`）和统一复习的新卡：`maybeAutoSpeak`（`autoReadOnTapForActiveCourse` + `ttsFeatureEnabled`）；`SpeakerButton` 播放中会变样式并禁点。

### 8.5 离线 TTS

用系统 / Google TTS（`tr`），Android 优先 `com.google.android.tts`。听力练习用预生成的 `audioAsset`（见第 12 节）。

> 人工录音替换 TTS 的提交规范（仅限听力课的长句 / 对白，单词与短表达仍走运行时 TTS）见 [`docs/audio-recording-guidelines.md`](./audio-recording-guidelines.md)。

---

## 9. 主题与可访问性

### 9.1 TurnaTheme

`lib/core/theme.dart` 提供 `lightTheme` / `darkTheme` / `highContrastLightTheme` / `highContrastDarkTheme`，以及一组按 `Brightness` 自适应的语义化颜色 helper（`cardBg` / `scaffoldBg` / `textHintColor` / `inputFillColor` / `bottomNavBg` / `glassSurface` 等）。

调色板（Turna「湿地鹤」[ADR 0033](./decisions/0033-turna-wetland-crane-palette.md) 方案 A —— 主色锁 `#1F727E`）：

```dart
const brandNavy      = Color(0xFF19324A);
const primaryColor   = Color(0xFF1F727E);  // Brand Teal（锁定）
const primaryLight   = Color(0xFF2F7F8E);
const primaryDark    = Color(0xFF145A64);  // ≡ GUI BRAND_TEAL_DARK
const brandSky       = Color(0xFF4A95A8);
const brandReed      = Color(0xFF5FB8C4);
const secondary      = Color(0xFFB85C3F);  // anatolianClay —— 只做暖色点缀
const secondaryLight = Color(0xFFEAD9B8);  // warmSand
const error   = Color(0xFFE74C3C);
const success = Color(0xFFFFD93D);
const warning = Color(0xFFFF9F43);
```

主 CTA 渐变：`brandTeal → brandTealLight`（关键路径用 `TurnaTheme.primaryCtaDecoration`）。Clay 用于完成/完美角标、成就向指标、About 品牌条，Play Hub 至多一处次要 soft tint。**角色边界**：success 黄=答题反馈；clay=进度/成就；streak 橙=连胜 chip（不同控件）；高对比模式下 secondary 可以偏离 clay。**Android 状态栏/导航栏**对齐 AppBar 表面（不是铺一条 teal）：`colors.xml` + `TurnaTheme.systemUiOverlayFor`。调色板真源是 `lib/core/theme.dart` 和 `tool/gui/src/theme_tokens.py`（ADR 0033）。

`ThemeProvider`（light / dark / system）持久化到 `StreamingSharedPreferences`，个人页可以切换。

**全应用使用系统字体（2026-09-01 定案，不要回退）**：`google_fonts` 依赖和 `AppFonts` 包装类已整体删除，无障碍里的 `dyslexiaFont`（Lexend）连同设置项、Provider 字段、备份清单条目和 l10n 键一并下线（存量 `settings.dyslexiaFont` 偏好项成为死键，不迁移）。**理由不是审美而是 ANR**：原来欢迎页的永久动画循环（文字轮播 + 3 秒换图）保证每秒都有 rebuild → 每次 rebuild 都调 `GoogleFonts.nunito()` 走**运行时字体拉取** → 大陆网络 `fonts.gstatic.com` 持续 408，而沙箱里的缓存目录从来不存在（字体一次都没加载成功）→ 失败重试 + fallback 重解析 → 帧泵永续（真机实测 8 秒窗口 241 帧，每帧全量 LAYOUT+PAINT+COMPOSITING）→ 主线程 CPU 饱和（`utm` 124.9s / 进程存活 188s）→ 触摸 5 秒无人消费 → `Input dispatching timed out` **ANR 击杀**（没有 SIGSEGV、没有 tombstone，所以表现成「闪退」）。复现矩阵 3/3 落在欢迎页、0/2 在课程页。这条链路对每个大陆网络用户都会成立，不是设备特例。系统字体零网络依赖、零资产、确定性 100%，把 Nunito/Lexend 打进资产包的混合方案已被否决。

### 9.2 AccessibilityProvider

`lib/application/accessibility_provider.dart`，6 项持久化偏好：

| 偏好 | 作用 |
|---|---|
| `textScale` | 文本缩放 100–200% |
| `cardTextScale` | 卡面文字大小 100–200%（只有 >100% 生效，缩放轨道见 6.3） |
| `reducedMotion` | 减少动画（`MediaQuery` 的 disableAnimations） |
| `highContrast` | 切高对比主题（纯黑白表面 + 强边框 + 最大对比文本） |
| `sensoryReduce` | 静音音效和触觉反馈 |
| `focusMode` | 关掉 splash 旋转图计时器这类分心元素 |

`app.dart` 的 `_AppShell` 监听 ThemeProvider 和 AccessibilityProvider，选 light / dark / high-contrast 变体，注入根 `MediaQuery` 覆盖（textScaler + accessibleNavigation）。设置页分 7 类：Account / Learning / Audio & Haptics / Accessibility / AI Tools / Data / About。

**各表面覆盖情况**（`已实现` = 该表面有可观察效果；`不适用` = 该表面没有对应的动态 / 声音 / 可裁剪装饰，因而不存在"有开关但无效果"的承诺）：

| 表面 | 文本缩放 | 卡面字号 | 减少动态 | 高对比 | 静音反馈 | 专注模式 |
| --- | --- | --- | --- | --- | --- | --- |
| 设置 | 已实现：根 `MediaQuery.textScaler`，滑杆与分类页支持换行 | 已实现：`cardTextScale` 滑杆独立于根缩放 | 已实现：页面切换 / 展开动画用零时长 | 已实现：根高对比主题、控件边界加粗 | 已实现：全局声音 / 触觉控制器静音 | 不适用：设置项都是用户主动操作，没有推荐或装饰区 |
| Home | 已实现：根缩放，导航和课程树有大字布局测试 | 不适用：Home 不渲染 Anki 卡面 | 已实现：课程树、底栏、滚动隐藏动画静态化 | 已实现：实色底栏与强化边界 | 已实现：欢迎反馈和全局音触觉都受抑制 | 已实现：隐藏随机欢迎装饰，底栏改实色稳定态 |
| 复习概览 | 已实现：Hero / 到期卡在大字时改纵向布局，无溢出测试 | 不适用：概览页不渲染卡面，卡片缩放作用于 Anki 复习器 | 不适用：概览没有持续或装饰动画 | 已实现：根主题；状态同时有文字、图标和数值 | 不适用：概览不主动播放声音或触觉 | 已实现：保留今日 / 待复习，隐藏 streak、质量、来源和洞察推荐入口 |
| 学习洞察 | 已实现：筛选可换行，热力图 200% golden | 不适用：洞察是 Flutter 自绘，不渲染卡面 | 不适用：图表为静态绘制 | 已实现：高对比明 / 暗 golden；热力格有边框、数值摘要和逐日语义 | 不适用：洞察不播放声音或触觉 | 已实现：保留筛选 / KPI / 曲线 / 热力图，隐藏次要统计和来源推荐区 |
| AI | 已实现：根缩放，聊天内容自然换行 | 不适用：AI 对话不渲染卡面 | 已实现：流式更新分批；根 `disableAnimations` 关掉装饰过渡 | 已实现：根主题，状态有文本和图标 | 已实现：全局音触觉控制器静音 | 已实现：隐藏快捷推荐 chips，仍可手动输入 |
| 装扮商店 | 已实现：商品详情和购买操作在大字时改纵向排列，价格不省略 | 不适用：商店不渲染卡面 | 已实现：商品预览无自动动画 | 已实现：可用 / 不可用有语义 value、文字和 2px 边界，不依赖透明度 | 已实现：购买链不触发强音效或触觉 | 不适用：目录预览是辨认待购商品所必需的，不属于可隐藏推荐 |
| 完成页 | 已实现：根缩放，完成内容可滚动 / 换行 | 不适用：完成页不渲染卡面 | 已实现：装备效果替换为带"静态效果"语义的静态徽章 | 已实现：根主题；徽章用图标、边框和文本语义共同表达 | 已实现：完成效果本身无音效或触觉，全局控制器仍会抑制其他反馈 | 不适用：完成结果和下一步操作都是当前任务必需信息 |

**卡片字号的实际作用域**：`cardTextScale`（`AccessibilityProvider.cardTextScale` / `cardTextScaleOf(context)`）**只被 Anki 卡面消费**，不作用于上表任何表面。三个消费点：

- `lib/views/anki/anki_html_card_view.dart`：向卡面注入缩放层，100% 时不注入以保持默认。
- `lib/views/review/components/official_template_webview_body.dart`：转成 WebView 的 `textZoom`。
- `lib/views/anki_official/official_anki_reviewer_stage.dart`：官方 Anki 复习器对 HTML 模板和 `typedAnswer` 字号应用同一百分比。

**豁免约定**：上表的"不适用"只覆盖没有对应副作用的静态或任务必需表面，不允许用"不适用"掩盖已经存在的动画、声音、触觉或推荐区。这些表面以后新增上述行为时，必须同时消费 `AccessibilityCapabilities` 并补测试；新增会渲染 Anki 卡面的表面时，必须消费 `cardTextScaleOf(context)`。对应的回归测试在 `test/golden/round2_accessibility_golden_test.dart`、`test/views/review/review_dashboard_page_test.dart`、`test/views/review/learning_insights_accessibility_test.dart`、`test/views/ai/ai_focus_mode_test.dart`、`test/application/accessibility_provider_test.dart`。

---

## 10. 平台与构建

### 10.1 支持平台

| 平台 | 状态 | 备注 |
|---|---|---|
| **Android** | 主力 | 发布产物 APK/AAB；官方 Anki 内核首发平台。`minSdk 24`、`compileSdk 36`，发布包只发 arm64。 |
| **iOS** | 支持 | 保真渲染可用；官方 Anki 内核已接通（静态链接 rslib 的 `TurnaAnki.xcframework` + WKWebView 复习器 `turna-anki://anki.local`），和 Android 同走官方路径；构建见 [`ios-build-setup.md`](./ios-build-setup.md)。 |
| **HarmonyOS** | 伴生轻量版 | 产品级支持已 EOL（[ADR 0041](./decisions/0041-ohos-product-eol.md)），但有一个**不进主交付**的伴生版（[ADR 0047](./decisions/0047-ohos-companion-lite-build.md)）：课程 / 间隔重复 / 复习 / 词典 / 设置 / 备份 + 自维护 ArkTS 通道。官方 Anki 接线已授权并施工到步 5b（[ADR 0050](./decisions/0050-ohos-official-anki.md)），**余项（真机导入、课程学习解锁）和步 6 独立 CI 首跑收据待取**，口径一律以 [34 收据](./official-anki-migration/34-cutover-receipt.md) 为准。 |
| **Web / 桌面** | 有限 | 没有 WebView 保真（文本兜底）；`build_release.py --skip-web` 可以跳过 Web 构建。 |

### 10.2 官方 Flutter / Android

本项目用**官方 Flutter SDK**（不是 OpenHarmony fork）。CI 钉在 Flutter **3.44.5**。Android 构建需要 **JDK 17**。详见 [`docs/android-build-setup.md`](./android-build-setup.md)。

### 10.3 构建命令

```bash
flutter pub get        # 生成代码已提交，不跑 build_runner
flutter run            # 运行

# 改了 @freezed / @JsonSerializable / @AutoRoute / @injectable 才需要重新生成
flutter pub run build_runner build --delete-conflicting-outputs   # 或 make gen

# 发布（APK/AAB/可选 web + 内容清单）
# 注意：--version 的 X.Y.Z 必须和 pubspec.yaml 里的 version 一致，脚本会断言，不符就退出
python tool/build_release.py --version 0.8.0
# 或
make build-release VERSION=0.8.0

# 发布 APK 只发 arm64（官方原生内核只打包了 arm64-v8a）
flutter build apk --release --split-per-abi --target-platform android-arm64
```

### 10.4 Makefile

```bash
make gen                # 生成代码
make analyze            # 静态分析
make test               # Dart 测试
make test-python        # Python 工具测试
make format-check       # 格式检查
make lint-gui           # 桌面编辑器 lint
make guard-gui          # 桌面编辑器分层 + 数值 ratchet 门禁
make test-gui           # 桌面编辑器全量测试
make build-release-smoke # 构建冒烟
make ci                 # 以上全部
```

环境要求：官方 Flutter SDK **3.44.5** + JDK 17（Android）+ Python 3（工具和桌面编辑器）。Windows 上用 `python` 而不是 `python3`。

---

## 11. GUI 课程编辑器（作者工具）

在 [`tool/gui/`](../tool/gui/)，基于 **PySide6**，复用 `tool/course_cli.py` 的校验和归一化逻辑。JSON 仍是唯一真理源。运行：`pip install PySide6 && python tool/gui/src/main.py`。

### 11.1 定位与视图

- 打开 `assets/courses/<lang>/` 目录，三栏树（Section → Unit → Lesson）+ 右侧详情面板。详情按 lesson 的 `template` 切换可用字段，非法结构在界面层就构造不出来。
- **教师视图**：线性三层次（课 → 环节 → 步骤 → 题目），含 `LessonWizard`、`QuestionCards`、`TemplateEditors`、`VocabTable`、`ErrorMapper`、`LessonBlueprint`（卡片流蓝图，只读预览 + 命令化就地编辑）。
- **传统视图**：`CourseTree` + `LessonEditor` + `ResourceEditor` + `DetailPanel`。

### 11.2 教材导入（Textbook Import）

从外部教材（PDF / Word / 图片 / 文本）提取教学内容，多阶段向导：

1. **选材**：拖入文件，自动识别类型抽文本（PDF 用 PyPDF2 / Word 用 python-docx / 图片走 base64 进 vision API）。
2. **提取**：AI 逐章识别词汇、表达、语法点、对话、练习，`KnowledgeExtractor` 按 `KnowledgeSchema` 产出结构化条目。
3. **合并**：`KnowledgeMerger` 跨章节去重合并，处理多次出现、释义冲突、例句归并。
4. **预览**：`BulkImportPreviewPanel` 逐条确认/编辑/排除，按资源类型分 tab。
5. **导入**：写进 `vocab.json` / `expressions.json` / `grammar_points.json` 并生成 lesson。

配套：`extraction_quality.py`（提取质量控制）、`import_strategy.py`（保守/激进/交互式三种策略）、`textbook_presets.py`（教材预设）、`markdown_chopper.py`（大文件分段 + 断点续传），项目持久化到 `tool/var/textbooks/`（支持中断恢复）。格式细节见 [`docs/authoring/textbook-import.md`](./authoring/textbook-import.md)。

### 11.3 Workshop 窗口

独立于课程树的 **Workshop 窗口**（`workshop_window.py`），和 App Shell 松耦合，共享项目上下文。集中管理批量操作：教材导入任务列表、AI 批量生成队列、跨 section 内容迁移、操作日志。支持多任务并行，后台执行不阻塞主编辑器。

### 11.4 AI 生成引擎（GUI 端）

| 模块 | 职责 |
|---|---|
| `ai_generator.py` | 普通模式 + 许愿模式生成调度 |
| `ai_stream.py` | SSE 流式响应处理 |
| `ai_fixer.py` | 生成后自动修复：id 冲突、引用断裂、schema 不符 |
| `ai_prompt_library.py` | 可复用 prompt 模板库 |
| `ai_genre.py` | 类型标签映射，多模板批量生成编排 |
| `ai_usage.py` | Token 用量追踪 |

支持普通模式（表单 → 生成 → 预览 → 导入）、许愿模式（多轮对话 + 附件 → 生成 + 解释）、类型标签批量生成（`[intro]`/`[practice]`/`[listening]`/`[reading]`/`[review]`/`[mastery]`）、流式输出 + 中途取消、自动修复。

### 11.5 护栏

| 护栏 | 实现 |
|---|---|
| **校验单一来源** | 题型 schema 的唯一真相源是 `tool/gui/src/backend/lesson_content.py` 的 `INTERACTION_SCHEMA`，所有 widget 从它派生；lint/validate 规则只进 `tool/course_cli.py`，**GUI 不新增自有校验规则** |
| **round-trip 无损** | `normalize_item` 按 schema 白名单重建 dict，所以**每个 App 支持的字段都必须进 schema**（否则「打开→不动→保存」会静默丢字段）；Anki 交互的 `id`（`anki-<importId>-n<noteId>-c<ord>`）和 `sourceNoteId` / `sourceCardId` 在编辑和类型切换中保持原值 |
| **重新播种触发器** | App 的内容重建触发器是组合版本 `"$indexVersion+$expressionsVersion"`（`course_database_seeder.dart` 拼出的 `assetVersion`）。vocab 和 expressions 同属资源层，所以 vocab-only 的变更**要靠 bump expressions 版本**来触发客户端重建（`CourseReleaseService.version_bump_plan`；改 App 触发器超出 GUI 范围）。发布对话框要标注这个联动原因 |
| id 全局唯一 | id 只读；改名只改 name；validate 兜底查重；导入冲突弹窗 |
| 规模上限 | `MAX_UNITS_PER_SECTION=60` / `MAX_LESSONS_PER_UNIT=40` |
| 引用完整性 | `wordId` / `expressionId` / `grammarPointId` 从已加载资源下拉选 |
| 保存前校验 | `validate --format json` 失败 → 禁用保存 + 高亮问题节点 |
| 密钥不落盘 | API key / base URL / model 只存内存；附件用临时文件 |

### 11.6 打包与测试

```bash
pip install pyinstaller
python tool/gui/build_gui.py                # onefile → dist/turna-gui.exe
python tool/gui/build_gui.py --clean        # 先清 build/ 和 dist/

# 桌面编辑器测试：分档运行器（纯 unittest，不依赖 pytest）
cd tool/gui
python run_gui_tests.py ci -j 4             # 日常 / PR 默认：L0 gate + L1 fast
python run_gui_tests.py full -j 4           # 全量：逐模块独立子进程
cd ../..

# 分层门禁（和两个 CI workflow 同一组参数）
make guard-gui

# GUI ↔ CLI round-trip（不在 run_gui_tests.py 覆盖范围内）
python -m unittest discover -s test -p "*_test.py"
```

> 没有图形环境时先设 `$env:QT_QPA_PLATFORM = "offscreen"`（bash 用 `QT_QPA_PLATFORM=offscreen` 前缀写法）。分档定义见 `tool/gui/run_gui_tests.py` 的 docstring，指标基线见 `tool/gui/docs/ai_refactor_contract.md`。

---

## 12. 听力音频生成流水线

`listening` 模板的 `listeningPhases[].audioAsset` 指向预生成的 MP3。两步流水线离线生成，运行时**不**调云端 TTS。

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

[`tool/mix_listening_a1.py`](../tool/mix_listening_a1.py) 用 **pydub** 混音（需要 ffmpeg）。

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

混音结构：`debut + [主内容 + BGM(降 18dB)] + fin`，结尾 BGM 淡出 800ms。每节课映射到 A/B/C 三个变体（不同 debut/fin/bgm 组合），由 CSV mapping 指定；没映射的默认 A。

### 12.3 人工录音替换

人工录音可以替换 TTS 文件，规范见 [`docs/audio-recording-guidelines.md`](./audio-recording-guidelines.md)。文件名和 `audioAsset` 一致，放进 `assets/sounds/turkish/listening/`。

### 12.4 资产清单校验

```bash
python tool/course_cli.py audio-manifest --output manifest.csv
```

---

## 13. 课程数据格式与 Authoring

JSON 放在 `assets/courses/turkish/`，由 `CourseLoader` 加载、`DatabaseSeeder` 播种进 SQLite。最小 `index.json`：

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

每节包含 `units → lessons → content`（stages / subLessons / listeningPhases / readingPassage）。Interaction 的变体由 `runtimeType` 区分。完整的 authoring 契约见：

- [`docs/authoring/course-layout.md`](./authoring/course-layout.md)
- [`docs/authoring/course-pack-format.md`](./authoring/course-pack-format.md)（外部课程运行时只吃 `.turnapack` v1 JSON 或 v2 zip + `media/`，见 [ADR 0043](./decisions/0043-turnapack-external-courses.md)）
- [`docs/authoring/lesson-type-templates.md`](./authoring/lesson-type-templates.md)
- [`docs/authoring/listening-show-format.md`](./authoring/listening-show-format.md)
- [`docs/authoring/textbook-import.md`](./authoring/textbook-import.md)
- [`docs/authoring/teacher-guide.md`](./authoring/teacher-guide.md)

---

## 14. 测试与质量基线

```bash
flutter test --exclude-tags golden           # 最新全量计数看 test/BASELINE.md 顶条（不要在本文写死）
python -m unittest discover -s test -p "*_test.py"    # Python 工具测试
python tool/gui/run_gui_tests.py full        # 桌面编辑器全量（每模块独立子进程，runner 自动设 offscreen）
python -m ruff check tool/gui                # 桌面编辑器 lint（src + tests）
```

- `flutter analyze`：改动文件 0 error / 0 warning（只有历史 info 级 lint）。
- `tool/course_cli.py --course-dir assets/courses/turkish validate` 通过。
- CI（`flutter_ci.yml`）在 `flutter test` 之外还跑 format-check、ruff（GUI src）和 GUI 全量档，并采集覆盖率；Flutter 版本钉在 3.44.5。
- 最新基线和每轮改动记录见 [`test/BASELINE.md`](../test/BASELINE.md)。

---

## 15. 已明确不做（含教学法依据）

下面这些"游戏化"机制的移除是经过考量的教学法决策：

- ❌ **排行榜 / 天梯 / 好友 / 分享**。社会比较短期能提升参与度，但对内在动机有抑制作用（Deci & Ryan, 1985 自我决定理论）。本项目选内容驱动，不选竞争驱动。
- ❌ **活力值 / 连签修复 / 商店道具**。惩罚机制（答错扣活力）和"失败恐惧"相关，可能让学习者回避高难度内容——而高难度内容恰恰是 i+1 原则要求的习得区间。
- ❌ **口语录音匹配**。自动语音评分在非主流语种（含土耳其语）上可靠性和效度不足，本项目用 TTS + 听力路径覆盖语音输入训练。
- ❌ **云端 CMS / Firebase / 推送通知**。本地优先保证离线可用性和数据隐私，也避免服务端依赖的持续维护成本。
- ❌ **GUI 替代 JSON 作为真理源**。GUI 是 JSON 的可视化前端，JSON 始终是唯一权威存储，保证可版本化、可 diff、可脚本批处理。
- ❌ **XP 倍率 / 每日 XP 目标 / 宝石购买 / 道具 / 社交成就**。同上，去摩擦和付费。
- ❌ **全局错误弹窗**。错误分两类：可恢复的加载失败走 Provider 状态机承载（如 `SectionLoadState.error`），一次性动作用 SnackBar；不引入拦全应用的全局弹窗。
- ❌ **二元评分以外的档位扩展 / 课程树硬锁 / 云端推送**。练习题评分语义见 5.1（练习题二元 pass→Good / fail→Again，导入的 Anki 卡可传四档）；课程树结构由数据驱动，不写死。

> **与"社交成就"并存的长期硬约束（2026-08-22 成就体系焕新定案）**：课程成就的最终目标保持 **500 课**、完美课程最终目标保持 **100 课**，**不得下调或删除**。成就评估走唯一写入者 `AchievementService`（评估 → 持久化 → 发奖 → 两阶段反馈），指标投影持久化为 `achievements.metric_projection.v1`；宝石奖励入账以 `GemLedgerDao` 为事实源。

---

## 16. 文档索引

| 文档 | 说明 |
|---|---|
| [`README.md`](../README.md) | 项目概览与快速上手 |
| [`docs/README.md`](./README.md) | **全部文档的索引**（按「找什么 → 去哪」组织） |
| [`AGENTS.md`](../AGENTS.md) | AI Agent 行为规范（禁则、门禁、按需查阅指针） |
| **构建与发布** | |
| [`docs/android-build-setup.md`](./android-build-setup.md) | Android / 官方 Flutter 构建配置 |
| [`docs/ios-build-setup.md`](./ios-build-setup.md) | iOS 构建（静态链接 rslib xcframework + WKWebView 复习器） |
| [`docs/firebase-app-distribution.md`](./firebase-app-distribution.md) | 内发渠道配置 |
| **内容与课程** | |
| [`docs/content_inventory_current.md`](./content_inventory_current.md) | 土耳其语内容清单（**自动生成，勿手改**） |
| [`docs/authoring/`](./authoring/) | Authoring 契约与教师指南 |
| [`docs/audio-recording-guidelines.md`](./audio-recording-guidelines.md) | 人工录音提交规范 |
| **架构与设计** | |
| [`docs/decisions/`](./decisions/) | 架构决策记录（ADR） |
| **Anki 官方内核迁移** | |
| [`docs/official-anki-migration/`](./official-anki-migration/README.md) | 迁移文档索引；**状态唯一真源 = [`34-cutover-receipt.md`](./official-anki-migration/34-cutover-receipt.md)** |
| [`docs/official-anki-migration/archive/`](./official-anki-migration/archive/README.md) | 迁移历史结论速查（**勿按其施工**；原文已删，git tag `docs-cleanup-backup-2026-10-19` 可恢复） |
| **AI 与设置** | |
| [`docs/advanced-settings-system-health.md`](./advanced-settings-system-health.md) | 高级设置与系统健康（状态机依 ADR 0040） |
| **其他** | |
| [`test/BASELINE.md`](../test/BASELINE.md) | 测试基线与最近改动收据（更早见 [`test/archive/BASELINE-pre-2026-09-20.md`](../test/archive/BASELINE-pre-2026-09-20.md)） |

> **收据引用规则**：引用测试和改动记录必须用「文件 + 条目日期 + 标题」锚，**禁止用行号**——`test/BASELINE.md` 是前插式只增文件，行号必然腐坏。详见 [`AGENTS.md`](../AGENTS.md) 的「文档与收据锚点」。

---

## 17. 下一轮计划与致谢

### 下一轮

- **内容深化**：8 节已全部填真实内容，后续按这个优先级继续加深：
  1. **高频词汇优先**：参考 Turkish National Corpus 的词频数据，优先覆盖前 2000 个词族（能覆盖日常文本约 85%）。
  2. **语法渐进**：A1 集中在现在时、格标记（主/宾/与/属/方位/离格）、简单句；A2 引入过去时和将来时；B1 引入关系从句和名物化；B2 涉及语篇衔接和语体变化。
  3. **语用真实性**：表达和对话要反映目标语真实使用场景（比如 `Buyurun` 的多重语用功能），避免翻译腔。
- **Anki 生产收口**：按 [34 计划](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md) 走。真机验收矩阵（干净安装/升级安装/迁移包/备份恢复/强杀恢复）、iOS 真机（非模拟器）验收、正式发版都还没做，**不得写「迁移完成」**。
- **鸿蒙余项**：真机导入、课程学习解锁、步 6 独立 CI 首跑收据。
- **跨设备**：数据导出/导入的易用性。
- 持续完善无障碍和统计指标。

### 致谢

- 原始框架：[Turna](https://github.com/rshrc/Varnamala) —— Section/Unit/Lesson 树 + Provider + Drift + Freezed + auto_route 骨架。
- 复习算法：[fsrs](https://pub.dev/packages/fsrs)（FSRS）、SM-2（SuperMemo 2）。
- TTS：[flutter_tts](https://pub.dev/packages/flutter_tts)。
- 持久化：[drift](https://pub.dev/packages/drift) + [streaming_shared_preferences](https://pub.dev/packages/streaming_shared_preferences)。
- 依赖注入 / 路由：[get_it](https://pub.dev/packages/get_it) + [injectable](https://pub.dev/packages/injectable) + [auto_route](https://pub.dev/packages/auto_route)。
- Anki 保真渲染：[webview_flutter](https://pub.dev/packages/webview_flutter)。

### License

见 [`LICENSE`](../LICENSE)。
