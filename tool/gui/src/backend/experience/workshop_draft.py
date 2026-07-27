"""Workshop draft snapshot for ExperienceContext (E5 / M3).

Pure Python, no Qt. Builds a small JSON-safe dict that the main-window
Context Bus can carry so Dock / lifecycle share one view of the workshop
without a second truth tree.

``None`` means idle (no open workshop project / window not relevant).
"""
from __future__ import annotations

from typing import Any, Mapping, Sequence


# Closed key set for Context / Dock / telemetry (no free-form blobs).
WORKSHOP_DRAFT_KEYS = frozenset(
    {
        "project_id",
        "project_name",
        "ui_stage",
        "has_material",
        "has_knowledge",
        "has_draft",
        "has_imported",
        "draft_section_count",
        "imported_section_ids",
        "open",
    }
)


def build_workshop_draft(
    *,
    open: bool = False,
    project_id: str | None = None,
    project_name: str | None = None,
    ui_stage: int = 0,
    has_material: bool = False,
    has_knowledge: bool = False,
    has_draft: bool = False,
    has_imported: bool = False,
    draft_section_count: int = 0,
    imported_section_ids: Sequence[str] | None = None,
) -> dict[str, Any] | None:
    """Assemble a workshop_draft dict, or ``None`` when idle.

    Idle = not open **and** no project_id. A closed window with no project
    must not leave a stale draft on Context.
    """
    try:
        pid = (str(project_id).strip() if project_id is not None else "") or None
        is_open = bool(open)
        if not is_open and not pid:
            return None

        ids: list[str] = []
        for x in imported_section_ids or []:
            s = str(x or "").strip()
            if s and s not in ids:
                ids.append(s)

        return {
            "project_id": pid,
            "project_name": (str(project_name).strip() if project_name else "") or None,
            "ui_stage": int(ui_stage or 0),
            "has_material": bool(has_material),
            "has_knowledge": bool(has_knowledge),
            "has_draft": bool(has_draft),
            "has_imported": bool(has_imported) or bool(ids),
            "draft_section_count": max(0, int(draft_section_count or 0)),
            "imported_section_ids": ids,
            "open": is_open,
        }
    except Exception:
        return None


def normalize_workshop_draft(raw: Mapping[str, Any] | None) -> dict[str, Any] | None:
    """Sanitize an arbitrary mapping into the closed draft shape (or None)."""
    if not raw or not isinstance(raw, Mapping):
        return None
    try:
        return build_workshop_draft(
            open=bool(raw.get("open")),
            project_id=raw.get("project_id"),  # type: ignore[arg-type]
            project_name=raw.get("project_name"),  # type: ignore[arg-type]
            ui_stage=int(raw.get("ui_stage") or 0),
            has_material=bool(raw.get("has_material")),
            has_knowledge=bool(raw.get("has_knowledge")),
            has_draft=bool(raw.get("has_draft")),
            has_imported=bool(raw.get("has_imported")),
            draft_section_count=int(raw.get("draft_section_count") or 0),
            imported_section_ids=list(raw.get("imported_section_ids") or []),
        )
    except Exception:
        return None


def format_workshop_draft_line(draft: Mapping[str, Any] | None) -> str:
    """One Dock line for workshop state. Empty when idle. Never raises."""
    try:
        d = normalize_workshop_draft(draft) if draft else None
        if not d:
            return ""
        name = d.get("project_name") or d.get("project_id") or "工坊"
        marks = []
        if d.get("has_material"):
            marks.append("素材")
        if d.get("has_knowledge"):
            marks.append("知识")
        if d.get("has_draft"):
            n = int(d.get("draft_section_count") or 0)
            marks.append(f"草稿{n}" if n else "草稿")
        if d.get("has_imported"):
            marks.append("已导入")
        open_tag = "开" if d.get("open") else "关"
        body = " · ".join(marks) if marks else "进行中"
        return f"工坊[{open_tag}] {name} · {body}"
    except Exception:
        return ""
