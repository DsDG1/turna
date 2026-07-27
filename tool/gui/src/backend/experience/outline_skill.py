"""M-02 course.outline_shells skill (pure Python, no Qt).

Deterministic (zero-LLM) conversion of a pasted **bullet outline** into a
unit/lesson **shell** section, reusing ``ai_phased.outline_to_section_shell``
for the empty-content shells. The write is performed by the caller via
``plan_section_merge`` + ``SectionDiffView`` + ``MergeAiSectionCommand``
(preview + human confirm + Undo); this module never touches the adapter or Qt.

红线（experienceai.md §14.5.2 / §14.5.3）：
* 纯函数解析 / 构壳；无 Qt、不写树、不写盘、零网络、零 LLM。
* 永不抛：非法输入 -> 空大纲 / 空壳节；调用方据 ``"units"`` 是否为空给出提示。
* id 由 :func:`_slug_id` 派生并对全课程 existing ids 去重，绝不复用已占用 id。
* Context / Timeline scope 闭集（count / 新增 unit·lesson id 列表）——大纲原文、
  课名文本一律不进 scope（§14.5.3）。

大纲语法（缩进 / 连字符 / 数字序号三态，容错）::

    # 可选注释行（# 开头忽略）
    Unit 标题            # 顶格（或 ``- Unit``）= unit
      - 课标题           # 缩进一级 = lesson（template 默认 intro）
      - 课标题 [listening]   # 方括号指定课型（intro/listening/reading/mastery/...）
    1. 另一 Unit
      1.1 又一课

无缩进的行视为 unit；有缩进（或 ``- ``/``* ``/数字.`` 前缀）的子行视为其下 lesson。
"""
from __future__ import annotations

import re
from typing import Any, Mapping, Sequence

ACTION_ID = "course.outline_shells"


def is_outline_shell_enabled(settings: Any | None = None) -> bool:
    """True only when the outline-shell switch is on (default off, §6.4).

    Structure-creation capability — ships locked behind
    ``experience/outline_shell``. Missing settings -> False (conservative).
    """
    try:
        if settings is None:
            return False
        return bool(getattr(settings, "experience_outline_shell", False))
    except Exception:
        return False

# Template hint allowed in square brackets after a lesson title.
_KNOWN_TEMPLATES = frozenset(
    {
        "intro",
        "practice",
        "review",
        "mastery",
        "listening",
        "reading",
        "legacy",
    }
)

_BULLET_RE = re.compile(r"^(?:[-*•·]|\d+(?:\.\d+)*[.)])\s+")
_TEMPLATE_TAG_RE = re.compile(r"\[([A-Za-z][A-Za-z0-9_-]*)\]\s*$")


def _slug_id(text: str, prefix: str) -> str:
    """Derive a stable ascii-ish id from a title; never raises.

    Non-ascii (e.g. CJK) titles slug to a short content hash so distinct titles
    still get distinct, meaningful ids instead of all collapsing to the prefix.
    """
    raw = str(text or "")
    try:
        base = re.sub(r"[^A-Za-z0-9]+", "-", raw).strip("-").lower()
        if not base:
            import hashlib

            digest = hashlib.sha1(raw.encode("utf-8", "ignore")).hexdigest()[:6]
            base = f"{prefix}{digest}"
        return f"{prefix}-{base[:32]}"
    except Exception:
        return prefix


def _uniquify(wanted: str, taken: set[str]) -> str:
    """Return *wanted* or ``wanted-2``/``-3``… avoiding *taken* ids."""
    base = wanted or "id"
    if base not in taken:
        return base
    i = 2
    while f"{base}-{i}" in taken:
        i += 1
    return f"{base}-{i}"


