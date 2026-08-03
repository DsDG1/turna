# Anki 深度适配计划：框架改造与强兼容匹配

> 状态：已采纳（Adopted）  ·  4 项决策已冻结，见 §15  
> 日期：2026-07-31  
> 依据：Anki Desktop（AGPL）、AnkiDroid（GPL-3）、现有 `docs/anki-import-design.md` 与已实现导入/SRS/双轨适配代码  
> 目标：在 **不整仓搬迁** 开源 Anki 客户端的前提下，按 Anki 生态的**原理与分层**改造 Varnamala，使复杂 notetype（含中文政治多选、模板 JS、媒体）达到接近 AnkiDroid 的兼容度，同时保留语言课与客观题引擎。

---

## 0. 执行摘要

| 问题 | 根因 |
|------|------|
| 复杂多选卡选项错乱 | 强行「字段猜测 → Interaction」，模板/HTML/JS 语义丢失 |
| 兼容性天花板 | Anki 卡片本质是 **模板渲染结果**，不是固定题型 |
| 与语言课混在同一棵树 | 大牌组、校验上限、加载路径与 CEFR 课不同 |

**核心策略：双轨渲染 + 保真优先 + 结构化增强可选**

```
                    ┌─────────────────────────────────────┐
  .apkg 导入        │  保真轨 (Fidelity)  ★默认 Anki 复习  │
                    │  qfmt/afmt → HTML → WebView 翻面    │
                    │  与 AnkiDroid 同原理，不猜选项        │
                    └──────────────┬──────────────────────┘
                                   │ 可升级 / 可选
                    ┌──────────────▼──────────────────────┐
                    │  结构轨 (Structured)  语言课/客观练   │
                    │  字段/嵌入选项 → MCQ/MultiSelect/…   │
                    │  复用 LessonViewModel 判分链路        │
                    └─────────────────────────────────────┘
```

**明确不做**：把 AnkiDroid 整仓 merge 进 Flutter；不做 AnkiWeb 同步（保持本地优先，与既有 ADR 一致）。

---

## 1. 开源项目原理（要「搬」的是架构，不是仓库）

### 1.1 Anki Desktop（ankitects/anki）

| 层次 | 原理 | 对 Varnamala 的启示 |
|------|------|-------------------|
| 包格式 | `.apkg` = ZIP + SQLite（`notes`/`cards`/`col.models`） | 已有 `AnkiImporter`，保留 |
| 卡片定义 | **Notetype 模板** `qfmt`/`afmt` + 字段 `flds` | 兼容核心是**渲染模板**，不是猜 front/back |
| 调度 | queue/due/ivl/factor + revlog | 已有 `AnkiSrsMigrator`，可继续增强 |
| 媒体 | 包内编号文件 + media map | 已有 `anki://` 解析，WebView 需 `file://` 或 base64 |

### 1.2 AnkiDroid（ankidroid/Anki-Android）

| 层次 | 原理 | 对 Varnamala 的启示 |
|------|------|-------------------|
| 显示 | **WebView 加载渲染后的 HTML**（非原生列表猜选项） | 复杂卡必须走 WebView |
| 后端 | rsdroid / Anki 集合库 | 可选远期；MVP 不必嵌入 Rust 后端 |
| 复习 | 显示问面 → 显示答面 → 评分写入调度 | 与 SRS 解耦：显示层 ≠ 调度层 |
| 协议 | GPL-3 / 部分 AGPL | **禁止大段复制源码**；可复用行为与接口设计 |

### 1.3 关键洞察

> Anki 没有「单选题类型」作为一等公民。  
> 「单选/多选」是 **模板 + 字段约定 +（可选）JS** 的呈现；调度只关心「这张 card id 答得怎样」。

因此深度适配的第一性原理是：

1. **保真显示** = 模板渲染 + WebView（对标 AnkiDroid）  
2. **结构练习** = 启发式/显式映射到 `Interaction`（对标当前双轨，但不可再当唯一路径）  
3. **调度** = 统一 `SrsProvider` + `anki-<importId>-n<noteId>`（已有）

---

## 2. 现状与缺口

### 2.1 已有能力（可复用）

