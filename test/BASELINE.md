# Test Baseline

Generated: 2026-07-14 (App 内 AI 课程功能对齐 GUI — 核心生成 + 许愿模式)

## Results
- `flutter test`: **409 total** — 404 non-golden passed; 8 golden pixel diffs (env-sensitive, pre-existing font-rendering variance, unrelated to AI work)
- `flutter analyze`: only info-level lint (no errors) — `DropdownButtonFormField.value` deprecation + `prefer_const` infos in new AI code
- Python: `python3 -m unittest discover -s test -p "*_test.py"` — 14 passed
- `tool/course_cli.py validate` passes against the 8-section Turkish course

## Notes
- App 内 AI 课程功能已与 Python GUI 端（`tool/gui/src/backend/ai_generator.py` +
  `ai_genre.py`）对齐：完整模板/题型/资源 schema prompt、genre 标签批量、
  资源自洽校验与 autoFix、`validateSection` + 1 次自愈重试、许愿模式（独立聊天页
  `AiWishChatPage` 多轮对齐 + 「我感觉差不多了」生成 + 通俗解释）。不含编辑模式。
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
- AI align with GUI = 409 (404 non-golden pass; 8 golden env-diff); MiniMax migration = 385; Pre-pivot = 373; Phase 24 = 372; Phase 23 = 358; Phase 22 = 350; Phase 21 = 342.