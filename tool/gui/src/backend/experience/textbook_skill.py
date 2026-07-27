"""K-22 Textbook Experience skills — pure helpers (v4.58).

No Qt. Does not re-implement knowledge extraction; only closed-set readiness
and instruction builders for Experience Dock / handlers.
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence


def draft_import_ready(ctx: Any) -> bool:
    """True when workshop draft exists and has not been imported yet."""
    try:
        draft = getattr(ctx, "workshop_draft", None) or {}
        if not isinstance(draft, Mapping):
            return False
        if not draft.get("has_draft"):
            return False
        if draft.get("has_imported"):
            return False
        return True
    except Exception:
        return False


def build_import_suggestion(ctx: Any) -> dict[str, Any] | None:
    """P2 Dock suggestion for importing workshop draft. Scope closed-set."""
    try:
        if not draft_import_ready(ctx):
            return None
        draft = getattr(ctx, "workshop_draft", None) or {}
        count = int(draft.get("draft_section_count") or 0) or 1
        scope: dict[str, Any] = {
            "count": count,
            "ui_stage": int(draft.get("ui_stage") or 0),
        }
        pid = draft.get("project_id")
        if pid:
            scope["project_id"] = str(pid)[:64]
        return {
            "priority": 2,
            "title": f"导入工坊草稿（{count} 节）",
            "action_id": "textbook.import_draft",
            "scope": scope,
        }
    except Exception:
        return None


def build_grounded_instruction(
    attachments: Sequence[Mapping[str, Any]] | None,
    *,
    language: str = "Turkish",
) -> str:
    """Instruction fragment listing attachment kinds/counts only (no body text)."""
    try:
        rows = list(attachments or [])
        if not rows:
            return (
                f"Fill this empty lesson for {language} learners. "
                "Keep lesson id and existing structure ids unchanged."
            )
        kinds: dict[str, int] = {}
        ref_ids: list[str] = []
        for a in rows[:20]:
            if not isinstance(a, Mapping):
                continue
            k = str(a.get("kind") or "other")
            kinds[k] = kinds.get(k, 0) + 1
            rid = str(a.get("ref_id") or "").strip()
            if rid:
                ref_ids.append(rid[:24])
        kind_bits = ", ".join(f"{k}×{n}" for k, n in sorted(kinds.items()))
        refs = ",".join(ref_ids[:12])
        return (
            f"Fill this empty lesson for {language} learners grounded on "
            f"workshop attachments ({kind_bits}; refs={refs}). "
            "Use attachment material as topical constraint only; "
            "do not invent unrelated themes. "
            "Keep lesson id and existing structure ids unchanged."
        )
    except Exception:
        return (
            "Fill this empty lesson. Keep lesson id and structure ids unchanged."
        )


def grounded_fill_ready(ctx: Any) -> bool:
    """True when there is an empty lesson focus and attachments snapshot."""
    try:
        empty = int(getattr(ctx, "empty_lesson_count", 0) or 0)
        if empty <= 0:
            # still allow if selection is empty lesson via empty_lessons list
            els = list(getattr(ctx, "empty_lessons", None) or [])
            if not els:
                return False
        atts = list(getattr(ctx, "attachments", None) or [])
        return bool(atts)
    except Exception:
        return False


def build_grounded_fill_suggestion(ctx: Any) -> dict[str, Any] | None:
    try:
        if not grounded_fill_ready(ctx):
            return None
        atts = list(getattr(ctx, "attachments", None) or [])
        n = len(atts)
        return {
            "priority": 2,
            "title": f"基于 {n} 个附件填充空课",
            "action_id": "textbook.grounded_fill",
            "scope": {"attachment_count": n},
        }
    except Exception:
        return None
