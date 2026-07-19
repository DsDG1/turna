# 教师模式重构：从布尔覆盖层到自洽全窗口工作区（方案 B）

> 目标：消除教师模式的"割裂/违和"——把"工具栏开关 + 浮动 TeacherWindow + 内联
> show_teacher_lesson"三套并行面，以及 4 个异构课节编辑器、publish/resources 双胞胎，
> 收敛为**一个自洽的全窗口工作区**。专家模式基本不动。
>
> 范围选择（已与用户确认）：**B**——保留两模式，教师模式升级为全窗口工作区，外壳随模式切换。

## 验收

- 切到教师模式后只有**一个**面（主窗口右栏即教师编辑面），不再弹出独立窗口；课程树选课 -> 右栏直接渲染该课教师编辑器。
- 4 种课型（intro/practice/review/legacy、listening、reading、mastery）的教师编辑器共享同一外壳：相同面包屑/课型徽章/动作栏（预览 · AI 改写 · 高级编辑 · 模板特有动作），仅正文按模板差异。
- 每种教师编辑器都有"高级编辑"出口（切到专家 `LessonEditor`），sub-lesson 不再是例外。
- 教师模式下工具栏/树随模式切换（教师动作前置、课型徽章着色）。
- 发布对话框合并为单个 `PublishDialog(teacher_friendly=...)`，`if self.teacher_mode` 分支从 app.py 消失（或仅剩一处入口分发）。
- `QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"` 全绿；`tests/BASELINE.md` 更新。

## 现状回顾（割裂的 5 个源头）

1. **三套并行面**：`_on_mode_toggled`(app.py:447) 开关 -> 弹独立 `TeacherWindow`(app.py:467) **且** `_on_node_selected`(app.py:856-864) 在右栏 `show_teacher_lesson` 内联重建同一控件。注释(853-855)说"右栏留元数据不空"，代码却造双份。
2. **布尔标志缝合两套工具链**：`if self.teacher_mode` 散在 4 处读——app.py:179(标题)、852(选区)、888(资源)、938(发布)；发布 `widgets/publish_dialog.py` vs `teacher/publish_dialog.py` 双胞胎，资源 `ResourceEditorDialog` vs `VocabTableWidget` 双胞胎。
3. **4 个异构编辑器**：`build_teacher_widget`(detail_panel.py:21-54) 按 template 分派到 `SubLessonFlowWidget` / `ListeningTeacherWidget` / `ReadingTeacherWidget` / `MasteryTeacherWidget`。其中只有后 3 个继承 `TeacherTemplateWidget`(有"高级编辑"出口)；`SubLessonFlowWidget` 直接继承 `LinearFlowWidget`(680 行，独立 header，无高级编辑出口，但有"实时预览/从词库生成"另两个没有)——chrome 互不一致。
4. **线性流是独立范式**：`LinearFlowWidget` 自带拖拽重排、面包屑、预览按钮，与专家侧 `LessonBlueprint`+`LessonEditor` 是第三套渲染路径（detail_panel.py 既有 蓝图/高级编辑 切换，教师路径却走 `build_teacher_widget`，不用蓝图）。
5. **外壳不变**：切教师模式只换右栏 + 弹窗，左树/工具栏仍是专家向（`类型` 列裸露 template 文本、无色徽章）。

## 设计要点

1. **合并三面为一面**：教师模式下**主窗口右栏 DetailPanel 即教师工作区**，删除浮动 `TeacherWindow`。内联 `show_teacher_lesson` 路径已存在且可用，Phase 1 主要是"删窗口 + 修路由"，低风险。
2. **统一外壳，不强行统一正文**：4 种课型的内容形态本质不同（subLessons→stages vs listeningPhases vs passage+stages vs 单 stage），强行单正文会丢教学法特异性并触发大重写。改为**共享外壳 + 模板特有正文**：把 `TeacherTemplateWidget` 的 header/动作栏抽成所有 4 家共用，`SubLessonFlowWidget` 补齐"高级编辑"出口、纳入统一动作栏。用户体感=一个编辑器。
3. **boolean 分支收编**：发布/资源不再 `if teacher_mode` 挑类，而是单类 + `teacher_friendly` 形参自适应隐藏工程字段。
4. **外壳随模式切换**：`_on_mode_toggled` 触发 toolbar 可见性/标签 + 树的课型徽章着色重排；专家模式外观完全不变。
5. **蓝图收敛列为可选 Phase 5**：`LessonBlueprint` 已按 4 模板统一卡片视图且支持 undo/read_only，是未来把"教师正文"也收敛为单一蓝图的跳板；本轮不做，留口子。

