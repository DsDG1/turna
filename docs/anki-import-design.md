# Anki 导入与通用刷题集成设计

> 本文档描述如何将 Varnamala 从「单一语言学习应用」扩展为「可导入 Anki 牌组进行通用刷题」的学习平台，并保证已有的 SRS 引擎、错题记录、弱词回顾、统计面板、AI 辅助等功能无缝复用。文档面向实现者，包含数据模型映射、模块拆分、AI 增强路径、大单元处理策略、测试策略与落地路线图。

---

## 1. 背景与目标

Varnamala 当前是一套以语言学习为内容、以课程树（Section → Unit → Lesson → Stage → Interaction）为组织形式的本地优先学习框架。其学习引擎与 AI 能力已经具备以下「与具体语言无关」的通用基础设施：

学习引擎层：

- SM-2 间隔重复引擎（`lib/core/sm2.dart` + `SrsQueueProvider` / `SrsProvider`）；
- FIFO 错题日志（`MistakeProvider` + `MistakeEntry`，携带 `interactionSnapshot` 可重做）；
- 弱词回顾（`WeakWordQuizAssembler`，基于 30 天 ≥2 次错误聚合）；
- 学习统计（`StudyStatsProvider`，每日/每周 XP、用时、准确率）；
- 词典检索（`DictionarySearch`，覆盖词汇/表达/语法点，纯内存子串匹配）；
- 统一题型渲染器（`Interaction` sealed union 12 种变体 + `LessonViewModel` 单循环遍历）；
- 每日挑战（`DailyChallengeAssembler`，从课程树随机采样可评分 Interaction 合成临时 Lesson）；
- 错题重做（`MistakeReviewAssembler`，从 `interactionSnapshot` 还原 Interaction 列表，与 `LessonViewModel` 对接）；
- 学习完成协调（`LessonCompletionCoordinator`，XP/宝石/成就/统计并行副作用，单点失败不阻断）。

AI 能力层：

- AI 课程生成（`AiCourseProvider` + `AiCourseService`，支持 OpenAI 兼容 API，DeepSeek reasoning 原生支持）；
- AI 对齐对话 / Wish Mode（`AiWishProvider`，自然语言对齐需求后生成课程 JSON）；
- AI 课中提示（`AiHintProvider`，不泄露答案的启发式辅导，stale-request 防护）；
- AI 单课变换（`AiLessonHelperProvider`，对已有 Lesson 做 AI 指令变换）；
- AI 资源接地（`AiGroundedResourceProvider`，加载既有词汇/表达/语法供 AI 复用 ID）；
- AI 自洽引擎（`normalizeResources` / `autoFixResources` / `checkResourceSelfConsistency`，自动修复悬空引用并校验）；
- Genre 模板系统（`ai_genre.dart`，7 种 `[intro]/[practice]/[review]/[listening]/[reading]/[mastery]/[mixed]` 标签映射到 Lesson 模板）；
- Textbook 导入管线（`TextbookImportProvider` + `MarkdownChopper` + `KnowledgePrompt` + `KnowledgeMerger` + `TextbookToCourse`，完整的文件→章节切分→LLM 知识提取→碰撞合并→Section 生成→DB 落库流水线）。

这些能力的输入端都是「结构化卡片」（词汇/表达/语法点 + Interaction），与 Anki「笔记 (note) → 卡片 (card)」模型高度同构。同时，Textbook 导入管线已经证明了一条「外部内容 → 中间表示 → 适配 → 落库」的可行路径，Anki 导入可以复用其中的碰撞合并策略、Section 写入管道和 AI 自洽引擎。

核心目标：

1. 支持导入 Anki `.apkg` / `.colpkg` 文件，将其转换为 Varnamala 的课程结构并落库；
2. 支持超大牌组（万级卡片）的导入与复习，不阻塞 UI、不爆内存；
3. Anki 自带的复习状态（due/interval/ease/lapses/reps）迁移到 Varnamala 的 `SrsWord`，迁移后复习曲线连续；
4. 刷题过程中产生的错题进入既有 `MistakeProvider`，可被「错题本」「弱词回顾」「每日挑战」复用；
5. Anki 牌组与语言课程在 UI 上并存且可区分，但不引入新的渲染分支；
6. **AI 增强**：利用既有 AI 基础设施实现 notetype 智能识别、卡片质量提升、干扰项自动生成、课中提示、Wish 式课程化等能力，让 Anki 牌组不仅是「翻面卡片」，还能升级为结构化课程。

非目标：

- 不做 Anki 同步（AnkiWeb 对接）——保持本地优先；
- 不内嵌 Anki 牌组编辑器——编辑仍由 Anki 桌面端完成，Varnamala 只做「消费侧」；
- 不替换现有课程树结构——Anki 牌组作为「另一类 Section」挂载，复用同一棵树。

---

## 2. Anki 文件格式概览

`.apkg` 本质是一个 ZIP 压缩包，解压后包含：

| 文件 | 作用 |
|------|------|
| `collection.anki2`（或 `media` 列表 + `collection.anki21`） | SQLite 数据库，存放 notes / cards / revlog / decks / notetypes |
| `media` | JSON 映射 `<数字>: <媒体文件名>`，媒体文件以数字命名散落在包内 |
| `0` `1` `2` ... | 实际的图片/音频媒体文件 |

`collection.anki2` 的关键表：

- `col`：单行表，存放 `decks`（JSON）、`models`/`notetypes`（JSON，定义字段与模板）、`conf`（调度参数）等；
- `notes`：`id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data`。`flds` 是字段值用 `\x1f` 分隔的字符串，`mid` 指向 notetype；
- `cards`：`id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data`。`did` 指向 deck，`ord` 指向该 note 的第几张卡片模板；
- `revlog`：复习日志，可选迁移用于统计还原。

调度字段含义（Anki 的 SM-2 变体）：

- `due`：到期日（学习队列中是分钟数，复习队列中是天数偏移）；
- `ivl`：当前间隔（天）；
- `factor`：易度因子 ×1000（Anki 内部 2.5 对应 2500）；
- `reps`：连续正确次数；`lapses`：遗忘次数；
- `queue`：-2 埋葬 / -1 暂停 / 0 新卡 / 1 学习 / 2 复习 / 3 日复习预演。

理解 `queue` 与 `due` 的双语义是状态迁移的关键（见 §6.4）。

---

## 3. 现状可复用点

### 3.1 领域模型契合度

Varnamala 的 `WordEntry`（id/term/translation/pronunciation/audioAsset/pos/tags）与 Anki 一条 note 的「正面/反面」二元字段几乎一一对应；`Expression` 对应带上下文的句子卡；`GrammarPoint` 对应带说明的语法卡。三者的并集足以覆盖绝大多数 Anki 基础牌组。

`Interaction` sealed union 已覆盖 12 种题型。Anki 的「正面提示 → 反面答案」最自然地映射到 `Interaction.multipleChoice`（自动生成干扰项）或 `Interaction.fillBlank`（若正面包含挖空）或一种新的轻量 `Interaction.ankiCard`（正面/反面纯展示，见 §5.2）。

### 3.2 SRS 引擎契合度

`SrsQueueProvider` 是一个 **id → SrsWord 的 prefs blob**，与卡片类型解耦：任何 id 都可以注册进队列并参与 SM-2 调度。`SrsWord` 字段（intervalDays / ease / reps / lapses / dueAt / isLeech）与 Anki 的 `ivl / factor / reps / lapses / due` 语义完全一致，迁移是字段重命名 + 单位换算。这意味着 Anki 牌组导入后，其原有复习进度可以直接续接，用户不会「从零开始」。

### 3.3 错题与弱词契合度

`MistakeEntry` 携带 `interactionSnapshot`（一个完整的 `Interaction` JSON 快照），这意味着错题重做不依赖原始课程是否还在——即使 Anki 牌组被删除，错题本仍可重放。`MistakeReviewAssembler` 已经证明这条路径可行：它从 `MistakeEntry.interactionSnapshot` 还原 `Interaction` 列表，重新分配 id（`mistake-review-${entry.id}`），组装成临时 Lesson 交给 `LessonViewModel`。`AnkiCard` 作为 `Interaction` 子类型，天然兼容这条路径。

`WeakWordQuizAssembler` 基于 `wordId` 聚合 30 天内 ≥2 次错误，只要导入时给每张 Anki 卡片分配稳定的 `wordId`，弱词回顾立即生效。

### 3.4 渲染与统计契合度

`LessonViewModel` 遍历 `List<Interaction>` 并通过渲染器注册表分发，刷题流程只是「把一组卡片拼成一个临时 Lesson」。`StudyStatsProvider` 聚合的是 study log（XP/用时/准确率），与内容来源无关。`LessonCompletionCoordinator` 在 Lesson 完成时并行触发 XP/宝石/成就/统计，与内容类型完全解耦——Anki 刷题完成后自动获得 XP、宝石、成就检查、统计记录。

### 3.5 Textbook 导入管线的可复用模式

Textbook 导入管线（`TextbookImportProvider`）已经建立了「外部内容 → Varnamala 课程」的完整流水线，其中多个组件可直接复用或模式复用：

