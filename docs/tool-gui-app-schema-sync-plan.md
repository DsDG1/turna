# Turna GUI 与 App 课程 Schema 对齐施工计划

> 状态：待施工
> 范围：仅改动 `tool/`（GUI + course_cli），不改 `lib/`（Flutter app 侧）
> 依据：2026-08 对 app（`lib/domain/course/`）与 GUI（`tool/gui/src/`）的全量 schema 对比结论

---

## 1. 背景

App 侧课程 schema 演进后，桌面编辑器（Turna GUI）出现 4 类落后，共 9 项缺口。已确认**同步、无需处理**的部分：7 种课时模板（含 `legacy`）、听力三阶段（`wordPairing/dialogue/summary`）、`readingPassage` 全部字段、Section→Unit→Lesson 三级结构、`index.json` 元数据、规模上限校验。

| # | 缺口 | 严重度 |
|---|------|--------|
| G1 | `ankiCard` / `ankiHtmlCard` 题型不被编辑器认识，`normalize_item` 直接抛 `ValueError`，GUI 自己的 Anki 导入产物无法编辑 | **高（功能断裂）** |
| G2 | `anki://<importId>/<file>` 媒体协议不被 lint/音频校验认识 | 高 |
| G3 | `showWord` 缺 6 个内联覆盖字段（`term/translation/pronunciation/audioAsset/imageAsset/example`） | 中 |
| G4 | `multipleChoice` 缺 `audioAssets` 列表；`fillBlank` 缺 `audioAssets` + `imageAssets` 列表 | 中 |
| G5 | `content.linkedGrammarPointIds` 无任何编辑入口（app 开课时注册语法点 SRS 依赖它） | 中 |
| G6 | grammar_points 的 `practiceItems` 无编辑列 | 中 |
| G7 | vocab 的 `pos` 字段无资源表列，且 CSV 往返会丢失 | 中 |
| G8 | AI 生成 prompt 的题型/字段枚举与上述缺口同步落后 | 中 |
| G9 | vocab-only 变更不触发任何版本 bump，已装 app 收不到更新（app 重播种触发器 = `index+expressions` 组合版本） | 中 |

## 2. 目标与非目标

**目标**：GUI 能无损打开、编辑、再保存 app 当前 schema 能表达的全部课程内容；AI 生成 prompt 与编辑器 schema 一致；发布流程保证任何资源变更都能触发客户端内容重建。

**非目标（明确不做）**：

- 不在 GUI 中复刻 `ankiHtmlCard` 的完整 HTML/CSS/JS WebView 渲染（教师模式给降级预览即可）。
- 不在 `course_cli validate` 中把未知 `runtimeType` 升级为 **error**（`showExpression`、`matchWords` 等历史字符串仍存在于语料；只加 lint warning，守住"校验单一来源"约束的同时不破坏既有课程）。
- 不改 Flutter app 侧任何代码；`pos` 字段当前 app 只定义了镜像枚举（`lib/domain/course/pos_tag.dart`）尚未解析，GUI 补齐属前瞻对齐。
- 不新增 GUI 自有校验规则（设计约束 #1：所有校验走 `course_cli`）。

## 3. 设计约束（继承 GUI 四约束）

1. **校验单一来源**：题型 schema 的唯一真相源是 `tool/gui/src/backend/lesson_content.py`（`INTERACTION_SCHEMA`），所有 widget 从它派生；lint/validate 规则只进 `tool/course_cli.py`。
2. **JSON 唯一真相源**：新增字段必须保证「打开 → 不动 → 保存」round-trip 无损（未知字段不得被静默丢弃——现有 `normalize_item` 按 schema 白名单重建 dict，因此**每个 app 支持的字段都必须进 schema**，这是 G1–G4 的根因）。
3. **ID 不可变**：anki 交互的 `id`（`anki-<importId>-n<noteId>-c<ord>`）与 `sourceNoteId/sourceCardId` 在编辑/类型切换中保持原值。
4. **保存失败自动回滚**：不受本计划影响，回归确认即可。

---

## 4. 工作流分解

### P0 — Anki 卡片题型闭环（G1 + G2 + G8 anki 部分）

