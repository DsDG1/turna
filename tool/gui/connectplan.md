# connectplan — 教材导入 × AI 生成课程 一体化改造计划

> 目标：把「导入教材（Beta）」和「AI 生成课程（Beta）」从两个割裂的 modal 对话框，改造为一条**连贯的课程创作流水线**：素材 → 知识 → 设计 → 审校 → 导入。
> 本文档基于对 `tool/gui/src` 现状的逐文件分析（2026-07），所有引用均带文件/行号，可直接落地。

---

## 一、现状诊断：割裂点清单

### 1.1 两条互不相见的流水线

```
导入教材（Beta）                                    AI 生成课程（Beta）
─────────────────                                  ─────────────────
TextbookLibraryDialog (modal)                      AiGeneratorDialog (modal, 2196 行)
  └─ TextbookImportDialog 6 步向导 (modal)           ├─ 普通模式: spec 表单 → 一次性生成
     ①选教材 ②解析(死页面) ③勾选章节                    └─ 许愿模式: 多轮聊天 → 生成
     ④提取知识点 ⑤审校 ⑥导入
     产物: build_intro_lesson 机械拼课                          │
     （每词一个 sublesson，无 AI 课程设计）                        │
     数据: var/textbooks/{id}/project.json            数据: 仅 prompt 历史，草稿关窗即丢
                     │                                          │
                     └────────────► app.py:546 ◄────────────────┘
                        _import_section_dict_result（唯一交汇点）
```

**唯一共享的只有最后一步导入命令**（`ImportAiSectionCommand` / `MergeAiSectionCommand`）。此前所有环节——入口、UI 范式、数据持久化、Prompt、资源上下文——全部各自为政。

### 1.2 用户视角的"割裂感"具体来自哪里

| # | 割裂点 | 证据 |
|---|---|---|
| D1 | **AI 生成看不到教材知识点**。老师导入教材后想让 AI 设计好课，AI 却对刚提取的几百个词条一无所知，只能凭空造词 | `ai_generator.py` 全文无 textbook/knowledge 引用；普通模式 `build_prompt` 只用 spec 字段，连课程现有 vocab 都不注入 |
| D2 | **教材导入产出的课是"死课"**。每章 = 每词一个 sublesson（showWord→translate→fillBlank），无听说读写模板混合，无单元/课时编排 | `textbook_to_course.py:42-81` 确定性拼接；practice/review 模板已接线但无任何 preset 使用、UI 不可选（`textbook_presets.py:33-35` 自述 "Only intro is meaningfully implemented"） |
| D3 | **两个入口、两套 Beta 警告、两个 modal 互相阻塞**。不能一边看教材知识点一边让 AI 生成 | `app.py:158-166` 两个独立 toolbar action；`app.py:491-499` 与 `app.py:681-690` 两个独立 QSettings 警告；两对话框均 `.exec()` |
| D4 | **AI 草稿无持久化**。关掉 AI 对话框，未导入的草稿和许愿聊天记录全部丢失；教材项目却能断点续传——同一 app 内两种待遇 | `ai_prompt_library.py` 只存 prompt 模板/历史；`textbook_project_store.py` 存全量状态 |
| D5 | **两套 Prompt 库**。教材抽取用 `KnowledgePromptLibrary`（knowledge_prompt.py），AI 生成用 `ai_prompt_library.py`，模板无法互通 | bookplan2.md:22 自述 "与现有 AI 生成功能割裂"，Phase 5 只打通了一半 |
| D6 | **教材向导内部也不顺**：②解析页是死页面（load_file 直接跳 ③）；步骤条不可点击、不能回退；新建项目时选过的文件到①还要再选一遍 | `textbook_import_controller.py:259-266`；`textbook_import_dialog.py:390-392`；`textbook_library_dialog.py:143-148` |
| D7 | **合并策略 = N 个串行 modal**。默认合并策略下 K 章冲突弹 K 次 `AiMergePreviewDialog`，取消被算作"跳过" | `app.py:630-650` |
| D8 | **重导入必然产生垃圾**。unit/lesson id 用 `short_id()` 随机生成，再次导入同章 = 全新 lesson，合并去重失效 | `textbook_to_course.py:66-70` 及其 docstring 自述 "re-import is out of scope" |
| D9 | **导入状态从不落盘**。`imported_section_ids` 只在测试里写过，项目库的"已导入"列永远显示"否" | `textbook_project.py:108-111`；仅 `tests/test_textbook_project.py:75-83` 写入 |
| D10 | **项目语言对硬编码** Turkish←Chinese，新建项目不可改 | `textbook_library_dialog.py:146-147` |