- `ImportStrategy` 枚举（`merge` / `skipExisting` / `forceReplace` / `appendAsNew`）——Anki 导入同样面临「同一牌组重复导入」或「Anki 词汇与课程词汇碰撞」的场景，可直接复用这一策略体系；
- `KnowledgeMerger.analyze()` 的碰撞报告模式——导入前预览「N 条新词 / M 条重复」，让用户决策策略；
- `AiCourseProvider.saveSectionJson()` 的事务写入管道（`normalizeResources` → `autoFixResources` → `checkResourceSelfConsistency` → `Section.fromJson` → `_writeSectionToDb`）——Anki 导入的 Section 写入走同一管道，保证资源自洽；
- `TextbookToCourse.buildSections()` 的「知识 → Section」组装模式——Anki 的 `AnkiDeckAssembler` 可参考其 Section/Unit/Lesson 组装逻辑。

### 3.6 AI 能力的可复用点

| AI 能力 | Anki 场景应用 |
|---------|--------------|
| `AiCourseService.requestTextReply()` | notetype 智能识别：把 notetype 字段定义发给 LLM，让它判断该映射为 `AnkiCard` / `WordEntry+MCQ` / `Expression+FillBlank` |
| `AiCourseService.requestLessonTransform()` | 卡片增强：对一批 `AnkiCard` 调用 AI 变换，自动生成干扰项、补充释义、添加例句 |
| `AiHintProvider.explainQuestion()` | Anki 卡片课中提示：用户翻面前可请求 AI 给出解题思路（不泄露答案） |
| `AiGroundedResourceProvider` | 导入时检查 Anki 词汇与既有课程词汇的重叠，复用已有 `wordId` 避免重复 |
| `autoFixResources` / `checkResourceSelfConsistency` | Anki 导入 Section 的自洽校验，与 AI 课程生成走同一管道 |
| `AiWishProvider` | 「把我的 Anki 牌组变成结构化课程」：用户用自然语言描述需求，AI 对齐后把 Anki 卡片重组为 intro/practice/listening 等模板 |
| `AiLessonHelperProvider` | 对 Anki Lesson 做 AI 变换：「给这 20 张卡加例句」「把 Cloze 卡转成 MCQ」 |
| `GenreMeta` / `genreToTemplate()` | Anki Lesson 的模板标注：导入时 AI 识别卡片内容特征，自动打 `[practice]` / `[reading]` 等 genre 标签 |

---

## 4. 整体架构

```
┌──────────────────────────────────────────────────────────────────────┐
│                            用户操作                                    │
│    导入 .apkg / AI 增强预览 / 选择牌组刷题 / 课中 AI 提示 / 每日挑战      │
└────────┬──────────────────────────────────┬──────────────────────────┘
         │                                  │
  ┌──────▼──────────┐              ┌────────▼────────┐
  │  AnkiImportFlow │              │ AnkiReviewHub   │ (Play Hub 入口)
  │  (导入向导)      │              │ (组装临时Lesson) │
  └──┬──┬──┬───────┘              └────────┬────────┘
     │  │  │                               │
     │  │  │  ┌────────────────────────────▼──────────┐
     │  │  │  │ AnkiReviewAssembler (分批20张/批)       │
     │  │  │  │ → DailyChallengeAssembler (混入每日挑战) │
     │  │  │  │ → MistakeReviewAssembler (错题重做)     │
     │  │  │  └────────────────────┬──────────────────┘
     │  │  │                       │
     │  │  │              ┌────────▼────────┐
     │  │  │              │ LessonViewModel │ ◄── 既有，零改动
     │  │  │              │ + AnkiCardRenderer│
     │  │  │              └────────┬────────┘
     │  │  │                       │
     │  │  │       ┌───────────────┼───────────────┐
     │  │  │       │               │               │
     │  │  │  ┌────▼────┐   ┌──────▼──────┐  ┌────▼─────┐
     │  │  │  │SrsProvider│  │MistakeProvider│  │StudyStats│ ◄── 既有，复用
     │  │  │  └─────────┘   └─────────────┘  └──────────┘
     │  │  │
     │  │  │  ┌─────────────────────────────────────────┐
     │  │  │  │ AI 增强层 (可选，用户配置 API 后启用)       │
     │  │  │  │  ┌────────────────┐  ┌────────────────┐ │
     │  │  │  │  │AnkiNotetypeAI  │  │AnkiCardEnhancer│ │
     │  │  │  │  │(LLM识别notetype)│  │(干扰项/例句/释义)│ │
     │  │  │  │  └────────┬───────┘  └───────┬────────┘ │
     │  │  │  │           │                  │          │
     │  │  │  │  ┌────────▼──────────────────▼────────┐ │
     │  │  │  │  │ AiCourseService (既有 HTTP 核心)    │ │
     │  │  │  │  │ + AiGroundedResourceProvider       │ │
     │  │  │  │  │ + autoFixResources (自洽修复)       │ │
     │  │  │  │  └────────────────────────────────────┘ │
     │  │  │  │  ┌────────────────┐  ┌────────────────┐ │
     │  │  │  │  │AiHintProvider  │  │AiWishProvider  │ │
     │  │  │  │  │(课中提示)       │  │(牌组→课程化)    │ │
     │  │  │  │  └────────────────┘  └────────────────┘ │
     │  │  │  └─────────────────────────────────────────┘
     │  │  │
     │  │  ┌▼──────────────┐
     │  │  │AnkiCardAdapter│ (note→WordEntry/Interaction)
     │  │  │ + 碰撞合并     │ (复用 ImportStrategy)
     │  │  └──────┬────────┘
     │  │         │
     │  ┌▼──────────────────┐
     │  │AnkiDeckAssembler  │ (deck→Section/Unit/Lesson)
     │  │ + AiCourseProvider│ (saveSectionJson 管道)
     │  └──────┬────────────┘
     │         │
  ┌──▼─────────┐
  │AnkiImporter│ (解析 .apkg → AnkiCollection)
  └────────────┘
```

新增模块集中在「导入与适配」层（左侧 + AI 增强层），右侧的复习调度、错题、统计、弱词全部是既有 Provider，无需改动其核心逻辑。

---

## 5. 数据模型与映射

### 5.1 Anki 牌组 → Varnamala 课程树

一个 Anki deck 映射为一个 Varnamala `Section`，其下挂一个或多个 `Unit`（按子牌组或按卡片数量分片，见 §7）。每个 `Unit` 下生成若干「虚拟 Lesson」，每节 Lesson 容纳固定数量的卡片（默认 20 张），避免单 Lesson 过大导致一次加载全部 Interaction。

映射规则：

| Anki 概念 | Varnamala 概念 | 说明 |
|-----------|----------------|------|
| Collection（一个 .apkg） | 一棵「Anki 导入」Section 子树 | id 前缀 `anki-<importId>-` |
| Deck | Section 或 Unit（视层级） | 顶层 deck → Section；子 deck → Unit |
| Note（mid + flds） | `WordEntry` / `Expression` / `AnkiCard` | 按 notetype 字段数与命名启发式或 AI 识别映射 |
| Card（nid + ord + 调度） | `Interaction` + `SrsWord` | ord 决定正反面方向 |
| Tags | `WordEntry.tags` | 直接搬运，支持词典过滤 |
| Media（图片/音频） | `audioAsset` / 图片 asset | 拷贝到 `<app docs>/anki_media/<importId>/` |

Section 的 `level` 字段填 `"Anki"`，`prerequisiteSectionIds` 留空——Anki 牌组不参与语言课程的前置依赖链，独立可达。

### 5.2 新增 Interaction 变体：`AnkiCard`

Anki 卡片本质是「正面 HTML → 反面 HTML」，强行套到 `MultipleChoice` 会丢失 Cloze/图片/音频等富信息。新增一个轻量变体：

```dart
const factory Interaction.ankiCard({
  @Default('') String id,
  required String front,        // 正面（已渲染的纯文本或简易 HTML 子集）
  required String back,         // 反面
  @Default(<String>[]) List<String> audioAssets,  // 正反面音频
  @Default(<String>[]) List<String> imageAssets,  // 正反面图片
  String? hint,                 // extra 字段或 AI 生成的提示
  String? sourceNoteId,         // 追溯到 Anki note
}) = AnkiCard;
```

渲染器实现一个「翻面卡片」组件：先显示 front，用户点击「显示答案」后翻面显示 back，并提供「再次/困难/良好/简单」四档评分按钮（与 Anki 体验一致，映射到 `ReviewGrade`）。这个变体是唯一需要新增的渲染分支，其余 12 种既有 Interaction 不受影响。

`AnkiCard` 被纳入 `isChallengeGradable()` 的判断（见 §8.7），使每日挑战可以混入 Anki 卡片。`MistakeReviewAssembler` 也天然支持它——快照中存的就是 `AnkiCard` JSON，还原后走翻面渲染器。

