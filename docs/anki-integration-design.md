# Anki 集成设计（已交付）

> 状态：**部分 superseded**。Note/Card 保真与导入语义仍有效；“默认 Again/Hard/Good/Easy”和词汇自动升级正式 MCQ 已被 [ADR 0037](./decisions/0037-anki-course-review-unification.md) 取代。课程/复习大一统主计划见 [`# Anki 课程与复习大一统实施计划.md`](./# Anki 课程与复习大一统实施计划.md)。
> 当前实现概览见 [`project-guide.md`](../project-guide.md) §6；评审修复记录见 ADR [`0030-anki-deep-adaptation-review-fixes`](./decisions/0030-anki-deep-adaptation-review-fixes.md)。
> 合并日期：2026-08-07（自 2026-07-31 两份计划）。

---

## 1. 不可变决策

1. **Anki 原卡是主数据，结构化题目是派生数据。** 导入后必须先完整保存 Note / Card / Deck / NoteType / Template / CSS / 媒体与可选调度状态；单选、多选、填空等 `Interaction` 不能替代原卡。
2. **默认 Anki 式复习。** 先显示问题面，再显示答案面，由学习者选 Again / Hard / Good / Easy。客观题自动判分仅作辅助，不替代最终评分。
3. **不把 Anki 卡天然解释为单选/多选。** Anki 无通用"单选/多选"字段；只有满足严格可解释契约的卡才生成派生结构化练习。
4. **渲染模式不决定课程树成员资格。** Fidelity / Structured / JS / 图片 / 长答案只决定"怎么显示"，不决定"卡片是否进 Section/Lesson"。
5. **Lite 是存储/加载优化，不是空壳。** 大牌组仍须有完整可导航的牌组层级与虚拟 Lesson；Lite ≠ "空壳 Section + 0 Lesson"。
6. **导入分阶段、可验证、原子提交。** `cards > 0 && sections == 0`、孤儿 Card、缺失 Note/Deck、无法渲染等情况不得静默成功。
7. **自动识别留证据、置信度、冲突信息。** AI 只提建议，不得在用户确认前覆盖确定性规则或人工映射。
8. **wordId 为 card 级** `anki-<importId>-c<cardId>`，clean break，无 migration（早期 note 级 `n<noteId>` 已弃用）。
9. **WebView JS 默认禁。** notetype 级检测 `<script>`/`on*=` 存 `allowJs`，开启时容器隔离（navigationDelegate 拦外网 + 限文件访问）。
10. **导入模式按 deck 大小自适应。** <2k 卡 Full tree 进课程树；≥2k 卡 Lite 独立复习流；均可 override。渲染统一 Policy 混合（简单卡 structured MCQ，复杂卡 fidelity WebView）。
11. **HarmonyOS WebView 暂不管。** 保真门控到 Android/iOS，其余平台 fidelity 降级文本 `AnkiCard`。

---

## 2. 官方语义基线

以 Anki 官方文档与 `schema11.sql` 为准：

```text
Collection
  ├─ Deck / Subdeck：学习范围与调度配置
  ├─ Note Type
  │    ├─ Fields
  │    └─ Card Types (templates: qfmt / afmt / css)
  ├─ Note：字段内容，身份以 guid / note id 保持
  ├─ Card：由 Note + Card Type(ord) 生成，有独立 card id 与调度状态
  └─ Revlog：每次评分记录
```

Turna 可在此模型上增加"课程导航"与"结构化练习"，但不能反向改变原始 Card 的含义。

---

## 3. 数据模型

### 3.1 NoteStore 三表（schema v9 起）

**`anki_notetypes`**（每 import 一份 mid 快照）：`import_id, mid` 主键；`name, is_cloze, field_names_json, templates_json`（完整 `[{name,qfmt,afmt}]`）、`css`、`allowJs`、schema fingerprint。

**`anki_notes`**：`(import_id, note_id)` 主键；`mid, tags, fields_json`（原始 HTML 保留）、`sfld`、`guid`、source revision。

**`anki_cards_meta`**（Card 主索引，服务显示；调度在 `srs_states`）：`(import_id, card_id)` 唯一；`note_id, ord, did, word_id`（= `anki-<importId>-c<cardId>`）、`render_mode`（fidelity / structured / hybrid）、`queue/type/due/ivl/factor/reps/lapses`、`suspended/buried_until/marked/flag`、`course_index_id`。

### 3.2 牌组与导入记录

**`anki_decks`**：`import_id/did/name/parent_did`、deck config 引用、source/descendant card count、synthetic 标记、display order。Card 引用不存在 `did` 时创建 `Recovered / Missing deck <did>` 并记 warning，不丢卡。

**`anki_imports`**：`status`（staging/validating/committing/complete/failed/cancelled）、`source_format`、source/stored/indexed/renderable card counts、structured projection / conflict / error counts、classifier/template renderer version、last error。

**`anki_practice_projections`**（派生练习独立保存）：`card_id, projection_type`（singleChoice/multiSelect/fillBlank/typeAnswer）、`status`（candidate/accepted/rejected/conflict/stale）、options + 答案索引、`evidence_json`、confidence、classifier version、user override、source fingerprint。源 Note/Template 变化自动标 `stale`。

**`anki_import_issues`**：severity（info/warning/error/fatal）、scope、stable code、source ids、可恢复方式、用户处理状态。错误码如 `DECK_JSON_ENTRY_INVALID` / `CARD_DECK_MISSING_RECOVERED` / `CARD_NOTE_MISSING` / `FRONT_EMPTY` / `TEMPLATE_RENDER_FAILED` / `ANSWER_KEY_AMBIGUOUS` / `SINGLE_CHOICE_MULTIPLE_KEYS` / `COUNT_RECONCILIATION_FAILED`。

**`anki_prerendered_html`**（schema v10，智能去解密缓存）：见 §10。

---

## 4. 导入流水线（分阶段、原子）

```
.apkg/.colpkg
  │
  ▼
Package Reader ──格式/安全/媒体校验──► Import Staging
  │                                  ├─ decks / notetypes/templates/css
  │                                  ├─ notes / cards / revlog / issues
  ▼
Invariant Validator ──失败不提交；可恢复项进 Recovery Deck
  ▼
Canonical Anki Store（唯一主数据） + 媒体拷贝（事务外，best-effort）
  ├─ Deck Navigator / Virtual Lesson Index（所有卡都有位置）
  ├─ Fidelity Renderer（默认复习）
  ├─ Scheduler Adapter（自评四按钮 -> FSRS）
  └─ Optional Practice Projection（MCQ/MultiSelect/FillBlank，有证据、可撤销）
```

**阶段**：A 包读取与格式识别（路径穿越/绝对路径/超大压缩比/总大小/文件数限制；`.apkg` vs `.colpkg` 区分；未知格式报错不返回空集）-> B 逐实体解析（Deck/Notetype 单条解析单条记 issue，不外层 try/catch 丢整张 map；身份字段转换失败 fatal，不默认 0）-> C 强不变量校验 -> D 暂存与原子提交（先写 staging，校验+媒体+导航索引后一次提交；失败/取消清 staging 不碰上一次 complete 导入；重导入"先构建新快照再原子切换"）。

**强不变量**：`storedCards == parsedCards`；每 Card 找到 Note 或 fatal；每 Note 找到 Notetype 或 fatal；每 Card 找到 Deck（否则 Recovery Deck）；每非空 Card 有可检查正面渲染；每 Card 有导航 index；每 SRS card id 解析回 canonical Card。`sourceCardCount > 0 && indexedCardCount == 0` = fatal；`sourceCardCount > 0 && sectionCount == 0` = fatal；`structuredProjectionCount == 0` 不是错误。

`CourseLoader.invalidateCaches()` 与 scope 切换只在 commit 成功后发生。

---

## 5. 双轨渲染

### 5.1 保真轨（Fidelity，默认）

每张卡按 `note + notetype + ord` 生成正反面：qfmt -> question；afmt -> answer（正确处理 `FrontSide`）；应用 notetype CSS；支持字段替换、条件块、Cloze、`type:`、媒体与特殊字段；保留 card ord（正/反/多模板独立）；前面为空显示兼容性错误卡而非让 Card 消失。

`AnkiHtmlCardView`（`webview_flutter`）渲染原 HTML + CSS，模板 `{{field}}` 替换、cloze 挖空。**平台门控**：仅 Android/iOS 有 WebView；HarmonyOS/Web/桌面降级文本兜底，不实例化 `WebViewController`。暗色主题时注入暗色 CSS。JS 与网络隔离：`allowJs` 默认关；离线/询问策略通过 CSP 实际阻断 `fetch`/XHR/WebSocket/外部资源。

### 5.2 结构轨（Structured，可选）

`AnkiRenderPolicy`（纯函数）逐卡判定：

1. 模板 qfmt/afmt 含 `<script>` 或 data- 交互属性 -> fidelity
2. 能稳定抽出 ≥2 选项 + 可解析答案键 -> structured (MCQ/MultiSelect)
3. cloze 标记 -> structured FillBlank 或 fidelity
4. wordEntry 短词 + 干扰项 ≥2 -> structured MCQ
5. 其余 -> fidelity

**铁律**：凡 `looksLikeEmbeddedOptions(front)` 且解析失败 -> **不得**用牌组 distractors 冒充选项。

### 5.3 Interaction

`Interaction.ankiHtmlCard`（保真，不 strip 成纯文本）：`frontHtml` / `backHtml`（已渲染 qfmt/afmt）、`css`、`mediaBasePaths`、`sourceNoteId` / `sourceCardId` / `wordId`。保留 `AnkiCard`（纯文本翻面）作轻量回退。

---

## 6. 单选/多选识别

每张 Card 默认始终拥有 Fidelity 表示。结构化识别返回 `AcceptedProjection` / `NoProjection` / `ConflictedProjection`。**禁止**用"解析失败后生成牌组级干扰项"作默认回退。

**证据优先级**（高到低）：(1) 用户对具体 notetype/card 的显式覆盖；(2) 已注册带版本的已知模板适配器；(3) 独立字段明确契约（`Question + OptionA..D + AnswerKey`）；(4) template 稳定结构与专用 data 属性；(5) notetype/字段名称；(6) 题面"单项/多项选择题"正文提示（弱证据）；(7) AI 建议（仅预览/批量辅助）。

**严禁**单独作为答案键：整个渲染后 afmt、含解析说明的 Back、题面重复出现的 A/B/C/D、任意长文本中的孤立字母、同牌组其他卡片抽取的答案文本。

**单选**：必须恰好 1 个选项；0 个 = NoProjection；≥2 个 = `SINGLE_CHOICE_MULTIPLE_KEYS`，保留 Fidelity，禁止静默变多选。**多选**：必须有明确多选证据 + ≥2 不同选项；仅 1 个 = 冲突，不自动降单选。

逐 Card 自动判断：题面明示优先，未明示时由完整答案键数量决定；导入页不要求用户为整个 NoteType 选单选/多选，同一模板可混合。AI 不参与 canonical import 成败；输出仅 suggestion，用户确认后转显式 mapping。

---

## 7. Anki 式复习

```
Question -> 用户回忆/可选作答 -> Show Answer -> 完整 Answer
         -> Again / Hard / Good / Easy -> 写入调度与 revlog（FSRS）
```

结构化题可在 Show Answer 前收集答案给"完全/部分/错误"提示，但最终评分仍由用户选。不得把"点了正确选项"直接等同 Good。Anki 原卡与 HTML 保真卡支持点击卡面正反面往返翻转，翻回正面不提交评分。

**调度兼容等级**（UI 须明确显示）：
- **Reset**：忽略源进度，所有卡作新卡（共享 `.apkg` 建议默认）。
- **Migrate snapshot**：迁移 queue/due/ivl/factor/reps/lapses/revlog，再由 FSRS 继续（标记"近似迁移，不保证与同版本 Anki 下一间隔完全一致"）。revlog ease 1->1 / 2->3 / 3->4 / 4->5。
- **Exact backend（远期）**：仅集成 Anki 官方调度后端/等价实现后才可宣称精确兼容。

导入 UI 须让用户选择是否迁移学习进度，不能因包内有调度数据就默认采用。

**复习入口**：`AnkiReviewRoute` + `AnkiReviewSessionRoute`。`AnkiReviewAssembler` 把 NoteStore 中到期且不在 lesson 的卡渲染为 `ankiHtmlCard`；`assembleBatchAsync` 用 `wordIdsForDecks` 单次批量查询替代 N+1。

---

## 8. 课程树、Deck 层级与 Lite

Anki Deck/Subdeck 对应学习范围，是导航主来源（tags/自定义字段可作可选视图但不能取代）。映射：Course Entry（一次导入/合并后的 collection scope）-> Section（顶层 Deck）-> Unit（Subdeck 层级或分页容器）-> Virtual Lesson（固定大小 Card 引用页）-> Stage（运行时按 Card 引用加载，不复制完整 Interaction JSON）。

**Lite = 按需加载**，仅控制：是否预生成 Interaction、是否预渲染 HTML、每页索引大小、缓存策略。无论 10 张还是 100,000 张都建立轻量导航索引；大牌组 Virtual Lesson 只存 card ids，不物化全量 Interaction JSON。`ankiLiteThreshold`（2000）改为缓存/预加载设置，不影响 Lesson 是否存在。

**Fidelity 不从 Lesson 跳过**：Virtual Lesson 存 CardRef 而非具体 Renderer；运行时 `CardRef -> canonical card -> accepted projection（可选 Structured）/ always available（Fidelity）`。因此全 JS/全图片/长答案牌组仍有完整 Lesson；结构化识别为 0 不影响课程可见性；Anki 复习页与课程页引用同一 Card。

**智能组织**：`AnkiOrganizationResolver` 从 notetype 字段名抽取 unit/lesson 键（unit/chapter/section/单元/章；lesson/topic/subunit/课/节）与标签，字段优先，HTML 去标签；`assemble(smartGrouping:)` 据此分卡入 Units->Lessons（deck 名兜底）；多块（>20）lesson 命名 `"$lessonKey #N"`。

---

## 9. Full / Lite 模式

按牌组规模自动选择（`assemble(liteThreshold: 2000)`）：
- **Full**（<2k 卡）：完整 Section->Unit->Lesson 树，卡进 lesson 互动。
- **Lite**（≥2k 卡）：仅 shell Section（无 lesson），复习走 fidelity 路径，避免巨型牌组撑爆课程树。

---

## 10. 智能去解密（Pre-render Cache，schema v10）

部分牌组（如加密考研牌组）在 notetype CSS 中含混淆的解密 JS。首次复习时 `AnkiHtmlCardView` 在 WebView 跑一次 JS，延迟捕获 `document.body.innerHTML`，去 `<script>`，缓存到 `anki_prerendered_html`。后续复习直接服缓存纯 HTML（`allowJs=false`，无 JS/无网络/无沙箱）。`allowJs` notetype 自动触发；卸载牌组按前缀清缓存。高级页提供渲染/网络与单牌组覆盖、失败降级。

---

## 11. 重复导入与更新

不只靠文件 hash 判"同一批"。保留并利用：Note guid、Note id/Card id、notetype/template/field id、mod 时间、schema fingerprint、source package lineage。UI 提供更新选项：仅添加新 Note/Card、新版本覆盖本地、保留本地不更新、notetype schema 冲突预览合并、学习进度独立选择保留本地/采用源/重置。重导入保证 Card 本地稳定标识不因 Section/Lesson 重建变化；源 Card 删除先标 missing/tombstone，是否删调度/历史由用户确认。

---

## 12. 已延期（二期/远期）

- `{{type:}}` 输入桥（WebView 填空）。
- rsdroid / Anki 官方 FFI 后端（仅当模板兼容仍不足）。
- `collection.anki21b`（schema-v18，Zstandard + Protobuf 元数据）原生解析：不能仅加解压库后复用旧解析器，须独立兼容里程碑 + 真实 fixture + 各平台原生库 + 许可证审查。在此之前保持显式拒绝与重新导出指引。
- OHOS import sqlite3 FFI（当前 OHOS import 抛错）。
- 错题快照瘦身（存 noteId 引用而非全 HTML）、WebView 池化。

---

## 13. 明确不做

- 不实现、不宣称与 AnkiWeb / 官方 Anki 账号同步。
- 未使用 Anki 官方调度后端前，不宣称下一间隔与 Anki 完全一致。
- 不自动执行 `.colpkg` 覆盖 Turna 全部本地数据的官方桌面行为。
- 不把 AI 识别包装成 Anki 官方功能。
- 不保证任意第三方 add-on JS 可运行；不能运行时安全降级并可诊断。
- 不从 Anki 源码复制受许可证约束的大段实现；若集成官方后端须单独完成许可证与分发评审。

---

## 14. 最终产品定义

> 导入任何有效 Anki 牌组后，每张 Card 都能在对应 Deck/Subdeck 与课程导航中找到，并可按原模板完成"问题-答案-自评"复习。系统可额外把少量高置信度卡转成单选/多选/填空练习，但该转换始终可解释、可撤销，冲突时绝不改变原卡或隐藏卡片。