def parse_bullet_outline(
    text: str,
    *,
    existing_ids: Sequence[str] | None = None,
    section_id: str = "outline",
) -> dict[str, Any]:
    """Parse pasted bullet outline text into an outline dict; never raises.

    Returns the ``ai_phased`` outline shape::

        {"id", "name", "description", "words": [], "expressions": [],
         "grammarPoints": [], "units": [{"id", "name", "lessons": [
           {"id", "name", "template", "description", "prerequisiteLessonIds"}]}]}

    ``existing_ids`` (all ids already used in the course) keeps generated
    unit/lesson ids collision-free. Comment lines (``#``) and blanks are
    skipped. Lines with leading whitespace (or a bullet/numbered marker) nest
    under the most recent unit; a lesson with no enclosing unit is grouped
    under an implicit first unit.
    """
    taken: set[str] = {str(x) for x in (existing_ids or []) if x}
    outline: dict[str, Any] = {
        "id": str(section_id or "outline"),
        "name": "大纲导入",
        "description": "",
        "words": [],
        "expressions": [],
        "grammarPoints": [],
        "units": [],
    }
    try:
        lines = str(text or "").splitlines()
    except Exception:
        return outline

    current_unit: dict[str, Any] | None = None

    def _new_unit(title: str) -> dict[str, Any]:
        uid = _uniquify(_slug_id(title, "u"), taken)
        taken.add(uid)
        unit = {"id": uid, "name": title or uid, "lessons": []}
        outline["units"].append(unit)
        return unit

    def _add_lesson(unit: dict[str, Any], title: str, template: str) -> None:
        lid = _uniquify(_slug_id(title, "l"), taken)
        taken.add(lid)
        unit["lessons"].append(
            {
                "id": lid,
                "name": title or lid,
                "template": template,
                "description": "",
                "prerequisiteLessonIds": [],
            }
        )

    for raw in lines:
        if not isinstance(raw, str):
            continue
        if not raw.strip():
            continue
        stripped = raw.strip()
        if stripped.startswith("#"):
            continue
        # Determine nesting by leading whitespace OR an explicit bullet marker.
        indented = bool(raw[:1].isspace())
        body = _BULLET_RE.sub("", stripped).strip()
        if not body:
            continue
        template = "intro"
        m = _TEMPLATE_TAG_RE.search(body)
        if m:
            cand = m.group(1).lower()
            if cand in _KNOWN_TEMPLATES:
                template = cand
                body = body[: m.start()].strip()
        if not body:
            continue
        # A top-level (non-indented, no bullet) line is a unit header. A bulleted
        # or indented line under an open unit is a lesson; otherwise it starts a
        # new unit when nothing is open yet.
        is_lesson = indented or bool(_BULLET_RE.match(stripped))
        if is_lesson and current_unit is not None:
            _add_lesson(current_unit, body, template)
        else:
            current_unit = _new_unit(body)
            if is_lesson and template != "intro":
                # bulleted single-line unit hint ignored; keep as unit title
                pass
    return outline


def outline_to_shell_section(
    outline: Mapping[str, Any],
    *,
    section_id: str | None = None,
) -> dict[str, Any]:
    """Build a unit/lesson shell section from a parsed outline; never raises.

    Delegates content-shell construction to
    :func:`ai_phased.outline_to_section_shell`. When *section_id* is given the
    shell section adopts it so ``plan_section_merge`` appends units into the
    existing target section (never replaces).
    """
    try:
        from src.backend.ai_phased import outline_to_section_shell

        shell = outline_to_section_shell(dict(outline or {}))
    except Exception:
        shell = {"id": "outline", "name": "大纲导入", "units": []}
    if section_id:
        shell["id"] = str(section_id)
    return shell


def shell_stats(shell: Mapping[str, Any]) -> dict[str, Any]:
    """Closed-set summary for confirmation copy / metrics scope. Never raises."""
    try:
        units = [u for u in (shell.get("units") or []) if isinstance(u, Mapping)]
        unit_ids = [str(u.get("id")) for u in units if u.get("id")]
        lesson_ids: list[str] = []
        for u in units:
            for les in (u.get("lessons") or []):
                if isinstance(les, Mapping) and les.get("id"):
                    lesson_ids.append(str(les.get("id")))
        return {
            "unit_count": len(unit_ids),
            "lesson_count": len(lesson_ids),
            "unit_ids": unit_ids[:20],
            "lesson_ids": lesson_ids[:20],
        }
    except Exception:
        return {"unit_count": 0, "lesson_count": 0, "unit_ids": [], "lesson_ids": []}


def all_course_ids(adapter: Any) -> list[str]:
    """Collect every id already used across the course (units/lessons/sections).

    Used to keep generated shell ids collision-free. Never raises.
    """
    ids: list[str] = []
    try:
        for section in getattr(adapter, "sections", None) or []:
            if not isinstance(section, Mapping):
                continue
            if section.get("id"):
                ids.append(str(section.get("id")))
            for unit in (section.get("units") or []):
                if not isinstance(unit, Mapping):
                    continue
                if unit.get("id"):
                    ids.append(str(unit.get("id")))
                for les in (unit.get("lessons") or []):
                    if isinstance(les, Mapping) and les.get("id"):
                        ids.append(str(les.get("id")))
    except Exception:
        return ids
    return ids
