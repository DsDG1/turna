"""T-06 rule-first semantic lesson search (pure Python, no Qt / no LLM).

Authors type short phrases like ``空课`` / ``缺 transcript`` / ``待补`` in
the overview search box (or future tree filter). Matching is **keyword
rules only** — never falls through to a model.

See experienceai.md R-04 batch / T-06.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Iterable

from src.backend.overview_stats import lesson_is_empty

LessonTriple = tuple[dict[str, Any], dict[str, Any], dict[str, Any]]
LessonPredicate = Callable[[dict[str, Any], dict[str, Any], dict[str, Any]], bool]


@dataclass(frozen=True)
class SemanticRule:
    """One local semantic filter."""

    rule_id: str
    label: str
    keywords: tuple[str, ...]
    description: str


# Order matters: first keyword hit wins (more specific rules first).
SEMANTIC_RULES: tuple[SemanticRule, ...] = (
    SemanticRule(
        rule_id="missing_transcript",
        label="缺 transcript / 听力缺口",
        keywords=(
            "缺 transcript",
            "missing transcript",
            "transcript",
            "听力缺口",
            "缺听力",
            "audioasset",
            "audio asset",
            "缺 audio",
        ),
        description="听力阶段或听选题缺少 transcript / audioAsset",
    ),
    SemanticRule(
        rule_id="empty",
        label="空课",
        keywords=("空课", "空白课", "empty lesson", "empty", "placeholder"),
        description="主内容槽为空的课时",
    ),
    SemanticRule(
        rule_id="stub",
        label="待补",
        keywords=("待补", "stub", "placeholder", "needs_review", "需复核"),
        description="词条/表达含待补占位或 needs_review 标记（课级启发式）",
    ),
)


def normalize_query(text: str) -> str:
    return (text or "").strip().lower()


def match_semantic_rule(text: str) -> SemanticRule | None:
    """Return the first rule whose keyword is contained in *text* (ci).

    Empty / pure name queries → None (caller falls back to name/id match).
    """
    needle = normalize_query(text)
    if not needle:
        return None
    for rule in SEMANTIC_RULES:
        for kw in rule.keywords:
            if kw.lower() in needle:
                return rule
    return None


def _item_missing_audio_or_transcript(item: dict[str, Any]) -> bool:
    if not isinstance(item, dict):
        return False
    rt = str(item.get("runtimeType") or "")
    listening_like = rt in {
        "listenAndPick",
        "typeTheWord",
        "listening",
        "ListenAndPick",
        "TypeTheWord",
    } or "listen" in rt.lower()
    # Listening phase items always need audio/transcript readiness.
    phase_item = bool(item.get("_in_listening_phase"))
    if not (listening_like or phase_item):
        return False
    has_audio = bool(str(item.get("audioAsset") or "").strip())
    has_tr = bool(str(item.get("transcript") or "").strip())
    return not (has_audio and has_tr)


def lesson_has_missing_transcript(lesson: dict[str, Any]) -> bool:
    """True when any listening phase/item lacks audioAsset or transcript."""
    content = lesson.get("content") or {}
    if not isinstance(content, dict):
        return False
    for phase in content.get("listeningPhases") or []:
        if not isinstance(phase, dict):
            continue
        items = phase.get("items") or []
        if not items:
            # Empty listening phase counts as a gap.
            return True
        for raw in items:
            if not isinstance(raw, dict):
                continue
            item = dict(raw)
            item["_in_listening_phase"] = True
            if _item_missing_audio_or_transcript(item):
                return True
    # Also scan stages for listen* runtime types.
    for stage in content.get("stages") or []:
        if not isinstance(stage, dict):
            continue
        for item in stage.get("items") or []:
            if isinstance(item, dict) and _item_missing_audio_or_transcript(item):
                return True
    for sub in content.get("subLessons") or []:
        if not isinstance(sub, dict):
            continue
        for stage in sub.get("stages") or []:
            if not isinstance(stage, dict):
                continue
            for item in stage.get("items") or []:
                if isinstance(item, dict) and _item_missing_audio_or_transcript(item):
                    return True
    return False


def _text_looks_stub(value: Any) -> bool:
    s = str(value or "").strip().lower()
    if not s:
        return False
    markers = (
        "待补",
        "todo",
        "placeholder",
        "tbd",
        "xxx",
        "[stub]",
        "needs_review",
        "需复核",
    )
    return any(m in s for m in markers)


def lesson_has_stub_markers(lesson: dict[str, Any]) -> bool:
    """Heuristic: lesson name/description or nested string fields look stubby."""
    if _text_looks_stub(lesson.get("name")) or _text_looks_stub(lesson.get("description")):
        return True
    content = lesson.get("content") or {}
    if not isinstance(content, dict):
        return False

    def _walk(obj: Any, depth: int = 0) -> bool:
        if depth > 6:
            return False
        if isinstance(obj, dict):
            if obj.get("needsReview") or obj.get("needs_review"):
                return True
            for k, v in obj.items():
                if k in {"id", "runtimeType", "template"}:
                    continue
                if isinstance(v, str) and _text_looks_stub(v):
                    return True
                if isinstance(v, (dict, list)) and _walk(v, depth + 1):
                    return True
        elif isinstance(obj, list):
            for it in obj:
                if _walk(it, depth + 1):
                    return True
        return False

    return _walk(content)


def predicate_for_rule(rule: SemanticRule) -> LessonPredicate:
    if rule.rule_id == "empty":
        return lambda _s, _u, lesson: lesson_is_empty(lesson)
    if rule.rule_id == "missing_transcript":
        return lambda _s, _u, lesson: lesson_has_missing_transcript(lesson)
    if rule.rule_id == "stub":
        return lambda _s, _u, lesson: lesson_has_stub_markers(lesson)
    return lambda _s, _u, _l: False


def filter_lessons_semantic(
    sections: Iterable[dict[str, Any]],
    rule: SemanticRule,
) -> list[LessonTriple]:
    """Return (section, unit, lesson) triples matching *rule*."""
    pred = predicate_for_rule(rule)
    out: list[LessonTriple] = []
    for section in sections:
        if not isinstance(section, dict):
            continue
        for unit in section.get("units", []) or []:
            if not isinstance(unit, dict):
                continue
            for lesson in unit.get("lessons", []) or []:
                if not isinstance(lesson, dict):
                    continue
                try:
                    if pred(section, unit, lesson):
                        out.append((section, unit, lesson))
                except Exception:
                    continue
    return out


def filter_lessons_query(
    sections: Iterable[dict[str, Any]],
    *,
    text: str = "",
    template: str | None = None,
) -> tuple[list[LessonTriple], SemanticRule | None]:
    """Name/id filter with semantic-rule override.

    Returns ``(matches, rule_or_none)``. When a semantic rule matches the
    query text, name/id matching is skipped for that query.
    """
    from src.backend.overview_stats import filter_lessons

    rule = match_semantic_rule(text)
    if rule is not None:
        triples = filter_lessons_semantic(sections, rule)
        if template:
            triples = [
                (s, u, l)
                for s, u, l in triples
                if l.get("template", "legacy") == template
            ]
        return triples, rule
    return filter_lessons(sections, text=text, template=template), None
