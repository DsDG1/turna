# Varnamala Dream Plan：大规模语言学习 App 可行性分析

> 目标：承载 8,000 常规课 + 1,500 阅读课 + 1,500 听力课 ≈ 11,000 课，支持 Language → Section → Unit → Lesson → Sub-lesson 五级结构，完整 SRS、错题、TTS、本地外部 GUI 编辑器。本项目本地优先、无云。

---

## 1. 可行性结论

**总体判断：可行，但需要分阶段重构。**

当前 Varnamala 的代码基座质量较好：
- 清晰的 `Section > Unit > Lesson > Stage > Interaction` 领域模型
- 插件化的 InteractionRenderer 注册机制
- 已实现的 SM-2 SRS 引擎
- 稳定的 ID 化进度系统

但距离“11,000 课、每课 15 页、本地傻瓜式 GUI 编辑器、完整复习体系”仍有显著差距，主要集中在：内容模型扩展、加载策略、复习 UI、错题系统、TTS 策略、外部创作工具。

---

## 2. 当前资产盘点

| 模块 | 状态 | 关键文件 |
|------|------|----------|
| 课程模型 | ✅ 已扩展 | `domain/course/section.dart`, `unit.dart`, `lesson.dart`, `stage.dart`, `interaction.dart`，新增 `sub_lesson.dart`, `listening_phase.dart`, `expression.dart`, `grammar_point.dart`, `reading_passage.dart`, `lesson_template` |
| 交互题型 | ✅ 11 种已实现 | `ShowWord`, `MultipleChoice`, `FillBlank`, `TranslateSentence`, `ListenAndPick`, `TypeTheWord`, `ListenOnly`, `ReorderSentence`, `ReadingMCQ`, `ReadingTrueFalse`, `ReadingShortAnswer` |
| 课程加载 | ✅ 完成 | `courses/course_loader.dart`, `course_validator.dart`（已支持 sub-lesson / listening phase 校验）；per-section JSON + 懒加载 + drift SQLite seed |
| SRS 引擎 | ✅ 后端完成 | `application/srs_provider.dart`, `core/sm2.dart`, `domain/course/srs_word.dart` |
| SRS 复习 UI | ✅ 已完成 | `views/review/srs_review_screen.dart`，Play 页 "Review"；会话完成奖励 XP/Gems |
| 语法复习 | ✅ 已完成 | `GrammarReviewProvider` + `GrammarReviewPage`；`practiceItems` 练习步；Play 页入口；会话奖励 XP/Gems |
| 进度/XP/连胜 | ✅ 完成 | `application/game_provider.dart`, `progress_provider.dart`；含 `XPEvent.srsReviewSession` / `grammarReviewSession` |
| 错题本 | ✅ 已完成 | `MistakeProvider` + 列表 + `MistakePracticePage`；`grammarPointId` 跨路由到语法复习；上限 30 条 |
| TTS | ✅ 已完成 | `AudioController` 统一管理 TTS 与离线音频；按 `TargetLanguage` 配置语言码；SRS / 听力题 / summary / 字母页均走 `AudioController`；支持 0.8x/1.0x/1.2x 语速 |
| 内容管理 | ⚠️ JSON seed → SQLite | `assets/courses/swahili/`（`index.json` + `sections/*.json` + `vocab.json` + `grammar_points.json`）；含 `s-test` 冒烟课 |
| 外部 GUI 编辑器 | ❌ 未开始 | 无（Phase 7，最后一个开发 phase，纯本地） |

---

## 3. 差距分析

### 3.1 内容模型：Sub-lesson / 听力阶段 / 表达 / 语法 已建模并渲染 ✅

模型层已新增：
- `SubLesson` — 课内子课
- `ListeningPhase` — 听力三阶段
- `Expression` — 多词表达
- `GrammarPoint` — 语法点
- `ReadingPassage` — 结构化阅读文
- `LessonTemplate` — 课模板枚举