| 模块 | 路径 | 能力 |
|------|------|------|
| 解析 | `anki_importer.dart` | `.apkg` 分页读 notes/cards/revlog |
| 模板 | `anki_template_renderer.dart` | 最小 mustache：`{{}}`、条件块、`FrontSide` |
| 适配 | `anki_card_adapter.dart` | 字段启发式 + 行内 A/B/C + MultiSelect |
| 组装 | `anki_deck_assembler.dart` | Section/Unit 拆分、校验上限 |
| 复习 | `anki_review_assembler.dart` | 按批 due、懒加载 Interaction |
| SRS | `anki_srs_migrator.dart` | 状态迁移、新卡按日错开 |
| 领域 | `Interaction.ankiCard` / MCQ / MultiSelect | 渲染器已注册 |

### 2.2 缺口（深度适配必须补）

| # | 缺口 | 影响 |
|---|------|------|
| G1 | **无 WebView 保真轨** | 模板/HTML/JS 多选在「结构轨」必然失真 |
| G2 | 导入时 **丢弃完整 qfmt/afmt HTML 与样式**，只存 strip 后的 Interaction | 重开无法复现 Anki 观感 |
| G3 | `AnkiTemplateRenderer` 无 CSS/JS、`{{cloze:}}` 不完整、无 `{{type:}}` | 与桌面差一截 |
| G4 | 结构轨与保真轨 **未分层决策** | 政治多选等卡被伪干扰项 MCQ 污染 |
| G5 | 笔记级元数据（mid、ord、raw fields、template id）**未持久化到可查询表** | 无法按 note 重渲 |
| G6 | 大牌组 / 校验 / 预加载 已部分修，但 **HTML 体积与媒体** 未按 WebView 设计 | 可能 OOM |
| G7 | 导入 UI 映射不可调、无「保真/结构」策略 | 用户无法纠偏 |
| G8 | 错题/弱词对 HTML 卡 **无专用快照策略** | WebView 卡进错题本需约定 |

---

## 3. 目标架构（框架结构改造）

### 3.1 分层（对齐 Anki，适配 Varnamala）

```
┌──────────────────────────────────────────────────────────────┐
│  UI                                                          │
│  AnkiReviewSession │ AnkiHtmlCardView │ (可选) LessonViewModel │
└────────────┬───────────────────┬─────────────────────────────┘
             │                   │
┌────────────▼──────────┐ ┌──────▼─────────────────────────────┐
│  Fidelity pipeline    │ │  Structured pipeline                 │
│  CardHtmlRenderer     │ │  AnkiCardAdapter (增强)              │
│  + WebView shell      │ │  → MultipleChoice / MultiSelect /… │
└────────────┬──────────┘ └──────┬─────────────────────────────┘
             │                   │
┌────────────▼───────────────────▼─────────────────────────────┐
│  AnkiNoteStore（新）                                           │
│  notes / card_meta / notetypes(templates) / media refs         │
│  + 现有 course tree（Section 壳 + 可选 structured lessons）    │
└────────────┬─────────────────────────────────────────────────┘
             │
┌────────────▼─────────────────────────────────────────────────┐
│  AnkiImporter（增强） + AnkiSrsMigrator + SrsProvider          │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 领域模型扩展

#### 3.2.1 新表（或扩展现有 SQLite）

**`anki_notetypes`**（每 import 一份 mid 快照）

| 列 | 说明 |
|----|------|
| import_id, mid | 主键 |
| name, is_cloze | |
| field_names_json | |
| templates_json | 完整 `[{name,qfmt,afmt}]` |
| css | 可选，从 models 提取 `css` |

**`anki_notes`**

| 列 | 说明 |
|----|------|
| import_id, note_id | 主键 |
| mid, tags, fields_json | 原始字段（HTML 保留） |
| sfld | 排序字段 |

**`anki_cards_meta`**（调度已在 srs_states；此处只服务显示）

| 列 | 说明 |
|----|------|
| import_id, card_id | |
| note_id, ord, did | |
| word_id | `anki-<importId>-n<noteId>`（与 SRS 对齐；一 note 多 ord 时见下） |

> **一 note 多 card（ord）**：当前 wordId 仅 `n{noteId}`，多模板会冲突。深度适配阶段改为：  
> - 显示/调度主键：`anki-<importId>-c<cardId>` **或** `anki-<importId>-n<noteId>-o<ord>`  
> - 迁移策略与卸载前缀一并改（**破坏性变更**，见阶段 0）。

**`anki_card_render_mode`**（可选列或旁表）

| 值 | 含义 |
|----|------|
| `fidelity` | 仅 HTML 翻面 |
| `structured` | 仅 Interaction |
| `hybrid` | 默认 fidelity，可「练成客观题」 |

#### 3.2.2 Interaction 扩展

```dart
// 新增：保真轨，不 strip 成纯文本
Interaction.ankiHtmlCard({
  required String id,
  required String frontHtml,   // 已渲染 qfmt
  required String backHtml,    // 已渲染 afmt（含 FrontSide 策略可配置）
  String? css,
  @Default([]) List<String> mediaBasePaths, // 供 WebView 解析相对路径
  String? sourceNoteId,
  String? sourceCardId,
  String? wordId,              // SRS id
})
```

保留现有 `AnkiCard`（纯文本翻面）作为轻量回退。

#### 3.2.3 渲染决策器（新模块）

`AnkiRenderPolicy`（纯函数，可单测）：

```
输入: NotetypeMapping + note 字段 + 模板是否含 JS/复杂 HTML + 用户偏好
输出: fidelity | structured | hybrid

