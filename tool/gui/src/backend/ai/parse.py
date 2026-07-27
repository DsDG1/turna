"""Parse model completions into section JSON.

Extracted from ``ai_generator`` (M1 refactor).
"""
from __future__ import annotations

import json
from typing import Any

from src.backend.ai.resource_fix import (
    auto_fix_resources,
    check_resource_self_consistency,
    normalize_resources,
)

def strip_code_fences(text: str) -> str:
    s = text.strip()
    if s.startswith("```"):
        nl = s.find("\n")
        if nl >= 0:
            s = s[nl + 1 :]
        if s.endswith("```"):
            s = s[: -3]
    return s.strip()


def extract_content(
    body: dict, *, strip: bool = False, empty_msg: str = "API 返回的 choices 为空。"
) -> str:
    """Pull the assistant message content out of a chat-completion response body."""
    choices = body.get("choices") or []
    if not choices:
        raise ValueError(empty_msg)
    content = choices[0].get("message", {}).get("content", "")
    return content.strip() if strip else content


def parse_json_obj(content: str) -> dict:
    """Strip code fences and parse ``content`` as a JSON object (dict)."""
    cleaned = strip_code_fences(content)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ValueError(f"无法解析模型输出的 JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("模型输出不是 JSON 对象。")
    return parsed

def parse_completion(body: str | dict[str, Any]) -> dict:
    """Parse an OpenAI-compatible chat completion response body.

    Accepts either the raw response string or an already-parsed dict.
    Returns the decoded course JSON dict. Raises ``ValueError`` on malformed
    output so the dialog can surface a human-readable message.
    """
    if isinstance(body, dict):
        decoded = body
    else:
        try:
            decoded = json.loads(body)
        except json.JSONDecodeError as exc:
            raise ValueError(f"无法解析 API 响应 JSON: {exc}") from exc
    choices = decoded.get("choices") or []
    if not choices:
        raise ValueError("API 返回的 choices 为空。")
    message = choices[0].get("message") or {}
    content = message.get("content") or ""
    cleaned = strip_code_fences(content)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"无法解析模型输出的 JSON: {exc}\n原始内容前 200 字: {cleaned[:200]}"
        ) from exc
    if not isinstance(parsed, dict) or "units" not in parsed:
        raise ValueError("模型输出缺少顶层 'units' 数组。")
    normalize_resources(parsed)
    auto_fix_resources(parsed)
    check_resource_self_consistency(parsed)
    return parsed


def content_text(content: str | list[dict[str, Any]] | None) -> str:
    """Best-effort extract plain text from a message content for preview."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts: list[str] = []
    for piece in content:
        if isinstance(piece, dict):
            if piece.get("type") == "text":
                parts.append(str(piece.get("text", "")))
            elif piece.get("type") == "image_url":
                parts.append("[图片]")
    return "\n".join(parts)


# Back-compat aliases
_strip_code_fences = strip_code_fences
_extract_content = extract_content
_parse_json_obj = parse_json_obj
_content_text = content_text