已完成：
- `LessonContent` 的实际渲染流程：`NewLessonScreen` 按 `Lesson.template` 渲染
- `Lesson.flattenedStages` 把 sub-lesson / listening phase 展开为 stage 列表
- 听力课含 `summary` phase：flatten 合成 `ListenOnly`，`ListenOnlyRenderer` 只听不答
- 阅读 Passage 与题目的关联渲染
- 语法点独立复习队列 + 练习题（`GrammarPoint.practiceItems`）
- 错题 → 语法跨路由（`MistakeEntry.grammarPointId` / `Interaction.grammarPointId` + `markDueNow`）

可选后续：
- 完整 Expression/Sentence 实体层与 catalog（当前练习题直接挂在 `practiceItems`）
- 听力 word-pairing 专用配对 UI（现用通用题型）

### 3.2 加载策略：per-section + SQLite 已完成 ✅

- ✅ per-section JSON + `index.json` 轻量索引
- ✅ 启动只加载 index + vocab；`loadSection` 按需正文
- ✅ drift SQLite seed / 缓存（`course_database.dart` schemaVersion 3，含 grammar `practiceItems`）
- ⚠️ 内容变更后需清 `course.swahili.db` 才能 reseed（无自动 reseed）

### 3.3 SRS：引擎 + 复习 UI + 会话奖励 已完成 ✅

- ✅ `SrsReviewPage` 闪卡复习
- ✅ Play 页 "Review" 入口
- ✅ 单词来源追踪（`LessonWordLink`）
- ✅ 会话完成奖励 XP/Gems（`XPEvent.srsReviewSession` × 张数 + `GemEvent.srsReviewSession`）

### 3.4 错题本：记录 + 列表 + 重做 + 语法跨路由 已完成 ✅

- ✅ `MistakeProvider` 上限 30，FIFO 清除
- ✅ `LessonViewModel` 自动记录错题（含 `grammarPointId`）
- ✅ `MistakeListPage` / `MistakePracticePage` 重做
- ✅ 错题列表语法标签 +「Review grammar」→ `markDueNow`

### 3.5 TTS：已完成 ✅

- ✅ 按 `TargetLanguage` 配置 TTS 语言码（`LanguageProvider.ttsLanguageCode`）
- ✅ `AudioController` 统一接管 TTS、离线音频、语速控制
- ✅ 听力/打字/SRS/字母页全部使用 `AudioController`
- ⚠️ 预生成离线音频包尚未大规模填充，目前框架已支持，缺少资产

### 3.6 内容创作：无外部工具

当前手写 JSON 无法支撑 11,000 课量产。需要：
- 非技术人员可用的 GUI 编辑器
- 可导入/导出
- 与 App 内容解耦，支持热更新

---

## 4. 推荐架构演进

### 4.1 分层架构（保持不变并强化）

```
┌─────────────────────────────────────────┐
│  UI Layer (Views / Renderers)           │
├─────────────────────────────────────────┤
│  Application Layer (Providers/ViewModel)│
├─────────────────────────────────────────┤
│  Domain Layer (Models: Section/Unit/... │
├─────────────────────────────────────────┤
│  Course Service (Loader/Indexer/Cache)  │
├─────────────────────────────────────────┤
│  Data Layer (JSON Assets / SQLite)        │
└─────────────────────────────────────────┘
```

**关键原则**：
- 内容数据与运行状态彻底分离
- 内容不可变，状态（进度、SRS、错题）可变并持久化
- InteractionRenderer 插件机制继续复用

### 4.2 课程加载：从“整树加载”到“索引 + 按需加载”

**阶段 1（短期）**：把 monolithic JSON 拆成 per-section JSON
```
assets/courses/swahili/
  index.json          # Language 元数据 + Section 轻量列表
  sections/
    s-foundations.json
    s-a2-expansion.json
    ...
  vocab.json          # 全量词汇（仍可接受，或再拆分）
```

启动时只读 `index.json`（KB 级），进入某个 Section 时才加载该 Section 的完整内容。

