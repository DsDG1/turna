# tool-gui 使用逻辑改进：AI 冲突确认 + 工坊目标选择 + 越树移动

## 背景与现状

三个独立的 tool-gui（PySide6 课程编辑器）使用逻辑改进。当前代码现状已逐一确认：

1. **AI 编辑 unit/lesson 的 id 冲突需明确确认**
   - section 级：已有 `AiMergePreviewDialog`（逐项 replace/add/skip）+ 5 种导入策略（merge/skip/force_replace/append_as_new/append，见 `import_strategy.py`）+ `SectionImportService`（`section_import_service.py`）。✅ 已完善
   - unit/lesson 级：`_on_ai_edit`（`app.py:680`）的 unit/lesson 分支用 `_extract_unit`/`_extract_lesson`（`app.py:738,756`）**强制 AI 返回同 id**（找不到就报错），`AiEditUnitCommand`/`AiEditLessonCommand`（`commands.py:1064,1113`）整体替换，`validate_section_json(check_existing_ids=False)` 跳过子节点冲突——冲突**静默**，延迟到 `save()` 时 validate 才暴露。

2. **工坊生成内容可加入已有 section/unit**
   - 工坊导入路径 `design_panel._on_import`（`design_panel.py:696`）固定 `sections_ready.emit([data], "merge")`，单 section，经 `WorkshopWindow._on_panel_sections_ready` → `app.py:_on_textbook_sections` → `SectionImportService.import_bulk`，只能整 section 导入/合并。
   - 无法把生成的 unit/lesson 拆出来追加到**已有** section/unit。

3. **上下移动可越树**
   - `_move_current`（`course_tree.py:689`）严格同级，越界 no-op；tooltip 写死"仅同级"（`course_tree.py:64,613,619`）。
   - 已有 `BulkMoveLessonsCommand`（`commands.py:721`）跨 unit 移动 lesson（snapshot+remove+insert 模式），`clone_lesson_with_fresh_ids`（`lesson_content.py:558`）可重生 id，可作模板。

用户已确认设计选择：需求 1 用**覆盖/重命名追加/取消**三选一；需求 3 **lesson 跨 section、unit 跨 section**，**↑/↓ 到边界自动跨越**。

---

## 方案

### 需求 1：unit/lesson AI 编辑 id 冲突三选一

**核心**：在 `_on_ai_edit`（`app.py`）的 unit/lesson 分支，应用前检测冲突，弹三选一确认框。

**冲突检测**（新增 `CourseAdapter.check_node_id_conflicts` helper，或就地实现）：
- **场景 A（AI 改了 id）**：`_extract_unit`/`_extract_lesson` 找不到同 id 节点时，不再直接报错，改为取 AI 返回的第一个同 kind 节点作为候选，标记"AI 改了 id"。
- **场景 B（子节点 id 冲突）**：
  - unit：`new_unit` 内所有 lesson id 若与课程其他位置（排除当前 unit）的 lesson id 重复 → 冲突。
  - lesson：`new_lesson` 内子节点 id（subLesson/stage/item/listeningPhase）若与其他 lesson 重复 → 冲突（用 `all_lesson_ids`/遍历子节点比对）。

**处理流程**（修改 `app.py:_on_ai_edit` unit/lesson 分支）：
1. 提取候选 unit/lesson（容忍 AI 改 id）。
2. 检测冲突（场景 A/B），收集冲突 id 列表。
3. 无冲突 → 直接应用（现状）。
4. 有冲突 → 弹 `QMessageBox` 三选一，文案列出冲突 id：
   - **覆盖**：`AiEditUnitCommand`/`AiEditLessonCommand` 整体替换原节点（现状行为，现明确确认）。
   - **重命名追加**：
     - lesson：`clone_lesson_with_fresh_ids(new_lesson)` 重生所有结构 id → `AppendLessonCommand` 追加到同 unit。
     - unit：新增 `clone_unit_with_fresh_ids(new_unit)` 重生 unit id + 内部所有 lesson id → 新增 `AppendUnitCommand` 追加到同 section。
   - **取消**：return。

**新增**：
- `lesson_content.clone_unit_with_fresh_ids(unit, name=None)`：重生 unit id，内部每个 lesson 调 `clone_lesson_with_fresh_ids`，保留外部引用（wordId 等）。
- `commands.AppendUnitCommand`：把 unit 追加到 section，undo 移除（参照 `AppendLessonCommand` `commands.py:441`）。

### 需求 2：工坊导入目标选择

**核心**：在 `design_panel._on_import`（`design_panel.py:696`）发射 `sections_ready` 前，弹目标选择对话框。

**目标选择对话框**（新增 `dialogs/import_target_dialog.py`）：
- **作为新 Section 导入**（现状）：走 `import_bulk` + strategy（merge/append/...）。
- **导入到已有 Section（作为新 Unit）**：选目标 section，把 draft 的 units 拆出，每个 `clone_unit_with_fresh_ids` 后追加到目标 section。
- **导入到已有 Unit（作为新 Lesson）**：选目标 unit，把 draft 的所有 lesson 拆出，每个 `clone_lesson_with_fresh_ids` 后 `AppendLessonCommand` 追加到目标 unit。

**实现路径**：
- 目标选择结果经 `sections_ready` 信号（扩展携带目标信息）或新增信号传到 `app.py`。
- `app.py:_on_textbook_sections` 分发：
  - 新 section → 现状 `import_bulk`。
  - 追加 unit 到 section → 新增 `AppendUnitsToSectionCommand`（snapshot + append fresh-id units + merge resources）。
  - 追加 lesson 到 unit → 循环 `AppendLessonCommand`（或新增 `BulkAppendLessonsCommand`）。
