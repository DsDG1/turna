# 32 — 官方 Anki 与自研体验对齐

> 文档代号：P-EXPERIENCE-PARITY  
> 日期：2026-08-20  
> 状态：**施工规格（未实施）**  
> 文件：本目录 `32-official-anki-experience-parity-plan.md`  
> 前置：ADR `0036`、分类器与投影（`30` Host/Unit 已过）、产品入口（`31`）  
> 目标：官方 Collection 继续当唯一 Anki 事实源；Turna 课壳、练习形态、复习入口和产品反馈做到接近自研导入路径。

题型判定、kindsFor、练习链细规格以 [`30`](./30-course-like-card-experience-plan.md) 为准。导入向导 / chrome / 实验室入口以 [`31`](./31-anki-product-experience-plan.md) 为准。本文管：**哪些体验面要对齐自研、代码缺口在哪、按什么顺序补。**

每一波可单独开 PR、单独测试、单独回滚。

---

## 0. 一句话

内核用原版 Anki，外壳继续用自研课。能对齐的是组织、题型、上课节奏和产品反馈；不能对齐的是解析、模板渲染和调度账本。

```text
官方 Collection（rslib）
  导入 / 模板 / FSRS / revlog / Undo / 原卡 WebView
        │  只读：字段、渲染后文本、媒体、到期队列
        ▼
共享分类器 + 课程投影
        │  简单卡 → Interaction；复杂卡 → canonicalLink
        ▼
Turna 壳（要对齐自研的部分）
  课树 / LessonViewModel / InteractionRenderer
  复习枢纽 due / 宝石·错题·挑战·AI
  浏览器与统计（查询换官方）
```

---

## 1. 铁律

1. 官方 Collection 是唯一 Anki 事实源。不恢复自研 `.apkg` 解析、模板引擎、HTML fallback、Turna FSRS 给官方卡排期。
2. `lib/application/anki_official/` 禁止 import `package:turna/application/anki/` 或 `package:turna/views/anki/`。
3. 复杂卡（`<script>`、`{{type:`、表格/音视频控件、拆不出的「像选择题」）走隔离 WebView。禁止用牌组 distractor 冒充选项。
4. 不对同一张卡双写官方 Scheduler 和 Turna `srs_states`。`AnkiWriteGuard` 继续拦截：官方引擎上 `turnaSrs` / `legacyAnkiDao` 打分，投影层 `answer/undo/bury/suspend`。
5. `canonicalLink` 预览不写官方 Scheduler。正式复习走 `OfficialAnkiReviewPage`。
6. 官方导入失败不得静默回退 Legacy。OHOS 继续 Legacy。本计划首发 Android。
7. 不对 Android WebView 做 3D `rotateY`。

---

## 2. 代码现状（相对自研）

| 面 | 自研路径 | 官方路径现状 | 差距 |
|---|---|---|---|
| 题型分类 | `AnkiCardAdapter._autoDecide` | `AnkiPracticeCardClassifier` + `kindsFor()` | 分类器已有；课内练习链（见面→选择→听音）未默认铺开 |
| 课树 | `AnkiDeckAssembler`：牌组→Section/Unit，20 张/课，tags/字段分组 | `OfficialAnkiProjectionProjector` 同结构；`COURSE_ENTRY` 默认开 | 智能分组/映射确认仍弱于自研向导 |
| 上课壳 | 同一套 `LessonViewModel` + renderer | 投影项能进课；`LessonViewModel._applySrsOutcome` **仍会 `registerWord` 官方 wordId** | 官方卡可能污染 Turna SRS |
| 到期复习 UI | `AnkiReviewSessionPage` 走课 renderer + 四档 | `OfficialAnkiReviewPage` `_practiceMode = true`，自绘 `OfficialAnkiPracticeReviewSurface` | 未复用 `AnkiCardRenderer` / 语言课 renderer；打字题退化成翻面 |
| 保真卡 | `AnkiHtmlCard` | `canonicalLink` → WebView；预览不评分 | 正确；正式复习 fidelity 才 WebView |
| 到期数 | `SrsProvider` | `OfficialAnkiHomeDue` 双源相加 | 壳可用；首页 chrome 仍可能漏调试字（见 31） |
| 打分账本 | Turna FSRS | 正式复习写官方；`courseGradesScheduler` 默认关且 Lesson 未接线 | 课上练完，Anki 队列不知道 |
| 媒体 | `anki://` + `AnkiMediaStrip` | 官方 media resolver；练习表面几乎不播 | 课内点播/看图缺失 |
| 产品层 | 宝石 / 错题 / 挑战 / AI 解释挂课与复习 session | 每日挑战已认 `OfficialAnki`；官方 reviewer **无宝石/错题/AI** | 产品反馈断在 WebView/自绘表面 |
| 浏览器 / 统计 | `AnkiNoteDao` | 仍走 Legacy DAO | 官方源点进去是空的或错账本 |