为什么不在 `WordEntry` 上硬塞正反面：`WordEntry` 的 `term/translation` 是为语言学习语义设计的（会被词典、TTS、弱词回顾按 `term` 检索）。Anki 通用卡片的「正反面」没有语言语义，强行复用会污染词典索引。新增 `AnkiCard` 让两类内容在领域模型上清晰隔离，但在 SRS / 错题 / 统计层面共享同一套 id 机制。

### 5.2.1 客观题型双轨（已实现）

翻面卡只应承接「无法客观判分」的卡片。适配层（`AnkiCardAdapter.adapt`）按双轨输出：

- **客观轨**：卡片有可验证答案时，直接生成既有客观 `Interaction`（`MultipleChoice` / `FillBlank` / `ListenAndPick` / `TypeTheWord`），复用现有渲染器、`submitInteraction(bool)` 判分、错题本、SM-2 调度全链路，不引入第二条刷题流水线；
- **主观轨**：长答案（>60 字符或含换行）、空答案的卡片保留 `AnkiCard` 翻面卡 + 「忘了/记住」二元自评。

`NotetypeMappingType` 扩展为 `ankiCard / wordEntry / expression / cloze / multipleChoice / fillBlank / typeAnswer / listenPick`。其中 `ankiCard` 是「自动决策」而非「强制翻面」——逐卡决策顺序：

1. 正面含 `{{c\d+::` 挖空标记 → `FillBlank`；
2. 正面含音频且答案短 → `ListenAndPick`（deck 内 ≥3 个不同干扰项）或 `TypeTheWord`（不足时）；
3. 答案短且干扰项 ≥3 → `MultipleChoice`（不再用「—」占位，不足则降级）；
4. 答案短但干扰项不足 → 输入判定 `FillBlank`（正面 + `_____`，大小写不敏感 trim 比较）；
5. 其余 → `AnkiCard` 翻面卡兜底。

**模板渲染**：`AnkiNotetype.templates` 现在保存完整的 `qfmt`/`afmt`，由最小渲染器 `AnkiTemplateRenderer`（`lib/application/anki/anki_template_renderer.dart`）渲染：支持 `{{Field}}`、`{{#Field}}/{{^Field}}` 条件块、`{{FrontSide}}`、`{{cloze:Field}}`；`{{hint:}}` 丢弃、未知滤镜降级为字段值、特殊字段（`{{Tags}}` 等）渲染为空。每张卡按其 `ord` 对应模板渲染正反面（`afmt` 渲染时 `FrontSide` 置空以隔离答案部分），Basic (and reversed) 等卡组方向正确；同一张 note 的不同 ord 可走不同轨道。无模板体的导入（旧数据）回退到字段索引映射，行为不变。

**媒体透传**：`MultipleChoice` 增加 `audioAssets`，`FillBlank` 增加 `audioAssets`/`imageAssets`（均向后兼容的可选字段），渲染器通过共享组件 `AnkiMediaStrip`（`lib/views/lesson/components/anki_media_strip.dart`）展示音频播放按钮与图片；`AudioController.speakWord` 识别 `anki://` 引用并解析到本地文件直接播放（不进 TTS），因此 `ListenAndPick`/`TypeTheWord` 渲染器零改动即可播放 Anki 音频。

**错题接线**：`LessonViewModel.submitInteraction` 增加按题覆盖参数 `recordMistake` / `mistakeWordId`。Anki 复习会话（`AnkiReviewSessionPage`）仍然 `loadLessonInstance(recordMistakes: false)`，但提交回调对客观题传 `recordMistake: true`（附带 SRS wordId，弱词聚合可见），翻面卡自评不进错题本。评分粒度保持对错二元（correct→`ReviewGrade.known`，wrong→`ReviewGrade.unknown`），SM-2 引擎零改动。

**干扰项池**：组装器（`AnkiDeckAssembler`）现在为 `wordEntry / ankiCard / multipleChoice / listenPick` 映射同时收集正面值池与背面值池；适配器按「答案来自哪一面」选择对应池（反向卡的答案是正面字段，干扰项应同语言）。

### 5.3 导入元数据表

在 SQLite 中新增一张 `anki_imports` 表，记录每次导入的元信息，支持增量更新与卸载：

```sql
CREATE TABLE anki_imports (
  import_id     TEXT PRIMARY KEY,      -- UUID
  source_path   TEXT NOT NULL,         -- 原始 .apkg 路径
  source_hash   TEXT NOT NULL,         -- 文件 sha256，用于检测变更
  imported_at   INTEGER NOT NULL,
  deck_count    INTEGER NOT NULL,
  note_count    INTEGER NOT NULL,
  card_count    INTEGER NOT NULL,
  media_count   INTEGER NOT NULL,
  notetypes_json TEXT NOT NULL,        -- 原始 notetype 定义 + 映射决策
  ai_enhanced   INTEGER NOT NULL DEFAULT 0,  -- 是否经过 AI 增强
  version       INTEGER NOT NULL DEFAULT 1
);
```

卡片与 note 的映射关系通过 `WordEntry.tags`（或 `AnkiCard.sourceNoteId`）中的 `anki:<importId>` 标签反查，无需新建关联表——卸载时按标签批量删除即可。

### 5.4 碰撞合并策略（复用 `ImportStrategy`）

Anki 导入面临两类碰撞：同一牌组重复导入（note id 相同），以及 Anki 词汇与既有课程词汇碰撞（term 相同）。直接复用 Textbook 导入的 `ImportStrategy` 枚举：

| 策略 | 行为 | 对应 `KnowledgeMerger` 逻辑 |
|------|------|---------------------------|
| `merge` | 同 id 覆盖，新 id 追加 | DB `insertOnConflictUpdate` |
| `skipExisting` | 跳过已存在的 id | `existingIds.contains(id)` 过滤 |
| `forceReplace` | 全量覆盖 | 同 merge，但语义明确 |
| `appendAsNew` | id 追加时间戳后缀 | `'${id}-$suffix'` |

碰撞报告复用 `KnowledgeMerger.analyze()` 模式：导入前扫描 Anki notes 的 `wordId` 与 `CourseRepository.vocabulary()` 的 id 集合做交集，在预览页显示「N 条新卡 / M 条已存在」，用户选择策略后执行。

---

## 6. 关键模块设计

### 6.1 AnkiImporter（解析层）

职责：解压 `.apkg`、读取 `collection.anki2` SQLite、产出中间表示 `AnkiCollection`。

```dart
class AnkiImporter {
  /// 解析 .apkg，返回中间表示 + 媒体文件清单。
  /// 不触碰 Varnamala 数据库——纯函数，便于测试。
  Future<AnkiCollection> parse(String apkgPath);
}

@freezed
class AnkiCollection with _$AnkiCollection {
  const factory AnkiCollection({
    required Map<int, AnkiNotetype> notetypes,   // mid → 定义
    required Map<int, AnkiDeck> decks,           // did → deck
    required List<AnkiNote> notes,
    required List<AnkiCard> cards,
    required Map<int, String> media,             // 数字 → 文件名
    required String mediaDir,                    // 解压后的媒体目录
  }) = _AnkiCollection;
}
```

实现要点：

- 使用 `archive` 包解压 ZIP，`sqlite3`（dart 原生或 ffi）读取 `.anki2`——避免引入 Flutter 平台插件；
- `.colpkg`（Anki 2.1+ 导出格式）是带 `collection.anki21` 的变体，按文件头判断；
- 大文件流式读取：notes / cards 表用 `SELECT ... LIMIT ? OFFSET ?` 分页，避免一次性 `toList()` 万级数据；
- `flds` 按 `\x1f` split，长度对齐 notetype `flds` 定义；
- 媒体文件懒拷贝：导入时只记录映射，复习时按需拷贝到 assets 目录（首次访问触发）。

### 6.2 AnkiCardAdapter（适配层）

职责：把 `AnkiNote` + `AnkiCard` 转成 `(WordEntry?, Interaction)` 二元组。这是 Anki 语义 → Varnamala 语义的核心翻译器。

适配分两条路径：**启发式规则**（默认，离线可用）和 **AI 识别**（可选，需配置 API）。

#### 6.2.1 启发式映射（离线）

```dart
class AnkiCardAdapter {
  /// 按 notetype 字段命名启发式判断卡片类型。
  /// - 字段名含 Front/Back/正/反 → AnkiCard
  /// - 字段名含 Term/Translation/词/译 → WordEntry + MultipleChoice
  /// - 字段名含 Expression/Sentence/句 → Expression + FillBlank
  /// - 字段名含 Cloze/{{c1::}} → FillBlank（提取挖空）
  /// - 其余 → AnkiCard（兜底）
  (WordEntry?, Interaction) adapt(
    AnkiNote note,
    AnkiCard card, {
    required NotetypeMapping mapping,  // 可配置的映射表
  });
}
```

启发式规则用一张可配置的映射表（JSON），允许用户在导入预览页调整「这个 notetype 用哪种渲染器」。映射结果存入 `anki_imports.notetypes_json`，重导入时复用。

#### 6.2.2 AI 识别 notetype（在线，可选）

当用户配置了 `AiApiConfig` 时，导入预览页可启用「AI 智能识别」按钮。对每个 notetype，把字段定义发给 LLM：