- push 命令 → refresh tree → select 新节点。

**资源处理**：draft 的 words/expressions/grammarPoints 在拆分导入时调 `merge_section_resources`（已有，跳过重复 id），保证 lesson 引用可解析。

### 需求 3：越树移动

**核心**：修改 `course_tree._move_current`（`course_tree.py:689`），到边界时自动跨越相邻父节点；新增跨父移动命令。

**新命令**（`commands.py`，参照 `BulkMoveLessonsCommand` snapshot+remove+insert 模式）：
- `ReparentLessonCommand(adapter, lesson_id, new_section_id, new_unit_id, new_index)`：snapshot (old_section_id, old_unit_id, old_index, lesson)；redo: 从旧 unit 移除，插入新 unit 的 new_index；undo: 反向。
- `ReparentUnitCommand(adapter, unit_id, new_section_id, new_index)`：snapshot (old_section_id, old_index, unit)；redo: 从旧 section 移除，插入新 section；undo: 反向。

**修改 `_move_current(direction)`**（`course_tree.py:689`）：
- 同级边界内 → 现有 `MoveLessonCommand`/`MoveUnitCommand`/`MoveSectionCommand`。
- lesson 到 unit 顶部(idx=0)上移 → 找前一个 unit（同 section 前一 unit，否则上一 section 最后 unit）；存在 → `ReparentLessonCommand` 到该 unit 末尾；否则 no-op。
- lesson 到 unit 底部下移 → 找下一个 unit（同 section 后一 unit，否则下一 section 第一 unit）；reparent 到该 unit 开头；否则 no-op。
- unit 到 section 顶部上移 → 找上一 section；`ReparentUnitCommand` 到其末尾；否则 no-op。
- unit 到 section 底部下移 → 找下一 section；reparent 到其开头；否则 no-op。
- section 顶级 → 保持 `MoveSectionCommand`（已自由）。

**辅助**：新增 `_flatten_units()` 返回课程所有 (section_id, unit_id, unit) 有序列表；`_flatten_sections()` 返回 section 有序列表，用于定位前/后父节点。

**UI 更新**：
- `_update_move_buttons`（`course_tree.py:666`）：去掉"仅同级"判断，改为"是否课程的第一个/最后一个可移动节点"（第一个 lesson 往上无路、最后一个 lesson 往下无路时禁用）。
- tooltip（`course_tree.py:64,613,619`）：改为"上移（可跨 Unit/Section）"。
- 快捷键提示文案更新。

---

## 风险与注意

- **先修引用**：越树移动改变层级后，`prerequisiteLessonIds`/`prerequisiteUnitIds`/`prerequisiteSectionIds` 仍指向原 id（id 不变，引用不断裂），但跨层级先修语义可能变怪。首版**不自动清理**，仅在状态栏提示"已移动，请检查先修依赖"。
- **重命名追加的先修**：`clone_lesson_with_fresh_ids` 保留 `prerequisiteLessonIds`（指向原 lesson）。追加为新节点时，应清空 `prerequisiteLessonIds`（新节点不应继承原节点的先修链）——在 clone 后显式清空。
- **工坊拆分导入的资源**：`merge_section_resources` 跳过重复 id，安全；但若 draft 的 lesson 引用了 draft 内未 merge 的资源 id，需确保 merge 在前。
- **undo 一致性**：所有新命令严格 snapshot+reverse，参照 `BulkMoveLessonsCommand` 的"先一次性快照再操作"模式，避免多节点 undo 错序。

## 文件改动清单

- `src/backend/lesson_content.py`：新增 `clone_unit_with_fresh_ids`
- `src/backend/course_adapter.py`：新增 `check_node_id_conflicts` helper（可选）
- `src/application/commands.py`：新增 `AppendUnitCommand`、`AppendUnitsToSectionCommand`（或 `BulkAppendLessonsCommand`）、`ReparentLessonCommand`、`ReparentUnitCommand`
- `src/app.py`：修改 `_on_ai_edit` unit/lesson 分支（冲突检测+三选一）；扩展 `_on_textbook_sections` 分发工坊拆分导入
- `src/widgets/course_tree.py`：修改 `_move_current`/`_update_move_buttons`/tooltip；新增 `_flatten_units`/`_flatten_sections`
- `src/dialogs/ai/design_panel.py`：修改 `_on_import`（接入目标选择）
- 新增 `src/dialogs/import_target_dialog.py`（工坊目标选择对话框）
- 新增/更新 tests

## 测试

- 需求 1：`test_commands_and_ai_edit.py` 加 unit/lesson 冲突三选一用例（覆盖/重命名追加/取消，含 AI 改 id 场景）。
- 需求 2：新增 `test_import_target_dialog.py` + `test_design_panel.py` 扩展（三种目标路径）。
- 需求 3：`test_course_tree.py` 加越树用例（lesson 跨 unit、lesson 跨 section、unit 跨 section、边界 no-op、undo 还原层级）。
- 运行：`cd tool/gui && python3 -m unittest discover -s tests`（PySide6 在系统 Python 3.12 可用，无需 venv；offscreen 模式注意 `test_ai_generator_dialog.py::test_wish_generation_chain_updates_explanation` 预存 hang）。
- 更新 `test/BASELINE.md` 测试计数。
