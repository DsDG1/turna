# GUI 课程编辑器开发计划

> 本计划基于 [`docs/authoring/gui-course-editor.md`](../../docs/authoring/gui-course-editor.md) 的设计约束，把它拆成可执行的里程碑、任务、数据模型映射和验收标准。
> 契约本体仍以 `course-layout.md` 为准；JSON 是唯一真理源，GUI 只是受约束表单前端。

---

## 1. 目标

为教师提供一个本地桌面 GUI，打开 `assets/courses/<lang>/` 目录后，能以表单/树形视图编辑课程 JSON。所有写操作都落到现有 JSON 文件，且保存前必须通过 `tool/course_cli.py validate` 与 `lint`。

---

## 2. 前置条件

| 条件 | 检查方式 |
|------|----------|
| Python 3.11+ | `python --version` |
| PySide6 可用 | `pip install pyside6` |
| `tool/course_cli.py` 命令可用 | `python tool/course_cli.py --help` |
| 课程目录结构符合 `course-layout.md` | 以 `assets/courses/turkish/` 为例 |
| 模板文件已补全 | 6 个模板均位于 `docs/authoring/templates/` |

---

## 3. 技术栈

采用 [`gui-course-editor.md`](../../docs/authoring/gui-course-editor.md) 推荐的方案：

- **Python 3.11+**
- **PySide6**（本地桌面窗口）
- 直接 `import course_cli` 复用现有后端函数：
  - `load_index` / `load_sections` / `load_vocab` / `load_expressions` / `load_grammar_points`
  - `save_json` / `normalize_section`
  - `cmd_validate` / `cmd_lint` / `cmd_export_csv` / `cmd_import_csv`

这样校验逻辑保持单一来源，GUI 只负责表单绑定和错误映射，不重复实现业务规则。

---

## 4. 范围边界

### 4.1 GUI 做

- 打开课程目录，三栏树：Section → Unit → Lesson
- 按 `template` 切换右侧 detail 表单
- 编辑 `index.json`、section 文件、资源文件（`vocab.json` / `expressions.json` / `grammar_points.json`）
- 保存前调用 `validate --format json` 并高亮错误节点
- 保存后调用 `lint` 显示警告
- 新建 lesson 时从 [`docs/authoring/templates/`](../../docs/authoring/templates/) 克隆模板
- 撤销/重做（MVP 后可考虑，至少支持保存前回滚）

### 4.2 GUI 不做

| 禁止 | 原因 |
|------|------|
| 写 app 的 SQLite 缓存 | SQLite 是派生缓存，非真理源（ADR 0002） |
| 把多 section 合并成一个大 JSON | 违反 L0/L1/L2 分层 |
| 自动重编号 / 改 lesson id | id 不可变，改动会孤立学习记录 |
| 引入新 `runtimeType` | 每个 `runtimeType` 必须有 Dart `Interaction` case |
| 绕过 `validate`/`lint` 直接保存 | 校验是双源契约，GUI 不另立标准 |
| 超过 scale ceiling 仍允许保存 | 上限在 `course_validator.dart` 与 `course_cli.py` 双处定义 |

---

## 5. 目录结构

```text
tool/gui/
  guiplan.md              # 本文件
  README.md               # 运行说明
  pyproject.toml          # 项目依赖
  src/
    __init__.py
    main.py               # 入口
    app.py                # 主窗口 / QApplication
    models/
      course_tree.py      # 内存中的课程树模型
      change_tracker.py   # 改动追踪 / 版本号检测
    widgets/
      course_tree.py      # Section/Unit/Lesson 树控件
      detail_panel.py     # 右侧详情面板容器
      metadata_form.py    # Section/Unit/Lesson 元数据表单
      lesson_editor.py    # Lesson 内容编辑容器（按 template 切换）
      interaction_forms.py # 12 种 Interaction 表单
      resource_editor.py   # vocab/expressions/grammar 编辑器
    backend/
      course_adapter.py    # 调用 course_cli 的封装层
      template_loader.py   # 加载 docs/authoring/templates/
    dialogs/
      new_lesson_dialog.py
      confirm_dialog.py
      validation_report.py
  tests/
    test_round_trip.py
    test_course_adapter.py
```

---

## 6. 数据模型映射

### 6.1 文件 ↔ 树节点

| 文件 | 树节点 | 可编辑字段 |
|------|--------|------------|
| `index.json` | 根节点 | `version` |
| `sections/<section>.json` | Section | `id`（只读）、`name`、`description` |
| `sections/<section>.json` | Unit | `id`（只读）、`name`、`description` |
| `sections/<section>.json` | Lesson | `id`（只读）、`name`、`description`、`type`、`template`、`prerequisiteLessonIds`、content |
| `vocab.json` | Resources → Vocab | `id`、`term`、`translation`、`pronunciation`、`audioAsset`、`tags` |
| `expressions.json` | Resources → Expressions | `id`、各字段 |
| `grammar_points.json` | Resources → Grammar | `id`、各字段 |

### 6.2 Lesson Template ↔ Content 形态

| `template` | 可用 content 字段 | 禁用字段 |
|------------|-------------------|----------|
| `intro` | `subLessons` | `stages` / `listeningPhases`（主线） |
| `practice` | `subLessons` | `stages` / `listeningPhases`（主线） |
| `review` | `subLessons`（推荐）或 `stages` | — |
| `listening` | `listeningPhases` | `subLessons` / `stages`（主线） |
| `reading` | `readingPassage` + `stages` | `subLessons` / `listeningPhases` |
| `mastery` | `stages`（且 `len == 1`） | `subLessons` / `listeningPhases` |