规则（默认）:
1. 模板 qfmt/afmt 含 <script> 或 data- 交互属性 → fidelity
2. 能稳定抽出 ≥2 选项 + 可解析答案键 → structured (MCQ/MultiSelect)
3. cloze 标记 → structured FillBlank 或 fidelity（cloze 模板复杂则 fidelity）
4. wordEntry 短词 + 干扰项 ≥2 → structured MCQ
5. 其余 → fidelity（禁止「长文干扰项伪 MCQ」）
```

**铁律（已从事故中学到）**：凡 `looksLikeEmbeddedOptions(front)` 且解析失败 → **不得**用牌组 distractors 冒充选项。

### 3.3 课程树角色重新定义

| 角色 | Anki 牌组 |
|------|-----------|
| Section/Unit/Lesson | **导航与分片**（20 卡/课、校验拆分），不必承载全部 HTML |
| 复习主路径 | **不依赖**打开 Lesson body 全量加载；按 `wordId`/`cardId` 从 `anki_notes` 现渲 |
| 语言课 | 不变；Anki scope 隔离（已有 `courseScope`） |

导入时两种落库模式（可配置）：

| 模式 | 行为 | 适用 |
|------|------|------|
| **Lite**（推荐默认） | 只写 AnkiNoteStore + SRS + 轻量 Section 壳（按牌组/子牌组） | 万卡政治/医学 |
| **Full tree** | 现状：组装满树 structured lessons | 小词表、要走课程树刷 |

### 3.4 复习会话改造

```
AnkiReviewSessionPage
  → collectDue (SRS)
  → 对 batch 每张卡:
       load Note+Notetype → CardHtmlRenderer.render(front/back)
       或 load structured Interaction
  → 展示:
       Fidelity: AnkiHtmlCardView (WebView) + 自评/评分
       Structured: 现有 InteractionRenderer
  → reviewWithQuality → SrsProvider
```

**不再**为 fidelity 卡调用 `preloadInteractions` 全课 body。

---

## 4. 模块改造清单

### 4.1 新增

| 模块 | 职责 |
|------|------|
| `lib/data/anki_note_dao.dart` | notes/notetypes/cards_meta CRUD |
| `lib/application/anki/anki_card_html_renderer.dart` | 字段 + 完整模板 → front/back HTML；注入 base CSS |
| `lib/application/anki/anki_render_policy.dart` | 保真/结构决策 |
| `lib/application/anki/anki_media_url_resolver.dart` | `anki://` / 相对路径 → WebView 可用 URI |
| `lib/views/anki/anki_html_card_view.dart` | WebView 壳：问面/答面、媒体、安全限制 |
| `lib/views/anki/anki_html_card_renderer.dart` | `InteractionRenderer` for `AnkiHtmlCard` |
| `test/anki/anki_render_policy_test.dart` 等 | 策略与 HTML 黄金样例 |