**阶段 2（中期）：迁移到 SQLite — 已完成** ✅
- 课程树、词汇、lesson content 索引存入 drift SQLite（`lib/data/course_database.dart` + `course_database_seeder.dart` + `course_repository.dart`）
- 规范化 sections/units/lessons 索引表 + lesson `content` JSON blob + vocab 表；`Interaction` sealed union 随 blob 不拆表
- 启动只读 sections 索引 + vocab；section 正文按需从 DB 重建并缓存；新增 `SwahiliCourse.loadLessonById(id)`「按 lesson ID 查询」能力
- 首次启动从 JSON assets seed（normalize 后存）；后续启动跳过 seed（DB 缓存）
- 用户状态（SRS/错题/进度/计分）仍在 StreamingSharedPreferences，未动

**阶段 3（长期，本地）**：本地内容工作流闭环
- 外部 GUI 编辑器导出 JSON → 提交 App 仓库 → App 首次启动 seed 进 SQLite
- 内容版本随 Git 管理；App 端可按 `index.json` 的 `version` 字段判断是否需要 reseed（schema bump 触发 drop + 重 seed）
- 不引入云端 CMS / 后端发布 / 增量同步（本项目本地优先、无云）

### 4.3 新增核心领域模型

```dart
// Sub-lesson：Lesson 内部子课
class SubLesson {
  String id;
  String name;
  int sortOrder;
  List<Stage> stages;
}

// ListeningPhase：听力课的三阶段
class ListeningPhase {
  String id;
  ListeningPhaseType type; // wordPairing, dialogue, summary
  String audioAsset;
  String? transcript;
  List<Interaction> items;
}

// Expression：多词表达
class Expression {
  String id;
  String term;          // 目标语
  String translation;   // 英语
  String? pronunciation;
  List<String> tags;
}

// GrammarPoint：语法点
class GrammarPoint {
  String id;
  String title;
  String explanation;
  List<String> exampleExpressionIds;
}

// LessonWordLink：单词/表达首次出现记录
class LessonWordLink {
  String wordId;
  String lessonId;
  LinkType type; // word / expression / grammarPoint
}
```

---

## 5. 内容模型扩展详细设计

### 5.1 Lesson 支持 Sub-lesson

把 `LessonContent.stages` 升级为可嵌套：

```dart
class LessonContent {
  List<SubLesson>? subLessons;   // 用于 lesson 1 / 3 / 5 / 6
  List<Stage>? stages;           // 兼容旧课
  List<ListeningPhase>? listeningPhases; // 用于听力课
  ReadingPassage? readingPassage;        // 用于阅读课
  String? audioAsset;
}
```

渲染层根据 `LessonType` 决定使用哪种流程：
- `normal`：使用 `subLessons`
- `listening`：使用 `listeningPhases`
- `reading`：使用 `readingPassage + stages`
- `review` / `challenge`：使用 `stages`

### 5.2 Section 1 Unit 模板（可复用）

定义 6 种 Lesson Template：

| 课号 | 类型 | 结构 |
|------|------|------|
| 1 | `intro` | 4 Sub-lessons，每 Sub-lesson 3 分钟 |
| 2 | `listening` | 3 Phases：word pairing → dialogue → summary |
| 3 | `practice` | 4 Sub-lessons，对应 Lesson 1 的 4 个 Sub-lesson，难度更高 |
| 4 | `reading` | ReadingPassage + 阅读理解题 |
| 5 | `review` | 3 Sub-lessons 混合复习 |
| 6 | `mastery` | 1 Sub-lesson，多题型，80% 通过线，可无限重试 |

后续 Section 课数递增时，只需增加 Unit 数量或每 Unit 的 Lesson 数量。

### 5.3 听力课三阶段

**Phase 1 — Word Pairing**
- 展示 5 个 TL 单词按钮，点击播放 TTS
- 展示 5 个英文释义按钮
- 用户配对 TL ↔ English

**Phase 2 — Dialogue Comprehension**
- 播放对话音频
- 3 题：
  1. 听到了哪些词（5 选 3）
  2. 细节理解（3 选 1）
  3. 主旨大意（3 选 1）