### 1.3 架构上已有的好基础（改造要站在上面，不要推翻）

- **Controller/View 分层**：`TextbookImportController`（纯 Python 状态机 + `ImportStepResult` 回调）是现成的流水线控制器范式，许愿/设计阶段应复用此范式，而不是再造。
- **统一导入收尾**：`app.py:546-674` `_import_section_dict_result` + `import_strategy.resolve_action` + undo 命令栈，两条流水线已在此交汇——把它从 MainWindow 抽成服务即可服务双方。
- **知识点 schema = 课程资源 schema**：`KnowledgePoints`（words/expressions/grammarPoints）与课程 vocab/expressions/grammar_points 同构，`KnowledgeMerger` 已能做课程级去重。
- **共享 AI 基建**：中央 `AiApiConfig`、`AiRequestWorker`、`ai_usage`、`AiFixDialog` 已被两条线复用。
- **模板体系**：`lesson_content.py` 的 6 种模板（intro/practice/review/listening/reading/mastery）已被教材 builder、AI genre、教师视图三方消费。

---

## 二、目标形态：一体化「课程工坊」

### 2.1 核心理念

把两个功能重新表述为**一条流水线的不同阶段**，而不是两个功能：

```
  素材 Sources          知识 Knowledge          设计 Design            审校 Review         导入 Import
 ┌──────────────┐   ┌──────────────────┐   ┌────────────────────┐   ┌──────────────┐   ┌──────────────┐
 │ 教材文件      │   │ 资源池 Resource    │   │ AI 课程设计         │   │ JSON 编辑器   │   │ 批量预览      │
 │ (.md/.txt/   │──►│ Pool (words/      │──►│ （ grounded 生成：   │──►│ + 结构预览    │──►│ + 策略选择    │──►│ undo 命令栈
 │  .pdf 文本)   │   │  expressions/     │   │  AI 只做编排，       │   │ + diff       │   │ + 冲突解决    │   │ → 保存 → 发布
 │ 粘贴文本      │   │  grammarPoints)   │   │  词条来自资源池）     │   │ + AI 修复    │   │              │
 │ 附件/聊天输入  │   │ + 质量报告/去重    │   │ + 许愿聊天迭代       │   │ + 试做        │   │              │
 └──────────────┘   └──────────────────┘   └────────────────────┘   └──────────────┘   └──────────────┘
        ▲ 现有教材导入的 ①②③④              ▲ 现教材导入没有的能力              ▲ 现 AI 对话框的          ▲ 现教材导入的 ⑥
        ▲ 现教材导入的 ⑤ 强化版            ▲ （D2 的解法）                   ▲ 审校区块平移            ▲ + D7 批量合并
```

- **「导入教材」不再是独立功能，而是往资源池"投喂素材"的入口之一**。
- **「AI 生成课程」不再凭空生成，而是以资源池为 grounded context 做课程编排**（units/lessons/模板选择/题目设计），词条引用资源池已有 id——这同时解决了 D1（AI 看不见教材）和 D2（导入产出死课），并天然降低了 AI 造词的 token 消耗与幻觉。
- **从零生成（无素材）只是资源池为空的特例**：许愿聊天、主题生成照常工作，AI 在资源池为空时退回现在的自由造词模式。

### 2.2 目标用户体验（丝滑旅程）

1. 老师点工具栏唯一的「**课程工坊**」按钮（取代两个 Beta 按钮），打开一个**非 modal** 工作窗口——不阻塞主窗口课程树，可随时切回去看现有课程。
2. 左侧是可点击的阶段导航（素材/知识/设计/审校/导入），已完成阶段可自由回跳，改动向后级联（复用现有 autosave）。
3. 拖入教材文件 → 自动解析、切章、勾选 → 点「提取知识点」→ 资源池表格（现有 `ResourceReviewTable` 平移）带红黄质量标记。
4. 资源池上方一个醒目的「**AI 设计课程 →**」按钮。点击后进入设计阶段：左栏是资源池摘要 + 编排参数（单元数、模板混合、难度），右栏是许愿聊天区——老师可以说"前两章做成 intro+listening，语法点单独一个 review 单元"。
5. AI 产出的 section JSON 里 `wordId` 全部引用资源池已有 id；流式写入 JSON 编辑器（现有组件平移）。
6. 审校阶段：diff、试做、AI 修复——三个功能三条流水线共用同一面板。
7. 导入阶段：批量预览 + 策略 + **一次性**冲突解决表（不再是 N 个 modal）。
8. 任何时刻关闭窗口，项目在 `var/textbooks/{id}/project.json`（升级为 authoring project）里完整续存——包括 AI 草稿和聊天记录。

