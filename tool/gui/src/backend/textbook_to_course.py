"""Build a schema-valid course section from a chapter + knowledge points.

The ④→⑤ step of the textbook import pipeline (bookplan.md): given a chopped
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
    short_id,
)
from src.backend.markdown_chopper import Chapter


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
      Unit/lesson ids are random ``short_id`` — accepted for MVP; re-import
      is out of scope.
    - Resources carried under the top-level ``words`` / ``expressions`` /
      ``grammarPoints`` keys (the only names ``merge_section_resources`` reads).
    - ``prerequisiteSectionIds`` left empty; the GUI import path fills it via
      ``setdefault``.
    """
    section_id = f"ch-{chapter.slug}-{idx}"
    lesson = _build_lesson(lesson_template, chapter.title, kp)
    unit = {
        "id": short_id("u"),
        "name": f"Chapter {idx}",
        "description": "",
        "lessons": [lesson],
    }
    return {
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