"""Coerce raw knowledge-point drafts into schema-valid resource entries.

Pure-Python normalisation for the ③→④ step of the textbook import pipeline
(bookplan.md). The upstream source may be a hand-coded dict or (later) an LLM
JSON object — this module guarantees the three resource lists satisfy the
field constraints enforced by ``course_cli`` (word/expression need non-empty
``term`` and ``translation``; grammar point needs non-empty ``title``).

It does NOT call any LLM and does NOT touch the course adapter.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from src.backend.lesson_content import slugify


@dataclass
class KnowledgePoints:
    """Normalised resource groups ready for ``build_section_from_chapter``."""

    words: list[dict[str, Any]] = field(default_factory=list)
    expressions: list[dict[str, Any]] = field(default_factory=list)
    grammarPoints: list[dict[str, Any]] = field(default_factory=list)


def _coerce_word_entry(entry: dict[str, Any], *, id_prefix: str) -> dict[str, Any]:
    term = (entry.get("term") or "").strip()
    if not term:
        raise ValueError("word entry missing required 'term'")
    eid = (entry.get("id") or "").strip() or f"{id_prefix}w-{slugify(term)}"
    return {
        "id": eid,
        "term": term,
        "translation": (entry.get("translation") or "").strip(),
        "pronunciation": (entry.get("pronunciation") or "").strip(),
        "tags": list(entry.get("tags") or []),
    }


def _coerce_expression_entry(
    entry: dict[str, Any], *, id_prefix: str
) -> dict[str, Any]:
    term = (entry.get("term") or "").strip()
    if not term:
        raise ValueError("expression entry missing required 'term'")
    eid = (entry.get("id") or "").strip() or f"{id_prefix}e-{slugify(term)}"
    return {
        "id": eid,
        "term": term,
        "translation": (entry.get("translation") or "").strip(),
        "pronunciation": (entry.get("pronunciation") or "").strip(),
        "tags": list(entry.get("tags") or []),
    }


def _coerce_grammar_entry(
    entry: dict[str, Any], *, id_prefix: str
) -> dict[str, Any]:
    title = (entry.get("title") or "").strip()
    if not title:
        raise ValueError("grammar point entry missing required 'title'")
    gid = (entry.get("id") or "").strip() or f"{id_prefix}g-{slugify(title)}"
    return {
        "id": gid,
        "title": title,
        "explanation": entry.get("explanation") or "",
        "exampleExpressionIds": list(entry.get("exampleExpressionIds") or []),
        "exampleSentenceIds": list(entry.get("exampleSentenceIds") or []),
        "practiceItems": list(entry.get("practiceItems") or []),
    }


def _dedupe(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Keep the first entry per id; drop entries with empty id."""
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for e in entries:
        eid = e.get("id", "")
        if not eid or eid in seen:
            continue
        seen.add(eid)
        out.append(e)
    return out


def _raw_list(raw: dict[str, Any], *keys: str) -> list[Any]:
    """Return the first present list among ``keys`` (accepts aliases)."""
    for k in keys:
        v = raw.get(k)
        if isinstance(v, list):
            return v
    return []


def coerce_knowledge_points(raw: dict[str, Any], *, id_prefix: str = "") -> KnowledgePoints:
    """Coerce a raw draft into a :class:`KnowledgePoints`.

    Accepted key aliases: ``words`` or ``vocab``; ``expressions``; ``grammarPoints``.
    Each entry is normalised to its full schema shape. Missing ids are
    synthesised from ``slugify(term/title)``. Word/expression entries require a
    non-empty ``term``; grammar points require a non-empty ``title`` — both
    raise ``ValueError``. Duplicate ids are collapsed to the first occurrence.
    """
    if not isinstance(raw, dict):
        raise TypeError("raw knowledge points must be a dict")

    words = _dedupe(
        _coerce_word_entry(e, id_prefix=id_prefix)
        for e in _raw_list(raw, "words", "vocab")
        if isinstance(e, dict)
    )
    expressions = _dedupe(
        _coerce_expression_entry(e, id_prefix=id_prefix)
        for e in _raw_list(raw, "expressions")
        if isinstance(e, dict)
    )
    grammar_points = _dedupe(
        _coerce_grammar_entry(e, id_prefix=id_prefix)
        for e in _raw_list(raw, "grammarPoints")
        if isinstance(e, dict)
    )
    return KnowledgePoints(words=words, expressions=expressions, grammarPoints=grammar_points)