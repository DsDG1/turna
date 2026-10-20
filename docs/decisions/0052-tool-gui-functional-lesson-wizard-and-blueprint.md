# ADR 0052 — tool-gui 功能课向导 + 可视化蓝图 + 批量/快捷键 + 课程总览

> **Status**: Accepted ｜ **Date**: 2026-07-17
>
## 决策

### P1 预设库 + 复制 + 快捷键

- 新增 `backend/lesson_presets.py`：`FUNCTIONAL_PRESETS` 注册表（听力三阶段 / 阅读三类题 / 综合测验混合 / 认识新词三步 / 巩固练习混合）+ `build_preset_lesson(id, name)` + `apply_preset_to_lesson(lesson, id)`。纯 Python、无 PySide6，可单测。
- `backend/lesson_content.py` 新增 `clone_lesson_with_fresh_ids(lesson, name)`：深拷贝并重生所有结构 id（lesson / subLessons / stages / items / listeningPhases），保留引用型 id（wordId / expressionId / grammarPointId / linkedWordIds / linkedExpressionIds / prerequisiteLessonIds）。
- `CourseAdapter.duplicate_lesson(lesson_id)`：同 unit 末尾追加克隆副本。
### P2 功能课向导

- 新增 `dialogs/functional_lesson_wizard.py`：`FunctionalLessonWizard(QDialog)` 三步 `QStackedWidget`：① 选类型（listening/reading/mastery）+ 名称 + 预设（或空白骨架）② 轻配置（听力阶段名/音频/转录；阅读篇章；测验题型勾选）③ 只读蓝图预览。
### P3 可视化蓝图

- 新增 `widgets/lesson_blueprint.py`：`LessonBlueprint(adapter, lesson, undo_stack, read_only)` 卡片流总览：listening 为横向阶段卡片（wordPairing → dialogue → summary）+ `->` 箭头；reading 为篇章卡片 + 理解题卡片；mastery 为单 stage 题目卡片流；intro/practice/review/legacy 为 subLesson 分栏（kanban）。
### P4 课程总览 + P5 批量操作

- 新增 `widgets/course_overview.py`：`CourseOverviewWindow`（非模态，QSettings 几何）按 Section → Unit → Lesson 芯片（左侧 4px 课型色条 + 名称 + 课型 label），顶部统计行（计数 + 课型分布）。点芯片发 `lesson_selected` → `MainWindow` 调 `tree.select_lesson` 并 raise；`_on_tree_changed` 可见时 `refresh()`。
## 影响与边界

- 编辑器对功能课的设置过程首次「可见、可引导」：向导建课、蓝图就地编辑、总览鸟瞰。
- 批量与快捷键显著降低重复操作成本；所有结构变更仍走 `QUndoStack`，可撤销。
- 蓝图与既有 teacher widget（`build_teacher_widget`）功能部分重叠：以蓝图为 DetailPanel 主视图，teacher widget 保留为教师模式窗口的兼容路径，未删除以避免回归。
## 理由