**Phase 3 — Summary**
- 播放总结音频，无题目，纯收尾

### 5.4 阅读课

```dart
class ReadingPassage {
  String title;
  List<String> paragraphs;
  int difficulty; // CEFR 数值
  List<String> linkedWordIds; // 本课要学的词
  List<String> linkedExpressionIds;
}
```

题目使用现有 `ReadingMCQ / ReadingTrueFalse / ReadingShortAnswer`。

---

## 6. SRS / 错题 / 复习体系（已部分实现）

### 6.1 SRS 复习流程 ✅

1. 用户点击 Play 页 "Review" 卡片
2. `SrsProvider.getDueWords()` 取出到期单词
3. 进入 `SrsReviewPage`
4. 展示卡片：正面 TL 词 + TTS 按钮，背面 English
5. 用户自评 Again / Hard / Good / Easy
6. 调用 `reviewWithQuality()` 更新 SM-2 状态
7. 完成队列后显示完成页，并发放会话奖励：
   - XP：`XPEvent.srsReviewSession` base 5 × 本会话张数
   - Gems：`GemEvent.srsReviewSession` 固定 +2（每会话一次）

### 6.2 首次出现追踪 ✅

在 `LessonViewModel` 中已注册 `ShowWord` 的 `wordId` 到 SRS，并写入 `LessonWordLink`：
- `{ wordId, lessonId, type }` 持久化到 `LocalStateKeys.lessonWordLinks`
- 复习时显示 "Learned in [Lesson Name]"
- 仅记录首次出现的课程，后续重复出现不覆盖

### 6.3 语法复习 ✅

为语法点单独建立 SRS 队列：
- ✅ `GrammarReviewProvider` 维护 `Map<String, SrsWord>`（key 是 grammarPointId），独立持久化键 `grammarReview.state`，复用 `SrsWord`/`Sm2Engine`/`ReviewQuality`
- ✅ 语法内容链路：`assets/courses/swahili/grammar_points.json` → drift `GrammarPoints` 表（schemaVersion 3，含 `practiceItems` JSON）→ seeder → `CourseRepository` → `swahiliGrammarPointById`
- ✅ `LessonContent.linkedGrammarPointIds` 声明本课所教语法点，`LessonViewModel._registerGrammarPoints` 在开课时注册进队列
- ✅ `GrammarReviewPage`：Explain（title + explanation）→ Practice（`practiceItems` via `InteractionRenderer`）→ Rate（Again/Hard/Good/Easy）
- ✅ 会话完成奖励：`XPEvent.grammarReviewSession` × 张数 + `GemEvent.grammarReviewSession` +2
- ✅ 错题→语法：`MistakeEntry.grammarPointId` + `Interaction.grammarPointId`；答错时 `markDueNow`；错题列表「Review grammar」
- ⚠️ 完整 Expression/Sentence catalog 仍 defer（练习题直接挂 `GrammarPoint.practiceItems`）
- ⚠️ 页内「Again」经 SM-2 lapse 回队列；与 `markDueNow` 并存

### 6.4 错题本 ✅

```dart
class MistakeEntry {
  String id;              // 错题唯一 ID
  String? wordId;         // 相关单词/表达
  String? grammarPointId; // 关联语法点（跨路由）
  String lessonId;
  String stageId;
  String interactionId;
  Interaction? interactionSnapshot; // 原题快照，用于重做
  String userAnswer;
  String correctAnswer;
  DateTime timestamp;
  int rewriteCount;       // 重写次数
}
```

`MistakeProvider`：
- ✅ 上限 30，新错题入队时若超限移除最旧条目
- ✅ `LessonViewModel` 在答错时自动记录（含 interaction 快照 + grammarPointId）
- ✅ `MistakeListPage` 查看错题（语法标签 + Review grammar）
- ✅ `MistakePracticePage`：把错题快照渲染成 Interaction 重做，答对后自动 `recordRewrite`，`rewriteCount >= 2` 移除
- ✅ "I got it now" 按钮仍可手动移除错题