```dart
class AnkiNotetypeAI {
  /// 用 LLM 识别 notetype 应映射为哪种 Varnamala 卡片类型。
  /// 复用 AiCourseService.requestTextReply()。
  Future<NotetypeMapping> identify({
    required AiApiConfig config,
    required AnkiNotetype notetype,
  });
}
```

System prompt 示例：

> 你是一个 Anki 牌组分析助手。给定一个 Anki notetype 的字段定义（字段名列表），判断它最适合映射为以下哪种 Varnamala 卡片类型：
> 1. `ankiCard` — 通用正反面卡片（适合非语言类内容）
> 2. `wordEntry` — 词汇卡（正面是词，反面是释义，可生成选择题）
> 3. `expression` — 句子/表达卡（可生成填空题）
> 4. `cloze` — 挖空卡（Anki Cloze 格式）
>
> 返回 JSON：`{"mapping": "wordEntry", "frontField": "Term", "backField": "Translation", "reason": "..."}`

这与 `KnowledgePrompt.buildExtractionMessages()` 的模式一致——构建 system+user 消息对，调用 `requestTextReply()`，解析 JSON 结果。

id 生成策略：`wordId = "anki-${importId}-n${note.id}"`，`interactionId = "${wordId}-c${card.ord}"`。note id 在原 Anki 库中是毫秒时间戳，全局唯一且稳定，重导入时可按 id 幂等合并。

### 6.3 AnkiDeckAssembler（组装层）

职责：把适配后的卡片按 deck 结构组装成 Section/Unit/Lesson 并写入数据库。

```dart
class AnkiDeckAssembler {
  /// 将 AnkiCollection 组装为 Varnamala 课程树并落库。
  /// 返回导入摘要（importId, 计数）。
  Future<AnkiImportSummary> assemble({
    required AnkiCollection collection,
    required String importId,
    required ICourseRepository repo,
    required AiCourseProvider? courseProvider,  // 可选：走 AI 自洽管道
  });
}
```

组装规则：

- 顶层 deck → Section（`id = "anki-${importId}-s${did}"`）；
- 若 deck 含子 deck，每个子 deck → Unit；否则该 deck 下直接挂一个 Unit；
- 每个 Unit 下的卡片按 20 张一组切分为 Lesson（`id = "anki-${importId}-l${did}-${seq}"`），Lesson 名为「Deck名 #1/#2/...」；
- Lesson 的 `template` 用 `LessonTemplate.legacy`（flat stage list），每个 Stage 含一个 `AnkiCard` Interaction；
- 写入优先走 `AiCourseProvider.saveSectionJson()`——这样自动经过 `normalizeResources` → `autoFixResources` → `checkResourceSelfConsistency` 自洽管道，与 AI 课程生成和 Textbook 导入走同一条写入路径。如果 `courseProvider` 不可用（离线模式），降级走 `CourseRepository.bulkInsertCourseTree()`。

### 6.4 SRS 状态迁移

这是「无缝衔接」的关键。Anki 的调度字段到 `SrsWord` 的映射：

| Anki 字段 | SrsWord 字段 | 转换 |
|-----------|--------------|------|
| `cards.due`（queue=2 复习队列，天数偏移） | `dueAt` | `DateTime.now().add(Duration(days: due))` |
| `cards.due`（queue=1 学习队列，分钟数） | `dueAt` | `DateTime.now().add(Duration(minutes: due))` |
| `cards.due`（queue=0 新卡） | `dueAt` | `DateTime.now()`（立即到期） |
| `cards.ivl` | `intervalDays` | 直接取值 |
| `cards.factor` | `ease` | `factor / 1000.0` |
| `cards.reps` | `reps` | 直接取值 |
| `cards.lapses` | `lapses` | 直接取值 |
| `cards.queue` ∈ {-2,-1} | `isLeech = true` | 暂停/埋葬视为 leech |
| `cards.queue` = 0 且无复习记录 | `SrsWord.fresh(id)` | 全新状态 |

迁移实现：

```dart
class AnkiSrsMigrator {
  /// 将 Anki 卡片调度状态迁移到 SrsWord 并批量注册进 SrsProvider。
  Future<void> migrate({
    required List<AnkiCard> cards,
    required AnkiIdMapper idMapper,   // note.id → wordId
    required SrsProvider srsProvider,
  });
}
```

注意 Anki 的 `ease` 下限是 1.3（1300），而 Varnamala 的 `Sm2Engine` 默认下限需对齐——迁移时若 `factor < 1300` 钳制到 1300，避免复习时 ease 溢出导致间隔塌缩。

迁移后 `SrsProvider.getDueWords()` 会自动包含 Anki 卡片，既有 SRS 复习 UI（`SrsReviewScreen`）无需改动即可刷 Anki 卡——只要 `SrsReviewScreen` 的渲染能识别 `AnkiCard` 类型 Interaction 并翻面展示。

可选：迁移 `revlog` 表到 `StudyStatsProvider` 的 study log，还原历史复习记录。这需要把 Anki 的 `revlog`（时间戳/评分/时长）映射为 `StudyLog` 条目，用于统计面板的「历史准确率」曲线。MVP 不做，作为阶段三的可选项。

### 6.5 CourseRepository 扩展

`ICourseRepository` 新增批量写入接口（仅 Anki 导入使用，语言课程仍走 seeder）：

```dart
abstract class ICourseRepository {
  // ... 既有读接口 ...

  /// 批量写入词汇（Anki 导入用）。
  Future<void> bulkInsertVocabulary(List<WordEntry> words);
  /// 批量写入 Section/Unit/Lesson（Anki 导入用）。
  Future<void> bulkInsertCourseTree(Section section);
  /// 按标签批量删除（Anki 卸载用）。
  Future<int> deleteByTag(String tag);
}
```

`CourseRepository`（concrete）实现这些方法时，用 SQLite 事务包裹批量插入，万级卡片在单事务内完成，避免逐条提交的开销。这与 `AiCourseProvider._writeSectionToDb()` 的事务写入模式一致。

### 6.6 AnkiReviewHub（复习入口）

在 `PlayHubScreen` 新增一个「Anki 刷题」入口卡片。点击后进入 `AnkiReviewScreen`，该页面：

- 列出所有已导入的 Anki Section，显示到期卡片数（通过 `SrsProvider.getDueWords()` 过滤 `anki-` 前缀的 wordId）；
- 选择某个 Section 后，`AnkiReviewAssembler` 把该 Section 下到期的 `AnkiCard` Interaction 收集起来，组装成一个临时 `Lesson`（`template: legacy`），交给既有 `NewLessonScreen` / `LessonViewModel` 跑完整刷题流程；
- 刷题过程中的评分（再次/困难/良好/简单）映射到 `ReviewGrade`，调用 `SrsProvider.reviewWord(wordId, quality)`；
- 答错的卡片通过既有 `MistakeProvider.record(MistakeEntry(...interactionSnapshot: ankiCard...))` 记录，错题本和弱词回顾立即收录；
- 完成时触发 `LessonCompletionCoordinator.complete()`，自动获得 XP、宝石、成就检查、统计记录。

这条路径完全复用 `LessonViewModel` 的「遍历 Interaction → 渲染 → 评分 → 记录」主循环，不引入第二条刷题流水线。

`AnkiReviewAssembler` 的实现模式参考 `DailyChallengeAssembler`：收集可评分的 Interaction → 分批采样 → 重新分配 id → 包装成单 Stage 的临时 Lesson。区别在于 DailyChallenge 是随机采样，AnkiReview 是按到期日排序。

---

## 7. AI 增强路径

本节详述如何利用既有 AI 基础设施为 Anki 导入增加智能能力。所有 AI 功能都是**可选的**——用户未配置 `AiApiConfig` 时，导入走纯启发式路径，功能完整但无 AI 增强。

### 7.1 AI Notetype 智能识别

**场景**：用户导入一个「日语核心 1 万词」牌组，notetype 字段名为 `Expression` / `Meaning` / `Reading` / `Audio`。启发式规则可能误判为 `AnkiCard`（兜底），但 AI 能识别出 `Expression` 对应 `Expression` 模型、`Meaning` 对应 `translation`、`Reading` 对应 `pronunciation`。

**实现**：`AnkiNotetypeAI.identify()`（见 §6.2.2）。对牌组中每个 notetype 调用一次 LLM（通常一个牌组只有 1-3 种 notetype，成本极低）。识别结果在预览页展示，用户可修改后确认。

**复用点**：`AiCourseService.requestTextReply()` + system/user 消息对构建模式（同 `KnowledgePrompt.buildExtractionMessages`）。

### 7.2 AI 卡片增强（`AnkiCardEnhancer`）

**场景**：用户有一批「正面=英文单词 / 反面=中文释义」的卡片，导入后只是翻面卡片。用户希望把它们升级为选择题（自动生成干扰项），或者给每张卡补充例句。

**实现**：

