"""C-06: optional LLM intent classification for ⌘K (default off).

Pure Python, no Qt. Local ``route_intent`` / ``match_commands`` remain the
synchronous source of truth. This module only classifies **when local match
is empty**, maps free text onto the closed ``ACTIONS`` id set, and returns
``None`` on low confidence or parse failure (禁止瞎猜执行).

红线：
* 默认关；observer 零请求
* 置信 < LLM_INTENT_MIN_CONFIDENCE → None
* action_id 必须在允许闭集
* 不自动 dispatch；不写树；不记完整 prompt
"""
from __future__ import annotations

import json
import re
from typing import Any, Callable, Iterable

from src.backend.experience.intent_router import Intent
import logging
logger = logging.getLogger(__name__)

LLM_INTENT_MIN_CONFIDENCE = 0.55

_CODE_FENCE_RE = re.compile(
    r"```(?:json)?\s*(\{.*?\})\s*```",
    re.DOTALL | re.IGNORECASE,
)


def allowed_action_ids() -> frozenset[str]:
    """Closed set of classifiable action ids (implemented ACTIONS only)."""
    try:
        from src.backend.experience.actions import ACTIONS

        return frozenset(
            aid for aid, spec in ACTIONS.items() if getattr(spec, "implemented", True)
        )
    except Exception:
        return frozenset()


def is_llm_intent_enabled(
    settings: Any | None = None,
    *,
    usage_today: Any | None = None,
) -> bool:
    """True only when flag on **and** not observer (S-15 zero side-effects).

    Also respects M-08 budget when ``usage_today`` is provided (via policy).
    Delegates to ``policy.resolve_policy``; falls back to raw flag + mode.
    Never raises.
    """
    if settings is None:
        try:
            from src.application.runtime_context import current_settings

            settings = current_settings()
        except Exception:
            return False
    try:
        from src.backend.experience.policy import resolve_policy

        return bool(
            resolve_policy(settings, usage_today=usage_today).allow_llm_intent
        )
    except Exception:
        try:
            # Prefer presence_level semantics if resolve_policy partially failed above.
            mode = str(getattr(settings, "experience_mode", "copilot") or "")
            if mode.strip().lower() == "observer":
                return False
            return bool(getattr(settings, "experience_llm_intent", False))
        except Exception:
            return False


def build_classify_messages(
    text: str,
    allowed_ids: Iterable[str] | None = None,
) -> list[dict[str, str]]:
    """Short system+user messages; ask for a single JSON object."""
    ids = sorted(allowed_ids if allowed_ids is not None else allowed_action_ids())
    id_list = ", ".join(ids[:80])
    system = (
        "You are an intent classifier for a language-course editor command palette.\n"
        "Map the author's free-text request to exactly one action_id from the allowed list.\n"
        "Reply with ONLY a JSON object: "
        '{"action_id":"<id>","confidence":0.0-1.0,"label":"<short chinese optional>"}\n'
        "If nothing fits, reply {\"action_id\":null,\"confidence\":0}.\n"
        "Do not invent action ids. Do not explain."
    )
    user = (
        f"Allowed action_ids:\n{id_list}\n\n"
        f"Author text:\n{(text or '').strip()}\n"
    )
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def parse_classify_response(
    raw: Any,
    allowed_ids: Iterable[str] | None = None,
    *,
    min_confidence: float = LLM_INTENT_MIN_CONFIDENCE,
) -> Intent | None:
    """Parse model output into Intent or None. Never raises."""
    try:
        allowed = frozenset(
            allowed_ids if allowed_ids is not None else allowed_action_ids()
        )
        data = _extract_json_object(raw)
        if not isinstance(data, dict):
            return None
        action_id = data.get("action_id")
        if action_id is None or action_id == "":
            return None
        action_id = str(action_id).strip()
        if action_id not in allowed:
            return None
        try:
            conf = float(data.get("confidence", 0) or 0)
        except Exception:
            conf = 0.0
        if conf < 0:
            conf = 0.0
        if conf > 1:
            conf = 1.0
        if conf < float(min_confidence):
            return None
        label = str(data.get("label") or "").strip()
        if not label:
            label = _default_label(action_id)
        # Prefix so authors see LLM origin in the list.
        if not label.startswith("AI"):
            label = f"AI · {label}"
        return Intent(
            action_id=action_id,
            label=label,
            confidence=conf,
            scope={},
        )
    except Exception:
        return None


def classify_intent_sync(
    config: Any,
    text: str,
    *,
    allowed_ids: Iterable[str] | None = None,
    cancel_check: Callable[[], bool] | None = None,
    timeout: float = 20.0,
    max_tokens: int = 120,
    temperature: float = 0.0,
) -> Intent | None:
    """Call chat model; return Intent or None. Never raises to caller."""
    t = (text or "").strip()
    if not t:
        return None
    if config is None or not getattr(config, "is_complete", False):
        return None
    ids = frozenset(allowed_ids if allowed_ids is not None else allowed_action_ids())
    if not ids:
        return None
    try:
        from src.backend.ai import request_chat

        messages = build_classify_messages(t, ids)
        model = None
        try:
            # Prefer cheap chat model when configured.
            if hasattr(config, "select_model"):
                model = config.select_model("chat")
        except Exception:
            model = None
        body = request_chat(
            config,
            messages,
            temperature=temperature,
            timeout=timeout,
            cancel_check=cancel_check,
            max_tokens=max_tokens,
            model=model,
            response_format={"type": "json_object"},
        )
        content = _content_from_body(body)
        return parse_classify_response(content, ids)
    except Exception:
        return None


def _default_label(action_id: str) -> str:
    try:
        from src.backend.experience.actions import get_action

        spec = get_action(action_id)
        if spec is not None and spec.title:
            return str(spec.title)
    except Exception:
        logger.debug("backend/experience/intent_llm.py:_default_label best-effort step failed", exc_info=True)
    return action_id


def _content_from_body(body: Any) -> str:
    if isinstance(body, str):
        return body
    if not isinstance(body, dict):
        return ""
    try:
        choices = body.get("choices") or []
        if choices:
            msg = choices[0].get("message") or {}
            return str(msg.get("content") or "")
    except Exception:
        logger.debug("backend/experience/intent_llm.py:_content_from_body best-effort step failed", exc_info=True)
    return str(body.get("content") or "")


def _extract_json_object(raw: Any) -> dict[str, Any] | None:
    if isinstance(raw, dict):
        return raw
    text = str(raw or "").strip()
    if not text:
        return None
    # Direct JSON
    try:
        obj = json.loads(text)
        if isinstance(obj, dict):
            return obj
    except Exception:
        logger.debug("backend/experience/intent_llm.py:_extract_json_object best-effort step failed", exc_info=True)
    # Fenced ```json ... ```
    m = _CODE_FENCE_RE.search(text)
    if m:
        try:
            obj = json.loads(m.group(1))
            if isinstance(obj, dict):
                return obj
        except Exception:
            logger.debug("backend/experience/intent_llm.py:_extract_json_object best-effort step failed", exc_info=True)
    # First {...} slice
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        try:
            obj = json.loads(text[start : end + 1])
            if isinstance(obj, dict):
                return obj
        except Exception:
            logger.debug("backend/experience/intent_llm.py:_extract_json_object best-effort step failed", exc_info=True)
    return None