### 6.5 听力 summary phase ✅

- ✅ `Interaction.listenOnly` + `ListenOnlyRenderer`（只听不答，CONTINUE）
- ✅ `Lesson._flattenListeningPhases` 对 `ListeningPhaseType.summary` 合成 `ListenOnly`（可用 phase.transcript TTS 回退）
- ✅ 测试课 `s-test` / `l-test-listening-1`：wordPairing → dialogue → summary

---

## 7. 内容创作与外部 GUI

### 7.1 内容创作分层

| 层级 | 负责内容 | 工具 |
|------|----------|------|
| 课程设计师 | 设计 Section/Unit/Lesson 结构、目标词表 | 外部 GUI / 表格 |
| 内容作者 | 编写题目、听力稿、阅读文 | 外部 GUI |
| 本地化/审核 | 校对、音频录制/TTS 校验 | 外部 GUI |
| 开发者 | 导入、版本管理、发布 | CLI / CI |

### 7.2 外部 GUI 工具建议

**方案：Tauri 桌面应用（纯本地，推荐）**
- 技术栈：React/Vue + Tauri（轻量原生壳）
- 功能：
  - 树形编辑器：Language → Section → Unit → Lesson → Sub-lesson
  - 题型模板：选择 Lesson Template 后自动生成占位题目
  - 词汇库管理：批量导入 CSV/Excel
  - 预览：实时模拟 App 渲染
  - 导出：生成 `assets/courses/` 下的 JSON 包（index.json + per-section files + vocab.json），直接落入 App 仓库
  - 校验：内置 JSON Schema + 复用 App 的 `validateSwahiliCourse` 规则，导出前本地校验
- 优点：非技术人员友好、完全离线、无托管成本、版本随 Git 可控、与现有 per-section JSON + SQLite seed 流程无缝衔接
- 缺点：多作者协作需靠 Git 分支（非实时）；需维护一个桌面应用

**明确不做云端 CMS**：本项目定位本地优先、无云。内容通过编辑器导出 JSON → 提交到 App 仓库 → App 首次启动 seed 进本地 SQLite。不引入 Supabase/Firebase 内容后端、不做云端发布与增量同步。

### 7.3 内容格式规范

从手写 JSON 迁移到编辑器产出，沿用现有布局：
- `assets/courses/<lang>/index.json` + `sections/<id>.json` + `vocab.json`（已落地）
- 词汇表集中单文件（当前规模可接受）
- 音频文件按 Lesson 文件夹组织
- 引入 JSON Schema 校验，编辑器自动生成符合 Schema 的内容；导出前跑与 App 一致的校验规则（`validateSwahiliCourse` / `validateSection`）

---

## 8. TTS / 音频策略 ✅

### 8.1 TTS 配置

按 TargetLanguage 配置：

| 语言 | TTS 语言码 | 备注 |
|------|-----------|------|
| Swahili | `sw` | `LanguageProvider.ttsLanguageCode` 返回 |
| Kannada | `kn` | 需扩展 `TargetLanguage` 与 `ttsLanguageCode` |
| Tamil | `ta` | 需扩展 `TargetLanguage` 与 `ttsLanguageCode` |

`AudioController.speak()` 调用前会自动 `setLanguage(_languageProvider.ttsLanguageCode)`，确保所有语音通道使用正确语言。

### 8.2 离线音频包

- 关键单词/表达预生成音频，打包到 `assets/audio/swahili/`
- `AudioController.speakWord()` 优先播放本地音频，缺失时回退到 TTS
- 听力课对话必须预生成音频，避免 TTS 不一致（目前听力题仍走 TTS，资产到位后自动切换）

### 8.3 TTS 语速与音色

- ✅ 提供 0.8x / 1.0x / 1.2x 速度选项（SRS Review 页可切换）
- 区分“单词慢读”与“句子常速”（可后续通过 `speak(speed: ...)` 细化）

---