已有、不要撤回：分类器、投影 kinds、正式复习写官方 Scheduler、practice 默认开、WriteGuard、due 双源、forbidden import 测试。

---

## 3. 完成态

导入一副普通中英 Basic 牌组后：

1. 课程树出现 Section → Unit → Lesson，简单卡是 Flutter 练习（展示 / 选择 / 听选 / 填空 / 翻面），不是整课 WebView。
2. 到期复习默认同一套课面；fidelity 卡才嵌官方 Reviewer。
3. Again / Hard / Good / Easy 写官方 FSRS；Turna `srs_states` 不含 `official-anki-` wordId。
4. 课内客观题对错可记错题、发宝石；翻转自评分卡不进错题本（与自研一致）。
5. 音频/图片在课面可点播、可见。
6. 复习枢纽按牌组显示官方到期；浏览器/统计读官方 collection。
7. 复杂卡点开 WebView 能看原卡；预览不改队列。

明确不做：AnkiWeb、再克隆桌面 Reviewer、恢复自研解析器、默认 3D 翻转、P5-E 删 Legacy、把 JS/复杂 Cloze 硬转成课内题。

---

## 4. 波次

禁止把 renderer 复用、SRS 隔离、课程写回、浏览器换源揉进同一个 PR。

| 波次 | 名称 | 用户能感到什么 | 写官方 Scheduler | 建议顺序 |
|---|---|---|---|---|
| **P0** | 官方卡不进 Turna SRS | 无 UI；账本不再双写 | 否 | **第一刀** |
| **P1** | 复习复用课 renderer | 单词/选择/挖空长得像语言课，不再是平行自绘页 | 是（已有 session.answer） | 紧接 P0 |
| **P2** | 媒体 + 打字 | 课面能听、能看图；短答案能打字比对 | 是（已有） | 可与 P1 同批后半 |
| **P3** | 产品层挂壳 | 宝石 / 错题 / AI 解释出现在课和到期复习 | 否 | P1 之后 |
| **P4** | 课树与映射 | 导入后像自研那样按牌组/标签成课；映射页可改字段角色 | 否 | 可与 P1 并行；依赖导入稳定（31 W2） |
| **P5** | 课程评分桥 | 课上练完，官方到期减少 | **是（新增，默认关）** | 最后，单独评审 |
| **P6** | 浏览器 / 统计换源 | 官方牌组能搜卡、看统计、暂停 | 是（suspend/bury 走官方） | 不阻塞 P1–P3 |

推荐第一批：**P0 + P1**。做完账本干净、复习手感接近自研。

---

## 5. P0 — 官方卡不进 Turna SRS

### 5.1 目的

自研 `LessonViewModel._applySrsOutcome` 对任何有效 wordId 都会 `registerWord` + `reviewWord`。官方 wordId 形如 `official-anki-<profileKey>-c<cardId>`。现在投影课一旦提交，就会把官方卡写进 Turna `srs_states`。

### 5.2 改哪里

- `lib/application/lesson_viewmodel.dart`：`effectiveWordId` 以 `official-anki-` 开头则跳过 `_srsProvider.registerWord` / `reviewWord` / undo 栈。
- 错题 / 宝石仍可记（P3），只隔离调度账本。
- `canonicalLink` 的 `showWord` 提交：保持预览语义，不写官方、不写 Turna SRS（已有 p3r 测试口径）。

