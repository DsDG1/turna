# Anki 官方语义对齐与导入可靠性改造计划

> 状态：核心改造已实施并通过回归测试；最新版 schema-v18 原生解析另行实施  
> 日期：2026-07-31  
> 适用范围：`lib/application/anki`、Anki 数据表、导入 UI、课程树索引、Anki 复习与 SRS 迁移  
> 目标：修复“单选误变多选”和“导入成功但课程中没有卡片/只有 Anki 复习入口”，同时把兼容边界调整为符合 Anki 官方模型的可解释架构。

## 1. 执行摘要

本次改造采用以下不可变决策：

1. **Anki 原卡是主数据，结构化题目是派生数据。** 导入后必须先完整保存 Note、Card、Deck、Note Type、Card Template、CSS、媒体和可选调度状态；单选、多选、填空等 `Interaction` 不能替代原卡。
2. **默认使用 Anki 式复习。** 先显示问题面，再显示答案面，最终由学习者选择 Again、Hard、Good、Easy。客观题自动判分只能作为辅助，不得直接替代 Anki 的最终评分。
3. **不再把 Anki 卡天然解释为单选或多选。** Anki 官方模型没有通用的“单选题/多选题”字段。只有满足严格、可解释契约的卡，才允许生成派生的结构化练习。
4. **渲染模式不得决定课程树成员资格。** Fidelity、Structured、JS、图片、长答案只决定“怎么显示”，不能决定“卡片是否进入 Section/Lesson”。
5. **Lite 只是一种存储和加载优化。** 大牌组仍必须拥有完整可导航的牌组层级与虚拟 Lesson；Lite 不再等价于“空壳 Section + 0 Lesson”。
6. **导入必须是分阶段、可验证、原子提交的。** `cards > 0 && sections == 0`、孤儿 Card、缺失 Note、缺失 Deck、无法渲染等情况不得静默成功。
7. **任何自动识别必须留下证据、置信度和冲突信息。** AI 只能提出建议，不能在没有用户确认时覆盖确定性规则或人工映射。

## 2. 官方语义基线

本计划以 Anki 官方文档和官方仓库为准：

