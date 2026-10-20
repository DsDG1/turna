# Turna 项目指南（架构与设计）

> README 给概览和快速上手，本文只给各子系统的设计与决策依据。本文只写还在的代码，已删掉或被取代的实现去看 Git 历史；状态数字现场查证：schema 版本看 `lib/data/course_database.dart` 的 `kSchemaVersion`，内容版本看 `assets/courses/turkish/index.json` 的 `version`，测试计数看 `test/BASELINE.md` 顶条。
>
> 本文是架构与设计叙述的真源，不覆盖另外两类文档：[`AGENTS.md`](../AGENTS.md) 是行为规范；[`docs/status.md`](./status.md) 是子系统状态（含 Anki 内核迁移）的唯一来源。

## 1. 项目定位与设计哲学

**Turna** 是本地优先、离线的语言学习应用，当前目标语是**土耳其语（Turkish）**。骨架来自 [Varnamala](https://github.com/rshrc/Varnamala)，在其上做三件事：把复习做准（用 **FSRS** 替代 SM-2）、接上 Anki 生态（`.apkg` 牌组直接导入并投影成课程目录）、把 AI 收成一层（所有大模型调用走同一个引擎层：流式、缓存、取消、结构化输出）。

| 原则 | 含义 |
|---|---|
| 本地优先 | SQLite（drift）存数据，没有云后端、没有推送、没有登录。 |
| 单人离线 | 没有好友、排行榜这类社交设计，也没有活力值和内购。 |
| JSON 是真理源 | 课程内容是 JSON，可版本化、可 diff、可脚本批处理。 |
| 数据库是派生缓存 | 首次启动从包内 JSON 播种进 `course.db`，之后复用；内容版本号变了就重新播种。 |
| 教学法驱动 | 功能取舍以二语习得研究为依据（见第 2 节）。 |

> 本仓库不是上游官方版本，纯原版功能请访问 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)。

## 2. 教学与二语习得基础

课程设计与复习机制建立在二语习得（SLA）与认知心理学上。

- **可理解输入与 i+1 原则**（Krashen）：习得发生在接触略高于当前水平的可理解输入时。CEFR 分级课程（A1→B2）与课程前置依赖是它的工程化：A1 达标才解锁 A2。
- **间隔重复与遗忘曲线**（Ebbinghaus；Nation, 2013）：每次主动回想都能减缓衰减，复习要排在遗忘临界点附近。引擎用 **FSRS**（第 5 节）以目标保持率（默认 0.9）驱动间隔，比 SM-2 更贴近真实遗忘曲线；SM-2 后备保留在 `lib/core/sm2.dart`。
- **测试效应**（Roediger & Karpicke, 2006）与**技能习得理论**（DeKeyser, 2007）：前者说明主动提取比被动重读显著增强长期保持，填空 / 翻译 / 听写 / 选择题都是检索练习；后者把陈述性知识转成程序性知识，语法复习走 Explain → Practice → Rate 三段流。
- **交错练习**（Rohrer & Taylor, 2007）与**错误分析**（Corder, 1967）：前者让「每日挑战」随机抽真实题项合成挑战课；后者指出错误反映中介语规则系统而非随机。

Turkish 是黏着语，语法靠往词根加词缀表达；特征是元音和谐、SOV 语序、无语法性别、浅层正字法。据此设计渐进式语法复习和词形变化练习：`listenOnly` 纯听阶段专注音位解码，`typeTheWord` 把音位解码与拼写产出结合。

课时打字判分不能用 Dart 默认的 `toLowerCase()`：`'İ'` 会被拆成 `i` + 组合上点，看起来完全正确的 `iyi` 会被判错。比较统一走 `lib/core/turkish_text.dart` 的 `foldTurkish`（İ/I/ı 对称折成 `i`），两侧用同一个函数；词典查找走 `LanguageCodes.lookupFoldKey` 的语言学校准 `I → ı`。

## 3. 架构总览

Clean Architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route。`lib/` 按依赖方向单向流动：`application/`（门面层）→ `domain/`（领域模型 + Repository 接口）→ `data/`（drift 库、DAO、仓储实现）；`core/` 是跨层纯逻辑，`di/` 是唯一豁免跨层禁则的装配位置。