### 4.2 改造

| 模块 | 改动 |
|------|------|
| `anki_importer.dart` | 解析并保留 models 的 **css**；模板全文；可选 notetype 配置 |
| `anki_deck_assembler.dart` | Lite/Full；写 NoteStore；structured 仅对 policy=structured 的卡建 Interaction |
| `anki_card_adapter.dart` | 仅 structured 路径；加强字段/行内选项；永不伪 MCQ |
| `anki_template_renderer.dart` | 提升：css 包裹、cloze 单向显示、转义策略、可选允许 `{{FrontSide}}` 完整答面 |
| `anki_review_assembler.dart` | 按 card/note 取 HTML 或 Interaction；取消对 fidelity 的 lesson 全载 |
| `anki_srs_migrator.dart` | 稳定 id 方案（cardId）；多 ord |
| `course_database.dart` | schema 升版 + 表 |
| `anki_import_screen.dart` | 策略：保真优先 / 尽量客观题；映射可编辑 |
| `pubspec.yaml` | 增加 `webview_flutter`（或 `flutter_inappwebview`，需评估鸿蒙） |

### 4.3 依赖与平台

| 平台 | WebView |
|------|---------|
| Android / iOS | `webview_flutter` 优先 |
| Windows / Web | 评估；Web 可用 `HtmlElementView` 或降级纯文本 AnkiCard |
| HarmonyOS | 若无 WebView：fidelity 降级为 **flutter_html** 或纯文本，并 UI 提示 |

---

## 5. 保真轨详细设计

### 5.1 HTML 渲染管线

```
fields_raw (HTML 保留)
  → AnkiTemplateRenderer.render(qfmt, fields) → frontHtml
  → AnkiTemplateRenderer.render(afmt, fields, frontSide: frontHtml) → backHtml
  → wrapDocument(css, frontHtml|backHtml, baseHref: mediaDir)
```

`wrapDocument`：

- 注入 notetype `css` + 最小重置样式（字号、图片 max-width、暗色可选）  
- `<base href="file://.../anki_media/<importId>/">` 或替换媒体为 `file://` 绝对路径  
- **禁用** 外网导航；`javascriptMode` 默认 **restricted**，仅当模板检测含 script 时开启并沙箱

### 5.2 WebView 交互

| 动作 | 行为 |
|------|------|
| 初始 | 仅 front |
| 显示答案 | 加载 back（或同文档切换 `#answer`，对齐 Anki `hr#answer`） |
| 评分 | 应用内按钮 → `SrsProvider`（不依赖页面 JS 评分） |
| 音频 | 优先拦截 `anki://` / 相对 mp3 → `AudioController` |

### 5.3 与 AnkiDroid 的差异（刻意简化）

| AnkiDroid | Varnamala MVP |
|-----------|----------------|
| 完整 libanki 调度 | 已有 FSRS/SM-2 迁移态 |
| 编辑卡片 | 不做 |
| 同步 | 不做 |
| 打字题 `{{type:}}` | 二期：结构轨或 WebView 输入桥 |
| 完整 cloze 遮挡 UI | 二期；MVP cloze 可用结构 FillBlank 或 fidelity 全文 |

---

## 6. 结构轨详细设计（兼容「能客观练」）

### 6.1 何时 structured

- 独立 Option 字段（Option A/B、选项A…）  
- 行内/分行 `A./B./C.` **且** 答案键可解析（`B` / `A,C` / `答案：ABCD`）  
- 词表短答 + 干扰项  
- 用户强制映射

### 6.2 禁止事项

- 用其它笔记长文作「选项」冒充实战题  
- 用 `—` 填充假选项  
- 在 looks-like-MCQ 但拆分失败时仍输出 MultipleChoice

### 6.3 与语言课复用

Structured Interaction 继续：

- `LessonViewModel.submitInteraction`  
- 错题快照  
- 弱词（wordId）  
- 每日挑战（可配置 includeAnki）