- [Anki Getting Started：Note、Field、Card Type、Card 的关系](https://docs.ankiweb.net/getting-started.html)
- [Anki Card Templates：模板决定正反面与卡片生成](https://docs.ankiweb.net/templates/intro.html)
- [Anki Packaged Decks：apkg 内容、进度导入与重复导入更新](https://docs.ankiweb.net/importing/packaged-decks.html)
- [Anki Studying：显示答案后由用户选择 Again/Hard/Good/Easy](https://docs.ankiweb.net/studying.html)
- [Anki Deck Options：子牌组、每日上限、FSRS 与显示顺序](https://docs.ankiweb.net/deck-options.html)
- [Anki Template Checks：空正面、模板错误、Cloze 错误](https://docs.ankiweb.net/templates/errors.html)
- [Anki 官方 schema11.sql：notes/cards/revlog 的身份和调度字段](https://github.com/ankitects/anki/blob/main/rslib/src/storage/schema11.sql)

需要遵守的模型关系：

```text
Collection
  ├─ Deck / Subdeck：学习范围与调度配置
  ├─ Note Type
  │    ├─ Fields
  │    └─ Card Types (templates: qfmt / afmt / css)
  ├─ Note：字段内容，身份以 guid/note id 等信息保持
  ├─ Card：由 Note + Card Type(ord) 生成，具有独立 card id 与调度状态
  └─ Revlog：每次评分记录
```

Turna 可以在此模型上增加“课程导航”和“结构化练习”，但不能反向改变原始 Card 的含义。

## 3. 当前问题与根因

### 3.1 单选误变多选

当前流程会从题面提取 A/B/C/D，再把答案字段或渲染后的背面交给 `parseCorrectIndices()`。只要解析出两个以上索引，`_buildChoiceInteraction()` 就创建 `MultiSelect`。题面正文中的“单项选择题”不是强约束，人工选择的单选映射也没有形成稳定的冲突处理契约。

风险包括：

- 把解释文字里独立出现的 A/C/D 当作答案键；
- 把 afmt 中重复呈现的题面选项当作答案；
- 原始数据自身“单选 + 多答案”时静默改题型；
- notetype 名称含 `multiple choice` 时发生中英文语义误判；
- 人工指定单选后，解析器放弃结构化结果并退回牌组级伪干扰项，生成另一道错误单选；
- 识别结果缺少证据和冲突记录，用户无法知道为何变成多选。

### 3.2 导入后没有 Lesson

当前有两条设计分支会主动产生 0 Lesson：

- 单个顶层牌组卡数达到 `ankiLiteThreshold`，只写空壳 Section/Unit；
- 卡片全部被 `AnkiRenderPolicy` 判为 Fidelity，在 `_buildUnit()` 中被跳过。

另外还有真正的数据丢失风险：

- `decks` JSON 整体解析使用宽泛 `try/catch`，一个异常条目可能令 Deck 列表为空或不完整；
- Card 的 `did` 找不到 Deck 时没有恢复牌组；
- Card 的 `nid` 找不到 Note 时只在建 Stage 时跳过；
- 本次有效集合为空仍可能写入导入记录；
- 导入成功页没有阻止 `sourceCardCount > 0 && sectionCount == 0`；
- SRS/NoteStore 与课程树独立提交，造成“复习页有卡、课程页无卡”的双源分裂。

### 3.3 与 Anki 语义的根本偏差

当前架构把“能否转成 Turna Interaction”当成卡片是否可用的前提。Anki 的正确前提应是“Card 能否按 qfmt/afmt 渲染并完成自评”。结构化选择题只是一种可选增强。

## 4. 目标架构

```text
.apkg/.colpkg
      │
      ▼
Package Reader ──格式/安全/媒体校验──► Import Staging
      │                                  │
      │                                  ├─ decks
      │                                  ├─ notetypes/templates/css
      │                                  ├─ notes
      │                                  ├─ cards
      │                                  ├─ revlog/scheduling
      │                                  └─ issues
      │
      ▼
Invariant Validator ──失败则不提交；可恢复项进入 Recovery Deck
      │
      ▼
Canonical Anki Store（唯一主数据）
      ├─ Deck Navigator / Virtual Lesson Index（所有卡都有位置）
      ├─ Fidelity Renderer（默认复习）
      ├─ Scheduler Adapter（自评四按钮）
      └─ Optional Practice Projection
             └─ MCQ / MultiSelect / FillBlank（有证据、可撤销）
```

核心约束：

- `Card membership` 与 `render mode` 分离；
- `Canonical Card` 与 `Practice Projection` 分离；
- `Course navigation index` 与大块 Lesson JSON 分离；
- `Import staging` 与正式数据分离；
- `Import status=complete` 只在所有强不变量通过后写入。

## 5. 数据模型修改

### 5.1 保留并补强现有表

`anki_imports` 增加：

- `status`: `staging | validating | committing | complete | failed | cancelled`；
- `source_format`: `apkg | colpkg | legacy_apkg`；
- `import_progress`: 是否采用源调度；
- `source_note_count/source_card_count/source_deck_count`；
- `stored_note_count/stored_card_count/indexed_card_count/renderable_card_count`；
- `structured_projection_count/conflict_count/error_count/warning_count`；
- `classifier_version/template_renderer_version`；
- `last_error_code/last_error_detail`。

`anki_notetypes` 增加或确认保存：

- 原始 notetype id、名称、类型；
- 字段 id、字段名称和原始顺序；
- template id、ord、qfmt、afmt；
- CSS；
- JS 能力标记与安全策略；
- schema fingerprint，用于重复导入和变更检测。

`anki_notes` 必须以 `(import_id, note_id)` 保存，同时持久化：

- `guid`、`mid`、`mod`、tags、原始字段；
- 字段 schema fingerprint；
- source revision，用于重导入比较。

`anki_cards_meta` 调整为真正的 Card 主索引，至少包含：

- `(import_id, card_id)` 唯一；
- `note_id`、`ord`、`did`；
- `queue/type/due/ivl/factor/reps/lapses/left/odue/odid/flags/data`；
- `render_capability`，不是排他性的课程归属；
- `front_status/back_status/media_status`；
- `source_suspended/source_buried`；
- `course_index_id`。

### 5.2 新增 `anki_decks`

不要只把 Deck 临时转成 Section。持久化：

- `import_id/did/name/parent_did`；
- deck config/preset 引用；
- source card count、descendant count；
- synthetic 标记；
- display order。

当 Card 引用了不存在的 `did` 时，创建 `Recovered / Missing deck <did>`，并记录 warning，不能丢卡。

### 5.3 新增 `anki_practice_projections`

派生练习独立保存：

- `card_id`；
- `projection_type`: `singleChoice | multiSelect | fillBlank | typeAnswer`；
- `status`: `candidate | accepted | rejected | conflict | stale`；
- options 与答案索引；
- `evidence_json`；
- confidence；
- classifier version；
- user override；
- source fingerprint。源 Note/Template 变化后自动标记 `stale`，不得继续使用旧答案。

### 5.4 新增 `anki_import_issues`

统一记录：

- severity：info/warning/error/fatal；
- scope：package/deck/notetype/note/card/media/scheduling；
- stable code；
- source ids；
- 可恢复方式；
- 用户处理状态。

建议的错误码：

- `DECK_JSON_ENTRY_INVALID`
- `CARD_DECK_MISSING_RECOVERED`
- `CARD_NOTE_MISSING`
- `NOTETYPE_MISSING`
- `FRONT_EMPTY`
- `TEMPLATE_RENDER_FAILED`
- `ANSWER_KEY_AMBIGUOUS`
- `SINGLE_CHOICE_MULTIPLE_KEYS`
- `MULTI_CHOICE_SINGLE_KEY`
- `MEDIA_MISSING`
- `COUNT_RECONCILIATION_FAILED`

## 6. 导入管线重构

### 阶段 A：包读取与格式识别

1. 在临时目录解包，进行路径穿越、绝对路径、超大压缩比、总展开大小和文件数限制。
2. 明确区分 `.apkg` 与 `.colpkg`；Turna 不执行 Anki `.colpkg` 的“替换整个 collection”语义，而应在 UI 中说明“作为新的本地 Anki 课程导入”。
3. 支持并测试传统与现代 package 变体；未知格式必须报明确错误，不能返回空集合。
4. 媒体文件只允许通过导入专属目录解析，WebView 禁止任意 `file://`、外部网络和跨导入访问。

### 阶段 B：逐实体解析

1. Deck、Notetype 单条解析、单条记录 issue；不得用一个外层 `try/catch` 丢掉整张 map。
2. Notes、Cards 分页读取后建立索引：`noteById/cardById/deckById/notetypeById`。
3. 所有整数转换失败都记录字段名和源 id；身份字段转换失败是 fatal，不允许默认为 0。
4. 保留 card id、note id、ord、did 的原始关系；禁止以 note id 代替 card id 做调度身份。

### 阶段 C：强不变量校验

提交前必须验证：

```text
storedCards == parsedCards
每个 Card 都能找到 Note 或被标记为 fatal
每个 Note 都能找到 Notetype 或被标记为 fatal
每个 Card 都能找到 Deck，找不到则进入 Recovery Deck
每个非空 Card 至少存在可检查的正面渲染结果
每个 Card 都有 course/navigation index
每个 SRS card id 都能解析回 canonical Card
```

规则：

- `sourceCardCount == 0`：默认阻止导入，并说明包中无 Card；
- `sourceCardCount > 0 && indexedCardCount == 0`：fatal；
- `sourceCardCount > 0 && sectionCount == 0`：fatal；
- `structuredProjectionCount == 0`：不是错误，仍可进行原生 Anki 复习；
- Fidelity 卡数量不限，也不得从导航索引消失。

### 阶段 D：暂存与原子提交

1. 先写 staging 表或同一数据库事务中的临时 import id。
2. 完成校验、媒体复制和导航索引后一次提交。
3. 失败、取消时清除 staging，不触碰上一次 complete 导入。
4. 重导入采用“先构建新快照，再原子切换”的方式，避免 Merge 中途留下半棵课程树。
5. `CourseLoader.invalidateCaches()` 和 scope 切换只能发生在 commit 成功之后。

## 7. 单选/多选识别重做

### 7.1 默认策略

每张 Card 默认始终拥有 Fidelity 表示。结构化识别返回：

```dart
sealed class PracticeClassification {
  AcceptedProjection projection;
  NoProjection reason;
  ConflictedProjection conflict;
}
```

不得用“解析失败后生成牌组级干扰项”作为 Anki 卡的默认回退。

### 7.2 证据优先级

从高到低：

1. 用户对具体 notetype/card 的显式覆盖；
2. 已注册并带版本的已知模板适配器；
3. 独立字段中的明确契约，例如 `Question + OptionA..D + AnswerKey`；
4. notetype/card template 的稳定结构和专用 data 属性；
5. notetype 名称、字段名称；
6. 题面“单项选择题/多项选择题”等正文提示，只作为弱证据；
7. AI 建议，只用于预览和批量辅助。

严禁把以下内容单独作为答案键：

- 整个渲染后的 afmt；
- 含解析说明的 Back；
- 题面重复出现的 A/B/C/D；
- 任意长文本中的孤立字母；
- 从同牌组其他卡片抽取的答案文本。

### 7.3 答案键解析契约

新增 `AnswerKeyParser`，输入必须包含来源类型：

```dart
AnswerKeyParseResult parse({
  required String raw,
  required AnswerSource source,
  required Map<String, int> optionLabels,
  required ExpectedCardinality cardinality,
});
```

只有 `dedicatedAnswerField`、受信模板适配器或用户指定区域可以自动接受。解析结果包含 normalized key、命中的原文范围、未消费字符和冲突原因。

单选规则：

- 必须恰好解析到 1 个选项；
- 解析到 0 个：`NoProjection`；
- 解析到 2 个以上：`SINGLE_CHOICE_MULTIPLE_KEYS`，保留 Fidelity，禁止静默变多选。

多选规则：

- 必须有明确的多选证据；
- 必须解析到至少 2 个不同选项；
- 只有一个答案时标记冲突，不自动降为单选；
- `minSelections/maxSelections` 默认都等于正确答案数；若产品希望允许任意数量，应在文案中说明，但这不是 Anki 原生语义。

### 7.4 自动映射与高级覆盖

导入默认不要求用户为整个 Note Type 选择 Single choice 或 Multi select，因为同一模板可能混合两种题型。系统按每张 Card 独立判定：

- 当前题面明确写单选/多选时作为硬约束；
- 题面未说明时，由显式答案字段中的完整答案键数量判定；
- Note Type 只用于定位题干、选项和答案字段，不强制整类卡片使用同一答案基数；
- 数据冲突时保留原卡，不要求用户在导入阶段替系统猜测。

未来若提供高级覆盖，只保留 `Fidelity only`、`Auto`、`Ignore projection` 等安全策略，不再提供容易与逐卡内容冲突的 Note Type 级单选/多选开关。诊断需展示原始字段、正反面预览、答案键精确字段、逐卡识别证据和冲突原因。

### 7.5 AI 的边界

- AI 不参与 canonical import 的成功与否；
- AI 输出只能是 suggestion；
- 用户确认后转成显式 mapping；
- 同一输入必须保存模型、prompt 版本和结果，重导入默认复用；
- AI 不得从常识“纠正”牌组答案，也不得把解析说明猜成答案键。

## 8. 渲染与复习流程

### 8.1 Fidelity 为默认能力

每张卡按 `note + notetype + ord` 生成正反面：

- qfmt 生成 question；
- afmt 生成 answer，并正确处理 `FrontSide`；
- 应用 notetype CSS；
- 支持字段替换、条件块、Cloze、`type:`、媒体与特殊字段；
- 保留 card ord，确保正向、反向和多模板卡独立；
- 前面为空时显示兼容性错误卡，而不是让 Card 消失。

JS 模板不能因为含 JS 就从课程树中删除：

- 安全允许时在受限 WebView 运行；
- 禁止网络、任意文件访问、窗口跳转和跨卡存储；
- 安全模式禁用 JS 时，仍显示降级内容和“模板需要 JS”提示；
- 可选预渲染缓存必须带 source/template fingerprint，内容变化即失效。

### 8.2 Anki 式主复习

主流程：

```text
Question → 用户回忆/可选作答 → Show Answer → 展示完整 Answer
         → Again / Hard / Good / Easy → 写入调度与 revlog
```

结构化题目可以在 Show Answer 前收集答案并给出“完全正确/部分正确/错误”提示，但最终评分仍由用户选择。可提供建议：

- 错误或未答：建议 Again；
- 正确但犹豫：用户自行选 Hard；
- 正确：建议 Good；
- 轻松正确：用户自行选 Easy。

不得把“点了正确选项”直接等同于 Good，也不得把“知道了”作为唯一 Anki 评分。

### 8.3 调度兼容等级

产品必须明确显示兼容等级：

- **Reset**：忽略源学习进度，所有 Card 作为新卡；对共享 `.apkg` 建议默认使用。
- **Migrate snapshot**：迁移 queue/due/ivl/factor/reps/lapses/revlog，再由 Turna 调度器继续；明确标记“近似迁移，不保证与同版本 Anki 下一间隔完全一致”。
- **Exact backend（远期）**：只有集成并持续跟进 Anki 官方调度后端/等价实现后，才可宣称精确兼容。

导入 UI 必须让用户选择是否导入学习进度。不能仅因为包内存在调度数据就默认采用。

## 9. 课程树、Deck 层级与 Lite 改造

### 9.1 牌组层级是导航主来源

Anki Deck/Subdeck 对应学习范围；tags/自定义字段可以作为可选视图，但不能取代 Deck 主层级。

建议映射：

- Course Entry：一次导入或用户合并后的 Anki collection scope；
- Section：顶层 Deck；
- Unit：Subdeck 层级或分页容器；
- Virtual Lesson：固定大小的 Card 引用页，或用户显式选择的标签分组；
- Stage：运行时按 Card 引用加载，不在导入时复制完整 Interaction JSON。

### 9.2 删除“空壳 Lite”的产品语义

Lite 改名为“按需加载”，仅控制：

- 是否预生成 Interaction；
- 是否预渲染 HTML；
- 每页索引大小；
- 缓存策略。

无论牌组是 10 张还是 100,000 张，都建立轻量导航索引。大牌组的 Virtual Lesson 只保存 card ids，因此不会产生当前 5,000 份大 JSON 的内存问题。

### 9.3 Fidelity 不再从 Lesson 跳过

Virtual Lesson 保存 CardRef，而不是保存具体 Renderer。运行时：

```text
CardRef → canonical card
        ├─ accepted projection → 可选 Structured View
        └─ always available   → Fidelity View
```

因此：

- 全 JS 牌组仍有完整 Lesson；
- 全图片牌组仍有完整 Lesson；
- 长答案牌组仍有完整 Lesson；
- 结构化识别为 0 不影响课程可见性；
- Anki 复习页和课程页引用同一 Card，而不是两份内容。

## 10. 重复导入与更新策略

不要只使用文件 hash 决定“同一批导入”。需要保留并利用：

- Note guid；
- Note id/Card id（同一来源快照内）；
- notetype/template/field id；
- mod 时间；
- schema fingerprint；
- source package lineage。

UI 提供与现代 Anki 类似的更新选项：

- 仅添加新 Note/Card；
- 新版本覆盖本地内容；
- 保留本地内容，不更新；
- notetype schema 冲突时预览合并；
- 学习进度独立选择保留本地/采用源/重置。

重导入必须保证 Card 的本地稳定标识不因 Section/Lesson 重建而变化。源 Card 删除时先标记 missing/tombstone，是否删除调度和历史由用户确认。

## 11. UI 修改

### 11.1 导入预检页

显示：

- 包类型、Deck/Subdeck、Notes、Cards、媒体；
- 可渲染卡数、空正面数、缺失 Note/Deck 数；
- 预计 Fidelity 数；
- 可选结构化练习数与冲突数；
- 是否导入学习进度；
- 牌组层级预览；
- 对每个 notetype 抽样至少 3 张，不只看首张。

主按钮文案使用“导入 Anki 卡片”，不要使用“生成课程题目”。

### 11.2 冲突处理页

对于 `SINGLE_CHOICE_MULTIPLE_KEYS`：

- 左侧显示原始正面；
- 中间显示原始答案面；
- 右侧显示结构化解析及证据；
- 选项为“保持 Anki 原卡”“指定唯一答案”“确认改为多选”“应用到同 notetype”；
- 默认选择“保持 Anki 原卡”。

### 11.3 导入完成页

分开显示：

- 源 Card 数；
- 已保存 Card 数；
- 已建立导航索引数；
- 可原样复习数；
- 已生成派生练习数；
- 冲突/降级/缺失媒体数；
- 学习进度采用方式。

禁止把“Card 已保存”写成“Lesson 已生成”。当 `lessonCount == 0` 时不得提供误导性的“开始课程”；如果按新架构正常建立虚拟 Lesson，则该情况只可能是 fatal。

### 11.4 诊断页

每次导入可打开诊断报告，支持按错误码筛选和导出 JSON。用户应能从任意复习卡查看：

- source deck/note/card/notetype/template ord；
- 当前 Fidelity/Projection；
- 识别证据；
- 调度来源；
- 媒体和模板警告。

## 12. 代码修改清单

> 注：本节为改造前的计划清单；P0–P3 核心项已实施（见 §18 实施记录），实际落地模块名以 §18 与代码为准。

### P0：立即止损

`lib/application/anki/anki_card_adapter.dart`

- 拆出 `AnswerKeyParser`；
- 禁止从整个 back/afmt 解析答案键；
- 删除 `correct.length > 1` 静默升级多选；
- 删除单选失败后牌组级伪干扰项回退；
- 人工 mapping 改为硬约束；
- 返回 classification diagnostics。

`lib/application/anki/anki_importer.dart`

- Deck/Notetype 逐条解析；
- 身份字段解析失败不再默认为 0；
- 返回 parse issues；
- 卡片与 Deck/Note/Notetype 对账。

`lib/application/anki/anki_deck_assembler.dart`

- 临时阶段先增加成功守卫；
- `sourceCardCount > 0 && sectionCount == 0` 抛出明确异常；
- Fidelity 不影响 Section 计数诊断；
- 修正 shell Unit 未计入 summary 的统计问题。

`lib/views/anki/anki_import_screen.dart`

- 导入前显示冲突数；
- 导入完成前验证 summary；
- 增加“导入学习进度”开关；
- 不在无 Section 时切换到新的 course scope。

### P1：主数据与原子导入

`lib/data/course_database.dart`、`lib/data/anki_note_dao.dart`、`lib/data/anki_import_dao.dart`

- 增加上述表和字段；
- 引入 staging/status；
- 增加一次导入的 count reconciliation 查询；
- 建立 `card_id/note_id/did/guid` 索引；
- schema migration 必须可回滚并保留旧数据。

新增（实际落地模块，详见 §18）：

- `lib/application/anki/anki_compatibility_diagnostics.dart`（兼容性诊断 + issue 记录，替代计划中的 validator/issue 独立模块）
- `lib/application/anki/anki_deck_manager.dart`（牌组管理与恢复）
- `lib/application/anki/anki_import_cleanup_service.dart`（导入暂存清理）
- `anki_import_issues` 表（`lib/data/course_database.dart`）
- 答案键解析与练习分类逻辑内联于 `anki_card_adapter.dart`（P0 拆出，未单列文件）

### P2：虚拟课程索引

重构：

- `anki_deck_assembler.dart` → 只创建导航索引，不决定 renderer；
- `course_loader.dart` → 支持 Virtual Lesson/CardRef 分页；
- `course_provider.dart` → Anki scope 加载 canonical deck tree；
- 课程树 UI → Fidelity 与 Structured 统一显示；
- `ankiLiteThreshold` → 改为缓存/预加载设置，停止影响 Lesson 是否存在。

### P3：官方式复习与调度边界

重构：

- `anki_review_assembler.dart` 只按 CardRef 取 canonical Card；
- `anki_review_session_page.dart` 固定 Question/Show Answer/四按钮流程；
- `anki_srs_migrator.dart` 增加 Reset/Migrate snapshot 模式；
- revlog 记录评分、间隔和耗时；
- 支持按选中 Deck 及其 Subdeck 收集卡片和每日上限。

### P4：模板兼容、安全与媒体

- 完善 qfmt/afmt/FrontSide/Cloze/type/特殊字段；
- 为 JS、网络、文件、媒体制定沙箱；
- 现代 package 与压缩媒体兼容；
- 建立官方/真实牌组兼容样本库；
- 预渲染缓存按 fingerprint 失效。

### P5：可选结构化练习

- 仅在 canonical review 稳定后上线；
- notetype adapter registry；
- 用户确认与批量覆盖；
- 结构化练习和原卡一键切换；
- 任何冲突默认回 Fidelity。

## 13. 测试计划

### 13.1 解析与不变量

- Deck JSON 中一个坏条目不影响其他 Deck；
- 缺失 did 自动进入 Recovery Deck；
- 缺失 nid/mid 阻止提交；
- 空 cards 包阻止导入；
- `cards > 0` 时最终 indexed cards 必须等于 cards；
- 取消/失败不改变上一份完整导入；
- 10、1,999、2,000、5,000、100,000 卡均建立可导航索引。

### 13.2 题型识别

- “单项选择题 + Answer=A” → SingleChoice；
- “单项选择题 + Answer=ACD” → Conflict + Fidelity；
- “多项选择题 + Answer=ACD” → MultiSelect；
- Back 解释中出现 A/C/D，但专用答案字段是 A → SingleChoice；
- afmt 重复 FrontSide/选项 → 不参与答案键解析；
- 人工 SingleChoice + 多答案 → 不允许静默升级；
- AI 建议不得覆盖人工映射；
- 源内容变化后旧 projection 变 stale。

### 13.3 渲染

- Basic、反向卡、可选反向卡；
- Cloze 多 ord；
- type answer；
- 图片、音频、CSS、相对媒体；
- JS 开/关与降级；
- 空正面显示诊断而不是消失；
- 同一 Note 的多个 Card 拥有独立调度身份。

### 13.4 复习与调度

- Show Answer 前不可评分；
- Again/Hard/Good/Easy 均写 review history；
- suspended/buried 不进入正常队列；
- Deck 选择包含其 Subdeck；
- Reset 与 Migrate snapshot 结果分离；
- 结构化答题结果只建议评分，不自动提交评分。

### 13.5 端到端验收样本

至少固定以下真实或脱敏 fixture：

- 官方 Basic；
- Basic and reversed；
- Cloze；
- 中文考研单选；
- 中文考研多选；
- 背面含长解析和 A/B/C/D 引用；
- JS 选择题模板；
- 图片遮挡/图片题；
- 多级 Deck/Subdeck；
- 2,000+ 大牌组；
- 缺失 Deck 元数据的损坏包；
- 重导入更新包。

## 14. 验收门槛

发布前必须同时满足：

1. 任意成功导入满足 `source cards == stored cards == indexed cards`，除非用户明确排除，并在报告中逐卡列出。
2. Fidelity 卡、JS 卡、图片卡和长答案卡全部能在课程导航中找到。
3. 不再存在“题面单选但无提示变为多选”。冲突默认 Fidelity。
4. 不再存在 `sourceCardCount > 0 && sectionCount == 0` 的成功状态。
5. 大牌组不物化全量 Interaction，首次打开只加载可见页或当前复习批次。
6. 导入失败、取消和重导入失败均不破坏上一次完整数据。
7. UI 明确区分“原卡”“派生练习”“学习进度迁移”。
8. 主复习流程支持 Show Answer 与四级自评，并正确写入历史。
9. 安全测试证明模板不能读取任意本地文件或访问未授权网络。
10. 所有兼容性降级均能从导入报告和单卡诊断中解释。

## 15. 发布顺序与迁移策略

### 里程碑 1：可靠性补丁

- 单/多选冲突不再静默转换；
- 导入强不变量和错误报告；
- Deck 恢复策略；
- 完成页计数修正。

上线条件：现有数据结构不大改，可快速阻止继续产生错误内容。

### 里程碑 2：Canonical Store v2

- 新 Deck/Projection/Issue 数据；
- 原子导入；
- 旧导入后台迁移并对账；
- 无法对账的旧导入标记“需要重新导入”，不删除原 SRS。

### 里程碑 3：虚拟 Lesson

- 所有 Card 建立轻量导航；
- Lite 改为按需加载；
- Fidelity 不再缺席课程页；
- 旧实体 Lesson 可以逐步废弃。

### 里程碑 4：Anki 式复习

- 正反面、四按钮、进度导入选择；
- Deck/Subdeck 队列；
- 调度兼容等级标识。

### 里程碑 5：结构化练习增强

- 严格 classifier；
- 模板适配器；
- AI 建议；
- 用户批量确认。

迁移期间使用 feature flags：

- `ankiCanonicalStoreV2`
- `ankiVirtualLessons`
- `ankiStrictPracticeClassifier`
- `ankiOfficialReviewFlow`

每个 flag 都必须支持回退到“只读旧导入 + 新导入走新管线”，禁止在回退时删除用户复习历史。

## 16. 明确不做与兼容声明

- 本计划不宣称实现 AnkiWeb 同步。
- 在未使用 Anki 官方调度后端前，不宣称下一间隔与当前 Anki 完全一致。
- 不自动执行 `.colpkg` 覆盖 Turna 全部本地数据的官方桌面行为。
- 不把 AI 识别包装成 Anki 官方功能。
- 不保证任意第三方 add-on JS 都可运行；不能运行时必须安全降级并可诊断。
- 不从 Anki 源码复制受许可证约束的大段实现；若未来集成官方后端，需要单独完成许可证与分发评审。

## 17. 最终产品定义

改造完成后，用户应看到的是：

> 导入任何有效 Anki 牌组后，每张 Card 都能在对应 Deck/Subdeck 和课程导航中找到，并可按原模板完成“问题—答案—自评”复习。系统可以额外把少量高置信度卡转换成单选、多选或填空练习，但这种转换始终可解释、可撤销，发生冲突时绝不改变原卡或隐藏卡片。

## 18. 2026-07-31 实施记录

本轮已完成面向原问题的核心改造：

- 单选/多选采用“当前卡题面明示 > 当前卡完整答案键数量 > Note Type 弱提示”的逐卡判定；单选声明与多个答案冲突时回退原卡，不再静默升级为多选。
- 答案键只从显式答案字段读取，解析说明中的 `A/B/C/D` 字母不再被误当作多答案。
- Canonical Note/Card/Deck/Notetype/Template/CSS 作为主数据落库；结构化 Interaction 作为带证据与状态的派生投影保存。
- 所有源 Card 均建立轻量课程导航索引；Fidelity、长答案、JS 与大牌组只改变按需渲染方式，不再导致 0 Section/0 Lesson。
- 对空牌组、孤儿 Card、缺失 Note Type、计数不一致设置强校验；成功条件为 `source == stored == indexed`。
- 缺失 Deck 元数据恢复到可见的合成牌组，并记录导入问题；循环层级不会再吞掉卡片。
- 导入数据库写入使用事务；重导入按完整集合重建派生索引，取消或失败不再留下“成功但为空”的课程。
- 用户可选择是否迁移 Anki 学习进度；关闭时全部按新卡导入，开启时保留可映射的排程和复习历史。
- 主复习流程改为 Show Answer 后由用户选择 Again / Hard / Good / Easy，并保留四级评分进入 FSRS 与历史记录。
- 模板 WebView 增加 CSP、URL 清理、媒体目录边界和外部导航阻断。
- 卡片浏览页点击卡片可查看 Card/Note/Deck 身份、原卡渲染模式、派生练习状态和识别证据。
- 单选/多选基数改为逐 Card 自动判断：题面明示优先，未明示时由完整答案键数量决定；导入页不再要求用户为整个 Note Type 选择单选或多选，同一模板可混合两种题型。
- Anki 原卡与 HTML 保真卡支持点击卡面在正反面之间往返翻转，翻回正面不会提交评分或改变学习进度。
- `collection.anki21b` 会被识别为最新版 schema-v18 包并给出兼容导出指引，不再误报“没有数据库”或生成空课程。

验证结果：相关 Anki/FSRS/DAO 回归测试通过；新增代码静态分析无错误。Flutter 测试运行时仍会输出项目既有的 `file_picker` 桌面插件元数据警告，不影响测试结果。

当前兼容边界：本轮完整支持 `collection.anki2` / `collection.anki21`（Anki 的“支持旧版 Anki”导出）；`collection.anki21b` 同时涉及 Zstandard、schema-v18 和 Protobuf 化元数据，不能仅增加解压库后复用旧解析器。原生读取该格式应作为独立兼容里程碑，并配套真实最新版 fixture、各平台原生库和许可证审查。在该里程碑完成前，产品必须保持当前的显式拒绝与重新导出指引，禁止静默降级。