| 层 | 职责 | 不许做 |
|---|---|---|
| `views/` | 页面与组件，只渲染和交互 | 不 import `lib/data/` |
| `application/` | 门面：编排 domain 契约和仓储接口 | 不 import `lib/data/` |
| `domain/` | 实体、状态模型、仓储接口 | 不反向依赖 `application` / `data` |
| `data/` | drift 库、DAO、仓储实现 | 不对 `views` / `application` 暴露 |
| `core/` | 跨层公共设施 | 不依赖 `views` |
| `di/` | 装配代码（唯一豁免跨层禁则的位置） | — |

规则由 `test/architecture/layering_guard_test.dart` 逐文件强制，失败即层边界已破；豁免白名单双向校验，既拦未授权导入，也报「已豁免但不再导入，去删豁免项」。

关键模式：

- 状态与模型：Provider + ChangeNotifier 同时充当依赖注入容器与状态广播器；GetIt + Injectable（`@injectable` / `@lazySingleton`）；Freezed + `@JsonSerializable`，Interaction 变体由 `runtimeType` 区分；接口在 `domain/repositories/`，实现在 `data/`。
- 路由（导航合同，CI 强制）：Auto Route + 代码生成（`.gr.dart`）+ `CourseReadyGuard`（播种完成前重定向到 splash）。全屏页面一律走 AutoRoute，全局 `AppRouter.defaultRouteType = RouteType.adaptive(enablePredictiveBackGesture: true)`：Android 用 Material 路由，iOS/macOS 用 Cupertino 路由，Web 无转场。禁止全局强制单一平台路由、自定义转场、调用点直接构造 `MaterialPageRoute` / `CupertinoPageRoute`、覆盖 `ThemeData.pageTransitionsTheme`；唯一例外是 `lib/routing/platform_page_route.dart`。
- 渲染器插件化：14 种 Interaction 各有一个 `@injectable` 渲染器，由 `di/renderer_module.dart` 收集成 `Set<InteractionRenderer>` 注册到 GetIt。分发走 `lookupRenderer()`，它先把实例映射到 freezed 公开接口类型再匹配——不能直接用 `runtimeType`，因为 freezed 生成的是私有的 `_$FooImpl`。

## 4. 课程引擎

```
Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction
```

全是 Freezed 不可变类 + JSON 序列化，`Lesson.flattenedStages` 把嵌套内容展平成渲染器可遍历的 `List<Stage>`。14 种 Interaction 题型均 `@injectable` 注册到 GetIt：`showWord`、`multipleChoice`、`multiSelect`、`fillBlank`（打字比对走 `foldTurkish`）、`translateSentence`、`reorderSentence`、`typeTheWord`、`listenAndPick`、`listenOnly`、`readingMcq`、`readingTrueFalse`、`readingShortAnswer`、`ankiCard`、`ankiHtmlCard`（官方复习路径用 WebView 渲染原 notetype HTML，存量卡降级为占位卡）。

6 种教学模板 + 1 种兜底：intro 认识新词；practice 受控语境反复操练填空 / 翻译 / 组句；listening 听力训练（自下而上的语音解码）；reading 阅读理解（短文 + 三道递进题）；review 跨单元回顾；mastery 混合题型限时完成；legacy 兜底模板，兼容旧版课程数据。

> 写课时内容的完整契约见 [`authoring/lesson-type-templates.md`](./authoring/lesson-type-templates.md)、[`authoring/course-layout.md`](./authoring/course-layout.md)、[`authoring/listening-show-format.md`](./authoring/listening-show-format.md)。

按需加载：`index.json` + 每节一个 JSON + drift SQLite 缓存，按内容版本号自动重新播种；`expressions` 表支持表达级间隔重复。

切换语言的三段式失败语义（`lib/application/course_provider.dart` 的 `setScope`）：先加载目标语言的内容，成功后才提交 scope；后续失败都整体回滚到上一个语言并抛 `CourseScopeSwitchException`。加载失败则拒绝切换，scope 和练习过滤条件留在原语言。

学习和备份互斥（`lib/service/remote_backup/remote_backup_busy_gate.dart` 的 `StudyActivityGate`）：`RemoteBackupService.backupNow` 在快照期间持锁并复查，学习活动中途出现就中止并清理暂存目录，上传读的是不可变的暂存副本。