```dart
class AnkiCardEnhancer {
  /// 对一批 AnkiCard 调用 AI 变换，生成增强版 Interaction。
  /// 复用 AiCourseService.requestLessonTransform()。
  Future<EnhancementResult> enhance({
    required AiApiConfig config,
    required List<Interaction> ankiCards,
    required String instruction,  // e.g. "为每张卡生成3个干扰项，变成选择题"
    required Set<String> resourceIds,  // 接地资源 ID
  });
}
```

底层调用 `AiCourseService.requestLessonTransform()`，把 AnkiCard 列表包装成一个临时 Lesson JSON，附带用户指令。LLM 返回变换后的 Lesson JSON，经 `parseCompletion()` 解析和自洽校验后，替换原始卡片。

**复用点**：`AiCourseService.requestLessonTransform()` + `buildLessonTransformPrompt()` + `parseCompletion()`（含 `autoFixResources` 自洽修复）。这与 `AiLessonHelperProvider.transform()` 走完全相同的管道，只是输入源从「课程树中的 Lesson」变成「Anki Card 列表」。

**增强类型示例**：

- 「生成干扰项，变成选择题」→ `AnkiCard` → `MultipleChoice`（正面=提示，正确答案=反面，干扰项=AI 生成）
- 「为每张卡添加例句」→ `AnkiCard` + `hint` 字段填充 AI 生成例句
- 「把 Cloze 卡转成填空题」→ `AnkiCard`（含 `{{c1::}}`）→ `FillBlank`
- 「提取关键词，生成匹配题」→ `AnkiCard` → `MatchWords`

### 7.3 AI 接地：词汇去重与复用

**场景**：用户既有一套土耳其语课程（Section 1 问候语 8 词），又导入一个 Anki「土耳其语 500 词」牌组。其中 `merhaba`（你好）在两边都有。如果各建一个 `WordEntry`，会产生两个独立 `wordId`，SRS 队列里会出现重复卡片。

**实现**：导入时加载 `AiGroundedResourceProvider`，把既有词汇的 `term` 集合作为接地上下文。`AnkiCardAdapter` 适配时检查 Anki note 的正面字段值是否与既有 `term` 匹配：

```dart
// 在 AnkiCardAdapter.adapt() 中
final existingWord = groundedProvider.findWordByTerm(note.frontField);
if (existingWord != null) {
  // 复用已有 wordId，只创建新的 Interaction（Card ord 不同）
  wordId = existingWord.id;
  // 标记为「已接地」，不重复写入 WordEntry
}
```

**复用点**：`AiGroundedResourceProvider.load(scope: ['words'])` + `formatContext()`。这与 AI 课程生成时的「复用已有资源 ID 避免重复」机制完全一致。

### 7.4 AI 课中提示（`AiHintProvider` 复用）

**场景**：用户在刷 Anki 卡片时，看到正面提示后想不起来答案，希望获得一个不泄露答案的提示。

**实现**：`AnkiCard` 渲染器在「显示答案」按钮旁增加一个「AI 提示」按钮（仅在 `AiApiConfig.isComplete` 时显示）。点击后构建 `AiQuestionContext`：

```dart
final ctx = AiQuestionContext(
  language: 'Anki',
  typeLabel: '翻面卡片',
  promptLabel: ankiCard.front,
  // correctLabel 不传——AiHintProvider 的 system prompt 明确不泄露答案
);
await aiHintProvider.explainQuestion(config: config, ctx: ctx);
```

`AiHintProvider` 的 system prompt 已经是「语言辅导老师，用启发式方法引导，不直接给出答案」的 persona，对 Anki 卡片同样适用。stale-request 防护（`_generation` token）也天然生效。

**复用点**：`AiHintProvider` 全量复用，包括 stale-request guard、对话历史管理、UI 渲染。

### 7.5 AI Wish Mode：牌组课程化

**场景**：用户导入了一个「英语 GRE 词汇 3000」牌组，但不想只是翻面刷题，希望 Varnamala 把它组织成 intro（展示新词）→ practice（选择题练习）→ review（混合复习）的结构化课程。

**实现**：导入后在 Anki Section 详情页提供「AI 课程化」按钮。点击后进入 `AiWishProvider` 的对话流：

1. 用户描述需求：「把这 3000 个 GRE 词汇组织成 10 个 Unit，每个 Unit 有 intro/practice/review 三课，每课 20 个词」；
2. `AiWishProvider.sendAlignment()` 与 LLM 对齐，LLM 给出 2-3 条具体建议（同 Textbook 的 alignment 模式）；
3. 用户确认后 `AiWishProvider.finalizeGeneration()`，在 prompt 中注入 Anki 词汇列表作为接地资源；
4. LLM 返回结构化 Section JSON（含 `subLessons` / `stages` / `MultipleChoice` 等），经 `parseCompletion()` + 自洽校验后写入 DB。

**复用点**：`AiWishProvider` 全量复用（`sendAlignment` + `finalizeGeneration`），`AiGroundedResourceProvider` 提供 Anki 词汇作为接地上下文，`AiCourseProvider.saveSectionJson()` 写入 DB。

**genre 标签**：用户可在指令中加 `[practice]` 或 `[reading]` 标签，`parseGenreTag()` 自动识别并切换 Lesson 模板——与 AI 课程生成的 genre 机制完全一致。

### 7.6 AI 卡片质量评估

**场景**：用户导入一个牌组后，想知道哪些卡片质量差（空字段、HTML 碎片、无释义等），需要修复或删除。

**实现**：可选的 AI 批量评估。对前 N 张卡片（默认 100）调用 `AiCourseService.requestTextReply()`，system prompt 要求评估卡片质量并返回 JSON 评分（`{cardId, score, issues: [...]}`）。结果在导入预览页以质量热力图展示。

GUI 工具中已有 `content_quality.py`（6 维度质量评分）和 `extraction_quality.py`，可参考其评估维度（完整性、准确性、格式规范、重复度等）。MVP 用简单规则（空字段检测 + HTML 碎片检测）替代 AI 评估，阶段二再引入 LLM 评估。

---

## 8. 与现有功能的无缝集成

### 8.1 SRS 引擎

`SrsProvider.registerAll(wordIds)` 已支持批量注册新词，`reviewWord(wordId, quality)` 已支持单卡评分。Anki 导入只需在 `AnkiSrsMigrator.migrate` 末尾调用 `registerAll` + 覆写已有 `SrsWord` 状态即可。复习 UI `SrsReviewScreen` 通过 `Interaction` 类型分发渲染，新增 `AnkiCard` 渲染器后即可展示 Anki 卡片，无需改动 SRS 调度逻辑。

### 8.2 错题记录

`MistakeEntry.interactionSnapshot` 携带完整 `Interaction` JSON，`AnkiCard` 作为 `Interaction` 子类型自然可被快照。错题本重做时，`MistakeReviewAssembler.assemble()` 把快照还原为 `Interaction` 列表——它已经实现了「从 `interactionSnapshot` 还原 → 重新分配 id（`mistake-review-${entry.id}`）→ 组装临时 Lesson」的完整流程，`AnkiCard` 无需特殊处理。

`MistakeEntry.wordId` 字段填入 Anki 卡片的 `wordId`（`anki-<importId>-n<noteId>`），`WeakWordQuizAssembler` 按 `wordId` 聚合弱词时自动包含 Anki 卡片。

### 8.3 弱词回顾

`WeakWordQuizAssembler` 查询 30 天内 ≥2 次错误的 `wordId`，从 `CourseRepository.vocabulary()` 取回 `WordEntry` 拼装小测。Anki 导入的卡片如果是 `WordEntry` 适配路径，弱词回顾立即生效。如果是 `AnkiCard` 路径（无 `WordEntry`），需要扩展 `WeakWordQuizAssembler` 支持「从 `interactionSnapshot` 直接拼装」——参考 `MistakeReviewAssembler` 的快照还原模式，从 `MistakeEntry` 的 `interactionSnapshot` 直接取 `AnkiCard` 而非查 `WordEntry`。这是一个小的适配点，不破坏既有语言卡片的弱词流程。

### 8.4 词典检索

`DictionarySearch` 是纯内存子串匹配函数（`searchDictionary(query, vocabById, expressionsById, grammarPointById)`），Anki 导入的 `WordEntry` 会自动进入词典检索范围（因为它写入 `vocabulary` 表）。`AnkiCard` 类型的卡片不进入词典（无 `term` 语义），但可在词典页增加「Anki 卡片」筛选 tab，按 `tags` 中的 `anki:<importId>` 过滤展示，展示时取 `AnkiCard.front` 作为 `title`、`back` 作为 `subtitle`。

### 8.5 学习统计

`StudyStatsProvider` 聚合 study log（XP/用时/准确率/打卡），与内容来源完全解耦。`LessonCompletionCoordinator.complete()` 在 Lesson 完成时调用 `StudyStatsProvider.recordActivity(StudyActivityType.lessonComplete, ...)`，Anki 刷题完成后自动走这条路径。统计面板增加「按来源分组」维度，通过 study log 的 `lessonId` 前缀 `anki-` 区分语言课程与 Anki 牌组。

### 8.6 每日提醒与 Streak