### 2.3 明确不做的（沿用 bookplan2 §八边界）

- 不做 OCR / MinerU；不做自动发布；不做云端同步。
- **不删旧入口的兼容期**：改造期间保留旧对话框代码路径，用 feature flag 切换，逐阶段替换（见 §五 阶段划分）。
- 不改动 Flutter 侧 `lib/application/ai/`（Dart 端 AI 生成是独立端，本次只统一 GUI 工具侧；但在文档中标注 prompt 漂移风险）。

---

## 三、后端改造设计

### 3.1 统一项目模型：`AuthoringProject`（解决 D4、D9、D10）

在现有 `TextbookProject`（`textbook_project.py:35`）上演进，**不新造存储**：

```
var/textbooks/{project_id}/project.json  →  version 1 → 2 迁移
```

新增字段（version 2）：

```jsonc
{
  "version": 2,
  // —— 现有字段全部保留（source_path/markdown/chapters/knowledge...）——
  "language": "Turkish",            // D10: 新建项目时可选，默认沿用
  "source_language": "Chinese",
  "resource_pool": {                // 审校后的资源池快照（= 合并后的 KnowledgePoints）
    "words": [], "expressions": [], "grammarPoints": [],
    "updated_at": "..."
  },
  "design": {                       // D4: AI 设计阶段持久化
    "chat_history": [],             // 许愿模式对话（含附件引用，不存 base64 本体）
    "params": {"units": 3, "template_mix": ["intro","listening"], "level": "A1"},
    "draft_sections": [],           // 未导入的 section JSON 草稿（编辑器文本即真相，同 B1 原则）
    "explanation": ""               // explain_course 输出缓存
  },
  "imported_section_ids": [],       // D9: 导入成功后真正写入
  "import_map": {"ch-xxx-1": "sec-id"}  // 章节 → section 映射，供重导入幂等
}
```

- `TextbookProjectStore` 增加 `migrate_v1_to_v2()`：旧项目打开时静默升级（补空字段），测试覆盖。
- 章节 `knowledge` 审校定稿后写入 `resource_pool`；`resource_pool` 是设计阶段的唯一知识来源。
- 无教材的纯 AI 项目也允许存在：`source_path` 为空、`chapters` 为空，直接从「素材」阶段跳到「设计」——**这就是原「AI 生成课程」在新模型里的形态**。

### 3.2 抽取服务：`SectionImportService`（解决 D7 的架构前置）

把 `MainWindow._import_section_dict_result`（`app.py:546-674`）及其辅助（`plan_bulk_import`、merge 预览调度）抽为 `src/backend/section_import_service.py`：

```python
class SectionImportService:
    def __init__(self, adapter: CourseAdapter, undo_stack: QUndoStack): ...
    def plan(self, sections: list[dict], strategy: ImportStrategy) -> BulkImportPlan
    def execute(self, plan: BulkImportPlan,
                merge_resolver: Callable[[SectionMergePlan], MergeDecision | None]
                ) -> ImportOutcome   # 成功/跳过/失败 + 每 section 结果
```

- MainWindow、教材控制器、未来的设计控制器都调这一个服务；UI 层只负责提供 `merge_resolver` 回调（GUI 弹对话框 / 测试给假决策）。
- **批量合并解析器**（解决 D7）：新增 `BulkMergeResolvePanel`——一张表列出全部冲突 section 的合并计划摘要（新增/替换/删除计数），行内复选"采用 AI 版 / 保留现有 / 跳过"，一键应用；逐条细看仍可点开现有 `AiMergePreviewDialog`。
- `execute()` 成功后回写 `imported_section_ids` 与 `import_map`（D9）。

### 3.3 幂等 id（解决 D8）

`textbook_to_course.build_section_from_chapter` 改造：