### 6.3 Interaction 字段清单

依据 [`lib/domain/course/interaction.dart`](../../lib/domain/course/interaction.dart) 的 12 个 variant，每个表单字段如下：

| runtimeType | 必填字段 | 可选字段 |
|-------------|----------|----------|
| `showWord` | `wordId` | `context`, `grammarPointId`, `expressionId` |
| `multipleChoice` | `prompt`, `options`, `correctIndex` | `imageAsset`, `grammarPointId` |
| `multiSelect` | `prompt`, `options`, `correctIndices` | `minSelections`, `maxSelections`, `imageAsset`, `grammarPointId` |
| `fillBlank` | `sentence`, `answer` | `hint`, `grammarPointId` |
| `translateSentence` | `source`, `expected` | `hints`, `grammarPointId` |
| `listenAndPick` | `audioAsset`, `prompt`, `options`, `correctIndex` | `grammarPointId` |
| `typeTheWord` | `audioAsset`, `prompt`, `expected` | `grammarPointId` |
| `listenOnly` | — | `audioAsset`, `transcript`, `prompt`, `grammarPointId` |
| `reorderSentence` | `scrambled`, `correct` | `grammarPointId` |
| `readingMcq` | `prompt`, `options`, `correctIndex` | `grammarPointId` |
| `readingTrueFalse` | `statement`, `answer` | `grammarPointId` |
| `readingShortAnswer` | `prompt`, `expectedAnswer` | `grammarPointId` |

**关键规则**：所有选择题用 `correctIndex`（int），不是 `correctAnswer`（string）。`readingPassage` 没有 `id` 字段。

---

## 7. 核心状态与保存流程

### 7.1 应用状态机

```text
[未打开]
    ↓ 选择课程目录
[已加载]  ← 显示树，detail 面板可编辑
    ↓ 编辑任意字段
[未保存]  ← 标题栏显示 *，启用保存按钮
    ↓ 点击保存
[校验中]  → validate --format json
    ↓ ok == true
[已保存]  → 运行 lint，显示警告
    ↓ ok == false
[回滚]    → 恢复修改前内存状态，高亮错误节点
```

### 7.2 保存时序

1. 用户点击保存
2. GUI 在内存中生成当前课程 JSON 的快照（作为回滚点）
3. GUI 调用 `course_adapter.save_course()` 写文件
4. 写完后调用 `cmd_validate`（`--format json`）
5. 如果 `ok == true`：
   - 调用 `cmd_lint`（非严格模式）
   - 在底部面板显示 lint 警告
   - 标记状态为已保存
6. 如果 `ok == false`：
   - 从快照恢复内存状态
   - 解析 `problems[].path`
   - 映射到树节点并在 detail 面板顶部显示错误 banner
   - 保持未保存状态，保存按钮仍可用

### 7.3 错误路径映射规则

`validate` 返回的 `path` 形如：

- `section:section4` → 高亮 Section 节点
- `section:section4/unit:u-1` → 高亮 Unit 节点
- `section:section4/unit:u-1/lesson:l-xxx` → 高亮 Lesson 节点（实际 CLI 不一定产出，可作为扩展）
- 空 `path` → 显示在全局错误面板

---

## 8. 关键类职责

| 类/模块 | 职责 |
|---------|------|
| `CourseAdapter` | 封装 `course_cli` 调用，加载/保存课程，运行 validate/lint，返回结构化结果 |
| `CourseTreeModel` | 维护内存中的 section/unit/lesson 树，提供增删改查和变更通知 |
| `ChangeTracker` | 检测哪些文件相对于磁盘有改动，用于版本号 bump |
| `TemplateLoader` | 加载 `docs/authoring/templates/*.json`，生成新 lesson 时做 id 替换 |
| `CourseTreeWidget` | 左侧三栏树，支持选中、展开、右键菜单 |
| `DetailPanel` | 右侧容器，根据选中节点切换子表单 |
| `MetadataForm` | Section/Unit/Lesson 元数据表单 |
| `LessonEditor` | 根据 `template` 选择具体 lesson 内容表单 |
| `InteractionForms` | 12 种题型的动态表单工厂 |
| `ResourceEditor` | vocab/expressions/grammar 表格 + CSV 导入导出 |
| `ValidationReport` | 显示 validate/lint 结果，支持双击跳转到节点 |

---

## 9. 里程碑与任务

### 里程碑 1：MVP —— 只读树 + section 元数据编辑  ✅ 已完成

**目标**：能打开课程目录，看到树，编辑 section/unit/lesson 的元数据，保存时校验。

