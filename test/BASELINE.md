# Test Baseline

Generated: 2026-07-17 (tool-gui workshop2：主课程编辑器功能课向导 + 可视化蓝图 + 批量/快捷键 + 课程总览。P1 预设库 `backend/lesson_presets.py`（FUNCTIONAL_PRESETS：听力三阶段/阅读三类题/综合测验/认识新词三步/巩固练习 + `build_preset_lesson`/`apply_preset_to_lesson`）+ `clone_lesson_with_fresh_ids` + `CourseAdapter.duplicate_lesson` + 新命令 `DuplicateLessonCommand`/`BulkDelete/Duplicate/Move/ApplyPreset`；课程树 `ExtendedSelection` + `keyPressEvent`（Ctrl+D 复制 · Delete 删除 · F2 重命名 · Ctrl+↑/↓ 同级移动）+ 批量菜单（复制/移动/套用预设/删除）。P3 `widgets/lesson_blueprint.py`（LessonBlueprint 卡片流蓝图，只读预览 + 命令化就地编辑），`DetailPanel` 加「蓝图/高级编辑」切换，功能课型默认蓝图。P2 `dialogs/functional_lesson_wizard.py`（3 步向导：选类型+预设 -> 配置 -> 蓝图预览，`NewLessonDialog` 加「向导创建」入口 + 单元右键「功能课向导…」）。P4 `widgets/course_overview.py`（CourseOverviewWindow 非模态总览，Section/Unit/Lesson 芯片 + 课型 badge + 统计，点击定位）。P5 批量套用预设/批量移动。新增测试 `test_lesson_presets` 13、`test_commands_bulk` 12、`test_lesson_blueprint` 12、`test_functional_lesson_wizard` 6、`test_course_overview` 4、`test_course_tree` 增键盘+批量 7。)