#### P0.1 扩展题型 schema（`tool/gui/src/backend/lesson_content.py`）

- `ALLOWED_RUNTIME_TYPES` 追加 `"ankiCard"`、`"ankiHtmlCard"`（追加在元组末尾，不打乱既有顺序）；同步 `INTERACTION_LABELS`：`"ankiCard": "Anki 卡片"`、`"ankiHtmlCard": "Anki HTML 卡片"`。
- `INTERACTION_SCHEMA` 新增（字段名/必填性对齐 `lib/domain/course/interaction.dart:160-199`）：

```python
"ankiCard": [
    FieldSpec("id", False, "string", ""),
    FieldSpec("front", True, "string", ""),
    FieldSpec("back", True, "string", ""),
    FieldSpec("audioAssets", False, "string_list", []),
    FieldSpec("imageAssets", False, "string_list", []),
    FieldSpec("hint", False, "string", ""),
    FieldSpec("sourceNoteId", False, "string", ""),
],
"ankiHtmlCard": [
    FieldSpec("id", False, "string", ""),
    FieldSpec("frontHtml", True, "string", ""),
    FieldSpec("backHtml", True, "string", ""),
    FieldSpec("css", False, "string", ""),
    FieldSpec("mediaBasePath", False, "string", ""),
    FieldSpec("allowJs", False, "bool", False),
    FieldSpec("audioAssets", False, "string_list", []),
    FieldSpec("sourceNoteId", False, "string", ""),
    FieldSpec("sourceCardId", False, "string", ""),
    FieldSpec("wordId", False, "string", ""),   # 注意：anki 合成 id（anki-<importId>-c<cardId>），不能 kind="ref_word"
],
```

- `switch_runtime_type` 语义组（`_field_to_group`）新增映射，保证普通题型与 anki 题型互转时内容尽量保留：
  - prompt 组扩为 `(prompt|sentence|source|statement|front|frontHtml)`；
  - answer 组扩为 `(expected|answer|expectedAnswer|back|backHtml)`（注意 `answer` 在 `readingTrueFalse` 是 bool，沿用现有 kind 兼容分支即可）；
  - hint 单独成组（`fillBlank.hint ↔ ankiCard.hint`）；
  - `audioAssets`、`imageAssets` 同名直传（现有同名字段逻辑已覆盖）。
- 模块 docstring「Defines the 12 Interaction runtimeType schemas」改为 14。

#### P0.2 属性表单与教师模式渲染

- **表单**（`tool/gui/src/widgets/interaction_forms.py`）：`InteractionForm` 是 schema 驱动的通用渲染，P0.1 完成后 `ankiCard`/`ankiHtmlCard` 自动获得表单；确认 `string_list`（audioAssets/imageAssets）与 `bool`（allowJs）控件可用。`frontHtml/backHtml/css` 用多行文本框（与 `context`/`transcript` 同款）。
- **教师模式卡片**（`tool/gui/src/widgets/teacher/question_cards.py`）：
  - `ankiCard`：翻卡交互（点击 front 显示 back），`audioAssets` 逐个给出播放占位（文件在 anki 导入目录内，桌面端不强制可播，显示路径即可）；`hint` 以「提示」按钮呈现。
  - `ankiHtmlCard`：降级预览——front/back 显示**剥除标签后的纯文本** + 顶部「HTML 卡片，完整渲染请以 App 为准」徽标；`css/allowJs` 不渲染。
  - 类型切换 combo（`ALLOWED_RUNTIME_TYPES` 驱动）自动包含新类型，无需单独改。
- **教师模式隐藏字段**（`tool/gui/src/i18n/labels.py:62-68` `HIDDEN_FIELDS`）：追加 `sourceNoteId`、`sourceCardId`、`mediaBasePath`、`allowJs`（教师视角噪音字段）。

#### P0.3 Anki 导入器打通（`tool/gui/src/backend/anki_import.py`）

- 导入流程结束后对每个 item 调 `normalize_item` 做一次自检（P0.1 之前它必然抛错，之后应通过），保证「导入 → 打开课时编辑器 → 保存」全链路无损。
- 现有产物字段（`front/back/audioAssets/imageAssets/sourceNoteId`，`tool/gui/src/backend/anki_import.py:277-285`）与 P0.1 schema 完全一致，无需改产出结构。