- unit id：`u-{chapter.slug}-{idx}`；lesson id：`l-{chapter.slug}-{idx}-{template}-{n}`；sublesson/stage id 同理派生。
- 全部 id 由 (project_id, chapter.slug, 位置) 确定性生成，重导入同章 = 同 id，`KnowledgeMerger` 与合并计划自然生效。
- AI 设计阶段生成的 section 沿用同一规则：控制器在落草稿前把 AI 给的 id 重写为确定性 id（保留 AI 的 name/结构）。

### 3.4 Grounded 生成：资源池注入 AI（解决 D1、D2，本计划的核心）

`ai_generator.py` 改动：

1. `AiCourseSpec` 增加可选字段 `resource_pool: KnowledgePoints | None` 与 `design_brief: str`（编排意图，可来自聊天总结）。
2. `build_prompt(spec)` 新增 `_resource_pool_block`：把资源池序列化为紧凑清单（`id: term = translation [tags]`，超出预算按章节顺序截断，预算纳入 `max_chapter_chars` 同款配置）。
3. Prompt 规则改为两态：
   - **有资源池**："words/expressions/grammarPoints 必须从给定清单中按 id 引用，禁止新造词条；你的任务是编排 units/lessons、选择模板、设计题目上下文"；lesson 里允许引用池外词时走现有 `_auto_fix_resources` 兜底（合成 `[待补]` stub，审校阶段可见）。
   - **无资源池**：现有自由生成 prompt 原样保留。
4. `generate_from_chat`（许愿）同样注入资源池块 + `draft_json` 迭代逻辑不变。
5. **Token 优化顺带做**：`_template_schema_block`/`_resource_schema_block` 在 grounded 模式下可裁掉资源 schema 段（约省 1/3 prompt），并修 `ai_generator.py:859-864` 流式 usage 丢失问题（SSE 末帧读取 usage，无则按 pricing 估算并标注"估算"）。
6. 抽取 system prompt 的 7 处复制粘贴（`ai_generator.py:884, 952, 1053, 1292, 1625, 1713, 1786`）收敛为模块级常量 `_SYSTEM_AUTHORING` / `_SYSTEM_CHAT`，一次性消除漂移源。

### 3.5 Prompt 库合并（解决 D5）

- `knowledge_prompt.py` 的 `KnowledgePromptLibrary` 并入 `ai_prompt_library.py`：模板增加 `kind` 字段（`course_gen` / `extraction` / `correction`），按 kind + 语言对索引。
- UI 侧 `PromptTemplateBar` 在设计阶段显示 `course_gen` 模板；知识阶段的提取 prompt 模板在设置对话框中可编辑（不进主界面，避免臃肿）。
- `textbook_presets.py` 保留（教材类型 → temperature/strategy/max_tokens），作为提取阶段的 preset；设计阶段 preset 复用 `ai_presets.py`。

---

## 四、UI 改造设计

### 4.1 新窗口：`WorkshopWindow`（非 modal，解决 D3）

`src/dialogs/workshop_window.py`，仿 `TeacherWindow` 模式（`.show()` + `Qt.Window` + QSettings 几何持久化，`app.py:412-451` 有现成范例）：

```
┌──────────────────────────────────────────────────────────┐
│ 项目: 土耳其语阅读 ▾   [保存项目]            阶段进度 ●●●○○ │
├──────────┬───────────────────────────────────────────────┤
│ ① 素材    │                                               │
│ ② 知识    │        QStackedWidget（5 个阶段页）             │
│ ③ 设计    │                                               │
│ ④ 审校    │   底栏: 进度条 | 阶段提示 | token 用量 | 取消    │
│ ⑤ 导入    │                                               │
└──────────┴───────────────────────────────────────────────┘
```

- **阶段导航可点击**（解决 D6 后半）：沿用 bookplan2 §4.4 未交付项，已完成阶段可回跳；回跳使后续阶段数据失效时给确认提示（如重提取后草稿作废）。
- 底栏组件直接从 `TextbookImportDialog` 平移（进度条、阶段 label、`ai_usage.format_usage_line` 成本行、autosave 时间）。
- **入口整合**：工具栏两个 Beta action 替换为一个「课程工坊」；首次打开显示一次（仅一次）统一的 Beta 提示。项目选择沿用 `TextbookLibraryDialog` 但改为非 modal 的窗口首页（项目列表页作为 QStackedWidget 第 0 页），新建项目时语言对可选（D10）。

### 4.2 五个阶段页的来源与改造量