### 5.3 验收

- 投影课做完 10 张官方卡：`srs_states` 无 `official-anki-` 前缀。
- Legacy `anki-<importId>-c*` 行为不变。
- `AnkiWriteGuard` 现有单测继续绿。

### 5.4 不改

不在本 PR 打开 `courseGradesScheduler`。课上练完队列不变，直到 P5。

---

## 6. P1 — 到期复习复用语言课 renderer

### 6.1 目的

`OfficialAnkiPracticeReviewSurface` 是平行 UI：词汇大号字 + 自绘选项，`typeAnswer` / `expression` / `fidelity` 全走翻面。自研手感来自 `AnkiCardRenderer`（翻面脉冲 + 四档）、`ShowWordRenderer`、`MultipleChoiceRenderer`、`FillBlankRenderer`、`ListenAndPickRenderer`。

### 6.2 做法

1. 分类结果 → 临时 `Interaction`（与 `OfficialAnkiProjectionPayloads.interactionJson` 同一套映射）。
2. `OfficialAnkiReviewPage` 在 practice 且非 fidelity 时，用现有 `InteractionRenderer` 画；提交映射：
   - 翻转卡：Again / Hard / Good / Easy → `_session.answer(rating)`
   - 客观题：错 → Again，对 → Good（Hard/Easy 可选，不在本波做定制）
3. fidelity / 分类失败 / 用户切 WebView → 现有 `OfficialAnkiReviewerStage`。
4. `OfficialAnkiPracticeReviewSurface` 保留到 renderer 路径绿，再删或降为 fallback。

禁导：本页已在 `views/anki_official/`，不要 import `views/anki/`。Renderer 从 `views/lesson/components/interactions/` 和 DI `Set<InteractionRenderer>` 取。

### 6.3 验收

- Basic 词汇卡：大号词或翻面脉冲，四档写官方 queue。
- 题干 A/B/C：选项可点，对错色与课内一致。
- Cloze：填空 UI，不是整段 HTML。
- `{{type:` 或 `<script>`：不进 practice，WebView 可切换且不可被强制切回。
- Device A：Again 后该卡离开 due（与现有正式复习门禁相同）。

---

## 7. P2 — 媒体与打字

### 7.1 媒体

- 从官方渲染 HTML / 字段取出 `[sound:]` 与图片文件名。
- 练习 Interaction 填 `audioAssets` / `imageAssets`，走官方 media 路径（不要 `anki://<legacyImportId>/`）。
- 复用 `AnkiMediaStrip` 或官方 resolver 适配层；适配放 `lib/application/anki_practice/` 或 `anki_official/render/`，不要让 official 去 import Legacy media 模块。

### 7.2 打字

- `AnkiPracticeShape.typeAnswer` 不再退化成翻面。
- 课内用 `TypeTheWord` / `FillBlank`；比较用现有 `AnkiTypeAnswerMatcher` 的归一化规则，尽量贴近官方 typed-answer。
- 官方模板 `{{type:` 仍算 fidelity，不在 Flutter 里复刻输入框套模板。

### 7.3 验收

- 正面有音的卡：未揭示即可播放。
- 有图的卡：图在题干侧可见。
- 短答案卡：输对/错有前后缀高亮或对错态，再按 Good/Again 写官方。

---

## 8. P3 — 产品层挂课壳

官方 reviewer / 自绘表面目前不碰 `GemsProvider` / `MistakeProvider` / AI。自研 `AnkiReviewSessionPage` 已经：客观题记错题、宝石、可开 AI 解释。

### 8.1 挂在哪

挂 **Flutter 壳**（投影课 + P1 复习页），不要塞进 WebView。

| 能力 | 规则 |
|---|---|
| 宝石 / 连胜 | 按本次提交对错发；不写 revlog |
| 错题本 | MCQ / 填空 / 听选记；`AnkiCard` / HTML 自评分不记 |
| AI 解释 | 当前卡 term/meaning 文本；失败不影响评分 |
| 每日挑战 | 已认 `OfficialAnki` section，回归即可，不新开账本 |