#### P0.4 course_cli 适配 `anki://` 媒体协议（`tool/course_cli.py`）

- 音频引用收集（`_iter` 侧，`course_cli.py:228` 只收 `audioAsset` 单字符串）：新增收集 `audioAssets`（List[str]）与 `imageAssets`（List[str]，仅用于 lint 提示，不参与音频规则）。
- lint 音频规则（`course_cli.py:1116-1198`）：
  - 引用值以 `anki://` 开头 → **跳过**「非听力课引用 audioAsset = error」与「`assets/sounds/listening/<asset>.mp3` 存在性 = warning」两条规则（媒体在 app 导入目录内解析，桌面仓库无此文件）。
  - 普通路径引用维持现规则不变。
- validate：`ankiHtmlCard.wordId` 的 `anki-<importId>-c<cardId>` 格式**不参与** `wordId` 悬空引用校验（在引用检查处按前缀 `anki-` 豁免）；`showWord` 相关校验不受影响。

#### P0.5 AI prompt 同步（G8 anki 部分）

`tool/gui/src/backend/ai/prompts.py:30-61` 与 `tool/gui/src/backend/ai_generator.py:226-259`（`_template_schema_block`）是**两份手写副本**，需同步追加：

```text
- ankiCard: { front, back, audioAssets?, imageAssets?, hint?, sourceNoteId? } — Anki 翻卡（仅限导入内容再编排，AI 不主动生成）。
- ankiHtmlCard: { frontHtml, backHtml, css?, mediaBasePath?, allowJs?, audioAssets? } — Anki HTML 卡（同上，AI 不主动生成）。
```

同时在两处的题型建议块加一句约束：**AI 生成课程时不要产出 anki 卡片题型（它们来自设备端导入）**，避免模型凭空造 `sourceNoteId`。

#### P0.6 测试

- `tool/gui/tests/test_lesson_content.py:157`：`len(ALLOWED_RUNTIME_TYPES) == 12` → `14`；断言新题型 schema 字段集合。
- 新增 round-trip 用例：构造含 `ankiCard`/`ankiHtmlCard` 的 lesson → `normalize_item` → 字段无损；`switch_runtime_type("ankiCard" → "multipleChoice")` 时 front→prompt、back→正确落入语义位；`id` 保持。
- `test_anki_import`（如无则新建）：导入 fixture apkg → `normalize_item` 全通过。
- `tool/test/tool/` 下 CLI 测试：`anki://` 引用不触发 lint 音频 error；`ankiHtmlCard.wordId` 不触发悬空引用 error。

**验收**：用 GUI 打开任一含 Anki 导入课时的课程 JSON，编辑器正常显示、可改 front/back、保存后 round-trip 无损；`course_cli lint` 对 `anki://` 无误报。

---

### P1 — 已有题型字段补齐（G3 + G4 + G8 字段部分）

#### P1.1 schema 追加（`lesson_content.py` `INTERACTION_SCHEMA`）

对齐 `lib/domain/course/interaction.dart:35-85,173-199`（全部可选）：

```python
# showWord 追加（内联覆盖词表查询结果的字段）
FieldSpec("term", False, "string", ""),
FieldSpec("translation", False, "string", ""),
FieldSpec("pronunciation", False, "string", ""),
FieldSpec("audioAsset", False, "string", ""),
FieldSpec("imageAsset", False, "string", ""),
FieldSpec("example", False, "string", ""),
# multipleChoice 追加
FieldSpec("audioAssets", False, "string_list", []),
# fillBlank 追加
FieldSpec("audioAssets", False, "string_list", []),
FieldSpec("imageAssets", False, "string_list", []),
```

注意：`showWord.wordId` 仍是唯一必填项；内联字段语义是「非空时覆盖词表条目显示」，表单控件旁给出行内提示说明该语义。

#### P1.2 表单与教师模式