## 9. 实施路线图（已更新进度）

### Phase 1：内容模型扩展（6–8 周）— 已完成
- ✅ 新增 `SubLesson`, `ListeningPhase`, `Expression`, `GrammarPoint`, `ReadingPassage`, `LessonTemplate`
- ✅ 改造 `LessonContent` 支持多种结构
- ✅ 更新 loader / validator
- ✅ 更新 renderer：`Lesson.flattenedStages` 把 sub-lesson / listening phase 展开为 stage；`NewLessonScreen` 渲染结构化 `ReadingPassage`
- ✅ 听力课 `summary` phase：`ListenOnly` + `ListenOnlyRenderer`（见 §6.5）

### Phase 2：SRS 复习 UI（2–3 周）— 已完成
- ✅ `SrsReviewPage`
- ✅ Play 页 "Review" 入口
- ✅ 单词来源展示（`LessonWordLink`）

### Phase 3：错题本（2–3 周）— 已完成
- ✅ `MistakeEntry` / `MistakeProvider`（含 `interactionSnapshot`、`grammarPointId`）
- ✅ `MistakeListPage`
- ✅ 30 条上限 FIFO
- ✅ `MistakePracticePage`：错题转成 Interaction 重做
- ✅ 错题 → 语法跨路由（`markDueNow`）

### Phase 4：TTS 与音频（2–3 周）— 已完成
- ✅ 按 TargetLanguage 配置 TTS
- ✅ 音频资产规范 + 本地 fallback
- ✅ 语速控制

### Phase 5：加载优化（3–4 周）— 已完成
- ✅ monolithic JSON → per-section JSON（`assets/courses/swahili/index.json` + `sections/*.json` + `vocab.json`）
- ✅ Section 索引（`index.json` 轻量列表 + `file` 指针）
- ✅ `SwahiliCourse` loader 重构：先读 index 再并行加载各 section 文件（仍一次性全量加载）
- ✅ 真懒加载：启动只加载 index + vocab（不碰 section 正文）；`SwahiliCourse.loadSection(id)` 按需加载并缓存某 section 正文；`CourseProvider.ensureSectionLoaded` 在切换 section 时触发；运行时 per-section 校验（`validateSection`），离线/CI 保留全树校验（`validateSwahiliCourse`）；同步词汇表启动仍就绪
- ✅ SQLite 迁移（§4.2 阶段2）：drift seed + 按需读

### Phase 6：补齐学习体系 — 核心项已完成
- ✅ 听力课 `summary` phase 专用 listen-only renderer（§6.5）
- ✅ 语法复习队列 `GrammarReviewProvider` + 语法复习页 + `practiceItems`（§6.3）
- ✅ SRS / 语法会话完成奖励 XP/Gems（§6.1）
- ✅ 错题 → 语法跨路由（§6.3 / §6.4）
- ✅ 冒烟测试课 `assets/courses/swahili/sections/s-test.json`（vocab / grammar / listening）
- ✅ **深色模式完整适配**：语义化颜色工具（`VarnamalaTheme.*(context)`）+ 全页面硬编码颜色修复 + `ThemeProvider` 持久化（`settings.themeMode`）+ 系统跟随（`ThemeMode.system`）+ Profile 页主题切换入口
- ✅ **学习数据统计仪表盘**：`StudyLog` / `DailyStudyStats` / `StudyLogRepository`（90 天日志 + 365 天聚合）/ `StudyStatsProvider` / `LearningStats` UI（今日概览 + 7 天 XP 柱状图 + 总时长/准确率/课数/复习数）；`LessonViewModel` / `SrsReviewPage` / `GrammarReviewPage` 集成自动记录
- 可选：游积分级/联赛、心数系统等 gamification（CLAUDE.md 待实现项）
- 可选：Expression/Sentence 完整内容层；word-pairing 专用配对 UI

