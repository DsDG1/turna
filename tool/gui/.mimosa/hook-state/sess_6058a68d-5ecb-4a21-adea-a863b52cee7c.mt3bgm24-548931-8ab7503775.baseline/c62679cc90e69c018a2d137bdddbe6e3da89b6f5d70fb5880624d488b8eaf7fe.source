"""Build a schema-valid course section from a chapter + knowledge points.

The ④→⑤ step of the textbook import pipeline (bookplan2.md): given a chopped
``Chapter`` and its normalised ``KnowledgePoints``, produce a section dict that
the existing import path (``CourseAdapter.validate_section_json`` +
``merge_section_resources`` + ``ImportAiSectionCommand``) can consume directly.

Key shape constraints (verified against ``course_adapter.merge_section_resources``
at course_adapter.py:996): resources must live under the top-level keys
``words`` / ``expressions`` / ``grammarPoints`` — NOT ``vocab`` — or the merge
will silently skip them.
"""
from __future__ import annotations

from typing import Any

from src.backend.knowledge_schema import KnowledgePoints
from src.backend.lesson_content import (
    build_intro_lesson,
    build_practice_lesson,
    build_review_lesson,
)
from src.backend.markdown_chopper import Chapter


def _rewrite_ids_deterministic(section: dict[str, Any], section_id: str) -> None:
    """Rewrite structural ids (unit/lesson/subLesson/stage/phase/item) in place.

    Ids are derived from ``section_id`` + position, so re-importing the same
    chapter produces byte-identical structure ids and routes through the merge
    path (``plan_section_merge``) instead of creating duplicate lessons.
    Resource *references* (``wordId`` / ``expressionId`` / ``grammarPointId``)
    and top-level resource ids are left untouched — ``KnowledgeMerger`` owns
    those. Unknown containers are skipped silently.
    """

    def _items(items: Any, prefix: str) -> None:
        if not isinstance(items, list):
            return
        for k, item in enumerate(items, start=1):
            if isinstance(item, dict) and "id" in item:
                item["id"] = f"{prefix}-it{k}"

    def _stages(stages: Any, prefix: str) -> None:
        if not isinstance(stages, list):
            return
        for j, stage in enumerate(stages, start=1):
            if not isinstance(stage, dict):
                continue
            stage["id"] = f"{prefix}-st{j}"
            _items(stage.get("items"), stage["id"])

    units = section.get("units")
    if not isinstance(units, list):
        return
    for n, unit in enumerate(units, start=1):
        if not isinstance(unit, dict):
            continue
        unit["id"] = f"{section_id}-u{n}"
        lessons = unit.get("lessons")
        if not isinstance(lessons, list):
            continue
        for m, lesson in enumerate(lessons, start=1):
            if not isinstance(lesson, dict):
                continue
            lesson["id"] = f"{unit['id']}-l{m}"
            content = lesson.get("content")
            if not isinstance(content, dict):
                continue
            sub_lessons = content.get("subLessons")
            if isinstance(sub_lessons, list):
                for i, sl in enumerate(sub_lessons, start=1):
                    if not isinstance(sl, dict):
                        continue
                    sl["id"] = f"{lesson['id']}-sl{i}"
                    _stages(sl.get("stages"), sl["id"])
            phases = content.get("listeningPhases")
            if isinstance(phases, list):
                for i, ph in enumerate(phases, start=1):
                    if not isinstance(ph, dict):
                        continue
                    ph["id"] = f"{lesson['id']}-ph{i}"
                    _items(ph.get("items"), ph["id"])
            # review / mastery / reading keep stages directly under content.
            _stages(content.get("stages"), lesson["id"])


def _build_lesson(template: str, title: str, kp: KnowledgePoints) -> dict[str, Any]:
    """Build one lesson from ``kp.words`` using the requested template.

    Only ``intro`` / ``practice`` / ``review`` are wired (they all consume the
    extracted words); any other value falls back to ``intro``. bookplan2 Phase 5.
    """
    if template == "practice":
        return build_practice_lesson(title, "", words=kp.words)
    if template == "review":
        return build_review_lesson(
            title, "", source_words=kp.words, source_expressions=kp.expressions
        )
    return build_intro_lesson(title, "", words=kp.words)


def build_section_from_chapter(
    chapter: Chapter,
    kp: KnowledgePoints,
    idx: int,
    *,
    level: str = "A1",
    lesson_template: str = "intro",
) -> dict[str, Any]:
    """Build an importable section dict from a chapter and its knowledge points.

    - ``id`` = ``ch-{slug}-{idx}`` — deterministic so re-importing the same
      chapter routes through the merge path (same id → ``plan_section_merge``).
    - One unit holding one intro lesson built from ``kp.words`` via
      ``build_intro_lesson`` (showWord → translateSentence → fillBlank per word).
      All structural ids (unit/lesson/subLesson/stage/item) are rewritten
      deterministically from the section id by ``_rewrite_ids_deterministic``,
      so re-import is idempotent at every level of the tree.
    - Resources carried under the top-level ``words`` / ``expressions`` /
      ``grammarPoints`` keys (the only names ``merge_section_resources`` reads).
    - ``prerequisiteSectionIds`` left empty; the GUI import path fills it via
      ``setdefault``.
    """
    section_id = f"ch-{chapter.slug}-{idx}"
    lesson = _build_lesson(lesson_template, chapter.title, kp)
    unit = {
        "id": f"{section_id}-u1",
        "name": f"Chapter {idx}",
        "description": "",
        "lessons": [lesson],
    }
    section = {
        "id": section_id,
        "name": chapter.title,
        "description": chapter.title,
        "level": level,
        "prerequisiteSectionIds": [],
        "units": [unit],
        "words": list(kp.words),
        "expressions": list(kp.expressions),
        "grammarPoints": list(kp.grammarPoints),
    }
    _rewrite_ids_deterministic(section, section_id)
    return section