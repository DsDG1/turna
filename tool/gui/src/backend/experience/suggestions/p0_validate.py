"""P0 structural validate suggestions."""
from __future__ import annotations
from typing import Any

def collect(ctx) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if ctx.validate_error_count > 0:
        out.append(
            {
                "priority": 0,
                "title": f"修复 {ctx.validate_error_count} 个校验错误",
                "action_id": "validate.open_and_fix",
                "scope": {"error_count": ctx.validate_error_count},
            }
        )
    return out
