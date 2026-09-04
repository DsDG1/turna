"""M-05 screenshot-explain skill (pure Python, no Qt).

Read-only Experience skill: captures the main editor window (done by the
application-layer controller via Qt ``grab()``), builds an OpenAI-compatible
``image_url`` chat message, and asks the chat model for a natural-language
explanation of the current editor state. The reply is shown in a read-only
preview dialog (mirrors K-24 ``git_skill``); nothing is written to the course
tree — no ConflictGuard, no sandbox, no undo, no ``dangerous`` flag.

红线（§14.5.3 M-05）：
* 纯函数构造 messages / 抽取回复；无 Qt、不写树、不写盘。
* 截图 PNG / base64 / 回复全文一律不进 Timeline/telemetry —— 只记
  ``action_id`` + ``truncate_reply``（≤80 字）短摘要。
* 永不抛：坏输入归一为空串/状态，对齐 §14.5.2 失败安全默认。
"""
from __future__ import annotations

import base64
from typing import Any, Literal, Sequence
import logging
logger = logging.getLogger(__name__)

# Max chars of the explanation reply kept for the Timeline short summary.
REPLY_SUMMARY_MAX_CHARS = 80

# Fixed user prompt (read-only; no tree writes). Kept constant so the skill
# never invents a mutating instruction.
_SCREENSHOT_PROMPT = (
    "请基于这张课程编辑器截图，用自然语言简述当前编辑状态、潜在问题与改进建议。"
    "不要逐区域复述截图内容。"
)

_SCREENSHOT_SYSTEM = (
    "你是课程编辑器的可视化审阅助手。基于给出的编辑器截图，用自然语言简述当前"
    "编辑状态、潜在的结构/内容问题与可操作的改进建议，分点说明。"
)

ScreenshotStatus = Literal["ok", "disabled", "no_window", "no_config", "failed"]


def is_screenshot_explain_enabled(settings: Any) -> bool:
    """True only when the ``experience/screenshot_explain`` switch is on.

    Reads ``experience_screenshot_explain`` from a settings object/dataclass
    (or Mapping); never raises — missing/false → False (default off).
    """
    try:
        if settings is None:
            return False
        if isinstance(settings, dict) or hasattr(settings, "__getitem__"):
            try:
                return bool(settings.get("experience_screenshot_explain", False))
            except Exception:
                logger.debug("backend/experience/screenshot_skill.py:is_screenshot_explain_enabled best-effort step failed", exc_info=True)
        return bool(getattr(settings, "experience_screenshot_explain", False))
    except Exception:
        return False


def png_bytes_to_data_url(png_bytes: bytes) -> str:
    """PNG bytes → ``data:image/png;base64,...`` URL. Never raises."""
    try:
        encoded = base64.b64encode(bytes(png_bytes or b"")).decode("ascii")
    except Exception:
        encoded = ""
    return f"data:image/png;base64,{encoded}" if encoded else ""


def build_screenshot_messages(
    png_bytes: bytes,
    *,
    prompt: str | None = None,
) -> list[dict[str, Any]]:
    """Build OpenAI-compatible chat messages for screenshot explanation.

    The user message carries both a text prompt and an ``image_url`` content
    piece. Empty/invalid PNG → text-only message with a note (the model still
    answers, degraded). Never raises.
    """
    text = str(prompt) if prompt is not None else _SCREENSHOT_PROMPT
    data_url = png_bytes_to_data_url(png_bytes)
    if data_url:
        content: list[dict[str, Any]] = [
            {"type": "text", "text": text},
            {"type": "image_url", "image_url": {"url": data_url}},
        ]
    else:
        content = [{"type": "text", "text": f"{text}\n\n（截图缺失或为空）"}]
    return [
        {"role": "system", "content": _SCREENSHOT_SYSTEM},
        {"role": "user", "content": content},
    ]


def run_screenshot_skill(
    config: Any,
    png_bytes: bytes,
    prompt: str | None = None,
) -> str:
    """Run the screenshot skill via ``request_chat``; return plain-text reply.

    Raises ``RuntimeError`` on network/parse failure (propagated by the worker
    as ``error_occurred``). Pure: no Qt, no tree writes.
    """
    from src.backend.ai_generator import content_text, request_chat

    messages = build_screenshot_messages(png_bytes, prompt=prompt)
    body = request_chat(config, messages, temperature=0.4)
    choices = (body or {}).get("choices") or []
    if not choices:
        return ""
    msg = (choices[0].get("message") or {}).get("content")
    return content_text(msg)


def truncate_reply(text: Any, limit: int = REPLY_SUMMARY_MAX_CHARS) -> str:
    """Short summary for Timeline/telemetry (§14.5.3 — never the full reply)."""
    s = str(text or "").strip().replace("\n", " ")
    if len(s) <= limit:
        return s
    return s[:limit] + "…"