| 阶段页 | 来源 | 改造量 |
|---|---|---|
| ① 素材 | 教材向导 ①（选文件）+ ③（章节勾选/preset/并发）合并；②死页面删除，解析预览做成选文件后的内联摘要 | 中：两页并一页，去掉死代码（`textbook_import_dialog.py:390-392` 的 `_parse_preview` 填充）；新建项目已选文件直接自动 load，不再二次选择（D6） |
| ② 知识 | 教材向导 ④（提取日志）+ ⑤（审校）合并为上下分栏：提取进度/日志在上，`ResourceReviewTable` 在下，提取完一章即入表 | 小：现有组件重组；`ImportStepResult.recoverable`/`recovery_options` 在此首次真正渲染为错误条上的动作按钮（现有字段从未被读取，见 `controller.py:231,248,292,301`） |
| ③ 设计 | `AiGeneratorDialog` 的许愿聊天区（`ChatView` + 附件栏 + `PromptTemplateBar`）+ 普通模式 spec 表单，**左栏新增资源池摘要 + 编排参数** | 大：从 2196 行 modal 对话框中拆出可嵌入 widget（见 §4.3）；`build_prompt` 换 grounded 版 |
| ④ 审校 | AI 对话框右侧结果区（`ResultPreviewWidget` + `JsonEditor` + 试做/diff/AI 修复按钮）平移为独立页 | 中：试做按钮、diff、结构删除确认（B3）逻辑随迁；多个草稿 section 用 tab 或下拉切换 |
| ⑤ 导入 | 教材向导 ⑥（策略 + `BulkImportPreviewPanel`）+ 新 `BulkMergeResolvePanel` | 中：接入 `SectionImportService`；导入成功后显示"定位到课程树"按钮（bookplan2 §4.4 已列未做项） |

### 4.3 `AiGeneratorDialog` 拆解（最大的一块手术）

2196 行的 modal 巨石拆为：

- `src/dialogs/ai/design_controller.py`（新，纯 Python）：持有 spec、chat history、draft、worker 生命周期；信号/回调模式照抄 `TextbookImportController`。worker 状态机把 B1/B2/B6/B7/B11 一系列 bug 疤痕注释（`ai_generator_dialog.py` 内）转化为显式状态字段与测试。
- `src/dialogs/ai/design_panel.py`（新，QWidget）：聊天 + spec + 结果区的可嵌入面板，供工作台 ③④ 页使用。
- `AiGeneratorDialog` 保留为薄壳（内部嵌入 `DesignPanel`），旧入口在兼容期内继续可用；课程树右键 "AI 编辑此 Section/Unit/Lesson"、校验报告 "AI 修复" 等 edit_mode 调用点（`app.py:752`、`app.py:867`、`app.py:1047`）**继续走薄壳不动**——edit 模式不进工作台，控制改造范围。

### 4.4 主窗口改动（克制）

- `app.py`：两个 Beta action → 一个「课程工坊」action；`_on_textbook_import`/`_on_ai_generate` 在兼容期保留但指向薄壳。
- `_on_textbook_sections`（`app.py:706-750`）整体迁入 `SectionImportService` 调用点，MainWindow 只留信号接线。
- 状态栏 AI 免责声明合并为一条。

---

## 五、实施阶段

> 原则：每阶段独立可交付、可回滚；旧路径 feature flag（`Settings.workshop_enabled`，默认关）保护；全程 `pytest tool/gui/tests` 绿。

### Phase 0 — 快赢修复（约 3 天，纯后端小改，立即可发）✅ 已完成

不改架构，先消掉最刺眼的割裂点：

1. 幂等 id（§3.3）——`textbook_to_course.py` + 测试。
2. `imported_section_ids` 真实回写（§3.2 的回写部分先内联在 `_on_textbook_sections`）——D9。
3. 新建项目自动加载已选文件 + 语言对可选（D6/D10）——`textbook_library_dialog.py`。
4. 删除死页面 ②，`ImportStepResult.recovery_options` 渲染为按钮（D6）。
5. AI 普通模式注入**课程现有资源摘要**（复用 edit 模式的 `_existing_context_block` 思路，做 course 级版本）——这是 D1 的 20% 投入 80% 收益版。
6. 流式 usage 修复（`ai_generator.py:859-864`）。

**验收**：`test_textbook_e2e.py`、`test_ai_generator.py` 全绿；新增 `test_textbook_reimport_idempotent.py`。

### Phase 1 — 统一地基（约 1 周）✅ 已完成