## 改动清单（按阶段，低风险→高风险）

### Phase 1：合并三面（删浮动窗口，修路由）——最直接消违和

**`src/app.py`**
- 删字段 `self._teacher_window`(L87) 及 `_open_teacher_window`(L467-506)/`_close_teacher_window`(L508-511)/`_on_teacher_window_closed`(L513-523)。
- `_on_mode_toggled`(L447-465)：去掉开/关窗口调用(L457-460)，保留标题/telemetry/`_on_node_selected` 重跑(L461-462) + 新增 `_apply_mode_shell()`(Phase 3)。
- `_on_node_selected`(L848-868)：teacher_mode 且 lesson 分支删去 `_teacher_window.show_lesson`(L857-858)，保留 `self.detail.show_teacher_lesson(...)`(L864)；非 lesson 仍 `show_node`(L866)。
- `_on_tree_changed`(L877-884)：删 `TeacherWindow.refresh_lesson_list()` 分支(L880-881)。
- `closeEvent`(L1118-1191)：删 `_teacher_window.close()`。
- `L179` 标题拼接保留（纯装饰，无害）。

**`src/dialogs/teacher_window.py`**：整文件删除。

**`src/widgets/detail_panel.py`**：`show_teacher_lesson`(L245-276) 不变（已是内联渲染入口）；`build_teacher_widget` 不变。

**测试**：重写 `tests/test_app.py::TeacherModeToggleTest`(L300-332) 4 个用例——不再断言 `_teacher_window`，改为断言：toggle on 后选 lesson 时 `self.detail` 内含教师控件（如 `findChild` 到 `QuestionCard` 或 `LinearFlowWidget`）、toggle off 后右栏回到 `show_node` 形态、无独立窗口存在(`self.assertEqual(self.win.findChildren(TeacherWindow), [])` 或等价)。

### Phase 2：统一 4 编辑器外壳（4→1 chrome）

**`src/teacher/template_editors.py`**
- 把 `TeacherTemplateWidget._build_ui` 的 header（面包屑 + 课型徽章 + 动作栏：预览/AI改写/高级编辑）抽成可复用方法 `_build_shell_header(extra_actions)`，供子类插入模板特有动作（如 listening 的"添加听力阶段"不在此、reading 的 passage 入口不在此——只放通用动作）。
- 动作栏统一为：`[预览本课] [AI 改写] [高级编辑 ✓]`，模板特有动作（从词库生成 / 实时预览）由子类通过 `extra_actions` 注入。

**`src/teacher/linear_flow.py` + `sublesson_flow.py`**
- 给 `LinearFlowWidget` 增加"高级编辑"出口：toggle 切到 `LessonEditor(adapter, lesson)`（复用 `TeacherTemplateWidget._on_advanced_toggled` 模式），与另 3 家一致。
- `SubLessonFlowWidget._build_ui` 的 header（L221-260 面包屑/徽章/预览/AI改写/实时预览）改为复用 Phase 2 抽出的 `_build_shell_header`，`从词库生成`/`实时预览` 作为 `extra_actions` 注入。保留其 live preview 容器逻辑(`_refresh_preview`)。
- 硬编码色值(`#1F232C`/`#232833`/`#1E3A8A` 等)迁到 `theme.py` 常量，与专家侧一致。

**`src/widgets/detail_panel.py:build_teacher_widget`**：分派不变（仍 4 类），但 4 类现共享外壳。

**测试**：`tests/test_linear_flow.py::SubLessonLivePreviewTest` 保留（实时预览仍在）；新增 1 个用例断言 `SubLessonFlowWidget` 具"高级编辑"按钮且能切到 `LessonEditor`。`tests/test_template_editors.py` undo 用例不动。

