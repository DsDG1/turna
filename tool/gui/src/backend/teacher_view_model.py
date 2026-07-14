"""Pure view-model helpers for teacher-view question cards (C2).

Extracts the item->card field logic that previously lived inline in the
PySide6-bound ``QuestionCard`` so it can be unit-tested in the sandbox
(without PySide6). These functions operate only on plain dicts and the
adapter's resource lists, never importing Qt.
"""
from __future__ import annotations

from typing import Any

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import INTERACTION_SCHEMA


def prompt_for(item: dict[str, Any]) -> str:
    """Return the human-facing prompt/lead text for an item, regardless of
    which field the runtimeType stores it in."""
    for field in ("prompt", "sentence", "source", "statement"):
        value = item.get(field)
        if value:
            return str(value)
    return ""


def correct_index_for(item: dict[str, Any]) -> int:
    """Return the single correct option index for exclusive-choice types.

    Defaults to 0 when missing/invalid; never raises.
    """
    try:
        return int(item.get("correctIndex", 0) or 0)
    except (TypeError, ValueError):
        return 0


def correct_indices_for(item: dict[str, Any]) -> list[int]:
    """Return the list of correct option indices for multi-select types."""
    raw = item.get("correctIndices", []) or []
    out: list[int] = []
    for v in raw:
        try:
            out.append(int(v))
        except (TypeError, ValueError):
            continue
    return out


def text_answer_for(item: dict[str, Any]) -> str:
    """Return the expected text answer for fill-blank / translate / short
    answer / type-the-word types."""
    for field in ("expected", "answer", "expectedAnswer"):
        value = item.get(field)
        if value is not None and value != "":
            return str(value)
    return ""


def bool_answer_for(item: dict[str, Any]) -> bool:
    """Return the boolean answer for readingTrueFalse."""
    return bool(item.get("answer", False))


def word_label(adapter: CourseAdapter, word_id: str) -> str:
    """Resolve a wordId to a ``term — translation`` display string, or the
    raw id if the word is not found."""
    if not word_id:
        return ""
    for w in adapter.vocab:
        if w.get("id") == word_id:
            return f"{w.get('term', word_id)} — {w.get('translation', '')}"
    return word_id


def expression_label(adapter: CourseAdapter, expression_id: str) -> str:
    """Resolve an expressionId to a display string."""
    if not expression_id:
        return ""
    for e in adapter.expressions:
        if e.get("id") == expression_id:
            return f"{e.get('term', expression_id)} — {e.get('translation', '')}"
    return expression_id


def grammar_label(adapter: CourseAdapter, grammar_id: str) -> str:
    """Resolve a grammarPointId to its title."""
    if not grammar_id:
        return ""
    for g in adapter.grammar_points:
        if g.get("id") == grammar_id:
            return g.get("title", grammar_id)
    return grammar_id


def visible_field_specs(runtime_type: str) -> list[Any]:
    """Return the schema FieldSpecs for a runtimeType, excluding the hidden
    engineering fields (id / runtimeType / grammarPointId handled separately)."""
    schema = INTERACTION_SCHEMA.get(runtime_type, [])
    hidden = {"id", "runtimeType"}
    return [spec for spec in schema if spec.name not in hidden]


def options_for(item: dict[str, Any]) -> list[str]:
    """Return the option strings for choice types as a plain list."""
    raw = item.get("options", []) or []
    return [str(o) for o in raw]


def is_answerable(runtime_type: str) -> bool:
    """Whether the preview / card can be answered (vs. display-only)."""
    return runtime_type not in ("showWord", "reorderSentence", "listenOnly")