| # | 任务 | 输入 | 输出 | 验收标准 | 状态 |
|---|------|------|------|----------|------|
| 1.1 | 项目骨架 | 空 `tool/gui/` | `pyproject.toml`、`src/main.py` | 能 `python -m src.main` 启动空窗口 | ✅ |
| 1.2 | CourseAdapter 封装 | `course_cli.py` | `src/backend/course_adapter.py` | 能加载 Turkish 课程目录，返回 index + sections | ✅ |
| 1.3 | 三栏树控件 | 加载后的课程数据 | `src/widgets/course_tree.py` | 显示 Section/Unit/Lesson 三级树 | ✅ |
| 1.4 | 元数据表单 | 选中节点 | `src/widgets/metadata_form.py` | id 只读，name/description 可编辑，prerequisiteLessonIds 多选下拉 | ✅（多选下拉待后续） |
| 1.5 | 保存与校验 | 修改后的内存数据 | 保存后的 JSON + 校验报告 | 保存成功时 validate 通过；失败时回滚并高亮 | ✅ |
| 1.6 | MVP 验证 | Turkish 课程目录 | 测试记录 | 能打开、改一个 section name、保存、validate 通过 | ✅ 后端测试通过；GUI 烟测需本机完成 |

### 里程碑 2：Lesson 内容编辑  ✅ 已完成

**目标**：按 `template` 切换 detail 面板，编辑 lesson 内容。

| # | 任务 | 输入 | 输出 | 验收标准 | 状态 |
|---|------|------|------|----------|------|
| 2.1 | 模板选择表单 | Lesson 节点 | 模板切换 UI | 切换 template 时自动清空/保留可用 content | ✅ 带确认对话框 |
| 2.2 | intro/practice/review 表单 | subLessons 数据 | 三级编辑器 | 可增删改 subLesson → stage → item | ✅ `SubLessonTreeEditor` |
| 2.3 | listening 表单 | listeningPhases 数据 | 三阶段编辑器 | 支持 wordPairing/dialogue/summary | ✅ `ListeningPhasesEditor` |
| 2.4 | reading 表单 | readingPassage + stages | 阅读编辑器 | readingPassage 无 id 字段 | ✅ `ReadingEditor` |
| 2.5 | mastery 表单 | stages 数据 | 单 stage 编辑器 | 阻止保存时出现多个 stage | ✅ `MasteryEditor` 强制单 stage |
| 2.6 | 题型表单 | Interaction 数据 | 12 种动态表单 | 所有字段与 `interaction.dart` 一致 | ✅ `InteractionForm` 工厂 |
| 2.7 | 引用下拉框 | 资源文件 | 自动完成/下拉 | 引用悬空时 validate 报错 | ✅ QComboBox 从已加载资源选 |
| 2.8 | 新建 lesson | 模板文件 | 新 lesson 节点 | 自动生成唯一 id，clone 模板并替换 id | ✅ `NewLessonDialog` + uuid |
| 2.9 | 删除节点 | 选中节点 | 确认对话框 | 删除 lesson/unit 带确认，保存后 validate 通过 | ✅ 右键菜单 + 确认对话框 |

### 里程碑 3：Resources 批量编辑  ✅ 已完成（2026-07-13，与 §9A 实际落地一致）

**目标**：vocab / expressions / grammar_points 用 CSV 进出。

| # | 任务 | 输入 | 输出 | 验收标准 | 状态 |
|---|------|------|------|----------|------|
| 3.1 | CSV 导出 | 选中资源表 | 临时 CSV | 调用 `export-csv` 成功 | ✅ `ResourceEditorDialog.export_csv` |
| 3.2 | 表格编辑 | CSV 或内存数据 | 编辑界面 | 可增删改行 | ✅ 内存直改 + CSV 运输 |
| 3.3 | CSV 导入 | 编辑后的 CSV | 写回 JSON | `import-csv --dry-run` 预检通过后再落盘 | ✅ `CourseAdapter.import_csv` |
| 3.4 | 引用同步 | vocab 改动 | 刷新后的下拉框 | lesson 表单的 wordId 下拉框反映最新资源 | 🟡 关闭对话框后整节点重载；实时联动见方向 A3（待办） |

> 说明：§9A 原先只承认 M1/M2，实际 M3（`src/widgets/resource_editor.py`）、M4（`src/widgets/publish_dialog.py`）代码均已落地。本表已与 §9A 对齐。

### 里程碑 4：发布工作流  ✅ 已完成（2026-07-13）

**目标**：辅助教师完成 export checklist。

| # | 任务 | 输入 | 输出 | 验收标准 | 状态 |
|---|------|------|------|----------|------|
| 4.1 | 版本 bump | 改动文件集合 | 更新后的 version | 仅当 index/expressions 改动时 bump 对应 version | ✅ `version_bump_plan` |
| 4.2 | 听力资源核对 | 课程目录 | audio-manifest CSV | 调用 `audio-manifest` 成功 | ✅ `audio_manifest_rows` |
| 4.3 | 发布 diff | 当前目录与 git HEAD | diff 报告 | 调用 `diff` 成功 | ✅ `release_diff` |
| 4.4 | 清单报告 | 发布数据 | 可导出文本 | 包含改动文件、version 变更、id 集变更 | ✅ `release_report` + `PublishDialog` |

### 里程碑 5：收尾与测试  🟡 部分进行

| # | 任务 | 输入 | 输出 | 验收标准 | 状态 |
|---|------|------|------|----------|------|
| 5.1 | Round-trip 测试 | 固定 fixture | `test/tool/gui_round_trip_test.py` | GUI 写出的 section 与手写等价 | 🟡 已有 `test_course_adapter.py` + `test_lesson_round_trip.py` 20 测试，待补 GUI→CLI 完整 fixture |
| 5.2 | 打包 | 源码 | 单文件 exe | `pyinstaller` 生成可执行文件 | ⬜ |
| 5.3 | 文档 | 实现细节 | `tool/gui/README.md` | 包含安装、运行、打包说明 | ⬜ |