`StreakProvider` 与 `flutter_local_notifications` 与内容无关，Anki 刷题自然延续打卡。无需改动。

### 8.7 每日挑战

`DailyChallengeAssembler.collectGradableInteractions()` 遍历课程树收集可评分 Interaction。当前 `isChallengeGradable()` 排除 `ShowWord` 和 `ListenOnly`。`AnkiCard` 需要加入可评分列表——因为翻面卡片有「再次/困难/良好/简单」四档评分，是可评分的。只需在 `isChallengeGradable()` 中不排除 `AnkiCard`（默认就不排除，因为它是新类型不是 `ShowWord`/`ListenOnly`）。

这意味着用户每日挑战可能混入 Anki 卡片，增加多样性。如果用户不希望混入，可在设置中关闭「每日挑战包含 Anki 卡片」开关，`collectGradableInteractions` 按 Section 的 `level != "Anki"` 过滤。

### 8.8 课程树 UI

Anki Section 与语言课程 Section 共用 `CourseTree`，通过 `level` 字段区分。课程树渲染时对 `level == "Anki"` 的 Section 使用独立图标（如卡片堆叠图标）和颜色分组，放在课程树底部或独立 tab。Anki Section 内的 Lesson 显示卡片数量而非完成星标（因为 Anki 刷题没有「完成」概念，只有「到期/未到期」）。

### 8.9 GUI 工具集成

`tool/gui` 的 PySide6 桌面编辑器已支持丰富的课程编辑能力。Anki 导入可在 GUI 侧增加一个「导入 Anki 牌组」菜单项，复用 `section_import_service.py` 的导入管道：

- GUI 侧解析 `.apkg`（Python 有成熟的 `genanki` / `sqlite3` 库，比 Dart 侧更简单）；
- 转换为 Varnamala Section JSON；
- 在 GUI 的 3-column workshop 中预览和编辑（`unified_workspace.py` + `course_tree.py`）；
- 通过 `CourseAdapter` 写入 assets 或通过 `git_library` 推送到资源库。

这条路径让教师在桌面端完成 Anki 导入和编辑，再同步到移动端。GUI 侧的 `experienceai.md` 中描述的 AI 能力（Workshop / Orbit / Quality Campaign）也可用于 Anki 卡片的 AI 增强。

---

## 9. 大单元处理策略

Anki 牌组动辄数千至数万张卡片（如「日语核心 1 万词」「英语 GRE 词汇」）。直接组装成一个 Lesson 会导致 `LessonViewModel` 一次性持有万级 Interaction 列表，内存与渲染都不可行。采用四层策略：

### 9.1 导入期分片

`AnkiDeckAssembler` 按 20 张卡片/Lesson 切分，一个万级牌组产生 500 个 Lesson。Lesson 元数据（不含 content）轻量，500 条 Section/Unit/Lesson 元数据在 SQLite 中约几十 KB，课程树加载无压力。Lesson content（Interaction JSON）按需懒加载——`lessonById` 已是 L2 按需加载（见 `docs/authoring/course-layout.md` 的三级加载模型），天然支持。

### 9.2 复习期分批

`AnkiReviewAssembler` 不会把所有到期卡片塞进一个临时 Lesson，而是分批：

- 每批最多 20 张到期卡片，组装成一个临时 Lesson；
- 用户完成一批后，检查是否还有到期卡片，有则继续下一批，无则结束；
- 顶部显示「本次已复习 X 张，剩余 Y 张到期」进度条。

这与 Anki 桌面端的「每日复习上限」体验一致，且保证单次 `LessonViewModel` 的 Interaction 列表不超过 20。实现模式参考 `DailyChallengeAssembler.assemble(count: 20, random: ...)` 的采样 + 包装逻辑。

### 9.3 媒体懒拷贝

Anki 牌组的媒体文件可能数百 MB（图片/音频）。导入时不全量拷贝到 assets 目录，而是：

- 媒体文件解压到 `<app docs>/anki_media/<importId>/`；
- `AnkiCardAdapter` 生成的 `audioAsset` / `imageAsset` 路径指向该目录的相对路径；
- 新增一个 `AnkiAudioResolver`（实现 `VocabAudioResolver` 接口）负责把 `anki://` 前缀的路径解析为本地文件流；
- 复习时首次访问某媒体文件才触发文件读取，未访问的媒体不占内存。

### 9.4 SRS 队列分桶

`SrsProvider` 的 state 是单一 prefs blob（`Map<String, SrsWord>`）。万级 Anki 卡片加入后，该 blob 会膨胀到几 MB，每次 `persist` 全量序列化会有性能问题。两个可选优化（按需启用）：

- **分 key 存储**：Anki 卡片的 SRS 状态存到独立 prefs key（`anki_srs_state_<importId>`），`SrsProvider` 内部合并多个 key 的视图。`getDueWords()` 跨 key 聚合，单次 persist 只写变更的 key。
- **迁移到 SQLite**：当卡片总量超过阈值（如 5000），SRS 状态从 prefs blob 迁移到 SQLite 表 `srs_state`，按 `wordId` 索引，支持增量更新。这是更大的改动，建议作为第二阶段优化。

第一阶段（万级以内）优先用分 key 存储，避免过早引入 SQLite 迁移复杂度。

### 9.5 Anki 复习上限配置

参考 Anki 桌面端的调度配置，在设置中增加：

- 每日新卡上限（默认 20）：`AnkiReviewAssembler` 每次最多取 N 张 `queue=0` 的新卡 + M 张到期复习卡；
- 每日复习上限（默认 200）：超过后提示「今日复习已完成」；
- 这两个参数存储在 `StreamingSharedPreferences`，key 为 `anki.dailyNewLimit` / `anki.dailyReviewLimit`。

---

## 10. 数据流：一次完整导入与复习

### 10.1 导入流（含 AI 增强）

```
用户选 .apkg
  → AnkiImporter.parse(path) → AnkiCollection
  → [可选] AnkiNotetypeAI.identify(notetype) → NotetypeMapping
    → AiCourseService.requestTextReply(config, messages)
    → LLM 返回 {"mapping": "wordEntry", "frontField": "Term", ...}
  → [可选] AiGroundedResourceProvider.load(['words'])
    → 检查 Anki 词汇与既有课程词汇的重叠
  → AnkiCardAdapter.adapt(note, card, mapping) → [(WordEntry?, Interaction)]
  → 碰撞报告 (复用 KnowledgeMerger.analyze 模式)
    → 用户选择 ImportStrategy (merge/skip/replace/append)
  → AnkiDeckAssembler.assemble(collection, importId, repo, courseProvider)
    → Section/Unit/Lesson 树
    → [优先] AiCourseProvider.saveSectionJson(sectionJson)
      → normalizeResources → autoFixResources → checkResourceSelfConsistency
      → Section.fromJson → _writeSectionToDb (事务)
    → [降级] CourseRepository.bulkInsertCourseTree (离线)
  → AnkiSrsMigrator.migrate(cards, srsProvider) → SrsWord 状态写入
  → 媒体文件拷贝到 <docs>/anki_media/<importId>/
  → anki_imports 表记录元数据
  → CourseLoader.invalidateCaches()
  → 课程树刷新，新 Section 出现
```

### 10.2 AI 增强流（导入后）

```
用户在 Anki Section 详情页点「AI 增强」
  → 选择增强类型（生成干扰项 / 加例句 / Cloze 转填空 / 课程化）
  → AnkiCardEnhancer.enhance(config, ankiCards, instruction, resourceIds)
    → AiCourseService.requestLessonTransform(lessonJson, instruction, resourceIds)
    → buildLessonTransformPrompt(lessonJson, instruction, resourceIds)
    → LLM 返回变换后的 Lesson JSON
    → parseCompletion(body) → autoFixResources → checkResourceSelfConsistency
  → 预览变换结果（diff 视图）
  → 用户确认 → AiCourseProvider.updateLessonInDb(lesson)
  → 或用户取消 → 保留原始卡片
```

### 10.3 复习流

```
用户进 Play → Anki 刷题入口
  → AnkiReviewScreen 列出 Anki Section + 到期数
    → SrsProvider.getDueWords() 过滤 anki- 前缀
  → 选择 Section
  → AnkiReviewAssembler.collectDue(sectionId)
    → 取到期 SrsWord.wordId
    → 按 wordId 查 Interaction（从 Lesson content 反查）
    → 分批 20 张 → 临时 Lesson (id: anki-review-<timestamp>)
  → NewLessonScreen + LessonViewModel 跑刷题
    → AnkiCardRenderer 渲染翻面卡片
    → [可选] AiHintProvider.explainQuestion() 课中提示
    → 每张卡评分 → SrsProvider.reviewWord(wordId, quality)
    → 答错 → MistakeProvider.record(MistakeEntry{wordId, interactionSnapshot})
  → LessonCompletionCoordinator.complete()
    → XP + 宝石 + 成就检查 + 统计记录 (并行)
  → 检查剩余到期 → 继续下一批 or 结束
```

### 10.4 混合每日挑战流

