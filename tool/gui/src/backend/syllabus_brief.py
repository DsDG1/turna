"""Turn a teaching syllabus into course-plan parameters.

A syllabus (教学纲领 / 课程大纲 / ders izlencesi) is the document that fixes the
*shape* of a course: which units exist, in what order, at what CEFR level, with
which can-do objectives and how many lessons each unit gets. It deliberately
says little about vocabulary — that is what the textbook and the AI designer
are for.

This module is the Qt-free seam between "a file the teacher uploaded" and
``CoursePlanSpec`` (``src.backend.ai.course_plan``):

- :func:`heuristic_brief` reads the document's own structure (headings,
  CEFR tags, objective lines, lesson counts). No network, always succeeds.
- :func:`ai_brief` asks the configured model to fill in what the heuristic
  cannot see (topic phrasing, per-unit can-do list, constraints). Failures fall
  back to the heuristic — planning must still work offline.
- :func:`brief_to_spec_values` returns the plain dict the plan window writes
  into its form, so the UI layer never touches these dataclasses' internals.

The brief never writes course JSON: the plan window still generates an outline
and imports through the existing validate/merge/undo path.
"""
from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass
from typing import Any
from collections.abc import Callable

from src.backend.ai.client import chat_json
from src.backend.ai.config import AiApiConfig, AiCancelled
from src.backend.ai.parse import extract_content, parse_json_obj
from src.backend.markdown_chopper import plain_unit_titles

logger = logging.getLogger(__name__)

#: CEFR ladder, shared with ``course_plan.CEFR_LEVELS`` (kept local so this
#: module does not import the plan generator just for a tuple).
_LEVELS: tuple[str, ...] = ("A1", "A2", "B1", "B2", "C1", "C2")

_LEVEL_RE = re.compile(r"\b(A1|A2|B1|B2|C1|C2)\b")
#: Lines that read like a can-do objective.
_CAN_DO_RE = re.compile(
    r"^\s*(?:[-*•·]|\d+[\.\)])?\s*"
    r"(?:能|可以|能够|会|掌握|学会|can\b|be able to|öğrenci|öğrenebilir|yapabilir)",
    re.IGNORECASE,
)
#: "每单元 6 课" / "each unit has 6 lessons" / "haftada 4 saat".
_LESSONS_PER_UNIT_RE = re.compile(
    r"(?:每\s*(?:单元|課|课)\s*(\d{1,2})\s*(?:课|课时|学时))"
    r"|(?:(\d{1,2})\s*lessons?\s*per\s*unit)",
    re.IGNORECASE,
)
#: "词汇量 800" / "800 words" / "800 kelime".
_WORD_BUDGET_RE = re.compile(
    r"(?:词汇量\s*[:：]?\s*(\d{2,4}))|(?:(\d{2,4})\s*(?:words|kelime))",
    re.IGNORECASE,
)

_MAX_UNITS = 24
_MAX_CAN_DO = 12
_MAX_CAN_DO_CHARS = 90
_MAX_CONSTRAINT_CHARS = 1800

_SYSTEM = (
    "You are a language-course planning assistant. "
    "You output ONLY valid JSON, no prose, no markdown fences."
)


@dataclass(frozen=True)
class SyllabusBrief:
    """Course-plan parameters distilled from a syllabus document.

    - ``topic``: short course topic ("日常土耳其语 · 旅行场景").
    - ``level_from`` / ``level_to``: CEFR range; equal when the syllabus spans
      one level.
    - ``section_count`` / ``lessons_per_section``: the unit ladder.
    - ``word_budget``: course-wide new-word budget (0 = plan decides).
    - ``can_do``: objective statements, one per line, teacher-editable.
    - ``constraints``: the unit order + hard requirements, fed to the planner.
    - ``units``: unit titles in document order.
    - ``source``: ``"heuristic"`` or ``"ai"``.
    - ``warnings``: everything the teacher should double-check.
    """

    topic: str = ""
    level_from: str = "A1"
    level_to: str = "A2"
    section_count: int = 6
    lessons_per_section: int = 9
    word_budget: int = 240
    can_do: tuple[str, ...] = ()
    constraints: str = ""
    units: tuple[str, ...] = ()
    source: str = "heuristic"
    warnings: tuple[str, ...] = ()


