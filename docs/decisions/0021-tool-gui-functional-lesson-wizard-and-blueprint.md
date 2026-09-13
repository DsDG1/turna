# ADR 0021: tool-gui 功能课向导 + 可视化蓝图 + 批量/快捷键 + 课程总览

- **Status**: Accepted
- **Date**: 2026-07-17
- **Scope**: `tool/gui/`（Python/PySide6 课程编辑器），不改 Flutter 端

## Context

主课程编辑器（`MainWindow`：课程树 + `DetailPanel` + `LessonEditor`）此前对功能课（listening / reading / mastery）的设置是自由式的：`NewLessonDialog` 仅选名称+课型即从 `docs/authoring/templates/lesson-*.json` 克隆骨架，内容编辑分派到 `ListeningPhasesEditor` / `ReadingEditor` / `MasteryEditor` 的三栏 splitter。用户难以"直观地看到设置过程"，且缺少复制、批量、快捷键、整体总览等编辑器常用能力。

workshop2 的目标（见 `tool/gui/workshop2.md`）：
1. 功能课以**分步向导**创建，完成后进入**可视化蓝图**就地编辑。
2. **功能课模板库**（开箱即用预设）。
3. **课程结构总览**。
4. **批量操作**。
5. **复制课时 + 键盘快捷键**。

## Decision

### P1 预设库 + 复制 + 快捷键
- 新增 `backend/lesson_presets.py`：`FUNCTIONAL_PRESETS` 注册表（听力三阶段 / 阅读三类题 / 综合测验混合 / 认识新词三步 / 巩固练习混合）+ `build_preset_lesson(id, name)` + `apply_preset_to_lesson(lesson, id)`。纯 Python、无 PySide6，可单测。
- `backend/lesson_content.py` 新增 `clone_lesson_with_fresh_ids(lesson, name)`：深拷贝并重生所有结构 id（lesson / subLessons / stages / items / listeningPhases），保留引用型 id（wordId / expressionId / grammarPointId / linkedWordIds / linkedExpressionIds / prerequisiteLessonIds）。
- `CourseAdapter.duplicate_lesson(lesson_id)`：同 unit 末尾追加克隆副本。
- `application/commands.py` 新增 `DuplicateLessonCommand`、`BulkDeleteLessonsCommand`、`BulkDuplicateLessonsCommand`、`BulkMoveLessonsCommand`、`BulkApplyPresetCommand`。批量删除/移动的 redo 先一次性快照（捕获原始 index）再删除，undo 按 (unit_id, index) 升序回插以恢复原位。
- `CourseTreeWidget` 开启 `ExtendedSelection`，新增 `keyPressEvent`：`Ctrl+D` 复制、`Delete` 删除、`F2` 重命名（发 `rename_requested` 信号，`MainWindow` 接到 `MetadataForm.focus_name()`）、`Ctrl+↑/↓` 同级移动。树 tooltip 列出快捷键。

### P3 可视化蓝图
- 新增 `widgets/lesson_blueprint.py`：`LessonBlueprint(adapter, lesson, undo_stack, read_only)` 卡片流总览：
  - listening：横向阶段卡片（wordPairing -> dialogue -> summary）+ `->` 箭头。
  - reading：篇章卡片 + 理解题卡片。
  - mastery：单 stage 题目卡片流。
  - intro/practice/review/legacy：subLesson 分栏（kanban）。
  - 题目就地编辑复用 `QuestionCard`，结构增删走命令（`AddItemCommand` 等，同 `LinearFlowWidget` 模式）；`read_only=True` 渲染题目摘要（向导预览用）。
- `DetailPanel` 对 lesson 加「蓝图 / 高级编辑」切换，功能课型默认蓝图，非功能课型默认 `LessonEditor`；两视图读同一 lesson dict 保持同步。

### P2 功能课向导
- 新增 `dialogs/functional_lesson_wizard.py`：`FunctionalLessonWizard(QDialog)` 三步 `QStackedWidget`：① 选类型(listening/reading/mastery)+名称+预设(或空白骨架) ② 轻配置（听力阶段名/音频/转录；阅读篇章；测验题型勾选）③ 只读蓝图预览。完成返回 lesson dict，由 `CourseTreeWidget._open_functional_wizard` 经 `AppendLessonCommand` 插入并 `select_lesson`。
- `NewLessonDialog` 加「向导创建（功能课）」按钮（仅功能课型可用）；单元右键菜单加「功能课向导…」。

### P4 课程总览
- 新增 `widgets/course_overview.py`：`CourseOverviewWindow`（非模态，QSettings 几何）按 Section -> Unit -> Lesson 芯片（左侧 4px 课型色条 + 名称 + 课型 label），顶部统计行（计数 + 课型分布）。点芯片发 `lesson_selected` -> `MainWindow` 调 `tree.select_lesson` 并 raise。`_on_tree_changed` 可见时 `refresh()`。

### P5 批量操作
- 课程树多选后右键菜单出现：批量复制 / 批量移动到…（`QInputDialog` 选目标 unit）/ 批量套用预设…（选预设 + 确认，`BulkApplyPresetCommand`）/ 批量删除。复用 P1 的 `Bulk*` 命令与键盘路径。

## Consequences
- 编辑器对功能课的设置过程首次"可见、可引导"：向导建课、蓝图就地编辑、总览鸟瞰。
- 批量与快捷键显著降低重复操作成本；所有结构变更仍走 `QUndoStack`，可撤销。
- 蓝图与既有 teacher widget（`build_teacher_widget`）功能部分重叠：以蓝图为 DetailPanel 主视图，teacher widget 保留为教师模式窗口的兼容路径，未删除以避免回归。
- 测试基线 `tool/gui` 377 -> 804（新增 5 个测试文件 + tree 键盘/批量用例），全量 offscreen 可跑。
- 未触碰 Flutter 端与课程 JSON schema；预设产出的 lesson 通过 `validate_section_json` 校验。
