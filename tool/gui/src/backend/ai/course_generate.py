"""High-level course generation helpers (retry, chat, explain, edit).

Extracted from ``ai_generator`` (M1 refactor).
"""
from __future__ import annotations

from typing import Any, Callable

from src.backend.ai.client import chat_json
from src.backend.ai.config import (
    SYSTEM_AUTHORING,
    SYSTEM_AUTHORING_CHAT,
    SYSTEM_AUTHORING_EDIT,
    SYSTEM_EDITING,
    AiApiConfig,
    AiCourseSpec,
    ChatMessage,
)
from src.backend.ai.parse import content_text, extract_content, parse_completion
from src.backend.ai.prompts import (
    _draft_json_suffix as draft_json_suffix,
    build_alignment_prompt,
    build_edit_prompt,
    build_prompt,
    build_response_format,
)
from src.backend.ai.section_ops import fill_needs_review_resources
from src.backend.ai.validate_loop import generate_with_validate_loop

_extract_content = extract_content

def request_course_with_retry(
    config: AiApiConfig,
    spec: AiCourseSpec,
    validator,
    timeout: float = 120.0,
    max_retries: int = 1,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    fill_needs_review: bool = False,
) -> dict:
    """Generate a course and, if ``validator(section_json)`` reports errors,
    re-prompt the model with those errors up to ``max_retries`` times (C3).

    ``validator`` is a callable ``(section_json: dict) -> list[dict] | list[str]``
    returning either Problem dicts (with ``level``/``message``) or plain error
    strings; empty == valid. Problem dicts whose ``level`` is not ``"error"``
    (e.g. warnings) are not re-fed to the model. The original generation is
    retried by appending an assistant turn (the last JSON) plus a correction
    turn to the conversation.

    When ``fill_needs_review`` is True, a cheap second pass tries to replace
    ``[待补]`` / needs-review stubs after a successful generate+validate loop.
    """
    messages = [
        {
            "role": "system",
            "content": SYSTEM_AUTHORING
        },
        {"role": "user", "content": build_prompt(spec)},
    ]
    section = generate_with_validate_loop(
        config,
        messages,
        validator,
        max_retries=max_retries,
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=config.select_model("json"),
    )
    if fill_needs_review:
        section = fill_needs_review_resources(
            config,
            section,
            language=spec.language,
            source_language=spec.source_language,
            timeout=min(timeout, 90.0),
            cancel_check=cancel_check,
            usage_callback=usage_callback,
        )
    return section