def _level_index(level: str) -> int:
    try:
        return _LEVELS.index(str(level).strip().upper())
    except ValueError:
        return 0


def _clean_unit_title(title: str) -> str:
    """Strip numbering / unit words from a heading for use as a topic name."""
    text = re.sub(r"^\s*\d+(?:\.\d+)*\s*[\.\)、:：]?\s*", "", str(title or ""))
    text = re.sub(
        r"^\s*(Ünite|Unite|Bölüm|Bolum|Ders|Unit|Lesson|Chapter|Module|"
        r"第\s*\d+\s*[章节课]|单元|模块)\s*\d*\s*[:：\.\-–—]?\s*",
        "",
        text,
        flags=re.IGNORECASE,
    )
    return text.strip().strip(":：.-–—").strip()


def _dedupe(items: list[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        key = item.strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(item.strip())
    return tuple(out)


def heuristic_brief(text: str, *, default_level: str = "A1") -> SyllabusBrief:
    """Read plan parameters from the syllabus structure alone (no network).

    Looks for: heading/unit ladder, CEFR tags, objective lines, "N lessons per
    unit", and a stated word budget. Everything it cannot find falls back to the
    planner defaults, and every fallback is recorded in ``warnings`` so the
    teacher knows what to fill in.
    """
    body = text or ""
    warnings: list[str] = []

    units = tuple(plain_unit_titles(body)[:_MAX_UNITS])
    if not units:
        warnings.append("未识别出单元标题：章节数按默认值给出，可手动调整。")

    levels = [m.group(1) for m in _LEVEL_RE.finditer(body)]
    if levels:
        ordered = sorted({lv.upper() for lv in levels}, key=_level_index)
        level_from, level_to = ordered[0], ordered[-1]
    else:
        level_from = default_level if default_level in _LEVELS else "A1"
        level_to = _LEVELS[min(_level_index(level_from) + 1, len(_LEVELS) - 1)]
        warnings.append("未找到 CEFR 等级标注：等级范围按默认值给出。")

    topic = ""
    for title in list(units)[:1]:
        topic = _clean_unit_title(title)
    if not topic:
        for line in body.splitlines():
            stripped = line.strip().lstrip("#").strip()
            if stripped and len(stripped) <= 60 and not stripped.endswith(("。", ".")):
                topic = stripped
                break
    if not topic:
        warnings.append("未找到可用的课程主题，请手动填写。")

    can_do_lines: list[str] = []
    for line in body.splitlines():
        stripped = line.strip().lstrip("-*•· ").strip()
        if not stripped or len(stripped) > _MAX_CAN_DO_CHARS * 2:
            continue
        is_can_do = _CAN_DO_RE.match(line) or (
            "目标" in stripped and len(stripped) <= _MAX_CAN_DO_CHARS
        )
        if is_can_do:
            clipped = stripped[:_MAX_CAN_DO_CHARS]
            if len(clipped) >= 4:
                can_do_lines.append(clipped)
        if len(can_do_lines) >= _MAX_CAN_DO:
            break
    can_do = _dedupe(can_do_lines)
    if not can_do:
        warnings.append("未找到 can-do 目标条目：规划将只依据单元列表。")

    lessons_match = _LESSONS_PER_UNIT_RE.search(body)
    lessons_per_section = 9
    if lessons_match:
        value = lessons_match.group(1) or lessons_match.group(2)
        try:
            lessons_per_section = max(1, min(60, int(value)))
        except (TypeError, ValueError):
            lessons_per_section = 9
    else:
        warnings.append("未写明每单元课时数：按 9 课/单元给出。")

    word_match = _WORD_BUDGET_RE.search(body)
    word_budget = 240
    if word_match:
        value = word_match.group(1) or word_match.group(2)
        try:
            word_budget = max(0, min(5000, int(value)))
        except (TypeError, ValueError):
            word_budget = 240

    section_count = len(units) if units else 6
    section_count = max(1, min(_MAX_UNITS, section_count))

    constraints = _build_constraints(units, can_do, body)
    return SyllabusBrief(
        topic=topic,
        level_from=level_from,
        level_to=level_to,
        section_count=section_count,
        lessons_per_section=lessons_per_section,
        word_budget=word_budget,
        can_do=can_do,
        constraints=constraints,
        units=units,
        source="heuristic",
        warnings=tuple(warnings),
    )


def _build_constraints(
    units: tuple[str, ...], can_do: tuple[str, ...], body: str
) -> str:
    """Compose the planner-facing constraint block (unit order + objectives)."""
    parts: list[str] = []
    if units:
        ladder = "\n".join(f"{i}. {title}" for i, title in enumerate(units, start=1))
        parts.append(
            "严格按教学纲领的单元顺序覆盖以下单元，不得增删或调换：\n" + ladder
        )
    if can_do:
        goals = "\n".join(f"- {item}" for item in can_do)
        parts.append("每个单元至少要落地一条以下目标：\n" + goals)
    excerpt = body.strip()
    if excerpt:
        # Keep the tail of the syllabus available to the planner without
        # dominating the prompt.
        parts.append("教学纲领原文摘录：\n" + excerpt[:_MAX_CONSTRAINT_CHARS])
    return "\n\n".join(parts)[: _MAX_CONSTRAINT_CHARS * 2]


def build_brief_messages(
    language: str,
    source_language: str,
    text: str,
    heuristic: SyllabusBrief,
    *,
    max_chars: int = 12000,
) -> list[dict[str, str]]:
    """Build the [system, user] messages that ask the model for plan values."""
    hint = json.dumps(
        {
            "units": list(heuristic.units),
            "level_from": heuristic.level_from,
            "level_to": heuristic.level_to,
            "section_count": heuristic.section_count,
        },
        ensure_ascii=False,
    )
    user = "\n".join(
        [
            "Read the teaching syllabus below and return the parameters a "
            "course planner needs.",
            "",
            f"Target language: {language}",
            f"Source language (for topic / can-do wording): {source_language}",
            "",
            "Return STRICT JSON with exactly this shape:",
            "{",
            '  "topic": "...",',
            '  "level_from": "A1", "level_to": "A2",',
            '  "section_count": 6, "lessons_per_section": 9,',
            '  "word_budget": 240,',
            '  "can_do": ["能...", "..."],',
            '  "units": ["Unit title", "..."],',
            '  "constraints": "hard requirements, one per line"',
            "}",
            "",
            "Rules:",
            "- Follow the syllabus: unit order, unit count and level range come "
            "from the document, not from your own course design.",
            "- section_count must equal the number of units you return.",
            "- can_do items are short, concrete, and in the source language.",
            "- constraints states only hard requirements (order, coverage, "
            "assessment, exclusions). No filler.",
            "- Use the heuristic pre-read as a cross-check, not as a ceiling:",
            hint,
            "",
            "Syllabus:",
            (text or "")[:max_chars],
        ]
    )
    return [
        {"role": "system", "content": _SYSTEM},
        {"role": "user", "content": user},
    ]


def _int_in(value: Any, low: int, high: int, fallback: int) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return fallback
    return max(low, min(high, number))


def coerce_brief(raw: dict[str, Any], fallback: SyllabusBrief) -> SyllabusBrief:
    """Validate a model response, keeping heuristic values on missing fields."""
    if not isinstance(raw, dict):
        return fallback
    units_raw = raw.get("units")
    units: tuple[str, ...] = fallback.units
    if isinstance(units_raw, list):
        cleaned = tuple(
            str(u).strip() for u in units_raw if str(u).strip()
        )[:_MAX_UNITS]
        if cleaned:
            units = cleaned

    level_from = str(raw.get("level_from") or fallback.level_from).upper()
    level_to = str(raw.get("level_to") or fallback.level_to).upper()
    if level_from not in _LEVELS:
        level_from = fallback.level_from
    if level_to not in _LEVELS:
        level_to = fallback.level_to
    if _level_index(level_to) < _level_index(level_from):
        level_from, level_to = level_to, level_from

    can_do_raw = raw.get("can_do")
    can_do = fallback.can_do
    if isinstance(can_do_raw, list):
        cleaned_can_do = _dedupe(
            [str(item).strip()[:_MAX_CAN_DO_CHARS] for item in can_do_raw if str(item).strip()]
        )[:_MAX_CAN_DO]
        if cleaned_can_do:
            can_do = cleaned_can_do

    constraints = str(raw.get("constraints") or "").strip() or fallback.constraints
    section_count = _int_in(
        raw.get("section_count"), 1, _MAX_UNITS, len(units) or fallback.section_count
    )
    if units and section_count != len(units):
        # Units are the authority: the plan must not silently drop chapters.
        section_count = len(units)

    return SyllabusBrief(
        topic=str(raw.get("topic") or fallback.topic).strip() or fallback.topic,
        level_from=level_from,
        level_to=level_to,
        section_count=section_count,
        lessons_per_section=_int_in(
            raw.get("lessons_per_section"), 1, 60, fallback.lessons_per_section
        ),
        word_budget=_int_in(raw.get("word_budget"), 0, 5000, fallback.word_budget),
        can_do=can_do,
        constraints=constraints,
        units=units,
        source="ai",
        warnings=fallback.warnings,
    )


def ai_brief(
    config: AiApiConfig,
    language: str,
    source_language: str,
    text: str,
    *,
    heuristic: SyllabusBrief | None = None,
    timeout: float = 90.0,
    temperature: float = 0.2,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
) -> SyllabusBrief:
    """Extract plan parameters with the model, falling back to the heuristic.

    ``AiCancelled`` propagates (a user cancel must stop the run); every other
    failure returns the heuristic brief, because planning must stay usable when
    the endpoint is down or the response is malformed.
    """
    base = heuristic or heuristic_brief(text)
    messages = build_brief_messages(language, source_language, text, base)
    try:
        body = chat_json(
            config,
            messages,
            temperature=temperature,
            timeout=timeout,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            model=config.select_model("json"),
        )
        raw = parse_json_obj(extract_content(body, strip=True))
    except AiCancelled:
        raise
    except (RuntimeError, ValueError, KeyError, TypeError, OSError):
        logger.debug(
            "syllabus_brief: AI extraction unavailable, using heuristic",
            exc_info=True,
        )
        return base
    return coerce_brief(raw, base)


def brief_to_spec_values(brief: SyllabusBrief) -> dict[str, Any]:
    """Return the plan-form values for ``CoursePlanService.build_spec``."""
    return {
        "topic": brief.topic,
        "level_from": brief.level_from,
        "level_to": brief.level_to,
        "section_count": brief.section_count,
        "lessons_per_section": brief.lessons_per_section,
        "word_budget": brief.word_budget,
        "can_do": list(brief.can_do),
        "constraints": brief.constraints,
    }


def brief_summary(brief: SyllabusBrief) -> str:
    """One-line summary for the plan window's status label."""
    unit_part = (
        f"{len(brief.units)} 个单元" if brief.units else "未识别单元"
    )
    return (
        f"教学纲领已解析（{brief.source}）：{unit_part}，"
        f"{brief.level_from}→{brief.level_to}，"
        f"{brief.section_count} 章 × {brief.lessons_per_section} 课，"
        f"{len(brief.can_do)} 条目标"
    )

