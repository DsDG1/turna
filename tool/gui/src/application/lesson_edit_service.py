"""Application facade for lesson editing, answer grading, and manifest helpers.

Keeps UI widgets/teacher modules from adding new direct UI -> backend imports
(preserving the ``max_ui_backend_imports`` ratchet in ``guard_limits.json``).
"""
from __future__ import annotations

from src.backend.answer_grading import (
    K_READ_ALOUD_PASS_RATIO,
    ReadAloudScore,
    ReadAloudWordOutcome,
    fold_turkish,
    matches_course_answer,
    matches_read_aloud_word,
    normalize_course_answer,
    sample_review_pool,
    score_read_aloud,
)
from src.backend.lesson_content import (
    GUIDE_BLOCK_LABELS,
    GUIDE_BLOCK_TYPES,
    add_guide_block,
    add_guide_page,
    default_guide_block,
    delete_guide_block,
    delete_guide_page,
    move_guide_block,
    move_guide_page,
    short_id,
)
from src.backend.manifest_service import (
    AUDIO_REVIEW_STATUSES,
    MEDIA_REVIEW_STATUSES,
    MediaAuditSummary,
    audit_audio_manifest_doc,
    audit_media_manifest,
    collect_course_media_references,
    load_audio_manifest_doc,
    load_media_manifest,
    register_missing_media_entries,
    resolve_asset_on_disk,
    save_audio_manifest_doc,
    save_media_manifest,
)

__all__ = [
    "AUDIO_REVIEW_STATUSES",
    "GUIDE_BLOCK_LABELS",
    "GUIDE_BLOCK_TYPES",
    "K_READ_ALOUD_PASS_RATIO",
    "MEDIA_REVIEW_STATUSES",
    "MediaAuditSummary",
    "ReadAloudScore",
    "ReadAloudWordOutcome",
    "add_guide_block",
    "add_guide_page",
    "audit_audio_manifest_doc",
    "audit_media_manifest",
    "collect_course_media_references",
    "default_guide_block",
    "delete_guide_block",
    "delete_guide_page",
    "fold_turkish",
    "load_audio_manifest_doc",
    "load_media_manifest",
    "matches_course_answer",
    "matches_read_aloud_word",
    "move_guide_block",
    "move_guide_page",
    "normalize_course_answer",
    "register_missing_media_entries",
    "resolve_asset_on_disk",
    "sample_review_pool",
    "save_audio_manifest_doc",
    "save_media_manifest",
    "score_read_aloud",
    "short_id",
]