- `interaction_forms.py` schema 驱动自动渲染；`string_list` 复用 options 同款编辑器。
- 教师模式（`question_cards.py`）：`showWord` 卡片在内联字段非空时优先显示内联值（与 app 行为一致）；`multipleChoice`/`fillBlank` 的 `audioAssets` 显示为可点占位（同 P0.2 的处理）。
- `labels.py` `FIELD_LABELS` 补中文标签（如 `example` →「例句」、`audioAssets` →「音频列表」）。

#### P1.3 AI prompt 同步

`prompts.py` 与 `ai_generator.py` 两份 schema 块同步：showWord 行补 `{ wordId, context?, term?, translation?, pronunciation?, audioAsset?, imageAsset?, example? }`；multipleChoice 补 `audioAssets?`；fillBlank 补 `audioAssets?/imageAssets?`。加一句：「showWord 内联字段仅在该卡需要覆盖词表默认显示时填写，通常留空」。

#### P1.4 测试

- round-trip：带全部新字段的 item → normalize → 无损。
- 既有 golden/生成测试（`tests/ai_goldens/`）跑通确认 prompt 变更未破坏稳定性探针。

**验收**：在 GUI 中为 showWord 填写内联例句/图片、为 multipleChoice 挂多条音频，保存后 app 侧解析行为一致（抽查 JSON 即可，不改 app）。

---

### P2 — 课时与资源字段（G5 + G6 + G7）

#### P2.1 `content.linkedGrammarPointIds` 编辑入口（G5）

- **后端**（`tool/gui/src/backend/course_adapter.py`）：仿 `prerequisiteLessonIds` 的处理（`course_adapter.py:810` 模式）增加 `set_linked_grammar_points(lesson_id, ids)`；新建课时默认 `"linkedGrammarPointIds": []`（对齐 `course_adapter.py:253` 的既有默认注入点）。
- **UI**（`tool/gui/src/widgets/lesson_editor.py` 元数据区）：新增「关联语法点」多选编辑器（checkable 下拉或标签选择器，数据源 = `grammar_points` 表，与 `ref_grammar` 下拉同源）；选中值写入 `content.linkedGrammarPointIds`。
- **校验**：`course_cli` 已校验悬空 `linkedGrammarPointIds`（无需新增）；确认 GUI 保存失败回滚路径覆盖该字段。
- **总览**（可选）：`overview_stats.py` 的语法覆盖率统计把 `linkedGrammarPointIds` 计入引用来源，与既有 stage 内 `grammarPointId` 引用合并去重。

#### P2.2 grammar_points `practiceItems` 编辑（G6）

- 资源表（`resource_editor.py`）grammar tab 增加「练习」单元格按钮 → 打开对话框，内嵌复用 `ItemListPanel`（`lesson_editor.py` 使用的同款 items 编辑面板，P0 后支持全部 14 种题型）绑定该条目的 `practiceItems` 列表。
- CSV 路径维持现状（`course_cli.py:847-857` 已在 `_build_entry` 保留 `practiceItems`），不扩 CSV 列（交互列表不适合表格交换）。
- 资源包 JSON 导入导出确认 `practiceItems` 随条目完整携带。

#### P2.3 vocab `pos` 列（G7）

- **CSV/表列**（`tool/course_cli.py:792-860`）：`build_csv_rows` vocab 分支 headers 追加 `"pos"`（expressions **不加**，词性仅属词汇）；`_build_entry` vocab 分支补 `"pos": row.get("pos", "").strip() or None`——修复 CSV 往返丢失。
- **资源表**（`resource_editor.py`）：vocab tab 新增 `pos` 列，控件为下拉（空 + `tool/gui/src/backend/experience/pos_constants.py` 的 10 值闭集），展示中文标签（名词/动词/…）存储英文枚举值。
- **lint**（`course_cli.py`）：vocab 条目 `pos` 非空但不在闭集内 → warning（不 error，与 tags 的处理同级）。
- **AI 技能**：`resource_batch_skill.py` 的 `POLISH_FIELDS` 已含 `pos`，无需改；确认其写入值与闭集一致（测试覆盖）。

#### P2.4 测试

- CSV 往返：带 `pos` 的 vocab 导出→导入→值保留；expressions 无 pos 列不受影响。
- `set_linked_grammar_points` 单测 + 保存回滚路径；`practiceItems` 对话框编辑 round-trip。