```
用户进 Play → 每日挑战
  → DailyChallengeAssembler.collectGradableInteractions(courseProvider)
    → 遍历所有 Section（含 Anki Section）
    → AnkiCard 被收录（isChallengeGradable 不排除它）
  → pickChallengeItems(pool, 15, random)
  → 组装临时 Lesson (id: daily-challenge)
  → NewLessonScreen + LessonViewModel
    → 混合渲染：MultipleChoice / FillBlank / AnkiCard / ...
  → 完成后统一走 LessonCompletionCoordinator
```

---

## 11. 测试策略

### 11.1 单元测试

| 模块 | 测试重点 | 模式参考 |
|------|---------|---------|
| `AnkiImporter` | 解压 + SQLite 读取 + `flds` 分隔 | 准备一个最小 `.apkg` 测试 fixture（3 notes / 2 decks / 1 notetype） |
| `AnkiCardAdapter` | 启发式映射：Front/Back → AnkiCard，Term/Translation → WordEntry，Cloze → FillBlank | 纯函数测试，输入 `AnkiNote` + `AnkiCard`，输出 `(WordEntry?, Interaction)` |
| `AnkiDeckAssembler` | deck → Section/Unit/Lesson 分片，20 张/Lesson | 输入 mock `AnkiCollection`，输出 Section 树结构断言 |
| `AnkiSrsMigrator` | queue/due 双语义，factor/1000，ease 钳制 | 输入 `AnkiCard`（各 queue 值），输出 `SrsWord` 字段断言 |
| `AnkiNotetypeAI` | LLM 返回 JSON 解析，fallback 到启发式 | mock `AiCourseService`，验证 NotetypeMapping 解析 |
| `AnkiCardEnhancer` | Lesson JSON 变换 + 自洽校验 | mock `AiCourseService.requestLessonTransform`，验证 `autoFixResources` 生效 |
| 碰撞合并 | `ImportStrategy.merge/skip/replace/append` | 复用 `KnowledgeMerger` 测试模式 |

### 11.2 集成测试

- **端到端导入**：准备一个 100 张卡片的 `.apkg` fixture → 导入 → 验证 Section/Unit/Lesson 落库 → 验证 SRS 队列注册 → 验证 `CourseLoader` 能加载新 Section；
- **端到端复习**：导入后 → `AnkiReviewAssembler` 组装临时 Lesson → `LessonViewModel` 遍历 → 验证评分写入 `SrsProvider` + 答错写入 `MistakeProvider` + 完成触发 `LessonCompletionCoordinator`；
- **错题重做**：Anki 卡片答错 → `MistakeReviewAssembler` 从快照还原 → `AnkiCardRenderer` 渲染 → 再次答题；
- **每日挑战混入**：导入 Anki 牌组 → `DailyChallengeAssembler.collectGradableInteractions` 包含 `AnkiCard` → 挑战中出现 Anki 卡片。

### 11.3 Golden 测试

`AnkiCardRenderer` 的翻面卡片 UI 需要 golden baseline（正面 / 翻面 / 评分按钮三态），与既有渲染器的 golden 测试模式一致。

### 11.4 性能测试

- 导入 5000 张卡片的 `.apkg`：导入时间 < 10s（不含 AI），内存峰值 < 100MB；
- SRS 队列 5000 个 `AnkiCard`：`getDueWords()` < 50ms，`persist()` < 200ms（分 key 存储后）；
- 复习分批：单批 20 张 Lesson 的 `LessonViewModel.load()` < 100ms。

---

## 12. 实现路线图

### 阶段一：MVP（最小可用刷题）

目标：能导入一个基础牌组并刷题，复用 SRS 与错题。

- [ ] `AnkiCard` Interaction 变体 + `AnkiCardRenderer` 翻面渲染器 + golden baseline；
- [ ] `AnkiImporter`：解压 + 读 SQLite，支持 Anki 2.1 格式；
- [ ] `AnkiCardAdapter`：基础 Front/Back notetype → `AnkiCard` 映射（启发式）；
- [ ] `AnkiDeckAssembler`：deck → Section/Unit/Lesson，按 20 张分片；
- [ ] `ICourseRepository` 扩展 `bulkInsert*` 接口；
- [ ] `AnkiSrsMigrator`：调度字段迁移到 `SrsWord`；
- [ ] `AnkiReviewScreen` + `AnkiReviewAssembler`：Play Hub 入口；
- [ ] 导入预览页（显示牌组结构、卡片数、notetype 识别结果、碰撞报告）；
- [ ] `isChallengeGradable` 确认包含 `AnkiCard`；
- [ ] 单元测试 + 集成测试 + `.apkg` fixture。

### 阶段二：AI 增强

目标：利用既有 AI 基础设施提升导入质量和学习体验。

- [ ] `AnkiNotetypeAI`：LLM 识别 notetype → NotetypeMapping；
- [ ] `AnkiCardEnhancer`：AI 变换（生成干扰项 / 加例句 / Cloze 转填空），复用 `requestLessonTransform` + `autoFixResources`；
- [ ] AI 接地：`AiGroundedResourceProvider` 检查 Anki 词汇与课程词汇重叠；
- [ ] `AiHintProvider` 适配 `AnkiCard` 课中提示；
- [ ] `AiWishProvider` 牌组课程化（`[practice]` / `[reading]` genre 标签）；
- [ ] 启发式映射表完善（Cloze → FillBlank，Term/Translation → WordEntry + MCQ）。

### 阶段三：富媒体与大单元

- [ ] `AnkiAudioResolver` + 媒体懒拷贝；
- [ ] 词典「Anki 卡片」筛选 tab；
- [ ] 弱词回顾支持 `AnkiCard` 快照路径（参考 `MistakeReviewAssembler` 模式）；
- [ ] 统计面板「按来源分组」维度；
- [ ] SRS 状态分 key 存储（`anki_srs_state_<importId>`）；
- [ ] 导入增量更新（按 `source_hash` 检测变更，仅导入新增/修改的 note）；
- [ ] 牌组卸载（按 `anki:<importId>` 标签批量删除 + 媒体清理）；
- [ ] Anki 复习上限配置（每日新卡/复习卡上限）。

### 阶段四：体验打磨

- [ ] `.colpkg` 格式支持；
- [ ] 导入进度条 + 取消；
- [ ] 牌组排序与置顶；
- [ ] GUI 工具「导入 Anki 牌组」菜单项（`section_import_service.py` 扩展）；
- [ ] 可选：SRS 状态迁移到 SQLite（>5000 卡片时自动切换）；
- [ ] 可选：`revlog` 迁移到 study log（历史复习记录还原）；
- [ ] 可选：导出 Varnamala 卡片为 .apkg（反向导出）。

---

## 13. 风险与权衡

**SQLite 依赖**：读取 `.anki2` 需要在 Flutter 端引入 `sqlite3` 包（dart 原生或 ffi）。项目已用 Drift/SQLite 存储课程数据，但 Drift 封装的是自有库；Anki 的 `.anki2` 是外部 SQLite 文件，需用 `sqlite3` 包直接打开只读连接。权衡：引入 `sqlite3` ffi 会增加约 2-3 MB 体积，但换来原生解析速度，优于纯 Dart 的 SQLite 实现。替代方案：在 GUI 侧（Python）解析 `.apkg` 并输出 Section JSON，Flutter 端只读 JSON——但这要求用户先在桌面端处理，降低移动端独立可用性。

**notetype 启发式的脆弱性**：Anki 牌组的字段命名无规范，启发式映射不可能 100% 准确。缓解：启发式 + AI 识别双路径；导入预览页让用户确认/调整每个 notetype 的映射目标；映射结果存入 `anki_imports.notetypes_json`，重导入时复用。

**HTML 渲染**：Anki 卡片正反面常含 HTML（`<br>`、`<img>`、`<b>`）。Flutter 的 `Html` widget 可渲染子集，但复杂 CSS/JS 不支持。权衡：MVP 只支持纯文本 + 图片 + 音频，复杂 HTML 降级为纯文本 + 警告提示；后续可引入 `flutter_widget_from_html` 提升兼容度。GUI 侧 Python 的 HTML 处理能力更强，可在导入时预处理 HTML（去 script/style、简化标签）。

**SRS 状态膨胀**：万级卡片的 SRS blob 可能达数 MB，prefs 全量序列化有性能风险。阶段三的分 key 存储是必选项，不是可选项——MVP 阶段若用户导入大牌组需明确提示「建议单牌组不超过 2000 张」。

**与语言课程的边界**：Anki 牌组与语言课程共用课程树，可能在课程树中造成视觉混乱。缓解：Section 的 `level` 字段区分（`"Anki"` vs `"A1"..."B2"`），课程树渲染时对 `level == "Anki"` 的 Section 用独立图标/颜色分组，放在课程树底部或独立 tab。

**AI 依赖的渐进式降级**：所有 AI 功能都是可选的。`AiApiConfig.isComplete == false` 时，导入走纯启发式路径，复习走纯翻面卡片，课中无 AI 提示，每日挑战仍可混入 Anki 卡片。这保证了离线/未配置 API 的用户体验完整，AI 只是锦上添花。