1. `AuthoringProject` v2 + 迁移（§3.1）：模型、store、迁移测试。
2. `SectionImportService` 抽取（§3.2）：`app.py:546-674` 逻辑平移，MainWindow 变薄；`BulkMergeResolvePanel`（D7）。
3. Prompt 库合并（§3.5）。
4. 7 处 system prompt 收敛（§3.4-6）。

**验收**：现有全部测试绿；新增 `test_section_import_service.py`、`test_bulk_merge_resolve.py`、`test_project_migration.py`；行为零变化（同一批 e2e 测试不改断言）。

### Phase 2 — 工作台骨架（约 1.5 周）✅ 已完成

1. `WorkshopWindow` 外壳 + 可点击阶段导航 + 底栏平移。
2. 阶段页 ①②⑤ 按 §4.2 重组（教材向导 controller 不变，只换 view 容器）。
3. 入口整合：工具栏单按钮 + 统一 Beta 提示；旧对话框 flag 切换。
4. 「定位到课程树」按钮（导入成功后选中主窗口树节点）。

**验收**：`test_textbook_e2e.py` 改造为走工作台路径仍绿（view 层替换，controller 断言不变）；`usability_smoke.py` 更新。

### Phase 3 — Grounded 设计（约 2 周，核心价值交付）✅ 已完成（实施方式有调整，见实施记录）

1. `AiGeneratorDialog` 拆解（§4.3）：`DesignController` + `DesignPanel`，edit_mode 薄壳保留。
2. `build_prompt` grounded 模式（§3.4）：资源池注入、两态 prompt、id 重写。
3. 工作台 ③④ 页接入：资源池摘要 + 编排参数 + 聊天；草稿/聊天记录持久化到 `design` 字段（D4）。
4. 「AI 设计课程 →」按钮与知识 → 设计的级联（资源池变更后提示草稿可能过期）。

**验收**：新增 `test_grounded_generation.py`（假 worker 断言 prompt 含资源池 id、输出引用被重写）；`test_design_controller.py`（移植 B 系列回归）；e2e：导入教材 → 资源池 → AI 设计 → 审校 → 导入 全链路测试 `test_workshop_e2e.py`。

### Phase 4 — 打磨去 Beta（约 1 周）

1. 删除旧对话框代码路径与 flag（薄壳除外），清理遗留：`review_rows_from_tables`、`apply_review_edits` 死代码（`controller.py:752-765`、`497-508`）、`_MAX_CHAPTER_CHARS` 未用 import。
2. 标题/横幅去 Beta 字样；统一遥测事件命名（`workshop.*` 取代 `textbook.*`/`ai.*` 双套，保留旧事件映射 30 天）。
3. 文档：更新 `docs/authoring/textbook-import.md` → `docs/authoring/course-workshop.md`；`tool/gui/README` 修正失效引用（guiplan.md、"向导建课"按钮）；`AGENTS.md`/CLAUDE.md 如有涉及同步。
4. 标注 Dart 侧 prompt 漂移：`lib/application/ai/ai_course_service.dart` 加注释指向新的 grounded prompt 规范。

**验收**：`grep -r "（Beta）" tool/gui/src` 仅剩历史注释；全量测试 + `test_workshop_e2e.py` 绿。

**总估算：约 5 周（1 人全职）**，Phase 0 可单独提前发布。

---

### 实施记录（Phase 0–2，2026-07-16）

与原计划的偏差与现状：

- `SectionImportService` 落在 `src/application/` 而非 `src/backend/`（依赖 `QUndoStack` + undo 命令，放 backend 会倒置分层）。UI 关注点全部回调注入；`MainWindow` 持实例并经 `adapter_fn` 延迟解析 adapter。
- system prompt 实为 8 处 5 种变体，收敛为 `ai_generator.SYSTEM_*` 5 个常量；`knowledge_prompt._SYSTEM_PROMPT` 保留为模板数据默认值。
- Prompt 库合并形态：`AiPromptTemplate.kind`（默认 `course_gen`）+ extraction override 存独立 QSettings key；查找顺序 内存 register > 持久化 override > 默认；设置对话框新增「提取 Prompt」tab。
- 教材向导页面两步重组（6→5→3）：现为 素材/知识/导入 三页；STEP 枚举值始终未变，旧 project.json 兼容。
- 工作台阶段导航为 4 档（项目/素材/知识/导入）；设计/审校阶段待 Phase 3。嵌入方式：两对话框 `embedded=True` + `setWindowFlags(Qt.Widget)`。
- 工具栏「课程工坊」与两个旧 Beta 按钮并存（Phase 4 再删旧按钮）；「定位到课程树」经 `locate_requested` 信号实现。
- 测试：730 全绿（Phase 0 末为 678）。