---

## 9A. 实施进度（同步于 2026-07-13）

> 本节记录实际落地的文件、测试基线、已验证范围与待办。与 §9 里程碑表格
> 互补——表格给任务定义，本节给执行现状。

### 已完成里程碑

| 里程碑 | 完成日期 | 后端测试 | GUI 烟测 |
|--------|----------|----------|----------|
| M1 MVP 只读树 + 元数据编辑 | 2026-07-13 | ✅ 3/3 | 需本机手动（沙箱无法装 PySide6） |
| M2 Lesson 内容编辑 | 2026-07-13 | ✅ 17/17 | 需本机手动 |

### 当前测试基线

`python -m unittest tool.gui.tests.test_course_adapter tool.gui.tests.test_lesson_content tool.gui.tests.test_lesson_round_trip` → **20 passed**

| 测试文件 | 用例数 | 覆盖 |
|----------|--------|------|
| `tests/test_course_adapter.py` | 3 | 加载 Turkish、保存 section rename 后 validate 通过、校验失败回滚 |
| `tests/test_lesson_content.py` | 11 | 12 题型 schema、normalize、模板切换、新建 lesson 唯一 id、添加 subLesson/stage/item/listeningPhase |
| `tests/test_lesson_round_trip.py` | 6 | 6 模板新建 lesson + 题目 + 保存 validate 通过、删除 lesson、schema 字段 round-trip |

### 已落地的文件清单

**后端（不依赖 PySide6，可独立测试）**

| 文件 | 作用 |
|------|------|
| `src/backend/course_adapter.py` | 复用 `course_cli` 加载/保存/validate/lint；新建/删除 lesson/unit；资源选项 |
| `src/backend/lesson_content.py` | 12 题型 schema、template↔content 映射（§6.2）、id 生成、教学语言标签（§15.2 基础） |

**Widgets（PySide6）**

| 文件 | 作用 |
|------|------|
| `src/widgets/course_tree.py` | 三级树 + 右键菜单新建/删除 Lesson/Unit |
| `src/widgets/detail_panel.py` | 右侧容器，lesson 节点显示元数据 + LessonEditor |
| `src/widgets/metadata_form.py` | id 只读 + name/description 可编辑 |
| `src/widgets/interaction_forms.py` | 12 题型动态表单 + 引用下拉框 + 字符串列表编辑器 |
| `src/widgets/lesson_editor.py` | 按课型切换：SubLessonTree / ListeningPhases / Reading / Mastery + 模板切换确认 |

**对话框与入口**

| 文件 | 作用 |
|------|------|
| `src/dialogs/new_lesson_dialog.py` | 新建 lesson（选课型 + 命名） |
| `src/main.py` | 入口，自动把 `tool/gui` 加入 sys.path |
| `src/app.py` | 主窗口，保存后刷新树 + 校验失败弹窗 |

**包标识**

| 文件 | 作用 |
|------|------|
| `tool/__init__.py` + `tool/gui/__init__.py` | 让 `tool.gui` 成为正规包，支持 `python -m tool.gui.src.main` |

### 启动方式

```bash
pip install pyside6
# 在仓库根目录运行（推荐）
python -m tool.gui.src.main
# 或在 tool/gui 目录运行
python -m src.main
```

> `src/main.py` 会自动把 `tool/gui` 加入 `sys.path`，因此 `from src.xxx`
> 的导入在两种运行方式下都成立。

### 已验证的设计约束

- ✅ JSON 唯一真理源：GUI 只持内存工作副本，保存写 JSON 文件
- ✅ 校验单一来源：保存走 `course_cli validate` + `lint` subprocess
- ✅ id 不可变：元数据表单 id 字段只读
- ✅ id 全局唯一：新建 lesson 用 `uuid.uuid4().hex[:8]`
- ✅ 引用完整性：wordId/expressionId/grammarPointId 用 QComboBox 从已加载资源选
- ✅ template↔content 一致：切换模板按 §6.2 清空不适用 content
- ✅ mastery 单 stage：MasteryEditor 强制 `len(stages)==1`
- ✅ 保存失败回滚：从上次已知良好快照恢复内存并重写文件
- ✅ 不引入新 runtimeType：12 题型与 `interaction.dart` 完全对齐

### 待办（按 guiplan 顺序）