**Anki 调度参数差异**：Anki 的 SM-2 变体与 Varnamala 的 `Sm2Engine` 在细节上有差异（Anki 有 fuzzing、learning steps、relearning steps；Varnamala 是标准 SM-2）。迁移后的首次复习可能与 Anki 桌面端的调度有 1-2 天偏差。缓解：迁移时记录原始参数，在 `SrsWord` 中增加可选字段 `originalScheduler: 'anki'`，后续可按需对齐调度行为。MVP 接受偏差——用户在 Varnamala 刷题后，调度由 Varnamala 的 `Sm2Engine` 接管，几轮后自然收敛。

---

## 14. 相关文件索引

### 既有文件 — 学习引擎

| 文件 | 角色 |
|------|------|
| `lib/core/sm2.dart` | SM-2 引擎，Anki 状态迁移的目标 |
| `lib/application/srs_queue_provider.dart` | SRS 队列基类，`registerAllItems` / `reviewItem` 复用 |
| `lib/application/srs_provider.dart` | 词汇/表达 SRS 队列，Anki 卡片注册入口 |
| `lib/application/mistake_provider.dart` | 错题日志，`record(MistakeEntry)` 复用 |
| `lib/application/mistake_review_assembler.dart` | 错题重做，快照还原模式参考 |
| `lib/application/weak_word_quiz_assembler.dart` | 弱词回顾，需扩展支持 AnkiCard 快照 |
| `lib/application/study_stats_provider.dart` | 学习统计，自动汇入 |
| `lib/application/lesson_completion_coordinator.dart` | 完成副作用协调，自动触发 |
| `lib/application/lesson_viewmodel.dart` | 学习主循环，Interaction 遍历零改动 |
| `lib/application/daily_challenge_assembler.dart` | 每日挑战，`isChallengeGradable` 包含 AnkiCard |
| `lib/application/dictionary_search.dart` | 词典检索，纯内存子串匹配 |

### 既有文件 — 领域模型

| 文件 | 角色 |
|------|------|
| `lib/domain/course/interaction.dart` | 题型 sealed union，需新增 `AnkiCard` 变体 |
| `lib/domain/course/word_entry.dart` | 词汇模型，Anki 适配路径之一 |
| `lib/domain/course/srs_word.dart` | SRS 状态模型，Anki 调度迁移目标 |
| `lib/domain/course/mistake_entry.dart` | 错题模型，`interactionSnapshot` 复用 |
| `lib/domain/course/lesson.dart` | Lesson 模型 + `LessonTemplate.legacy` |
| `lib/domain/repositories/i_course_repository.dart` | 仓库接口，需扩展 `bulkInsert*` |
| `lib/data/course_repository.dart` | 仓库实现，新增批量写入 |
| `lib/courses/course_loader.dart` | 课程加载器，Anki Section 走同一加载路径 |
| `lib/domain/audio/vocab_audio_resolver.dart` | 音频解析抽象，新增 `AnkiAudioResolver` 实现 |

### 既有文件 — AI 能力

| 文件 | 角色 |
|------|------|
| `lib/application/ai/ai_course_service.dart` | AI HTTP 核心，`requestTextReply` / `requestLessonTransform` / `parseCompletion` 复用 |
| `lib/application/ai/ai_course_provider.dart` | 课程生成 + `saveSectionJson` 写入管道复用 |
| `lib/application/ai/ai_hint_provider.dart` | 课中提示，AnkiCard 场景直接复用 |
| `lib/application/ai/ai_wish_provider.dart` | Wish Mode，牌组课程化复用 |
| `lib/application/ai/ai_lesson_helper_provider.dart` | 单课变换，AnkiCard 增强参考 |
| `lib/application/ai/ai_grounded_resource_provider.dart` | 资源接地，Anki 词汇去重复用 |
| `lib/application/ai/ai_resource_consistency.dart` | 自洽引擎，`autoFixResources` / `checkResourceSelfConsistency` 复用 |
| `lib/application/ai/ai_genre.dart` | Genre 模板，`[practice]` 等标签复用 |
| `lib/application/ai/ai_prompt_builder.dart` | Prompt 构建，`buildLessonTransformPrompt` 复用 |
| `lib/application/ai/ai_api_config.dart` | API 配置，`isComplete` / `isDeepSeekHost` 复用 |
| `lib/application/ai/textbook/knowledge_merger.dart` | 碰撞合并，`ImportStrategy` 枚举复用 |
| `lib/application/ai/textbook/textbook_import_provider.dart` | Textbook 导入流程，模式参考 |
| `lib/application/ai/textbook/textbook_to_course.dart` | 知识→Section 组装，模式参考 |

### 既有文件 — UI

| 文件 | 角色 |
|------|------|
| `lib/views/lesson/new_lesson_screen.dart` | 学习页，刷题复用 |
| `lib/views/review/srs_review_screen.dart` | SRS 复习 UI，需识别 AnkiCard 渲染 |
| `lib/views/play/play_hub_screen.dart` | Play Hub，新增 Anki 刷题入口 |

### 既有文件 — GUI 工具

| 文件 | 角色 |
|------|------|
| `tool/gui/src/backend/ai_generator.py` | AI 生成后端，Python 侧 Anki 导入参考 |
| `tool/gui/src/application/section_import_service.py` | Section 导入服务，可扩展 Anki 导入 |
| `tool/gui/src/backend/content_quality.py` | 质量评分，Anki 卡片质量评估参考 |
| `tool/gui/src/backend/knowledge_merger.py` | Python 侧碰撞合并，与 Dart 侧对齐 |

### 新增文件（按实现顺序）

| 文件 | 职责 | 阶段 |
|------|------|------|
| `lib/domain/course/anki_card.dart` | `AnkiCard` Interaction 变体 + freezed | 一 |
| `lib/views/lesson/renderers/anki_card_renderer.dart` | 翻面卡片渲染器 | 一 |
| `lib/application/anki/anki_importer.dart` | `.apkg` 解析 | 一 |
| `lib/application/anki/anki_card_adapter.dart` | note → Interaction 适配 | 一 |
| `lib/application/anki/anki_deck_assembler.dart` | deck → Section 组装 | 一 |
| `lib/application/anki/anki_srs_migrator.dart` | SRS 状态迁移 | 一 |
| `lib/application/anki/anki_review_assembler.dart` | 复习分批组装 | 一 |
| `lib/views/anki/anki_import_screen.dart` | 导入向导 UI | 一 |
| `lib/views/anki/anki_review_screen.dart` | 复习入口 UI | 一 |
| `lib/application/anki/anki_notetype_ai.dart` | AI notetype 识别 | 二 |
| `lib/application/anki/anki_card_enhancer.dart` | AI 卡片增强 | 二 |
| `lib/application/anki/anki_template_renderer.dart` | qfmt/afmt 最小模板渲染器（客观题型双轨引入） | 一 |
| `lib/views/lesson/components/anki_media_strip.dart` | 客观题干的 Anki 音频/图片展示组件 | 一 |
| `lib/domain/audio/anki_audio_resolver.dart` | Anki 媒体解析 | 三 |
| `test/anki/anki_importer_test.dart` | 解析层测试 | 一 |
| `test/anki/anki_card_adapter_test.dart` | 适配层测试 | 一 |
| `test/anki/anki_srs_migrator_test.dart` | SRS 迁移测试 | 一 |
| `test/anki/anki_integration_test.dart` | 端到端集成测试 | 一 |

---

## 15. 结论

Varnamala 的现有架构对「Anki 导入刷题」有天然的兼容性，而既有的 AI 基础设施进一步将其从「翻面卡片刷题器」升级为「智能学习平台」。

在引擎层，SRS 引擎与卡片类型解耦、错题携带完整快照可独立重放（`MistakeReviewAssembler` 已证明这条路径）、统计与内容来源无关、`LessonCompletionCoordinator` 自动处理完成副作用、`DailyChallengeAssembler` 可无缝混入 Anki 卡片、`Interaction` sealed union 可低成本扩展。主要新增工作集中在「Anki 解析 + 适配」这一层，以及一个翻面渲染器。

在 AI 层，`AiCourseService` 的 HTTP 核心可直接用于 notetype 识别和卡片增强；`AiHintProvider` 的课中提示对 Anki 卡片即插即用；`AiWishProvider` 可把 Anki 牌组课程化为结构化 intro/practice/review 课程；`AiGroundedResourceProvider` 可检测词汇重叠避免重复；`autoFixResources` / `checkResourceSelfConsistency` 自洽引擎保证导入质量；Textbook 导入的 `ImportStrategy` 碰撞合并策略可直接复用。所有 AI 功能都是可选的——未配置 API 时走纯启发式路径，功能完整。

大单元通过「导入分片 + 复习分批 + 媒体懒拷贝 + SRS 分 key」四层策略承接，万级卡片可平稳运行。整体落地建议分四阶段推进，MVP 聚焦「能导入、能刷题、能续接 SRS、能记错题」，AI 增强阶段利用既有基础设施实现「智能识别、卡片增强、课中提示、课程化」，后续阶段再补富媒体、大单元优化与体验打磨。
