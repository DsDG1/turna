"""E3-B1 optional LLM goal expand (default off).

Maps free-text goals onto a short list of ACTION ids; host rebuilds a
local plan from those foci. Never auto-merges; never writes the tree.

红线：默认关；observer 零；低置信 / 解析失败 → None（回落 local expand）。
"""
from __future__ import annotations

import json
import re
from typing import Any, Mapping

from src.backend.experience.planner import GoalPlan, expand_goal_local, plan_from_context

GOAL_LLM_MIN_CONFIDENCE = 0.55

_CODE_FENCE_RE = re.compile(
    r"```(?:json)?\s*(\{.*?\})\s*```",
    re.DOTALL | re.IGNORECASE,
)

# Closed skill ids the model may propose (must exist in ACTIONS).
_ALLOWED_FOCUS = frozenset(
    {
        "validate.open_and_fix",
        "lesson.fill_empty",
        "resource.fill_stubs",
        "listening.fill_gaps",
        "quality.campaign_worst_n",
        "soft.preview_hygiene",
        "lesson.balance",
    }
)


def is_goal_llm_enabled(settings: Any | None = None) -> bool:
    """True only when goal enabled AND goal_llm flag AND not observer."""
    try:
        from src.backend.experience.policy import resolve_policy

        pol = resolve_policy(settings)
        if not getattr(pol, "allow_goal", False):
            return False
        if settings is None:
            return False
        return bool(getattr(settings, "experience_goal_llm", False))
    except Exception:
        return False


def _count_of(value: Any) -> int:
    try:
        return len(value)  # type: ignore[arg-type]
    except Exception:
        return 0


def build_health_summary(ctx: Any) -> str:
    """Closed-set COUNT summary of Context health for the expand prompt.

    Counts only — never raw lesson text, terms, or secrets (§14.5.3).
    Never raises; returns "" on any failure.
    """
    try:

        def _get(name: str, default: Any = None) -> Any:
            try:
                if ctx is None:
                    return default
                if isinstance(ctx, Mapping):
                    return ctx.get(name, default)
                return getattr(ctx, name, default)
            except Exception:
                return default

        def _int(value: Any) -> int:
            try:
                return int(value or 0)
            except Exception:
                return 0

        errors = _int(_get("validate_error_count", 0))
        warnings = _int(_get("validate_warning_count", 0))
        empty = _get("empty_lesson_count", None)
        if empty is None:
            empty = _count_of(_get("empty_lessons", []) or [])
        empty = _int(empty)
        hygiene = _get("hygiene", {}) or {}
        placeholders = 0
        if isinstance(hygiene, Mapping):
            placeholders = _int(hygiene.get("placeholder_count", 0))
        listening = _count_of(_get("listening_gaps", []) or [])
        imbalanced = _count_of(_get("imbalanced_lessons", []) or [])
        return (
            f"errors={errors}, warnings={warnings}, "
            f"empty_lessons={empty}, placeholders={placeholders}, "
            f"listening_gaps={listening}, imbalanced={imbalanced}"
        )
    except Exception:
        return ""


def parse_expand_response(raw: str | None) -> list[str] | None:
    """Parse model JSON ``{\"actions\":[...],\"confidence\":0.7}`` → action ids."""
    if not raw or not str(raw).strip():
        return None
    text = str(raw).strip()
    m = _CODE_FENCE_RE.search(text)
    if m:
        text = m.group(1)
    try:
        # Find first JSON object
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            return None
        data = json.loads(text[start : end + 1])
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    try:
        conf = float(data.get("confidence") or 0)
    except Exception:
        conf = 0.0
    if conf < GOAL_LLM_MIN_CONFIDENCE:
        return None
    actions = data.get("actions") or data.get("action_ids") or []
    if not isinstance(actions, list):
        return None
    out: list[str] = []
    for a in actions:
        aid = str(a or "").strip()
        if aid in _ALLOWED_FOCUS and aid not in out:
            out.append(aid)
        if len(out) >= 6:
            break
    return out or None


def expand_goal_with_llm(
    ctx: Any,
    goal_text: str,
    *,
    settings: Any | None = None,
    chat_fn: Any | None = None,
) -> GoalPlan:
    """Try LLM expand; always fall back to expand_goal_local. Never raises."""
    local = expand_goal_local(ctx, goal_text=goal_text)
    if not is_goal_llm_enabled(settings):
        return local
    if chat_fn is None:
        return local
    try:
        health = build_health_summary(ctx)
        prompt = (
            "You map a language-course authoring goal to skill action ids.\n"
            f"Allowed ids: {sorted(_ALLOWED_FOCUS)}\n"
            f"Course health counts: {health or 'unknown'}\n"
            f"Goal: {goal_text or '(improve course health)'}\n"
            'Reply JSON only: {"actions":["lesson.fill_empty"],"confidence":0.0-1.0}'
        )
        raw = chat_fn(prompt)
        actions = parse_expand_response(raw if isinstance(raw, str) else None)
        if not actions:
            local.notes = list(local.notes or [])
            local.notes.append("LLM expand 回落 local（低置信或解析失败）")
            return local
        # Build keyword-style plan by synthesizing goal with first keyword per action
        keyword_map = {
            "validate.open_and_fix": "修校验",
            "lesson.fill_empty": "填空课",
            "resource.fill_stubs": "清待补",
            "listening.fill_gaps": "补听力",
            "quality.campaign_worst_n": "低质战役",
            "soft.preview_hygiene": "规则规范化",
            "lesson.balance": "题型配比",
        }
        synthetic = " ".join(keyword_map.get(a, a) for a in actions)
        plan = plan_from_context(ctx, goal_text=synthetic, max_fill_lessons=8, max_steps=16)
        plan.goal_text = goal_text or plan.goal_text
        plan.source = "llm"
        plan.notes = list(plan.notes or [])
        plan.notes.insert(0, f"LLM expand actions={actions}")
        if not plan.steps:
            local.notes = list(local.notes or [])
            local.notes.append("LLM expand 无步骤，回落 local")
            return local
        return plan
    except Exception as exc:
        local.notes = list(local.notes or [])
        local.notes.append(f"LLM expand 异常回落：{exc.__class__.__name__}")
        return local
