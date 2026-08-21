"""K-04 publish.brief — local release summary (no LLM).

Pure Python. Structural red must still block publish at the dialog/save
layer; this module only **describes** health for the author-facing brief.
"""
from __future__ import annotations

from typing import Any, Mapping


def build_publish_brief(
    ctx: Any | None = None,
    *,
    adapter: Any | None = None,
) -> dict[str, Any]:
    """Return a JSON-safe brief dict for PublishDialog.

    Keys: title, lines, error_count, warning_count, empty_lesson_count,
    placeholder_count, blocks_publish (True when structural errors > 0),
    summary (one line).
    Never raises.
    """
    try:
        err = 0
        warn = 0
        empty_n = 0
        ph = 0
        lessons = 0
        sections = 0
        yellow = ""

        if ctx is not None:
            err = int(getattr(ctx, "validate_error_count", 0) or 0)
            warn = int(getattr(ctx, "validate_warning_count", 0) or 0)
            empty_n = int(getattr(ctx, "empty_lesson_count", 0) or 0)
            lessons = int(getattr(ctx, "lesson_count", 0) or 0)
            sections = int(getattr(ctx, "section_count", 0) or 0)
            hygiene = getattr(ctx, "hygiene", None) or {}
            if isinstance(hygiene, Mapping):
                ph = int(hygiene.get("placeholder_count") or 0)
            try:
                from src.backend.experience.scope_format import yellow_quality_summary

                y = yellow_quality_summary(ctx)
                if isinstance(y, Mapping) and y.get("has_hints"):
                    yellow = str(y.get("message") or "")
            except Exception:
                yellow = ""
        elif adapter is not None:
            secs = list(getattr(adapter, "sections", None) or [])
            sections = len(secs)
            for sec in secs:
                if not isinstance(sec, Mapping):
                    continue
                for unit in sec.get("units") or []:
                    if not isinstance(unit, Mapping):
                        continue
                    for les in unit.get("lessons") or []:
                        if isinstance(les, Mapping):
                            lessons += 1

        lines: list[str] = []
        if sections or lessons:
            lines.append(f"规模：{sections} 节 · {lessons} 课")
        if err:
            lines.append(f"结构错误：{err}（必须修复后才能发布）")
        if warn:
            lines.append(f"警告：{warn}")
        if empty_n:
            lines.append(f"空课：{empty_n}")
        if ph:
            lines.append(f"待补词条：{ph}")
        if yellow:
            lines.append(f"质量提示：{yellow}")
        if not lines:
            lines.append("未加载健康上下文；发布前仍会跑校验。")

        blocks = err > 0
        summary = " · ".join(lines[:4])
        return {
            "title": "发布 Brief",
            "lines": lines,
            "error_count": err,
            "warning_count": warn,
            "empty_lesson_count": empty_n,
            "placeholder_count": ph,
            "blocks_publish": blocks,
            "summary": summary,
        }
    except Exception:
        return {
            "title": "发布 Brief",
            "lines": ["Brief 不可用"],
            "error_count": 0,
            "warning_count": 0,
            "empty_lesson_count": 0,
            "placeholder_count": 0,
            "blocks_publish": False,
            "summary": "Brief 不可用",
        }


def format_publish_brief_html(brief: Mapping[str, Any] | None) -> str:
    """HTML snippet for dialog. Never raises."""
    try:
        if not brief:
            return "<i>无 Brief</i>"
        title = str(brief.get("title") or "发布 Brief")
        lines = list(brief.get("lines") or [])
        color = "#dc2626" if brief.get("blocks_publish") else ""
        body = "<br/>".join(str(x) for x in lines)
        style = f" style='color:{color}'" if color else ""
        return f"<b{style}>{title}</b><br/>{body}"
    except Exception:
        return "<i>Brief 渲染失败</i>"