---

## 7. 导入策略 UX

导入向导增加：

1. **显示模式**  
   - 保真优先（默认）  
   - 尽量客观题  
   - 仅结构（小词表）

2. **Notetype 映射表**（可改）  
   - 每行：notetype 名 | 推断类型 | 覆盖下拉 | 预览一张样例卡（HTML 或 MCQ）

3. **冲突/体量**  
   - 卡数、预估 Section 拆分、Lite 模式提示

4. **完成后**  
   - `setCourseScope` + invalidate（已有）  
   - 引导「开始 Anki 复习」进入保真会话

---

## 8. 调度与 ID 迁移（阶段 0 必做决策）

### 8.1 问题

一 note 多 ord 时当前 `anki-…-n{noteId}` 只能有一条 SRS。

### 8.2 方案（推荐）

| 项 | 值 |
|----|-----|
| 新 wordId | `anki-<importId>-c<cardId>` |
| 卸载前缀 | `anki-<importId>-` 仍有效 |
| 迁移 | 导入版本 bump；旧 `n` 前缀读取时兼容映射到主 ord=0 或丢弃重复 |

### 8.3 新卡 due

保持「按 Anki due 位置 + dailyNewLimit 错开」（已实现），避免 5k 全 due。

---

## 9. 分阶段实施计划（PR 切分）

### 阶段 0 — 决策与契约（0.5–1 天）

- [x] 冻结：默认 **Lite + Fidelity**；结构轨可选  
- [x] 冻结：card 级 wordId 方案  
- [x] 记录协议边界：不复制 AnkiDroid 源码  
- [x] 本文档评审通过  

**交付**：本 plan 合入 `docs/`；本 plan 即活契约（`docs/decisions/` 已随 commit 4bce2fd 废弃，不另建 ADR）

---

### 阶段 1 — 数据层：NoteStore（2–3 天）

- [x] schema 升版：`anki_notetypes` / `anki_notes` / `anki_cards_meta`  
- [x] Importer 写入完整 templates + css + raw fields  
- [x] DAO + 单测  
- [x] 卸载时级联删除  

**验收**：导入后可不依赖 lesson content 查出 note 字段与 qfmt/afmt。

---

### 阶段 2 — 保真渲染核心（3–5 天）

- [x] 增强 `AnkiTemplateRenderer`（css wrap、FrontSide 完整答面模式）  
- [x] `AnkiCardHtmlRenderer`  
- [x] `Interaction.ankiHtmlCard` + freezed/codegen  
- [x] `webview_flutter` + `AnkiHtmlCardView`  
- [x] 媒体 base 路径  
- [x] 复习会话 batch 走 NoteStore 渲染  

**验收**：中文「行内 A.B.C.D + 答案 ABCD」类卡在 WebView 中观感接近 Anki（若模板是纯 HTML）；无伪选项。

**黄金样例**：保存 2–3 个最小 `.apkg` fixture（basic、inline MCQ 文本、含图片）。

---

### 阶段 3 — 渲染策略与结构轨收敛（2–3 天）

- [x] `AnkiRenderPolicy`  
- [x] Assembler：按策略写 structured 或仅 meta  
- [x] Adapter：仅 structured；强化字段/行内（已有基础上回归）  
- [x] 禁止伪 MCQ 单测固化  
- [x] 导入 UI 模式开关  

**验收**：词表卡仍可 MCQ；复杂卡强制 fidelity。

---

### 阶段 4 — 性能与树（2–3 天）

- [x] Lite 导入默认：壳 Section + NoteStore，不全量 Interaction JSON  
- [x] 复习侧零全量 preload（已部分完成）  
- [ ] WebView 复用 / 池化（可选）  
- [x] 大牌组进度与取消  

**验收**：5k 卡导入与首批复习可接受（对标既有性能目标：复习首屏 &lt; 2s 量级）。

---

### 阶段 5 — 引擎粘合（1–2 天）

- [x] 错题：fidelity 快照存 frontHtml/backHtml 截断或 noteId 引用  
- [x] 弱词：仅 structured / 有 term 的卡  
- [x] 每日挑战：默认排除 fidelity 或仅 include structured  
- [x] 统计 lessonId 前缀  

