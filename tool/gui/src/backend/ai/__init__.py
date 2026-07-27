"""AI backend package (OpenAI-compatible course generation).

Split from the former monolithic ``ai_generator`` module (M1 refactor).
Prefer importing from this package or the compatibility shim
``src.backend.ai_generator`` (re-exports the same public API).
"""
from __future__ import annotations

from src.backend.ai.client import (
    chat_json,
    estimate_usage_from_messages,
    looks_like_json_schema_rejection,
    read_streaming,
    request_chat,
    verify_connection,
)
from src.backend.ai.config import (
    SYSTEM_AUTHORING,
    SYSTEM_AUTHORING_CHAT,
    SYSTEM_AUTHORING_EDIT,
    SYSTEM_CORRECTION,
    SYSTEM_EDITING,
    AiApiConfig,
    AiCancelled,
    AiCourseSpec,
    ChatMessage,
)
from src.backend.ai.course_generate import (
    explain_course,
    generate_edit,
    generate_from_chat,
    request_alignment_reply,
    request_course_with_retry,
)
from src.backend.ai.facade import (
    GenerateResult,
    PipelineOptions,
    generate_course,
    normalize_generation_mode,
)
from src.backend.ai.parse import (
    content_text,
    extract_content,
    parse_completion,
    parse_json_obj,
    strip_code_fences,
)
from src.backend.ai.prompts import (
    apply_genre_to_spec,
    build_alignment_prompt,
    build_edit_prompt,
    build_prompt,
    build_response_format,
    detect_genre_from_spec,
)
from src.backend.ai.resource_fix import (
    auto_fix_resources,
    check_resource_self_consistency,
    iter_items,
    normalize_resources,
)
from src.backend.ai.section_ops import (
    fill_listening_gaps,
    fill_needs_review_resources,
    full_section_diff,
    has_audio,
    has_listening_gap,
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
    request_correction,
    request_item_transform,
    request_lesson_transform,
    splice_lesson,
    splice_lesson_in_place,
    structural_diff,
)
from src.backend.ai.validate_loop import (
    build_correction_user_turn,
    coerce_problem_messages,
    generate_with_validate_loop,
)

# Transitional private aliases (tests / older call sites). Prefer public names.
_auto_fix_resources = auto_fix_resources
_chat_json = chat_json
_coerce_problem_messages = coerce_problem_messages
_content_text = content_text
_looks_like_json_schema_rejection = looks_like_json_schema_rejection
_normalize_resources = normalize_resources
_splice_lesson_in_place = splice_lesson_in_place

__all__ = [
    "AiApiConfig",
    "AiCancelled",
    "AiCourseSpec",
    "ChatMessage",
    "SYSTEM_AUTHORING",
    "SYSTEM_AUTHORING_CHAT",
    "SYSTEM_AUTHORING_EDIT",
    "SYSTEM_CORRECTION",
    "SYSTEM_EDITING",
    "apply_genre_to_spec",
    "auto_fix_resources",
    "build_alignment_prompt",
    "build_correction_user_turn",
    "build_edit_prompt",
    "build_prompt",
    "build_response_format",
    "chat_json",
    "check_resource_self_consistency",
    "coerce_problem_messages",
    "content_text",
    "detect_genre_from_spec",
    "explain_course",
    "fill_listening_gaps",
    "fill_needs_review_resources",
    "full_section_diff",
    "GenerateResult",
    "PipelineOptions",
    "generate_course",
    "generate_edit",
    "generate_from_chat",
    "generate_with_validate_loop",
    "normalize_generation_mode",
    "has_audio",
    "has_listening_gap",
    "iter_items",
    "normalize_resources",
    "parse_completion",
    "regenerate_lesson_in_section",
    "regenerate_unit_in_section",
    "request_alignment_reply",
    "request_chat",
    "request_correction",
    "request_course_with_retry",
    "request_item_transform",
    "request_lesson_transform",
    "splice_lesson",
    "splice_lesson_in_place",
    "structural_diff",
    "verify_connection",
]