### 8.2 验收

- 投影课做错一道选择：错题本有一条，wordId 官方前缀，再练不写 Turna SRS。
- 官方 WebView fidelity 卡：不出现错题/宝石副作用。
- AI 面板可关，默认不阻塞提交。

---

## 9. P4 — 课树与字段映射

投影已能：顶层牌组 → Section（`official-anki-<sourceId>-s<deckId>`）、路径 → Unit、20 张/课、overflow → `canonicalLink`。

要对齐自研组织器的：

1. 字段名 / 标签 `unit::` `lesson::` `单元` `课` → 课名，而不是永远 `Lesson N`。
2. 映射页（`OfficialAnkiMappingPage`）在导入完成或来源管理可发现；改角色后重建投影，不改官方 Note。
3. `enabledKinds` 默认含 showWord / flip / multipleChoice / listenPick / fillBlank；fidelity 仍只出 canonicalLink。
4. 单字段 / 方向（target→native）与自研正反卡手感一致。

依赖 [`31`](./31-anki-product-experience-plan.md) W2：导入必须先能稳定写进 Collection。本波不修向导硬阻断。

---

## 10. P5 — 课程评分桥（单独 flag）

`TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER` 现默认 false。打开后：

1. 介绍类 `showWord` 不写分。
2. 同一 `cardId` 一课只 `answer` 一次。
3. 客观错 → Again；该卡本课练习全对 → Good。
4. 必须先证明：官方 `answer` 是否要求该卡当前在 due 队列。不在 due 则跳过或走允许的 intern 接口，禁止瞎写。
5. 失败 fail-closed：课继续推进，toast/诊断，不写 Turna SRS。

未完成 P0 / P1 不开。改变「课程练习不写官方调度」语义，必须单独 PR、默认可关。

---

## 11. P6 — 浏览器与统计换官方源

`AnkiCardBrowserPage` / `AnkiDeckStatsPage` 读 `AnkiNoteDao`。官方 section 点进去应对官方 collection：

- 搜索、旗标、暂停：走官方 engine 查询 + bury/suspend。
- 统计：新/学习中/到期来自官方 queue counts，不是 Turna SRS。
- 页面可留在 `views/anki/`，但 official 分支经 session/engine 取数，禁止再扫 Legacy note store。

不阻塞复习课化。可后置。

---

## 12. 文件边界

| 允许 | 禁止 |
|---|---|
| `lib/application/anki_practice/` 共享分类与 Interaction 映射 | official → Legacy `application/anki` |
| `views/lesson/.../interactions/` 作皮肤 | 再写第三套卡面（长期） |
| `OfficialReviewSession.answer/undo` 写账本 | Lesson 写 `SrsProvider` 给官方 wordId |
| 宝石/错题/AI 读卡面文本 | 宝石逻辑写 revlog |

---

## 13. 测试与回滚

每波最少：

- Host 单测：wordId 隔离、kinds→Interaction、客观题 Again/Good 映射、canonicalLink 0 次 scheduler 写。
- 现有 `official_anki_forbidden_imports_test` 继续绿。
- Device A：Basic 10 张 practice 评分；1 张 fidelity WebView；Undo 后 due 恢复。

回滚：P0/P1/P2 用 flag 切回 WebView 或旧 practice 表面；P5 关 `COURSE_GRADES_SCHEDULER`；P6 浏览器对官方源 fail-closed 提示，不读 Legacy 装数。

---

## 14. 与 30 / 31 的关系

| 文档 | 管什么 |
|---|---|
| `30` | 分类器、kindsFor、练习链、动画、课程写回细规格 |
| `31` | 导入硬阻断、默认打开什么、实验室入口、首页 due chrome |
| **本文** | 相对自研要对齐的**体验面**、现码缺口、施工顺序 |

30 的 A（分类器）已在代码里。本文 P1 ≈ 30 E（正式复习复用 renderer），P5 ≈ 30 G。31 W2 仍是产品可用性前提：导入都走不通时，本计划的课树/复习对齐没有用户。