- [x] **A1 增量刷新树**（2026-07-14）：`CourseTreeWidget.refresh()` 改为 `refresh_incremental()`，保留展开/选中/滚动状态；选中节点被删时回退到父 unit/section。测试 `tests/test_course_tree.py`。
- [x] **A2 校验报告面板**（2026-07-14）：新增 `src/widgets/validation_report.py`，复用 `teacher/error_mapper` 的纯函数；`app.py _on_save` 校验失败改为非模态列表，双击条目跳转高亮对应节点。
- [x] **A4 文档归一**（2026-07-14）：§9 的 M3/M4 标注与 §9A 对齐（实际已落地）。
- [x] **A3 资源↔课程树实时联动**（2026-07-14）：`CourseAdapter` 加 `resources_changed` 监听机制；资源编辑器/词库表改动时通知；`DetailPanel` 订阅并原地调用当前 widget 的 `refresh_references()` 重建引用下拉框，不再整节点重载（保留老师已填字段）。
- [x] **B1 实时预览/试做**（2026-07-14）：新增 `src/teacher/preview_window.py`（`LessonPreviewDialog`），按模板遍历 subLessons/stages/listeningPhases 渲染可做题卡片，提交即判对错；`LinearFlowWidget` 与 `TeacherTemplateWidget` 头部接入「🔍 预览本课」按钮。改题后重新打开即刷新。
- [x] **B3 题型卡片核对**（2026-07-14）：`typeTheWord`/`listenOnly`/`reorderSentence` 在 `question_cards.py` 均已可编辑，非占位文本。
- [x] **M5.1 补全**（2026-07-14）：`test/tool/gui_round_trip_test.py` 扩展到 12 用例（原 5 + 新 7：6 模板建课 round-trip / CSV 往返 / 增删 unit / lint 无 ERROR / 二次保存幂等 / section 删除清孤文件 / 校验失败回滚保护磁盘文件），全量 CLI validate/lint subprocess 兜底，沙箱可跑。
- [x] **§15.12 / T.9 零代码可用性测试**（2026-07-14）：新增 `tool/gui/tests/usability_smoke.py` 自动化回归（新建课程→向导建课→保存→预览可答→发布清单，输出 ✅/❌ 报告，无 PySide6）；人工清单 `docs/authoring/teacher-usability-checklist.md` 7 步路径 + 记录表 + 通过判据。
- [x] **B2 撤销/重做**（2026-07-14）：新增 `src/application/commands.py`（AddItem/DeleteItem/MoveItem/UpdateField/MoveSubLesson/MoveStage）；`app.py` 持有 `QUndoStack`，Ctrl+Z/Y 接线，保存成功标记 clean（标题栏 `*` 跟踪脏态），加载/新建课程时 clear；`LinearFlowWidget` 题目增删移/改类型经 undo 栈。
- [x] **C2 UI/VM 解耦**（2026-07-14）：抽取 `src/backend/teacher_view_model.py`（prompt/correctness/answer/label 解析纯函数，无 PySide6）；`tests/test_teacher_view_model.py` 30 用例可在沙箱跑，补齐 UI 逻辑测试盲区。
- [x] **C1 懒加载基础**（2026-07-14）：`CourseAdapter.lesson_body()` + `reload_section()` 为未来懒加载预留接口（当前预加载不变，避免破坏 139 测试）。
- [x] **C3 AI 自修复**（2026-07-14）：`ai_generator.request_course_with_retry()` 校验失败带错误回灌模型自动重试一轮。
- [x] **C4 i18n 基础**（2026-07-14）：`labels.py` 加 `locale` 维度（zh 默认 + en 镜像），`field_label/layer_label/level_label` 接受可选 locale，向后兼容。

### 已知限制

- PySide6 在 TRAE 沙箱里无法安装（`WinError 5 拒绝访问 AppData\Roaming\Python`），
  因此 GUI 启动烟测需在本机终端完成。所有后端逻辑已通过 20 个单元测试覆盖。
- prerequisiteLessonIds 当前是只读逗号分隔展示，M1.4 的多选下拉待后续补。

---

## 10. 测试策略

### 10.1 单元测试

| 测试目标 | 测试内容 |
|----------|----------|
| `CourseAdapter` | 加载/保存课程、validate 返回结构正确 |
| `TemplateLoader` | 模板 clone 后 id 全局唯一，字段完整 |
| `ChangeTracker` | 能正确检测改动文件 |
| `InteractionForms` | 每种题型表单生成的 JSON 与模型一致 |

### 10.2 集成测试

| 测试目标 | 测试内容 |
|----------|----------|
| Round-trip | GUI 写出的 section 经 `course_cli validate` 与手写等价 |
| 保存失败回滚 | 构造非法数据，保存失败后内存状态恢复，错误高亮正确 |
| 模板新建 | 用每个模板新建 lesson，保存后 validate + lint 通过 |
| CSV 导入 | vocab CSV 修改后导入，lesson 引用下拉框同步 |

### 10.3 手动测试清单

- [ ] 打开 `assets/courses/turkish/`
- [ ] 修改一个 section name 并保存
- [ ] 新建 intro / practice / review / listening / reading / mastery 各一个 lesson
- [ ] 给每个 lesson 添加至少一道题，保存后 validate 通过
- [ ] 删除一个 lesson，保存后 validate 通过
- [ ] 导出 vocab CSV，修改一行的 term，导入后保存
- [ ] 点击「发布」按钮，检查 version 是否按需 bump

---

## 11. 验收标准

1. GUI 写出的课程目录 100% 通过 `python tool/course_cli.py validate` + `lint`。
2. 新增 GUI→CLI round-trip 测试：固定 fixture JSON 经 GUI 写出后再经 CLI 校验，结果一致。
3. 不引入任何新 `runtimeType` 或契约字段。
4. 6 个 lesson 模板都能被 GUI 新建流程正确 clone 并保存。
5. 保存失败时回滚，并高亮具体错误节点。
6. 所有代码改动不破坏现有 `flutter test` 和 `test/tool/course_cli_validate_test.py`。

---