---

### 阶段 6 — 平台与打磨（按需）

- [x] 鸿蒙 WebView 降级  
- [x] 暗色 CSS  
- [ ] `{{type:}}` 输入桥  
- [x] Cloze 单向显示增强  
- [ ] （远期）评估 rsdroid / 官方后端 FFI —— 仅当模板兼容仍不足  

---

## 10. 测试策略

| 层级 | 内容 |
|------|------|
| 单元 | `AnkiRenderPolicy`、模板渲染、行内选项、答案键、伪 MCQ 禁止 |
| 组件 | WebView golden 难做 → 用 HTML 字符串快照测试 |
| 集成 | fixture `.apkg` → 导入 → due → 渲染路径断言 mode |
| 回归 | 截图类政治多选：structured 抽出 4 选项 + MultiSelect **或** fidelity 不出现无关长文选项 |
| 性能 | 5k notes 导入时间、首批 20 卡 HTML 渲染时间 |

---

## 11. 风险与缓解

| 风险 | 缓解 |
|------|------|
| WebView 包体积/平台差异 | 分平台实现；降级 AnkiCard 文本 |
| GPL 污染 | 只参考行为，自研渲染与 UI |
| ID 迁移破坏进度 | 版本开关 + 一次性迁移函数 |
| JS 模板安全 | 默认禁 JS；检测后再开沙箱 |
| 双轨维护成本 | Policy 单入口；Assembler 分支清晰 |
| 用户期望「100% AnkiDroid」 | 文档写清：无同步/无编辑；保真显示 + 本地 SRS |

---

## 12. 成功标准

1. **保真**：带 HTML 模板的常见牌组，复习页观感与 Anki 桌面预览大致一致（布局/图片/选项文字）。  
2. **无伪题**：不再出现「题干是 A/B/C/D，选项却是其它题全文」类事故。  
3. **结构**：标准词表/字段 MCQ 仍可客观判分、进错题本。  
4. **性能**：大牌组可导入可刷，不整库加载 Interaction。  
5. **架构**：NoteStore 与语言课 course tree 职责分离，可测、可卸载。

---

## 13. 建议实施顺序（立即开工顺序）

```
阶段 0 契约
  → 阶段 1 NoteStore（地基）
  → 阶段 2 WebView 保真（解决 80% 兼容投诉）
  → 阶段 3 Policy + 结构轨收敛
  → 阶段 4 Lite 性能
  → 阶段 5 错题/挑战粘合
```

**第一优先级交付物**：阶段 1+2 合并为「Anki 保真复习 MVP」——用户重新导入后，政治/考研类模板卡可用 WebView 正常刷，不再依赖脆弱的选项猜测。

---

## 14. 与既有文档关系

| 文档 | 关系 |
|------|------|
| `docs/anki-import-design.md` | 总设计；本 plan 是其 **显示层与兼容性深化** 的实施修订 |
| 已实现：拆 Section、due 错开、行内选项、缓存 invalidate | 保留；纳入阶段 3/4 回归基线 |
| 本文件 | **执行计划**；实施时按阶段开 PR，完成后可升格 ADR |

---

## 15. 决策记录（已冻结 · 2026-07-31 · 无用户·有 git -> clean break）

1. **默认导入模式** -> 落库按 deck 大小自适应（<2k 卡 Full tree 进课程树；≥2k 卡 Lite 独立复习流；均可 override）；渲染统一 Policy 混合（简单卡 structured MCQ，复杂卡 fidelity WebView）。  
2. **wordId** -> card 级 `anki-<importId>-c<cardId>`，clean break，无 migration。修 `anki_srs_migrator_test.dart` revlog 用例。  
3. **WebView JS** -> 默认禁；notetype 级检测 `<script>`/`on*=` 存 `allowJs`，开启时容器隔离（navigationDelegate 拦外网 + 限文件访问）。  
4. **鸿蒙** -> 暂不管；WebView 门控到 Android/iOS，其余平台 fidelity 降级文本 `AnkiCard`，阶段 6 再评估。  

---

*End of plan.*