### Phase 7：外部 GUI 编辑器 MVP（6–8 周）— **当前主路径 / 最后开发 phase**
- Tauri/React 桌面应用，纯本地（§7.2）
- Section/Unit/Lesson/Sub-lesson 树形编辑
- Lesson Template 与题型占位生成
- 词汇库批量导入（CSV/Excel）
- 实时预览（模拟 App 渲染）
- 导出 `assets/courses/<lang>/` JSON 包 + 内置 JSON Schema / `validateSwahiliCourse` 规则本地校验
- 多作者协作走 Git 分支（无实时云端协同）

### Phase 8：内容量产（持续）
- 招募内容作者，用 Phase 7 编辑器生产
- 按 Section 批量生产 → 导出 JSON → 提交 App 仓库 → App seed 进 SQLite
- QA 与 A/B 测试

**当前状态**：Phase 1–6 核心学习体系已完成（含 SQLite、语法复习+练习、SRS/语法奖励、听力 summary、错题跨路由、`s-test`）。另已完成架构加固 Wave A–E（GetIt 单例一致性、renderer `is` 分发、content version reseed、`LessonLinkStore` 单写、`loadLessonById` 开课、build 无副作用）。**下一步：Phase 7 本地 GUI 编辑器**，随后 Phase 8 内容量产。本项目本地优先、无云——不做云端 CMS / 后端发布 / 增量同步。

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 11,000 课 JSON 过大 | 启动慢、内存高 | 分 Section 加载 + SQLite |
| Freezed 模型频繁改动 | build_runner 生成开销 | 稳定核心模型后再大量生产内容 |
| 内容质量不一致 | 学习效果差 | 外部编辑器内置模板与校验；审核流程 |
| TTS 语种不支持 | 某些设备无法朗读 | 预生成离线音频包 |
| SRS 与课程进度耦合 | 代码复杂 | 保持 SRS 作为独立 Provider，通过事件通知 |
| 多作者冲突 | JSON 合并困难 | per-section 文件 + Git 分支（编辑器本地导出，无实时协同） |
| 开发周期过长 | 项目失控 | 按 Phase 交付 MVP，先跑通 Section 1 |

---

## 11. 技术选型建议

| 领域 | 当前 | 建议 |
|------|------|------|
| 状态管理 | Provider + ChangeNotifier | 保持，足够 |
| 路由 | Auto Route | 保持 |
| DI | GetIt + Injectable | 保持 |
| 本地持久化 | StreamingSharedPreferences + drift SQLite | SRS/进度/错题继续用 SharedPreferences；课程内容已迁 SQLite |
| 课程数据 | JSON Assets（seed 源）+ 本地 SQLite（运行时） | per-section JSON 由编辑器/开发者产出；App 首启 seed 进 SQLite，无云 |
| 外部编辑器 | 无 | Tauri + React/Vue，纯本地导出 JSON（最后开发 phase） |
| 后端 | Firebase（仅用户认证/排行榜/分析） | 内容分发**不上云**；Firebase 仅保留现有用户侧服务，不承载课程内容 |
| TTS | FlutterTts | 继续用，补充离线音频 |
| 构建 | flutter build | 保持 |

---

## 12. 下一步建议

1. **外部 GUI 编辑器（Phase 7）**：**当前主推荐**。Tauri/React 本地编辑器，导出 `assets/courses/<lang>/` JSON → Git → App seed SQLite；内置校验复用 `validateSwahiliCourse` / `validateSection`。
2. **内容量产（Phase 8）**：用编辑器按 Section 批量生产；先扩满 Section 1 模板课，再横向扩 Section。
3. **可选增强（非阻塞）**：
   - Expression/Sentence 完整 catalog（替代仅 `practiceItems`）
   - 听力 word-pairing 专用配对 UI
   - CLAUDE.md 中的联赛 / 心数 / 宝石消费等 gamification
   - 路由级 Lesson session dispose（Wave E 深化）
4. **内容版本**：`index.json` `version` 变化时自动 reseed（已实现）；发版改课请 bump version。

---

*文档更新日期：2026-07-09（Phase 6 收尾 + 架构 Wave A–E + 深色模式 + 学习数据统计）*