## 12. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| CLI 与 GUI 同进程 import 出现路径/依赖问题 | 启动失败 | 早期用 `subprocess` 调用 `course_cli` 兜底，稳定后再切同进程 import |
| PySide6 表格编辑体验差 | 教师不愿用 | 保留 CSV 导出/导入路径，教师可在外部编辑 |
| 大课程树（~9000 lessons）加载慢 | 卡顿 | 仅加载 L1 元数据，L2 body 延迟加载 |
| 模板与模型字段再次漂移 | 模板失效 | 每个模板都经过 `validate` + `lint` 测试守护 |
| 多教师同时编辑同一文件 | 覆盖冲突 | 文档声明 GUI 为本地单用户工具，不提供并发锁 |
| 保存失败但文件已部分写入 | 数据损坏 | 先写临时文件，validate 通过后再重命名覆盖 |

---

## 13. 模板资产

GUI 新建 lesson 时应复用的模板：

- [`docs/authoring/templates/lesson-intro.json`](../../docs/authoring/templates/lesson-intro.json)
- [`docs/authoring/templates/lesson-practice.json`](../../docs/authoring/templates/lesson-practice.json)
- [`docs/authoring/templates/lesson-mastery.json`](../../docs/authoring/templates/lesson-mastery.json)
- [`docs/authoring/templates/lesson-listening.json`](../../docs/authoring/templates/lesson-listening.json)
- [`docs/authoring/templates/lesson-reading.json`](../../docs/authoring/templates/lesson-reading.json)
- [`docs/authoring/templates/lesson-review.json`](../../docs/authoring/templates/lesson-review.json)

---

## 14. 下一步

从**里程碑 1**开始实施：先搭 `tool/gui/` 骨架，实现只读课程树和 section 元数据编辑，验证 PySide6 与 `course_cli` 的集成可行后再进入 lesson 内容编辑。

建议首个 commit 范围：
- `tool/gui/pyproject.toml`
- `tool/gui/src/main.py`
- `tool/gui/src/backend/course_adapter.py`
- `tool/gui/src/widgets/course_tree.py`
- 一个能打开 Turkish 课程目录并显示树的 MVP 版本

---

## 15. 教师视图（Teacher Mode）：面向零代码老师

> 里程碑 1–5 定义的是**专家视图（Expert Mode）**，受众是懂 `course-layout.md`
> 契约的作者。本节追加一层**教师视图**，让真正不会写代码的老师也能独立产
> 出课程。两视图共享同一套 `CourseAdapter` / CLI 后端，JSON 仍是唯一真理源，
> 校验单一来源不变。专家视图与教师视图只是 widgets 层的差异。

### 15.1 设计哲学跃迁

| 维度 | 专家视图（原计划） | 教师视图（本节） |
|------|-------------------|------------------|
| 抽象方向 | 让非法结构构造不出来 | 让老师根本看不到技术概念 |
| 字段语言 | 工程语言（`runtimeType` / `correctIndex`） | 教学语言（「选择题」/「正确答案」） |
| 嵌套深度 | Section→Unit→Lesson→subLesson→stage→item（6 层） | 课→环节→题目（3 层） |
| 新建路径 | clone 空模板填字段 | 向导式：选课型 + 选词 → 自动生成 |
| 引用展示 | 下拉框显示 id（`w-merhaba`） | 下拉框显示词面+释义，id 永不暴露 |
| 错误信息 | `path: section:section4/unit:u-1` | 「第 4 单元 第 1 课」+ 跳转高亮 |
| 发布流程 | 手动 bump version / validate / lint / diff | 一键「发布」按钮，自动处理 |

### 15.2 字段名翻译表

id 永远不暴露给老师。下拉框里看到的永远是 `Merhaba — Hello`，背后映射到 `w-merhaba`。

| 工程语言（专家视图） | 教学语言（教师视图） |
|----------------------|----------------------|
| `template: intro` | 「认识新词」课型 |
| `template: practice` | 「巩固练习」课型 |
| `template: review` | 「复习」课型 |
| `template: listening` | 「听力训练」课型 |
| `template: reading` | 「阅读理解」课型 |
| `template: mastery` | 「综合测验」课型 |
| `template: legacy` | 「基础题」（仅只读展示） |
| `runtimeType: showWord` | 「展示生词」 |
| `runtimeType: multipleChoice` | 「选择题」 |
| `runtimeType: multiSelect` | 「多选题」 |
| `runtimeType: fillBlank` | 「填空题」 |
| `runtimeType: translateSentence` | 「翻译题」 |
| `runtimeType: listenAndPick` | 「听音选词」 |
| `runtimeType: typeTheWord` | 「听写题」 |
| `runtimeType: listenOnly` | 「只听不答」 |
| `runtimeType: reorderSentence` | 「排序句子」 |
| `runtimeType: readingMcq` | 「阅读选择」 |
| `runtimeType: readingTrueFalse` | 「阅读判断」 |
| `runtimeType: readingShortAnswer` | 「阅读简答」 |
| `subLessons` | 「教学环节」 |
| `stages` | 「教学步骤」 |
| `items` | 「题目」 |
| `correctIndex` | 隐去，改「点选项前圆圈设为正确」 |
| `wordId` / `expressionId` / `grammarPointId` | 显示对应词面/表达/语法名，不显 id |

### 15.3 课型向导（替代空模板 clone）

新建 lesson 不再 clone 空模板，而是走向导：