def request_alignment_reply(
    config: AiApiConfig,
    spec: AiCourseSpec,
    messages: list[ChatMessage],
    timeout: float = 120.0,
    temperature: float = 0.7,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> str:
    """Get a plain-language alignment reply from the AI.

    ``messages`` must not include the system prompt; it will be prepended.

    第三枪 批次①: routes through ``model_chat`` when configured (alignment is a
    conversational call, not JSON generation).
    """
    api_messages = [
        {"role": "system", "content": build_alignment_prompt(spec)}
    ] + [m.to_api_dict() for m in messages]
    body = chat_json(
        config, api_messages, temperature=temperature, timeout=timeout,
        cancel_check=cancel_check, on_chunk=on_chunk,
        usage_callback=usage_callback, response_format=False,
        model=config.select_model("chat"),
    )
    content = _extract_content(body)
    return content.strip()


def generate_from_chat(
    config: AiApiConfig,
    spec: AiCourseSpec,
    messages: list[ChatMessage],
    draft_json: dict[str, Any] | None = None,
    timeout: float = 180.0,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    validator: Callable[[dict], Any] | None = None,
    max_retries: int = 0,
    fill_needs_review: bool = False,
) -> dict:
    """Generate the final course section JSON from the conversation history.

    If ``draft_json`` is provided, it is included as context so the model can
    produce a modified version of the course.

    ``validator`` / ``max_retries`` default to off so existing callers keep
    single-shot behaviour; pass a validator and ``max_retries>=1`` to enable
    the shared validate loop.
    """
    generation_prompt = build_prompt(spec)
    if draft_json is not None:
        generation_prompt += draft_json_suffix(draft_json)

    api_messages = [
        {
            "role": "system",
            "content": SYSTEM_AUTHORING_CHAT,
        }
    ] + [m.to_api_dict() for m in messages]
    api_messages.append({"role": "user", "content": generation_prompt})

    section = generate_with_validate_loop(
        config,
        api_messages,
        validator,
        max_retries=max_retries,
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=config.select_model("json"),
    )
    if fill_needs_review:
        section = fill_needs_review_resources(
            config,
            section,
            language=spec.language,
            source_language=spec.source_language,
            timeout=min(timeout, 90.0),
            cancel_check=cancel_check,
            usage_callback=usage_callback,
        )
    return section


def explain_course(
    config: AiApiConfig,
    spec: AiCourseSpec,
    section_json: dict[str, Any],
    timeout: float = 120.0,
    temperature: float = 0.6,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> str:
    """Ask the AI to explain the generated course in plain language.

    第三枪 批次①: routes through ``model_chat`` when configured (explanation is
    a conversational call, not JSON generation).
    """
    prompt = (
        "你刚刚为一位没有技术背景的教师生成了以下课程。"
        "请用通俗易懂的中文简要解释这门课的教学目标、单元划分、重点词汇/句型，"
        "以及为什么这样设计。不要输出 JSON 或代码。\n\n"
        f"课程语言：{spec.language}\n"
        f"提示语言：{spec.source_language}\n"
        f"等级：{spec.level}\n"
        f"课程名称：{section_json.get('name', '')}\n"
        f"课程描述：{section_json.get('description', '')}\n"
    )
    api_messages = [
        {"role": "system", "content": "你是语言课程设计助手，用中文通俗解释课程内容。"},
        {"role": "user", "content": prompt},
    ]
    body = chat_json(
        config, api_messages, temperature=temperature, timeout=timeout,
        cancel_check=cancel_check, on_chunk=on_chunk,
        usage_callback=usage_callback, response_format=False,
        model=config.select_model("chat"),
    )
    content = _extract_content(body, strip=True, empty_msg="AI 未返回解释")
    if not content:
        raise ValueError("AI 未返回解释")
    return content

def generate_edit(
    config: AiApiConfig,
    spec: AiCourseSpec,
    existing_section: dict[str, Any],
    edit_scope: str,
    scope_id: str,
    messages: list[ChatMessage] | None = None,
    draft_json: dict[str, Any] | None = None,
    timeout: float = 180.0,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    validator: Callable[[dict], Any] | None = None,
    max_retries: int = 0,
) -> dict:
    """Generate an edited section JSON based on an existing section.

    In normal mode ``messages`` is None and the edit prompt is the sole user
    turn. In wish mode the conversation history is prepended and the edit
    prompt is appended as the final user turn (so the model incorporates the
    teacher's latest instructions).

    Optional ``validator`` / ``max_retries`` use the shared validate loop
    (default off for backward-compatible single-shot edits).
    """
    edit_prompt = build_edit_prompt(spec, existing_section, edit_scope, scope_id)
    if draft_json is not None:
        edit_prompt += draft_json_suffix(draft_json)

    api_messages: list[dict[str, Any]] = [
        {
            "role": "system",
            "content": SYSTEM_AUTHORING_EDIT,
        }
    ]
    if messages:
        api_messages += [m.to_api_dict() for m in messages]
    api_messages.append({"role": "user", "content": edit_prompt})

    parsed = generate_with_validate_loop(
        config,
        api_messages,
        validator,
        max_retries=max_retries,
        temperature=temperature,
        timeout=timeout,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        model=config.select_model("json"),
    )
    # In edit mode the returned section must keep the same id.
    existing_id = existing_section.get("id", "")
    if existing_id and parsed.get("id") != existing_id:
        parsed["id"] = existing_id
    return parsed

