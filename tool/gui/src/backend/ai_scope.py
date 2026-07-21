"""Natural-language edit scope resolution (aiEnhance U1-1).

Rule-based (no LLM). Maps Chinese/English-ish instructions to lesson / item
targets inside a section draft. Low-confidence results set ``needs_confirm``.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any


@dataclass
class ScopeTarget:
    kind: str  # lesson | item | unit | section
    id: str
    label: str = ""


@dataclass
class ScopeResolution:
    targets: list[ScopeTarget] = field(default_factory=list)
    confidence: float = 0.0
    needs_confirm: bool = True
    note: str = ""
    raw_instruction: str = ""


_LESSON_ORDINAL = re.compile(
    r"(?:第\s*([0-9一二三四五六七八九十]+)\s*课)|(?:lesson\s*([0-9]+))",
    re.I,
)
_UNIT_ORDINAL = re.compile(
    r"(?:第\s*([0-9一二三四五六七八九十]+)\s*单元)|(?:unit\s*([0-9]+))",
    re.I,
)
_ALL_MCQ = re.compile(
    r"(全部|所有|every|all).{0,8}(选择题|MCQ|multiple\s*choice|单选)",
    re.I,
)
_ALL_FILL = re.compile(
    r"(全部|所有|every|all).{0,8}(填空|fill\s*blank)",
    re.I,
)
_ID_EXPLICIT = re.compile(r"\b([a-zA-Z][\w-]{2,})\b")

_CN_NUM = {
    "一": 1,
    "二": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
    "十": 10,
}


def _parse_ordinal(token: str) -> int | None:
    token = (token or "").strip()
    if not token:
        return None
    if token.isdigit():
        return int(token)
    if token in _CN_NUM:
        return _CN_NUM[token]
    return None


def _iter_lessons(section: dict[str, Any]) -> list[tuple[str, dict[str, Any], dict[str, Any]]]:
    """Return list of (unit_id, unit, lesson)."""
    out: list[tuple[str, dict[str, Any], dict[str, Any]]] = []
    for unit in section.get("units") or []:
        if not isinstance(unit, dict):
            continue
        uid = str(unit.get("id") or "")
        for lesson in unit.get("lessons") or []:
            if isinstance(lesson, dict) and lesson.get("id"):
                out.append((uid, unit, lesson))
    return out


def _iter_items(lesson: dict[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    content = lesson.get("content") or {}
    for stage in content.get("stages") or []:
        if isinstance(stage, dict):
            for it in stage.get("items") or []:
                if isinstance(it, dict):
                    items.append(it)
    for sub in content.get("subLessons") or []:
        if not isinstance(sub, dict):
            continue
        for stage in sub.get("stages") or []:
            if isinstance(stage, dict):
                for it in stage.get("items") or []:
                    if isinstance(it, dict):
                        items.append(it)
    for phase in content.get("listeningPhases") or []:
        if isinstance(phase, dict):
            for it in phase.get("items") or []:
                if isinstance(it, dict):
                    items.append(it)
    return items


def resolve_edit_scope(
    instruction: str,
    section: dict[str, Any] | None,
) -> ScopeResolution:
    """Resolve ``instruction`` against ``section`` into target nodes."""
    text = (instruction or "").strip()
    if not text:
        return ScopeResolution(
            confidence=0.0,
            needs_confirm=True,
            note="指令为空",
            raw_instruction=text,
        )
    if not isinstance(section, dict):
        return ScopeResolution(
            confidence=0.0,
            needs_confirm=True,
            note="无草稿 section",
            raw_instruction=text,
        )

    lessons = _iter_lessons(section)
    targets: list[ScopeTarget] = []
    confidence = 0.0
    note_parts: list[str] = []

    # Explicit lesson id in instruction.
    lesson_ids = {str(les.get("id")) for _u, _un, les in lessons}
    for m in _ID_EXPLICIT.finditer(text):
        token = m.group(1)
        if token in lesson_ids:
            les = next(les for _u, _un, les in lessons if les.get("id") == token)
            targets.append(
                ScopeTarget(
                    kind="lesson",
                    id=token,
                    label=str(les.get("name") or token),
                )
            )
            confidence = max(confidence, 0.95)

    # Ordinal lesson: 第2课 / lesson 2 (global order across units).
    m = _LESSON_ORDINAL.search(text)
    if m and not targets:
        n = _parse_ordinal(m.group(1) or m.group(2) or "")
        if n is not None and 1 <= n <= len(lessons):
            _uid, _un, les = lessons[n - 1]
            targets.append(
                ScopeTarget(
                    kind="lesson",
                    id=str(les.get("id")),
                    label=str(les.get("name") or les.get("id")),
                )
            )
            confidence = max(confidence, 0.85)
            note_parts.append(f"按序第 {n} 课")

    # All MCQ / fill blanks → item targets.
    runtime_filter: str | None = None
    if _ALL_MCQ.search(text):
        runtime_filter = "multipleChoice"
    elif _ALL_FILL.search(text):
        runtime_filter = "fillBlank"

    if runtime_filter:
        scope_lessons = (
            [next(les for _u, _un, les in lessons if les.get("id") == t.id) for t in targets]
            if targets
            else [les for _u, _un, les in lessons]
        )
        item_targets: list[ScopeTarget] = []
        for les in scope_lessons:
            for it in _iter_items(les):
                if it.get("runtimeType") == runtime_filter and it.get("id"):
                    item_targets.append(
                        ScopeTarget(
                            kind="item",
                            id=str(it["id"]),
                            label=f"{les.get('name', les.get('id'))}/{it.get('id')}",
                        )
                    )
        if item_targets:
            targets = item_targets
            confidence = max(confidence, 0.8)
            note_parts.append(f"匹配 {runtime_filter} ×{len(item_targets)}")

    # Unit ordinal without lesson.
    if not targets:
        um = _UNIT_ORDINAL.search(text)
        if um:
            n = _parse_ordinal(um.group(1) or um.group(2) or "")
            units = [u for u in (section.get("units") or []) if isinstance(u, dict)]
            if n is not None and 1 <= n <= len(units):
                unit = units[n - 1]
                targets.append(
                    ScopeTarget(
                        kind="unit",
                        id=str(unit.get("id")),
                        label=str(unit.get("name") or unit.get("id")),
                    )
                )
                confidence = max(confidence, 0.75)
                note_parts.append(f"第 {n} 单元")

    if not targets:
        # Whole section fallback with low confidence.
        sid = str(section.get("id") or "")
        targets = [
            ScopeTarget(
                kind="section",
                id=sid,
                label=str(section.get("name") or sid),
            )
        ]
        confidence = 0.35
        note_parts.append("未解析到具体课/题，默认整节")

    needs_confirm = confidence < 0.8 or any(t.kind == "section" for t in targets)
    return ScopeResolution(
        targets=targets,
        confidence=confidence,
        needs_confirm=needs_confirm,
        note="；".join(note_parts),
        raw_instruction=text,
    )


def format_scope_resolution(res: ScopeResolution) -> str:
    """One-line human summary for UI confirmation bars."""
    if not res.targets:
        return "未解析到作用域"
    parts = [f"{t.kind}:{t.label or t.id}" for t in res.targets[:6]]
    more = f" 等 {len(res.targets)} 处" if len(res.targets) > 6 else ""
    conf = f"置信 {res.confidence:.0%}"
    note = f" · {res.note}" if res.note else ""
    return f"将修改：{', '.join(parts)}{more}（{conf}）{note}"