```
1. 你想创建什么课？
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ 认识新词 │ │ 巩固练习 │ │ 复习     │
   └──────────┘ └──────────┘ └──────────┘
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ 听力训练 │ │ 阅读理解 │ │ 综合测验 │
   └──────────┘ └──────────┘ └──────────┘

2. 你今天要教哪些词？
   [ 从词库选: ☑ Merhaba  ☑ Nasılsın  ☑ İyiyim ]
   [ + 添加新词: 词汇 ___ 翻译 ___ 发音 ___ ]

3. ✓ 已自动生成：
   3 个教学环节，每个环节含「展示生词→翻译→填空」3 道题
   [ 预览 ]  [ 逐题调整 ]
```

老师只回答两个教学问题「教什么词」「用什么课型」，GUI 自动生成符合契约
的完整 lesson 结构，再让老师逐题微调。

### 15.4 线性题目流（折叠 6 层嵌套为 3 层）

```
📚 Merhaba（认识新词课）
├── 环节1: 认识 Merhaba
│   ├── [展示生词] Merhaba — Hello!
│   ├── [翻译] Hello! → Merhaba!
│   └── [填空] _____, nasılsın? → Merhaba
├── 环节2: 认识 Nasılsın
│   └── ...
└── [+ 添加环节]
```

- 左侧只剩「课 → 环节 → 题目」三层。
- Section/Unit 退到顶部面包屑（`Section 1 › Greetings › Merhaba`），不当主树。
- 「环节」对老师就是「这节课的几分钟」，对应 subLesson+stage 的折叠表达。
- 点题目直接右侧编辑，不跳层。

### 15.5 题型卡片（所见即所得）

选择题示例（`correctIndex` 概念隐藏）：

```
┌────────────────────────────────┐
│ 选择题                          │
│ 题目：What does "Merhaba" mean?│
│  ○ Hello     ← 点圆圈设为正确  │
│  ● Goodbye                      │
│  ○ Thank you                    │
│  ○ Yes                          │
│  + 添加选项    🗑 删除选项      │
└────────────────────────────────┘
```

- 选正确答案 = 点选项前圆圈，GUI 自动同步 `correctIndex`。
- 选项可拖拽排序，index 由 GUI 维护。
- 每种题型一张卡片，标题用教学语言。

### 15.6 词库内置表格编辑（CSV 降级为高级功能）

```
词库（共 42 个词）    [+ 新增词]  [🔍 搜索]
┌──────────┬──────────┬──────────┬────────┐
│ 词       │ 翻译     │ 发音     │ 标签   │
├──────────┼──────────┼──────────┼────────┤
│ Merhaba  │ Hello    │ mer-ha-ba│ 问候   │
│ Nasılsın │ How are u│ na-sıl-sın│问候   │
└──────────┴──────────┴──────────┴────────┘
```

- 直接在表格改，回车自动加新行。
- 「标签」多选 chip，选项来自 `ALLOWED_TAGS` 白名单（复用既有护栏）。
- CSV 导入导出保留为「高级功能」，藏在菜单里，不是主路径。

### 15.7 实时预览 + 一键试做

- 右下角「预览本课」按钮 → 打开与真实 app 一致的演示界面 → 老师可实际做题。
- 改题点保存，预览自动刷新。
- 把「我写的对不对」从「读懂 JSON」变成「自己做一遍」，零代码老师可自我验证。

### 15.8 人话报错（错误信息映射）

| 当前 CLI 输出 | 教师视图展示 |
|---------------|-------------|
| `path: section:section4/unit:u-1` | 「第 4 单元 第 1 课」+ 点击跳转高亮 |
| `Duplicate id: w-merhaba` | 「词库里有重复的词『Merhaba』，已在第 12 行」 |
| `Dangling wordId: w-xxx` | 「这道题引用了不存在的词，请从词库重新选择」 |
| `listening lesson missing audioAsset` | 「听力课的这道题还没有音频文件」 |
| 空 path | 显示在全局错误面板，不跳节点 |

点击错误条目直接跳转到对应题目并高亮，老师无需理解 path 结构。

### 15.9 引导式发布（隐藏 version 概念）

```
┌──────────────────────────────┐
│ 准备发布                      │
│ 本次改动：                    │
│  • 新增 3 节课（Section 1）   │
│  • 修改 5 个词（词库）        │
│  • 1 个音频文件未上传 ⚠️      │
│  [ 上传音频 ]  [ 仍然发布 ]   │
│ ✓ 自动版本号 3 → 4           │
│ ✓ 校验全部通过                │
└──────────────────────────────┘
```

- version bump 自动检测改动文件并执行，老师看不到 `index.json` `version` 字段。
- `audio-manifest` 自动跑，缺音频直接列出。
- 老师只看「改了什么」「缺什么」「点发布」。
- `validate` + `lint` 在后台跑，失败时不让点发布并展示人话错误。

### 15.10 分层架构（在 guiplan 第 5 节目录结构之上叠加）