### 实施记录（Phase 3，2026-07-16）

- **未拆解 `AiGeneratorDialog`**（§4.3 的有意调整）：2196 行巨石带 B1–B11 疤痕，拆解是最高风险项且收益有限。改为**新建** `src/dialogs/ai/design_controller.py`（纯 Python，仿 TextbookImportController 回调模式，含 stale-worker 防护）+ `src/dialogs/ai/design_panel.py`（可嵌入 QWidget，JSON 编辑器为草稿唯一真相源/B1）。旧对话框一行未动，edit_mode 与旧入口零回归风险；Phase 4 如需可再让旧对话框套壳 DesignPanel。
- Grounded prompt：`AiCourseSpec.resource_pool` + `design_brief`；`_resource_pool_block`（6000 字预算，截断注记）；grounded 模式裁掉 `_resource_schema_block`；语义为"从池选词、原 id 原样复制进顶层数组"，池外新词打 `"new"` tag 逃生——因此 `_check_resource_self_consistency` 无需改动。
- 草稿 id 确定性：生成后复用 `textbook_to_course._rewrite_ids_deterministic` 重写结构 id，草稿迭代与重导入可走合并。
- 工作台五阶段定型：项目/素材/知识/设计/导入；知识页「AI 设计课程 →」按钮（仅嵌入态可见）；进入设计阶段时自动按指纹刷新资源池并提示"草稿建议重生成"（§2.2 级联）。
- D4 落地：`project.design` 持久化 chat_history/params/draft_sections，关窗重开完整恢复；`DesignController.params` 含 `design_brief`。
- 未做（转入 Phase 4 或后续）：`explain_course` 通俗解释接入设计页（design.explanation 字段保留空）；许愿聊天附件；旧对话框套壳。
- 测试：752 全绿（新增 `test_design_controller.py`、`test_design_panel.py`、grounded prompt 用例、workshop 设计阶段用例）。

---

## 六、风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| `AiGeneratorDialog` 拆解引入 B 系列回归（worker 生命周期/流式状态） | 高 | Phase 3 先把现有 B1-B11 疤痕注释逐条转成 `test_design_controller.py` 断言再动手；拆解 = 平移代码，不改逻辑 |
| Grounded prompt 下模型仍造池外词 | 中 | 现有 `_auto_fix_resources` 兜底合成 `[待补]` stub + 审校页质量列已有红黄机制；prompt 中给"确需新词时放入 words 并打 `new` tag"的逃生口 |
| 资源池很大导致 prompt 超限 | 中 | 预算化截断（复用 `max_chapter_chars` 模式）；超预算时按章节截取并在 prompt 注明范围；UI 显示"注入 X/Y 词条" |
| 项目文件 v1→v2 迁移丢数据 | 中 | 迁移前备份原文件为 `project.v1.json.bak`；迁移幂等；`test_project_migration.py` 覆盖 |
| 非 modal 工作台与主窗口并发编辑冲突 | 中 | 工作台不直接持 `CourseAdapter` 写引用，只通过 `SectionImportService` 在导入瞬间接触；主窗口保存时若工作台有未导入草稿不受影响（草稿在项目文件里） |
| 兼容期内两套入口并存造成用户困惑 | 低 | flag 默认关，仅内部试用；Phase 4 删除旧路径前发公告/文档 |

---

## 七、验证清单（总）

- [ ] 同一教材项目重导入不产生重复 lesson（幂等 id）
- [ ] 项目库"已导入"列在真实导入后显示正确状态
- [ ] AI 设计生成的 section 中 `wordId` 100% 能在资源池或课程资源中找到（除显式 `new` tag）
- [ ] 关闭工作台后重开，草稿、聊天记录、资源池、阶段位置完整恢复
- [ ] K 章冲突导入只弹一次批量冲突面板
- [ ] 从拖入教材到导入完成，全程不离开工作台窗口、不遇第二个 Beta 警告
- [ ] `pytest tool/gui/tests` 全绿（含新 `test_workshop_e2e.py`）
- [ ] `grep -r "import.*mineru\|magic_pdf" tool/gui/` 仍无命中（AGPL 隔离不变）
