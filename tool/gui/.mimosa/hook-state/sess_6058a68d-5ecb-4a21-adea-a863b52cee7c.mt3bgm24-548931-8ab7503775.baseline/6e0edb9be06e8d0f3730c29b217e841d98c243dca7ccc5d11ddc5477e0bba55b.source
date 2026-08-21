"""Human-friendly error mapping for the teacher view (guiplan §15.8, T.7).

Converts CLI validate/lint problem dicts (with engineering `path` strings like
`section:section4/unit:u-1`) into teacher-facing messages and a node ref the
MainWindow can jump to. Pure functions; no PySide6 dependency so they are
unit-testable in the sandbox.
"""
from __future__ import annotations

import re
from typing import Any

_PATH_RE = re.compile(
    r"section:(?P<section>[^\s/]+)(?:/unit:(?P<unit>[^\s/]+))?(?:/lesson:(?P<lesson>[^\s/]+))?"
)


def parse_path(path: str) -> dict[str, str]:
    """Parse a CLI path string into {section, unit, lesson} ids (any may be '')."""
    if not path:
        return {"section": "", "unit": "", "lesson": ""}
    m = _PATH_RE.search(path)
    if not m:
        return {"section": "", "unit": "", "lesson": ""}
    return {
        "section": m.group("section") or "",
        "unit": m.group("unit") or "",
        "lesson": m.group("lesson") or "",
    }


def humanize_problem(problem: dict[str, Any]) -> str:
    """Turn a CLI problem dict into a teacher-facing sentence."""
    msg = str(problem.get("message", ""))
    low = msg.lower()

    if "duplicate" in low and "id" in low:
        return "有重复的编号，请检查是否有两节课/词用了相同的编号。"
    if "dangling" in low or "missing wordid" in low or "references missing" in low:
        return "这道题引用了不存在的词，请从词库重新选择。"
    if "missing expressionid" in low:
        return "这道题引用了不存在的表达，请重新选择。"
    if "listening" in low and "audioasset" in low:
        return "听力课的这道题还没有音频文件。"
    if "duplicate lesson id" in low:
        return "有两节课用了相同的编号，请删掉重复的那节重新新增。"
    if "scale" in low or "too many" in low:
        return "数量超出上限，一个单元最多 40 节课，一个章节最多 60 个单元。"
    return msg


def problem_to_node_ref(
    problem: dict[str, Any],
    sections: list[dict[str, Any]],
) -> tuple[str, str] | None:
    """Map a problem's path to a (kind, id) node ref for jumping, or None.

    kind is 'section' | 'unit' | 'lesson'. Resolves path ids to find the most
    specific node present in the tree.
    """
    parts = parse_path(problem.get("path", ""))
    if parts["lesson"]:
        return ("lesson", parts["lesson"])
    if parts["unit"]:
        return ("unit", parts["unit"])
    if parts["section"]:
        return ("section", parts["section"])
    return None