```
┌─────────────────────────────────┐
│  教师视图（Teacher Mode）       │  ← 本节新增，零代码老师用
│  - 教学语言字段名               │
│  - 课型向导                     │
│  - 线性题目流                   │
│  - 题型卡片                     │
│  - 实时预览                     │
│  - 人话报错                     │
│  - 一键发布                     │
├─────────────────────────────────┤
│  专家视图（Expert Mode）        │  ← guiplan 里程碑 1–5
│  - 工程字段名                   │
│  - 三栏树 + detail 表单         │
│  - CSV 导入导出                 │
│  - version/diff 等高级流程      │
├─────────────────────────────────┤
│  CLI 后端（course_cli）         │  ← 不变，单一真理源
│  validate / lint / load_* /     │
│  save_json / normalize_section  │
└─────────────────────────────────┘
```

两视图共享 `CourseAdapter`，差别只在 widgets 层。教师视图的「向导生成」
产出的 JSON 与专家视图手填的 JSON 等价，均须经 `validate` 兜底。

### 15.11 教师视图额外目录结构（叠加到第 5 节）

```text
tool/gui/src/
  teacher/                       # 教师视图专用 widgets
    lesson_wizard.py              # 课型向导（选课型+选词→生成）
    linear_flow.py                # 线性题目流（3 层折叠视图）
    question_cards.py             # 12 种题型卡片（所见即所得）
    vocab_table.py                # 词库内置表格编辑
    preview_window.py             # 实时预览/试做窗口
    publish_dialog.py             # 引导式发布对话框
    error_mapper.py               # CLI path → 人话 + 跳转
  i18n/
    labels.py                     # 工程语言↔教学语言映射表（15.2）
```

### 15.12 教师视图里程碑（叠加到里程碑 1–5 之后）

> 建议在里程碑 1（MVP）的 `CourseAdapter` 可用后，立即起一个教师视图原型窄路径
> 验证，再决定是否在里程碑 2 之前全面铺开。

| # | 任务 | 输入 | 输出 | 验收标准 |
|---|------|------|------|----------|
| T.1 | 字段名映射表 | `interaction.dart` 的 12 variant | `src/i18n/labels.py` | 12 题型 + 6 课型 + 嵌套层名全部有教学语言映射 |
| T.2 | 课型向导原型 | intro 课型 + 选词 | `src/teacher/lesson_wizard.py` | 选 3 个词自动生成「展示→翻译→填空」3 题，保存后 validate 通过 |
| T.3 | 线性题目流 | 生成的 lesson | `src/teacher/linear_flow.py` | 3 层展示，点题目右侧编辑，不跳层 |
| T.4 | 选择题卡片 | `multipleChoice` 数据 | `src/teacher/question_cards.py` | 点圆圈设正确答案，拖拽排序，`correctIndex` 自动同步 |
| T.5 | 词库表格 | vocab.json | `src/teacher/vocab_table.py` | 表格内增删改行，标签多选 chip 来自白名单 |
| T.6 | 实时预览 | 任意 lesson | `src/teacher/preview_window.py` | 打开演示界面，可实际做题，保存后自动刷新 |
| T.7 | 人话报错 | validate `problems[]` | `src/teacher/error_mapper.py` | path→「第 N 单元 第 M 课」，点击跳转高亮 |
| T.8 | 一键发布 | 改动检测 | `src/teacher/publish_dialog.py` | 自动 bump version，缺音频提示，validate 失败禁用发布 |
| T.9 | 零代码老师可用性测试 | 1 位不懂代码的老师 | 测试记录 | 老师能独立产出 1 节合格 intro 课，全程不接触 id/path/version 概念 |

### 15.13 与硬约束的对齐（不越权）

教师视图必须遵守 guiplan 第 4 节与 `gui-course-editor.md` 的全部边界：

- JSON 唯一真理源，教师视图不另立数据流。
- 保存仍走 `validate` + `lint`，`ok==false` 时禁用保存/发布。
- 不引入新 `runtimeType` / 新契约字段；教学语言只是展示层映射。
- id 不可变、id 全局唯一、scale ceiling 等护栏复用 CLI，教师视图不重复实现。
- 向导生成的 lesson 结构必须落在 §6.2 的 template↔content 映射允许的形态内。

### 15.14 最小验证步骤

不必等里程碑 2–5 完成。建议在里程碑 1 的 `CourseAdapter` 之上直接起原型：

1. 只做「认识新词」（intro）一种课型。
2. 实现「选词 → 自动生成展示+翻译+填空 3 题 → 预览」这一条窄路径。
3. 找一位不懂代码的老师试用，看能否独立产出一节合格的 intro 课。
4. 合格 → 推广到其他 5 种课型；不合格 → 迭代抽象层后再试。
5. 原型复用 `course_cli validate` 做兜底，不影响后端契约与现有测试。

### 15.15 风险与缓解（补充第 12 节）

| 风险 | 影响 | 缓解 |
|------|------|------|
| 教学语言映射与契约字段再次漂移 | 教师视图标签失效 | `labels.py` 由 `interaction.dart` variant 列表生成测试守护 |
| 向导生成的结构偏离 §6.2 允许形态 | validate 失败 | 向导模板与 `course_cli validate` 一起进 round-trip 测试 |
| 教师视图隐藏了太多细节，专家边界场景无处可改 | 进退两难 | 保留专家视图入口（设置里切换），教师视图搞不定的可切回专家 |
| 预览窗口与真实 app 渲染不一致 | 老师误判 | 预览复用 app 端 renderer 逻辑或固化 golden 截图比对 |
| 一键发布自动 bump 错误版本号 | 用户不触发重种子 | 发布前显示「本次 version: 3 → 4」并要求老师确认，保留撤销 |