**验收**：三项字段在 GUI 内可编辑、可保存、round-trip 无损，且 `course_cli validate` 全绿。

---

### P3 — 发布工作流缝隙（G9）

#### P3.1 vocab 变更联动版本 bump（`course_adapter.py:1291-1307`）

```python
if changes["expressions"] or changes["vocab"]:
    plan["expressions"] = (self.expressions_version, self.expressions_version + 1)
```

理由：app 重播种触发器是组合版本 `"$indexVersion+$expressionsVersion"`（`lib/data/course_database_seeder.dart:42-53`）；vocab 与 expressions 同属资源层，vocab 变更借道 expressions 版本触发客户端重建是最小改动（改 app 触发器超出本计划范围）。

#### P3.2 发布对话框提示（`tool/gui/src/widgets/publish_dialog.py`）

bump 预览中标注联动原因：「vocab 有变更 → 联动 bump expressions 版本 N→N+1（触发客户端内容重建）」，避免使用者困惑。

#### P3.3 测试

`version_bump_plan`：仅 vocab 变更 → expressions 出现在 plan；vocab+expressions 同时变更 → 单次 bump（不叠加）。

**验收**：仅改一条 vocab → 发布 → 客户端 composite 版本变化触发重播种。

---

## 5. 里程碑与顺序

| 里程碑 | 内容 | 依赖 |
|--------|------|------|
| M1 = P0 | Anki 题型闭环（schema → 表单/教师 → 导入器 → CLI → prompt → 测试） | 无 |
| M2 = P1 | 题型字段补齐 | M1（string_list 经验复用，可并行） |
| M3 = P2.3 | vocab pos 列 | 无（可与 M1 并行） |
| M4 = P2.1 + P2.2 | linkedGrammarPointIds + practiceItems | M1（practiceItems 面板依赖 14 种题型） |
| M5 = P3 + 文档 | bump 联动 + README/authoring 文档更新 | 无 |

文档收尾（M5）：更新 `tool/gui/README.md`（「12 种互动题型」→ 14 种、新增字段说明、pos 列、版本联动说明）、`docs/authoring/lesson-type-templates.md`（anki 题型与新字段）、`tool/gui/tests/BASELINE.md`（用例数）。

## 6. 测试与回归策略

- 每步跑 `QT_QPA_PLATFORM=offscreen python -m pytest tool/gui/tests/ --ignore=tests/test_app.py -q`，收尾跑全量 + `python test/tool/gui_round_trip_test.py -v` + `python -m unittest discover -s test -p "*_cli_test.py"`。
- **关键回归红线**：对 `assets/courses/turkish/` 现有课程做「打开 → 不改 → 保存」diff 必须为空（round-trip 无损是本计划的硬性验收，也是四约束之二）。
- 新增测试文件建议：`test_anki_interaction_schema.py`（P0）、`test_resource_pos.py`（P2.3）、扩展 `test_publish_flow`（P3）。

## 7. 风险与开放问题

| 风险 | 缓解 |
|------|------|
| `normalize_item` 白名单机制意味着 schema 漏一个字段就丢数据（本次 G1–G4 的根因） | P1 收尾时对照 `interaction.dart` 全字段清单逐项核对一遍 schema；长期可考虑「未知字段透传」而非丢弃（另行提案，本计划不做以避免静默保留脏数据） |
| AI prompt 双副本（prompts.py / ai_generator.py）漂移 | 两处同步列为每个 prompt 任务的检查项；长期可抽单一来源（超范围） |
| course_cli validate 对未知 runtimeType 保持宽松，可能漏掉真拼写错误 | lint 增加未知 runtimeType warning（对齐 `lesson_content.ALLOWED_RUNTIME_TYPES ∪ {showExpression, matchWords 等历史串}` 白名单） |
| `pos` app 侧尚未解析 | 字段无害（app 模型忽略未知键），属前瞻对齐；app 启用解析时零成本 |
| ankiHtmlCard 教师模式纯文本降级可能让创作者误判排版 | 徽标明示「以 App 渲染为准」；不做 WebView（非目标） |