## 5. 复习系统：FSRS、记忆曲线与错题

`lib/core/fsrs_engine.dart` 实现 `SrsScheduler` 接口，基于 [`fsrs`](https://pub.dev/packages/fsrs) 包。核心参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `desiredRetention` | 0.9 | 目标回忆概率，驱动下次间隔计算；实际会夹在 0.8–0.95。 |
| `maximumIntervalDays` | 730 | 间隔硬上限（天）。 |
| `enableFuzzing` | true | 是否给间隔加随机抖动（预览时关掉，保证确定性）。 |
| `maxSameDayFails` | 4 | 当天失败次数到这个数，下次到期时间推迟到第二天。 |
| `parameters` | FSRS 默认 21 个权重 | 可用个性化权重。 |

评分语义：练习题用二元 pass→Good / fail→Again，Anki 卡片可以传四档 Again / Hard / Good / Easy；失败路径走当日重学阶梯（`lib/core/fsrs_relearn.dart`，10 分钟学习步 + 重学步）。SM-2 后备保留在 `lib/core/sm2.dart`；`lib/core/fsrs_optimizer.dart` 按复习历史（`ReviewEvents`）拟合个性化权重。

持久化与记忆曲线：调度状态以 `wordId` 为主键存 `SrsStates` 表，`SrsQueueProvider` 是同步内存缓存 + 写入即持久化。`MemoryCurveProvider.snapshot()` 给出平均保持率 R = exp(-Δt/S)、到期 forecast、成熟度分布和经验回忆率曲线。

练习形态：错题本是 30 条 FIFO 队列，保留原始题目快照，支持重做清除和跳转到对应语法点复习；弱词复习把近 30 天里错 2 次以上的词汇成 10 题迷你测验。

撤销与并发：`undoReview` 和在途的 `reviewItem` 用 `_gradesInFlight` 集合防竞态，评分写入期间拒绝撤销；统一复习会话（`ReviewSessionController`）评分后先推进界面、后台写库，`isPersisting` 为真时禁用撤销。`lib/views/review/unified_review_page.dart` 的中途退出有 `PopScope` 确认，每场默认 25 张。

练习页（Play Hub）：`lib/views/play/play_hub_screen.dart` 是复习流的总入口，队列按 `CourseScope` 切开（[ADR 0037](./decisions/0037-anki-course-review-unification.md)），语言课与导入的 Anki 按 scope 分开显示（Anki 侧隐藏薄弱单词）；智能练习占队列第四格，短按进 AI Hub，长按弹引擎配置浮窗。

## 6. Anki 深度集成

> 状态口径：Anki 内核迁移的状态只认 [`status.md`](./status.md)。

本应用可以导入 Anki `.apkg` 牌组，作为课程目录里的一个 Section。产品合同和评分口径见 [ADR 0037](./decisions/0037-anki-course-review-unification.md)。

导入流水线：选 `.apkg` → 算一次 `AnkiImportExecutionPlan` → `OfficialAnkiOfficialFirstService` 写进官方 Collection → 投影成课程树 → 以 `sourceId` 进入课程 scope。不写 Turna 自己的 Anki 笔记表和间隔重复队列；`.colpkg` 和内存样例牌组在生产环境直接拒绝。执行计划只有 `officialFirst` / `failClosed` / `unsupported` 三种结果，官方内核不可用时一律 fail-closed，不会降级到别的实现。

保真渲染：复杂的 notetype（含自定义 HTML/CSS/JS）没法干净映射成结构化题型时走保真路径，映射编辑器在 `lib/views/anki_official/official_anki_mapping_page.dart`。

- `AnkiHtmlCardView`（`webview_flutter`，全项目唯一的 WebView 使用点）渲染原 notetype 的 HTML + CSS，替换 `{{field}}` 模板变量并处理 cloze 挖空；只有 Android / iOS 有 WebView 实现，桌面和 Web 降级成文本兜底。
- JS 和网络隔离：notetype 的 `allowJs` 默认关，联网默认完全离线；离线和询问策略通过 CSP 真正挡掉 `fetch`、XHR、WebSocket 和外部资源，不只是拦页面跳转。
- 卡面缩放（可选）：只有 `settings.cardTextScale` 调到 100% 以上才注入缩放，默认 100% 一个字节都不注入；三条轨道共用这一个设置项，作用域见第 9 节。

复习入口：`FormalReviewLauncher` → 共用 `AnkiReviewSessionRoute`。正式资格 = 官方到期搜索（`did:<deck> (is:due OR is:learn OR is:new)`）∩ 课程位置 ∩ 已解锁 ∩ 未暂停/搁置/退役；已解锁 = 该投影课时已完成，或导入历史里 `reps ≥ 1`。第一遍课内只解锁，不写官方排期、不记错题本；下课 flush 只抬高该课牌组的当天新卡名额，不改 `new_per_day` 预设。

浏览与数据访问：有官方内核时读 Collection 和 scheduler，没有时回退到 catalog，但统计不能把 catalog 总数当已验证数字。页面侧统一走 `official_anki_catalog_service.dart` 的 `OfficialAnkiCatalogService`，页面不许 import DAO 文件、不许自己 new `*Dao(`，由 `test/architecture/layering_guard_test.dart` 强制。系统健康告警见 [`advanced-settings-system-health.md`](./advanced-settings-system-health.md) 与 [ADR 0040](./decisions/0040-system-health-state-machine.md)。

## 7. AI 引擎层与 AI 功能

统一 AI 引擎层：`lib/application/ai/engine/` 是全应用唯一的模型调用出入口。`ai_engine.dart` 是 `@lazySingleton` 门面（`chat()` + `requestJson()` + 缓存接线）；`ai_engine_config.dart` 持 `AiEngineConfig`（双模型 + `StrictSchemaMode`）；`ai_engine_config_holder.dart` 是配置的唯一真理源并持久化到本地（API key 只进平台安全存储，缺插件时降级为会话内）；`ai_http_client.dart` 提供 `postJson` / `postStream` / `probeConnection`（json_schema → json_object 回退、`AiCancelToken` 取消）；`ai_cache.dart` 是 SHA-256 LRU + 磁盘镜像（key 不含 API key）。引擎层只暴露 `chat` + `requestJson`，领域方法、prompt 构建、`parseCompletion` 留在 `AiCourseService`，避免循环依赖。

AI Hub：`lib/views/ai/ai_hub_page.dart` 是集中的 AI 入口，五区：Hero（模型与配置）、我的练习（`AiPracticeLibrarySection`：生成中进度、最近草稿、查看全部）、Continue（可恢复的伴学任务）、Start（「生成练习」与「自定义课程」两张卡 + 伴学 4 格）、偏好与提示词（`AiExplainPrefsCard`；「系统提示词」入口只读展示实际发给模型的系统提示词，允许在末尾追加自定义要求）。

AI 练习生成：`lib/application/ai/practice/` 是唯一入口。`AiPracticeGenerator` 走「大纲 → 逐课填充 → 整节校验」的分阶段管线（提示词语义对齐 `tool/gui/src/backend/ai/` 的 phased/pedagogy 实现，输出仍是 `docs/authoring/course-layout.md` 的一份 section JSON）。`AiPracticeJobQueue` 是 app 级 `@lazySingleton`（挂在路由之上），生成任务在 `queued/running/ready/failed` 间流转，切页不中断；进程被杀后启动时把未完成行标成 `interrupted`。生成物落在 `course.db` 的 **`ai_courses` + `ai_course_versions`** 两张表（合集 / 每次生成一版），**不写** `sections/units/lessons`：seeder 在内容版本变化时会清空语言课程表，且生成物不应出现在「学习」页课程树。课稿默认 7 天后过期（从创建算），收藏即永久；清理在冷启动与打开库页时各跑一次。内容核验由 `AiPracticeQualityChecker` 两级把关：阻断级（越界正确答案、重复选项、空阶段、生词零覆盖等）会先修两次再判失败，提示级只写进核验报告。练习只允许文本题型（生成物没有预生成音频）；开练页 `AiPracticeRunPage` 从库里的 JSON 构造 `Lesson` 走 `LessonViewModel.loadLessonInstance`，与 Daily Challenge 同一条合成课路径，不记课程完成度/成就；详情页 `AiPracticeDetailPage` 展示目录树、核验报告与生成历史。决策与边界见 [ADR 0054](./decisions/0054-ai-practice-library.md)。

课时内只保留解释型 AI：课时 AppBar 提供单题 AI 提示与深度讲解，不提供改课入口，也不提供「降低/提高难度」等单课 chip。对生成物的整节调整在「我的练习」里进行。

伴学闭环的边界：知识笔记（`AiSavedExplanationsStore`）；资源接地（`AiGroundedResourceProvider` 把课程资源格式化成 prompt 片段；Top-K 检索和来源白名单校验没有实现）；导师会话（`AiTutorChatSession` 是内存模型，角色扮演以 `AiTutorChatMode.roleplay` 存在；难度选择、纠错节奏、成功条件、结束复盘和 TTS 朗读没有实现，会话持久化未接线）；请求节流（`CompanionRateLimiter` 本地去抖；每日软/硬预算没有实现）。

安全姿态与平台边界：API key / base URL / model 可以持久化到本地；设置页提供「清除凭据」，独立的「清除 AI 学习数据」入口没有实现。配置页常驻「接口与责任边界」卡：只接 OpenAI 兼容 Chat Completions、请求从本机直达用户填的服务商（应用不中转）、内容生成与合规责任归服务商。API key 不写进偏好、配置 JSON、日志、导出或缓存，旧明文 key 要等验证迁移成功后才删除（`lib/service/secure_credential_store.dart` + `AiEngineConfigHolder` 的迁移阶段机）；幂等键没有实现。key 存在系统钥匙串（`flutter_secure_storage`），缺原生安全存储插件的平台只在会话内保留；鸿蒙（伴生版）同样降级（`flutter_secure_storage` 9.2.4 无 `ohos` 平台声明），无真机收据。

## 8. 音频、TTS 与智能朗读

`lib/application/audio_controller.dart` 统一接管 TTS（`flutter_tts`，土耳其语 `tr`）和音效。`speak` / `speakWithResult` 支持可选的 `languageCode`：null 用目标语，非 null 用指定语言，解析失败回退目标语；`AccessibilityProvider` 注入，`sensoryReduce` 打开时音效和触觉反馈直接返回。

智能朗读（Smart Speech）：`lib/core/language_detector.dart` 按文字脚本返回 BCP-47 基础码——Han / Kana / Hangul / Cyrillic → zh / ja / ko / ru，Arabic / Thai / Devanagari / Greek / Hebrew → ar / th / hi / el / he，土耳其语特有字符（ğ ı ş İ；ç ö ü 不算，因为法德共用）→ tr，纯拉丁字母 → 回退到该课程的母语。`inferOptionLanguage` / `detectOption` 用提示方向推断选择题选项的语言（解决 "merhaba" 这种没有变音符号的土耳其词歧义），`detectCardPair` 用 Anki 正反面之一的土耳其信号推断另一面；`lib/core/html_stripper.dart` 去标签后再朗读。

每课程设置：`settings_provider.dart` + `LocalStateKeys` 提供 `autoReadOnTapFor(scope)`（默认 true）/ `nativeLanguageCodeFor(scope)`（默认 'en'），key 按 courseScope 编码。朗读接线点是选择题选项点击、Anki 翻牌、词典自由文本和课时听力题、统一复习新卡的 `maybeAutoSpeak`。离线 TTS 用系统 / Google TTS（`tr`），Android 优先 `com.google.android.tts`；听力练习用预生成的 `audioAsset`（见第 12 节）。

## 9. 主题与可访问性

`lib/core/theme.dart` 提供 `lightTheme` / `darkTheme` / `highContrastLightTheme` / `highContrastDarkTheme`，以及按 `Brightness` 自适应的语义化颜色 helper。调色板是 Turna「湿地鹤」方案 A（[ADR 0033](./decisions/0033-turna-wetland-crane-palette.md)），真源是 `lib/core/theme.dart` 与 `tool/gui/src/theme_tokens.py`：主色锁 `#1F727E`，另有 `brandNavy #19324A` / `primaryLight #2F7F8E` / `primaryDark #145A64` / `brandSky #4A95A8` / `brandReed #5FB8C4` / `secondary #B85C3F` / `secondaryLight #EAD9B8` / `error #E74C3C` / `success #FFD93D` / `warning #FF9F43`。

主 CTA 渐变 `brandTeal → brandTealLight`（关键路径用 `TurnaTheme.primaryCtaDecoration`）。角色边界：success 黄=答题反馈；clay=进度/成就；streak 橙=连胜 chip；高对比模式下 secondary 可以偏离 clay。Android 状态栏/导航栏对齐 AppBar 表面（不是铺一条 teal）：`colors.xml` + `TurnaTheme.systemUiOverlayFor`。

全应用使用系统字体（不要回退）：不引入 `google_fonts` / `AppFonts`，`dyslexiaFont`（Lexend）连同设置项、Provider 字段、备份清单条目和 l10n 键都不保留（存量 `settings.dyslexiaFont` 偏好项成为死键，不迁移）。理由不是审美而是 ANR：欢迎页永久动画循环每次 rebuild 都调 `GoogleFonts.nunito()` 走运行时拉取，`fonts.gstatic.com` 持续 408，于是失败重试 + fallback 重解析 → 帧泵永续（真机实测 8 秒窗口 241 帧）→ 主线程 CPU 饱和（`utm` 124.9s / 进程存活 188s）→ 触摸 5 秒无人消费 → `Input dispatching timed out` ANR 击杀。系统字体零网络依赖、确定性 100%。

`lib/application/accessibility_provider.dart` 的 6 项持久化偏好：

| 偏好 | 作用 |
|---|---|
| `textScale` | 文本缩放 100–200% |
| `cardTextScale` | 卡面文字大小 100–200%（只有 >100% 生效，缩放轨道见第 6 节） |
| `reducedMotion` | 减少动画（`MediaQuery` 的 disableAnimations） |
| `highContrast` | 切高对比主题（纯黑白表面 + 强边框 + 最大对比文本） |
| `sensoryReduce` | 静音音效和触觉反馈 |
| `focusMode` | 关掉 splash 旋转图计时器这类分心元素 |

`app.dart` 的 `_AppShell` 监听 ThemeProvider 和 AccessibilityProvider，选 light / dark / high-contrast 变体，注入根 `MediaQuery` 覆盖。卡片字号的实际作用域：`cardTextScale`（`AccessibilityProvider.cardTextScale` / `cardTextScaleOf(context)`）只被 Anki 卡面消费，三个消费点是 `lib/views/anki/anki_html_card_view.dart`、`lib/views/review/components/official_template_webview_body.dart`、`lib/views/anki_official/official_anki_reviewer_stage.dart`。豁免约定见 [`AGENTS.md`](../AGENTS.md)。

## 10. 平台与构建

| 平台 | 定位 | 备注 |
|---|---|---|
| Android | 主力 | APK/AAB；官方 Anki 内核首发平台。`minSdk 24`、`compileSdk 36`，发布包只发 arm64。 |
| iOS | 支持 | 保真渲染可用；官方 Anki 内核走静态链接 rslib 的 `TurnaAnki.xcframework` + WKWebView 复习器 `turna-anki://anki.local`；构建见 [`ios-build-setup.md`](./ios-build-setup.md)。 |
| HarmonyOS | 伴生轻量版 | 产品级支持已 EOL；伴生版不进主交付（[ADR 0047](./decisions/0047-ohos-companion-lite-build.md)），覆盖课程 / 复习 / 词典 / 设置 / 备份 + 自维护 ArkTS 通道；官方 Anki 接线见 [ADR 0050](./decisions/0050-ohos-official-anki.md)；构建见 [`ohos-build-setup.md`](./ohos-build-setup.md)。 |
| Web / 桌面 | 有限 | 没有 WebView 保真（文本兜底）；`build_release.py --skip-web` 可以跳过 Web 构建。 |

主工程用官方 Flutter SDK（不是 OpenHarmony fork），CI 钉在 Flutter **3.44.5**，Android 构建需要 **JDK 17**，详见 [`docs/android-build-setup.md`](./android-build-setup.md)；`ohos/` 目录的构建走 OHOS fork SDK，步骤见 [`docs/ohos-build-setup.md`](./ohos-build-setup.md)。发布脚本 `python tool/build_release.py --version 0.8.0` 的版本号必须和 `pubspec.yaml` 一致（脚本会断言）。codegen 与门禁命令见 [`AGENTS.md`](../AGENTS.md)。

## 11. GUI 课程编辑器（作者工具）

在 [`tool/gui/`](../tool/gui/)，基于 **PySide6**，复用 `tool/course_cli.py` 的校验和归一化逻辑。题型 schema 的唯一真相源是 `tool/gui/src/backend/lesson_content.py` 的 `INTERACTION_SCHEMA`，lint/validate 规则只进 `tool/course_cli.py`，GUI 不新增自有校验规则；`normalize_item` 按 schema 白名单重建 dict，所以每个 App 支持的字段都必须进 schema，否则「打开→不动→保存」会静默丢字段。重新播种触发器是组合版本 `"$indexVersion+$expressionsVersion"`，vocab-only 变更要靠 bump expressions 版本触发客户端重建。

## 12. 听力音频生成流水线

`listening` 模板的 `listeningPhases[].audioAsset` 指向预生成的 MP3。流水线离线生成，运行时**不**调云端 TTS：[`tool/generate_audio.py`](../tool/generate_audio.py) 调 **MiniMax T2A v2 REST API** 合成，再用 [`tool/mix_listening_a1.py`](../tool/mix_listening_a1.py) 以 **pydub** 混音（需要 ffmpeg）；结构是 `debut + [主内容 + BGM(降 18dB)] + fin`，结尾 BGM 淡出 800ms。人工录音可替换 TTS 文件，规范见 [`docs/audio-recording-guidelines.md`](./audio-recording-guidelines.md)。

## 13. 课程数据格式与 Authoring

JSON 放在 `assets/courses/turkish/`，由 `CourseLoader` 加载、`DatabaseSeeder` 播种进 SQLite。最小 `index.json`：

```json
{ "version": 12, "language": "tr", "displayName": "Turkish",
  "sections": [ { "id": "section1", "name": "Section 1", "level": "A1",
    "prerequisiteSectionIds": [], "file": "sections/section1.json" } ] }
```

每节包含 `units → lessons → content`。完整的 authoring 契约见 [`authoring/`](./authoring/)。

## 14. 测试与质量基线

见 [`test/BASELINE.md`](../test/BASELINE.md)。

## 15. 已明确不做（含教学法依据）

下面这些「游戏化」机制的移除是经过考量的教学法决策：

- 排行榜 / 天梯 / 好友 / 分享。社会比较短期提升参与度，但抑制内在动机（Deci & Ryan, 1985 自我决定理论）。本项目选内容驱动。
- 活力值 / 连签修复 / 商店道具。惩罚机制（答错扣活力）和「失败恐惧」相关，可能让学习者回避高难度内容——而高难度内容恰恰是 i+1 原则要求的习得区间。
- 口语录音匹配。自动语音评分在非主流语种（含土耳其语）上可靠性和效度不足，本项目用 TTS + 听力路径覆盖语音输入训练。
- 云端 CMS / Firebase / 推送通知。本地优先保证离线可用性与数据隐私，也避免服务端维护成本。
- XP 倍率 / 每日 XP 目标 / 宝石购买 / 道具 / 社交成就。同上，去摩擦和付费。
- 全局错误弹窗。可恢复的加载失败走 Provider 状态机承载（如 `SectionLoadState.error`），一次性动作用 SnackBar；不引入拦全应用的全局弹窗。
- 二元评分以外的档位扩展 / 课程树硬锁 / 云端推送。练习题评分语义见第 5 节；课程树结构由数据驱动，不写死。

> 与「社交成就」并存的长期硬约束：课程成就最终目标保持 **500 课**、完美课程 **100 课**，不得下调或删除。成就评估走唯一写入者 `AchievementService`（评估 → 持久化 → 发奖 → 两阶段反馈），指标投影持久化为 `achievements.metric_projection.v1`；宝石奖励以 `GemLedgerDao` 为入账事实源。

## 16. 文档索引

见 [`docs/README.md`](./README.md)。