### Phase 3：外壳随模式切换（toolbar + 树）

**`src/app.py`**
- 新增 `_apply_mode_shell()`：教师模式下——toolbar 隐藏/置灰专家专属项（如保留 保存/发布/资源库/设置，但把"教师动作"前置：向导建课入口、预览、词库）；专家模式恢复全量。实现上可对一组 `QAction` 调 `setVisible(not teacher_mode)`/调换顺序。
- `_on_mode_toggled` 末尾调 `_apply_mode_shell()`。

**`src/widgets/course_tree.py`**
- lesson 节点 `类型` 列(L96 `f"lesson ({template})"`)：教师模式下改为彩色徽章（复用 `widgets/course_overview.py::_TEMPLATE_COLORS`），专家模式保持文本。加一个 `set_teacher_mode(bool)` 刷新列绘制。
- `MainWindow._on_mode_toggled` 后调 `self.tree.set_teacher_mode(checked)`。

**测试**：`tests/test_app.py` 加 1 个用例断言 `_apply_mode_shell()` 切换后 toolbar 动作可见性；`tests/test_course_tree.py` 加 1 个用例断言教师模式下 lesson 节点徽章颜色/数据。

### Phase 4：合并发布对话框（收编 boolean 分支）

**`src/widgets/publish_dialog.py`**
- `PublishDialog.__init__(..., teacher_friendly: bool = False)`：`teacher_friendly=True` 时——隐藏 id 集变更 group(`_render_diff`)、把版本 bump 变只读(自动应用、不显文件名 checkbox)、隐藏 lint warnings(只留 error 阻断)、错误用 `teacher.error_mapper.humanize_problem` 人话化、按钮文案"发布"。即把 `TeacherPublishDialog` 的差异点吸收为形参分支。
- 保留导出报告的详简两档。

**`src/teacher/publish_dialog.py`**：删除（其逻辑被吸收）。

**`src/app.py:_on_publish`(L936-953)**：删 `if self.teacher_mode` 分支，统一 `PublishDialog(self.adapter, self, teacher_friendly=self.teacher_mode)`。

**资源对话框**：本轮**不合并**（`VocabTableWidget` vs `ResourceEditorDialog` 差异大、价值低），保留 L888 分支。如用户要求可后补。

**测试**：`tests/` 若有 publish 测试则补 `teacher_friendly=True` 路径；更新引用 `TeacherPublishDialog` 的用例改指 `PublishDialog(teacher_friendly=True)`。

### Phase 5（可选，本轮不做）：正文收敛到 LessonBlueprint

- 把 4 家 `_build_teacher_view` 替换为 `LessonBlueprint(adapter, lesson, undo_stack, read_only=False)` + 统一 header，真正单正文。前置：给 blueprint 补"从词库生成/AI改写/实时预览"动作。风险大，单列后续。

## 测试与基线

- 命令：`cd tool/gui && QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"`
- 受影响：`test_app.py`(TeacherModeToggleTest 重写 + 新增 shell 用例)、`test_linear_flow.py`(新增高级编辑用例)、`test_course_tree.py`(徽章用例)、`test_template_editors.py`(吸收 publish 用例若有)。
- 不受影响：`test_teacher.py`(纯 wizard/error_mapper)、`test_teacher_view_model.py`(纯 VM)。
- 完成后更新 `tool/gui/tests/BASELINE.md`（当前 848 passed, skipped=2）。

## 风险与回退

- **Phase 1 删 TeacherWindow** 是最大行为变化（教师习惯的弹窗消失）。回退：保留 `TeacherWindow` 作可选"分离窗口"入口（一个菜单项），默认关。建议先不做、观察反馈。
- **Phase 2 重基 LinearFlowWidget** 可能触及拖拽重排(`_DragDropFilter`)与 live preview 的布局耦合；保持 `_build_ui` 主结构、只换 header，正文构建不动，可把风险压到最低。
- **Phase 4 合并 publish** 需保证 `teacher_friendly=False` 路径与原专家对话框逐字段一致，避免专家侧回归——以现有 publish 测试为护栏。
- 建议按 Phase 1→2→3→4 顺序提交，每阶段独立可回退。
