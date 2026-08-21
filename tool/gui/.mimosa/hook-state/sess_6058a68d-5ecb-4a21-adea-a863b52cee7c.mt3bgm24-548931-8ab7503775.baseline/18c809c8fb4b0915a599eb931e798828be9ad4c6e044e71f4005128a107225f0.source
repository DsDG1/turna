"""P2 textbook / workshop draft suggestions (K-22 / v4.58)."""
from __future__ import annotations

from typing import Any


def collect(ctx: Any) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    try:
        from src.backend.experience.textbook_skill import (
            build_grounded_fill_suggestion,
            build_import_suggestion,
        )

        imp = build_import_suggestion(ctx)
        if imp:
            out.append(imp)
        g = build_grounded_fill_suggestion(ctx)
        if g:
            out.append(g)
    except Exception:
        return []
    return out
