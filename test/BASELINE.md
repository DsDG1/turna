# Test Baseline

Generated: 2026-07-15 (code-review 第二轮修复：ShowWord 未知类型 sentinel 不再渲染为字面词/TTS（改渲染占位卡片）+ ShowWord 语义节点拆分（朗读动作对读屏可达）、SRS notify 改回写盘前同步（去掉每张卡的热路径延迟）、study_log 合并缓存命中读绕过写链（仅 cache-miss 串行化）、reasoning 能力从主机推断改为 AiApiConfig.supportsReasoning 声明字段（Dart+Python 双端）、_completedItemCount 合并为 _questionResults.length 单一真相、抽取共享 ChatBubble、core/utils.enumByName 收敛 byName 回退、SRS persist/clear 写盘逻辑收敛到 _writeState)

## Results
- `flutter test`: **445 total** — all passed (新增 enumByName 3 + AiApiConfig reasoning 5 + reasoning override 2)
- `flutter analyze`: only info-level lint (no errors/warnings from new code) — `DropdownButtonFormField.value` deprecation + `prefer_const` infos (pre-existing)
- Python: `python3 -m unittest discover -s test -p "*_test.py"` — 14 passed; `tool/gui` suite (from `tool/gui`: `python3 -m unittest discover -s . -p "test_*.py"`) — 210 passed (新增 reasoning_enabled 回退/覆盖 2 + request_chat supports_reasoning 覆盖 2)
- `tool/course_cli.py validate` passes against the 8-section Turkish course

## Notes
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