"""Compatibility shim re-exporting symbols from ``src.backend.ai``.

Split from the former monolithic ``ai_generator`` module (M1 refactor).
New code should import directly from ``src.backend.ai``.

Legacy monkeypatch note: ``urllib`` and ``request_chat`` remain exposed here
so existing test fixtures (e.g. mock.patch on ``src.backend.ai_generator``)
continue to work without modification.
"""
from __future__ import annotations

# Standard urllib module exposure for monkeypatch compatibility
import urllib
import urllib.error
import urllib.parse
import urllib.request

# Re-export public symbols from the authoritative backend/ai package
from src.backend.ai import (
    GenerateResult,
    PipelineOptions,
    SYSTEM_AUTHORING,
    SYSTEM_AUTHORING_CHAT,
    SYSTEM_AUTHORING_EDIT,
    SYSTEM_CORRECTION,
    SYSTEM_EDITING,
    AiApiConfig,
    AiCancelled,
    AiCourseSpec,
    ChatMessage,
    apply_genre_to_spec,
    auto_fix_resources,
    build_alignment_prompt,
    build_correction_user_turn,
    build_edit_prompt,
    build_prompt,
    build_response_format,
    chat_json,
    check_resource_self_consistency,
    coerce_problem_messages,
    content_text,
    detect_genre_from_spec,
    estimate_usage_from_messages,
    explain_course,
    extract_content,
    fill_listening_gaps,
    fill_needs_review_resources,
    full_section_diff,
    generate_course,
    generate_edit,
    generate_from_chat,
    generate_with_validate_loop,
    has_audio,
    has_listening_gap,
    iter_items,
    looks_like_json_schema_rejection,
    normalize_generation_mode,
    normalize_resources,
    parse_completion,
    parse_json_obj,
    read_streaming,
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
    request_alignment_reply,
    request_chat,
    request_correction,
    request_course_with_retry,
    request_item_transform,
    request_lesson_transform,
    splice_lesson,
    splice_lesson_in_place,
    strip_code_fences,
    structural_diff,
    verify_connection,
)

# Re-export genre and pedagogy helpers that were formerly in this module
from src.backend.ai_genre import (
    genre_prompt_block,
    genre_tags_in_text,
    genre_to_template,
    template_label,
)
from src.backend.ai_pedagogy import pedagogy_prompt_block

# Backward-compatibility private aliases for legacy call sites and tests
_auto_fix_resources = auto_fix_resources
_chat_json = chat_json
_coerce_problem_messages = coerce_problem_messages
_content_text = content_text
_extract_content = extract_content
_looks_like_json_schema_rejection = looks_like_json_schema_rejection
_normalize_resources = normalize_resources
_splice_lesson = splice_lesson
_splice_lesson_in_place = splice_lesson_in_place

from src.backend.ai.section_ops import build_local_regen_instruction as _build_local_regen_instruction
from src.backend.ai.prompts import _distribute_genres_to_lessons