Previous: 2026-07-16 (Flutter app i18n + 分层 Settings。Task 1：把 lib/ 内中文 UI 文案与 AI prompt 脚手架全部改英文（AI 回复仍按 source language；ai_prompt_builder/ai_course_service 加 "reply in source language" 指令保输出语言）。改 `interactionTypeLabel`、`ai_genre` 的 label/description/`templateLabels` 与 `genrePromptBlock`、`ai_resource_consistency` 校验信息、`ai_course_service` 异常信息与 prompt、`ai_hint_provider` 讲解 prompt。UI 文案：play_hub/ai_hint_chat/new_lesson/ai_hint_sheet/mistake_review/review_components/srs_review/grammar_review/mistake_review_assembler。Task 2：`SettingsPage` 由单页改 StatefulWidget + 页内状态导航（`_category`：null=分类列表，0..4=Account/Learning/Audio & Display/Data/About 子页），复用现有 tile 与 bottom sheet；`SettingsAppBar` 降为零高度 stub，避免双层 AppBar；不走 AutoRoute，"去设置" TabRouter 切 tab 行为不变。同步更新 `ai_genre_test`/`ai_prompt_builder_test`/`ai_hint_provider_test`/`play_hub_screen_test` 的中文断言，重新生成 play_hub light/dark golden。）

Previous: 2026-07-15 (tool-gui guiplan2 阶段 P3：结构化预览 + JSON 智能编辑 + diff。新增 `src/widgets/json_editor.py`（JsonEditor：QSyntaxHighlighter 高亮 + Ctrl+Shift+F 格式化 + 错误行红标跳转 + set_json/to_json）。`ResultPreviewWidget` 加 QTreeWidget 结构树（Section→Unit→Lesson→subLesson/stage/listeningPhase→item，点节点发 `node_activated(id)` → dialog 跳 JSON 行；`_on_validate` 后用 `error_mapper.parse_path` 把 error 标红到对应 unit/lesson 节点 + humanize_problem tooltip）。wish 模式加同款 `wish_json_edit`，`_current_json()` 改为按模式读编辑器（修 B1/C4，`_generated` 仅作恢复快照），`_on_reset` 按模式重置。新增 `src/widgets/diff_view.py`（SectionDiffView：`full_section_diff` 增删改三色树，"查看 diff" 按钮在编辑模式可见）。新增 `full_section_diff` 纯函数（复用 `_section_unit_ids` 等，added/removed/changed by json.dumps fingerprint）。`LessonPreviewDialog`/`_PreviewCard` 加可选 `vocab_override`，"试做" 按钮用生成 section 的 words 构造 override，未导入也能查译文。新增 `test_json_editor.py` 5 + `test_diff_view.py` 4 + `test_ai_generator_dialog.py` B1 回归 3。)

Previous: tool-gui guiplan2 阶段 P5：排版归一 + 主题统一。拆出 `src/dialogs/ai/` 包：`worker.py`（AiRequestWorker/_AttachmentRecord）、`chat_view.py`（ChatView + 纯渲染函数，无 PySide6 可单测）、`prompt_template_bar.py`（单一共享模板选择器，修 B8——`_build_template_selector` 原两次调用覆盖 combo/cards/genre_switch，改为单实例 + `_update_mode_ui` reparent）、`chat_expand_window.py`（真子窗口，几何存 QSettings，第二 ChatView 共享 _messages，替代 resize/hide-chrome hack）。修 wish 模式 `_current_spec` topic 取值（原读 normal-only 孤儿 topic_edit，改按模式取 last user message）。`theme.py` 加 `ai_*` palette 键 + `current_palette()`/`ai_color()`，dialog 内联 hex 全部走 `_pal()` 查询。许愿一屏化：3 段 QSplitter（chat / 折叠结果摘要 / 输入），结果默认折叠为「✓ 已生成 · N 单元 · M 课时 · K 词」，解释就绪自动展开。可访问性：Enter 发送 checkbox（默认 ON）、Tab 顺序、附件 × tooltip + Delete 提示。附带修复 P2 残留回归：`test_ai_generator_dialog.py` 三个普通模式用例的 patch 目标 `generate_from_chat` → `request_course_with_retry`。新增 `test_ai_chat_view.py` 11。全量 GUI 套件 offscreen 本机可跑。

Previous: tool-gui guiplan2 阶段 P2：校验自愈 + 局部重生成。修 C3（普通模式接通 `request_course_with_retry`，校验错自动回灌一轮）/C5（编辑模式 lesson/unit 级走局部重生成 `regenerate_lesson_in_section`/`regenerate_unit_in_section`，只重发该子树）/B5（retry validator 适配 Problem dict，`_coerce_problem_messages` 取 .message、过滤 warning）/B3（`structural_diff` + 删除确认弹框）/B4（`_auto_fix_resources` stub 译文回退 `[待补]` + `needs-review` tag）。新增 `Settings.ai_retry_max`（0-5，默认 1）+ `current_settings()` helper。新增 16 个后端测试）

Previous: tool-gui guiplan2 阶段 P1：AI 流式生成 + 真正可中断取消 + token/成本可见。新增 `ai_stream.py`（SSE 解析）/`ai_usage.py`（token 估算+价目表）；`request_chat` 增加 stream/on_chunk/usage_callback 参数，所有生成路径透传；`AiRequestWorker` 新增 chunk_ready/usage_ready 信号并自动注入回调；dialog 修复 B2（wish 解释阶段 worker 接线）/B6（流式取消行读取前轮询）/B7（_request_start 每轮重置、完成清 None，duration 安全 helper）；新增 usage_label 用量行；阶段文案语义化（生成中流式/校验中/解释中）。修 C1/C2

Previous: tool-gui Phase 1+2+3+4：稳定层加固 + 教师视图覆盖全部 6 种模板 + AI 改写与易用性提升 + 稳定性加固。Phase 1：backend/api.py 隔离 CLI 内部函数、CourseAdapter 原子保存/备份/回滚、CSV None 容错、全局异常处理与日志。Phase 2：SubLessonFlowWidget 模板感知视图、intro/practice/review 一键生成助手、lesson_content 统一生成函数与测试。Phase 3：教师视图接入 AI 一键生成/改写/扩展题目；新增撤销/重做、sub-lesson 拖拽排序、实时预览。Phase 4：修复 widget 生命周期隐患、listening/reading/mastery 教师视图全面走 undo stack、wizard/AI 导入资源可撤销、AI API 配置持久化、异常不再静默吞掉

## Results
- `flutter test`: **445 total** — all passed
- `flutter analyze`: only info-level lint (no errors/warnings from new code) — `DropdownButtonFormField.value` deprecation + `prefer_const` infos (pre-existing)
- Python:
  - `python3 -m unittest discover -s test -p "*_cli_test.py"` — 7 passed
  - `tool/gui` suite (from repo root: `python3 -m unittest discover -s tool/gui/tests -p "test_*.py"`) — **804 passed** (workshop2：功能课向导+蓝图+总览+批量/快捷键；新增 test_lesson_presets/test_commands_bulk/test_lesson_blueprint/test_functional_lesson_wizard/test_course_overview + test_course_tree 键盘与批量用例)。全量 GUI 套件 offscreen 本机可跑（~39s）。
- `tool/course_cli.py --course-dir assets/courses/turkish validate` passes

## Notes
- `tool/gui` Phase 4 稳定性加固（方案 A）：
  - 修复 widget 生命周期：`DetailPanel.clear_content()` 与
    `TeacherTemplateWidget._clear_content()` 缓存 `widget = child.widget()`，
    避免 `setParent(None)` 后二次调用返回 `None` 导致的崩溃。
  - 撤销栈覆盖补齐：`ListeningTeacherWidget` / `ReadingTeacherWidget` /
    `MasteryTeacherWidget` 中的题目 add/delete/move/change-type/AI-rewrite 全部
    走 `AddItemCommand` / `DeleteItemCommand` / `MoveItemCommand` /
    `ReplaceItemCommand`；听力阶段 add/delete/rename/move 使用新增的
    `AddListeningPhaseCommand` / `DeleteListeningPhaseCommand` /
    `MoveListeningPhaseCommand` / `RenameListeningPhaseCommand`。
  - Wizard 与 AI 导入纳入 undo：`AppendLessonCommand` 让向导建课可撤销；
    `ImportAiSectionCommand` / `AiEditSectionCommand` / `AiEditUnitCommand` /
    `AiEditLessonCommand` 把 `merge_section_resources()` 收进 redo，undo 时
    精确回滚本次新增的词/表达/语法资源。
  - AI API 配置持久化：`MainWindow` 启动时从 `QSettings` 加载，关闭 AI 对话框
    后写回；配置对象在内存中原地更新，保证教师视图共享同一份设置。
  - 异常不再静默吞掉：`CourseAdapter.notify_resources_changed()` 和
    `DetailPanel._on_resources_changed()` 用 `logging.exception` 记录错误，
    保留容错但保留诊断信息。
- `tool/gui` Phase 3 创造性 + 易用性提升：
  - AI 改写助手接入教师视图：`SubLessonFlowWidget` 顶部「🤖 AI 改写本课」可基于
    教师指令改写整门 lesson；Listening/Reading/Mastery 模板编辑器顶部共用
    「🤖 AI 改写」；每道题目卡片右上角「🤖」支持单题改写/扩展。AI 输出保留
    id/template 并通过 `api.validate_lesson` / `lesson_content.normalize_item`
    校验，结果以 `AiEditLessonCommand` / `ReplaceItemCommand` 压入统一撤销栈。
  - 撤销/Redo 补全：新增 `Add/Delete/Rename/Move` 命令覆盖 sub-lesson、stage、
    item，以及 `ReplaceItemCommand`，教师视图所有增删改移动均走 `QUndoStack`。
  - 拖拽排序：`LinearFlowWidget` 安装 `_DragDropFilter`，支持拖拽 sub-lesson
    header 重新排序（sub-lesson → sub-lesson），通过 `_handle_drop` 计算目标
    索引并压入 `MoveSubLessonCommand`。
  - 实时预览：`SubLessonFlowWidget` 增加「👁 实时预览」开关，折叠显示当前 lesson
    所有题目的 `_PreviewCard`，内容变更时自动刷新。
- `tool/gui` Phase 2 教师视图覆盖全部 6 种 canonical 模板：intro/practice/review 不再混用
  通用 LinearFlowWidget，改由 `SubLessonFlowWidget` 显示模板标签并支持一键生成助手
  （intro：从词库生成认识课；practice：选择词汇+题型组合批量生成练习；review：从词库
  生成复习）。listening/reading/mastery 保持原有专用编辑器。生成逻辑统一迁移到
  `tool/gui/src/backend/lesson_content.py` 并新增单元测试。
- App 内 AI 课程功能已与 Python GUI 端（`tool/gui/src/backend/ai_generator.py` +
  `ai_genre.py`）对齐：完整模板/题型/资源 schema prompt、genre 标签批量、
  资源自洽校验与 autoFix、`validateSection` + 1 次自愈重试、许愿模式（独立聊天页
  `AiWishChatPage` 多轮对齐 + 滑动确认条「Swipe to finalize」生成 + 通俗解释）。
  入口已从 Learn 右下 FAB 迁到 `StatAppBar` 右上 `auto_awesome` 图标直进聊天页，
  课程参数移到页面 AppBar 齿轮按钮的底部弹层；普通模式/编辑模式与可编辑 JSON 已移除
  （`AiCourseGeneratorPage` 删除）；API 配置移到 Settings 页 AI 区块。不含编辑模式。
- 资源持久化：AI 生成的顶层 `words` / `expressions` / `grammarPoints` 现随 section
  一并写入 `CourseDatabase` 的 `vocabulary` / `expressions` / `grammarPoints` 表
  （`insertOnConflictUpdate`，已存在 id 跳过），与 DatabaseSeeder 合并语义一致。
- 模块化重构：`lib/application/ai/` 子目录承载 `AiApiConfig` / `AiCourseSpec` /
  `ai_genre` / `ai_prompt_builder` / `ai_resource_consistency` /
  `ai_course_service` / `ai_course_provider` / `ai_wish_provider`。原
  `lib/application/ai_course_*.dart` 已删除。
- 新增 24 个核心逻辑单测：`test/application/ai/`（genre 解析、prompt 构建、资源自洽/
  autoFix、parseCompletion + retry Mock HTTP）。
- 许愿模式本轮不支持附件（图片/PDF/Word），仅纯文本多轮对齐。
- Turkish course (`assets/courses/turkish/`) now ships **8 sections** with the
  CEFR progression A1/A1/A1/A2/B1/B1/B2/B2, wired with inter-section
  prerequisites. Section 1 ships a real **intro greetings lesson** (`s1-l2`,
  template `intro`, 3 subLessons: meet words / choose / practice) backed by
  8 vocab words + 2 expressions. Sections 2–8 are metadata-only placeholders
  (1 unit / 1 legacy MCQ lesson each, no vocab refs); full content authoring
  is a future round.
- Grammar points intentionally empty (`grammar_points.json`); this keeps a
  legitimately-empty table for the seeder-idempotent "empty table ≠ reseed"
  regression path.
- `seeder_idempotent_test.dart` asserts vocab + expressions are non-empty
  (real content) while grammar is empty; `course_cli_test.py` asserts the
  vocab CSV has a header + data rows (e.g. `w-merhaba`).
- Piper Swahili TTS + `sherpa_onnx` removed; TTS is system/Google `'tr'` only.

## Previous baselines
- 错题复习 + 二按钮复习 + SM-2 调优 = 411 (all pass); AI align with GUI = 409 (404 non-golden pass; 8 golden env-diff); MiniMax migration = 385; Pre-pivot = 373; Phase 24 = 372; Phase 23 = 358; Phase 22 = 350; Phase 21 = 342.