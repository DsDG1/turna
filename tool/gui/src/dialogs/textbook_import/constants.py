"""Step / strategy constants for the textbook import wizard."""
from __future__ import annotations

from src.backend.import_strategy import ImportStrategy


# Import-strategy radio options shown on the import page (bookplan2 Phase 4).
_STRATEGY_OPTIONS = (
    (ImportStrategy.MERGE.value, "合并预览（交互逐章确认）"),
    (ImportStrategy.SKIP_EXISTING.value, "跳过已存在 section"),
    (ImportStrategy.FORCE_REPLACE.value, "覆盖已存在 section"),
    (ImportStrategy.APPEND_AS_NEW.value, "作为新 section 追加（自动改 id）"),
)

# Steps of the timeline. STEP_PARSE is kept for project.json compatibility
# (saved projects persist numeric current_step values) but has no page of its
# own — the parse preview lives inline on the source page (P0-4).
# Pages were reorganized into three stages in Phase 2 (connectplan §4.2):
# 素材 (pick + chapters) / 知识 (extract + review) / 导入.
STEP_PICK, STEP_PARSE, STEP_CHAPTERS, STEP_EXTRACT, STEP_REVIEW, STEP_IMPORT = range(6)
_PAGE_FOR_STEP = {
    STEP_PICK: 0,
    STEP_PARSE: 0,
    STEP_CHAPTERS: 0,
    STEP_EXTRACT: 1,
    STEP_REVIEW: 1,
    STEP_IMPORT: 2,
}
_STEPPER_STAGES = (STEP_CHAPTERS, STEP_EXTRACT, STEP_IMPORT)
_STEP_TITLES = {
    STEP_CHAPTERS: "① 素材",
    STEP_EXTRACT: "② 知识",
    STEP_IMPORT: "③ 导入",
}
