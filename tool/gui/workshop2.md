# workshop2 — 课程工坊（主课程编辑器）功能课向导 + 蓝图 + 批量/快捷键

> 2026-07-17 启动。目标见 ADR 0021。范围：`tool/gui/` 主课程编辑器（`MainWindow`），不改 Flutter 端、不改课程 JSON schema。

## 背景

主课程编辑器此前对功能课（listening/reading/mastery）的设置是自由式骨架克隆，缺引导与可视化；并缺复制、批量、快捷键、整体总览。本计划补齐这些编辑器常用能力，并以"向导 + 蓝图"直观展现功能课设置过程。

## 阶段（建议顺序 P1 -> P3 -> P2 -> P4 -> P5 -> P6）

### P1 预设库 + 复制课时 + 快捷键 — ✅ done (2026-07-17)
- `backend/lesson_presets.py`：`FUNCTIONAL_PRESETS`（听力三阶段 / 阅读三类题 / 综合测验 / 认识新词三步 / 巩固练习）+ `build_preset_lesson` / `apply_preset_to_lesson`。
- `backend/lesson_content.py`：`clone_lesson_with_fresh_ids`（重生结构 id、保留引用 id）。
- `backend/course_adapter.py`：`duplicate_lesson`。
- `application/commands.py`：`DuplicateLessonCommand` / `BulkDelete/Duplicate/Move/ApplyPreset`。
- `widgets/course_tree.py`：`ExtendedSelection` + `keyPressEvent`（Ctrl+D / Delete / F2 / Ctrl+↑↓）+ tooltip + 批量菜单雏形。
- 测试：`test_lesson_presets.py`、`test_commands_bulk.py`、`test_course_tree.py` 键盘用例。

### P3 可视化蓝图 — ✅ done (2026-07-17)
- `widgets/lesson_blueprint.py`：`LessonBlueprint` 卡片流（listening 横向阶段 / reading 篇章+题 / mastery 题流 / subLesson kanban），只读预览 + 命令化就地编辑（复用 `QuestionCard`）。
- `widgets/detail_panel.py`：「蓝图 / 高级编辑」切换，功能课型默认蓝图。
- 测试：`test_lesson_blueprint.py`（含 DetailPanel 集成）。

### P2 功能课向导 — ✅ done (2026-07-17)
- `dialogs/functional_lesson_wizard.py`：3 步向导（选类型+预设 -> 配置 -> 蓝图预览），完成经 `AppendLessonCommand` 插入并选中。
- `dialogs/new_lesson_dialog.py`：「向导创建（功能课）」入口；单元右键「功能课向导…」。
- 测试：`test_functional_lesson_wizard.py`。

### P4 课程结构总览 — ✅ done (2026-07-17)
- `widgets/course_overview.py`：`CourseOverviewWindow`（非模态，Section/Unit/Lesson 芯片 + 课型色条 + 统计，点击定位）。工具栏「总览」按钮；`_on_tree_changed` 可见时刷新。
- 测试：`test_course_overview.py`。

### P5 批量操作 — ✅ done (2026-07-17)
- 课程树多选右键菜单：批量复制 / 移动到… / 套用预设… / 删除。`_pick_target_unit` + `BulkApplyPresetCommand`。
- 测试：`test_commands_bulk.py` 增 `ApplyPresetTest`/`BulkApplyPresetCommandTest`；`test_course_tree.py` 增 `CourseTreeBulkTest`。

### P6 打磨 + 文档 + 基线 — ✅ done (2026-07-17)
- 向导 `wizard.open` telemetry；树快捷键 tooltip。
- `test/BASELINE.md`（tool/gui 377 -> 804）；ADR 0021；本文件；memory 更新。

## 测试运行
- 后端纯函数：`python3 -m unittest tool.gui.tests.test_lesson_presets tool.gui.tests.test_commands_bulk`（无需 Qt）。
- 全量 GUI：`QT_QPA_PLATFORM=offscreen python3 -m unittest discover -s tool/gui/tests -p "test_*.py"`（~39s，804 passed）。
- 约束见 [[tool-gui-arch]]：PySide6 已在系统 Python 3.12 可用；`test_ai_generator_dialog.py::test_wish_generation_chain_updates_explanation` 预存 offscreen hang，与本次改动无关。

## 未做 / 后续
- 蓝图与 teacher widget 重叠未合并（teacher widget 作为兼容留底）。
- "批量逐题改"未做（"批量套用预设"覆盖了批量改结构的需求）。
- 蓝图未支持拖拽排序（`LinearFlowWidget` 有拖拽；蓝图用按钮上下移）。
- reading 蓝图的 `linkedWordIds` / `linkedExpressionIds` 仍未给独立 picker（与原 `ReadingEditor` 一致，留待后续）。
