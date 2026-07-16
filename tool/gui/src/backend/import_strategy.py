"""Import-strategy primitives for the textbook import flow (bookplan2 Phase 4).

The strategy decides what happens when a chapter's generated section id
already exists in the loaded course:

- ``MERGE``           : show ``AiMergePreviewDialog`` and merge unit/lesson-by-unit
  (the historical default, also used by the single-section AI generator).
- ``SKIP_EXISTING``   : skip the chapter entirely, leave the existing section.
- ``FORCE_REPLACE``   : overwrite the existing section wholesale via
  ``AiEditSectionCommand`` (no preview dialog).
- ``APPEND_AS_NEW``   : import as an independent section with a fresh,
  non-colliding id.

``resolve_action`` turns ``(exists_in_course, strategy)`` into a concrete
command-level action so the decision is unit-testable independent of Qt /
``app.py``. ``unique_section_id`` produces a non-colliding id for the
``APPEND_AS_NEW`` path.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any, Literal


class ImportStrategy(str, Enum):
    """How to handle a section-id collision during textbook import."""

    MERGE = "merge"
    SKIP_EXISTING = "skip_existing"
    FORCE_REPLACE = "force_replace"
    APPEND_AS_NEW = "append_as_new"


# Command-level action resolved from (collision, strategy).
ImportAction = Literal["append", "merge", "skip", "replace", "append_new"]


def resolve_action(exists_in_course: bool, strategy: str) -> ImportAction:
    """Return the command-level action for a section given collision + strategy.

    When the section id does **not** collide, every strategy just appends (the
    id is already fresh; ``APPEND_AS_NEW`` therefore degenerates to ``append``).
    On collision, the strategy selects the action. Unknown strategies fall back
    to ``merge`` so a bad persisted value can never silently destroy data.
    """
    if not exists_in_course:
        return "append"
    if strategy == ImportStrategy.SKIP_EXISTING.value:
        return "skip"
    if strategy == ImportStrategy.FORCE_REPLACE.value:
        return "replace"
    if strategy == ImportStrategy.APPEND_AS_NEW.value:
        return "append_new"
    # MERGE or anything unknown -> the safe, interactive default.
    return "merge"


def _existing_section_ids(adapter: Any | None) -> set[str]:
    """Collect section ids from both ``sections`` and ``index["sections"]``."""
    if adapter is None:
        return set()
    ids = {s.get("id", "") for s in getattr(adapter, "sections", []) or []}
    for entry in getattr(adapter, "index", {}).get("sections", []) or []:
        if isinstance(entry, dict):
            ids.add(entry.get("id", ""))
    return {i for i in ids if i}


def _unique_against(taken: set[str], base_sid: str) -> str:
    """Return an id derived from ``base_sid`` that is not in ``taken``.

    Shared by ``unique_section_id`` (single-section, checks the live adapter) and
    ``plan_bulk_import`` (simulates a sequential batch against a growing set).
    """
    if base_sid not in taken:
        return base_sid
    suffix = 2
    while f"{base_sid}-{suffix}" in taken:
        suffix += 1
    return f"{base_sid}-{suffix}"


def unique_section_id(adapter: Any | None, base_sid: str) -> str:
    """Return a section id that does not collide with the loaded course.

    For ``APPEND_AS_NEW``. If ``base_sid`` is free, return it unchanged;
    otherwise try ``{base_sid}-2``, ``-3``, ... With ``adapter=None`` the
    base id is returned as-is (no course to collide with).
    """
    return _unique_against(_existing_section_ids(adapter), base_sid)


@dataclass(frozen=True)
class SectionImportPlan:
    """Per-section decision for a bulk textbook import (bookplan2 Phase 4).

    ``target_id`` is the id that **will** be used when the section is actually
    imported: for ``append_new`` it is a fresh non-colliding id (simulated
    against the course plus previously-planned sections); for every other action
    it equals ``source_id``.
    """

    index: int
    source_id: str
    target_id: str
    exists: bool
    action: ImportAction


@dataclass(frozen=True)
class SectionImportPreview:
    """A ``SectionImportPlan`` enriched with chapter + resource counts for the
    bulk-import preview panel (bookplan2 Phase 4).

    ``new_*`` / ``duplicate_*`` are derived from the ``KnowledgeMerger`` report:
    a resource is ``duplicate`` if its key collides with another chapter or with
    the loaded course, ``new`` otherwise. Counts reflect the post-merge state
    (the merger rewrites ids, never removes entries).
    """

    chapter_index: int
    title: str
    source_id: str
    target_id: str
    exists: bool
    action: ImportAction
    word_count: int
    expression_count: int
    grammar_count: int
    new_words: int
    new_expressions: int
    new_grammar: int
    duplicate_words: int
    duplicate_expressions: int
    duplicate_grammar: int


def plan_bulk_import(
    sections: list[dict[str, Any]],
    adapter: Any | None,
    strategy: str,
) -> list[SectionImportPlan]:
    """Simulate a sequential batch import and return one plan per section.

    Shared by the bulk-import preview (controller, read-only) and
    ``app.py`` execution so both agree on ids / actions. The simulation tracks
    ids consumed by earlier sections in the batch so that ``append_new`` never
    collides with a section planned earlier in the same run.
    """
    taken = set(_existing_section_ids(adapter))
    plans: list[SectionImportPlan] = []
    for i, section in enumerate(sections):
        sid = section.get("id", "") if isinstance(section, dict) else ""
        exists = bool(sid) and sid in taken
        action = resolve_action(exists, strategy)
        if action == "append_new":
            target_id = _unique_against(taken, sid)
        else:
            target_id = sid
        if action != "skip":
            taken.add(target_id)
        plans.append(
            SectionImportPlan(
                index=i,
                source_id=sid,
                target_id=target_id,
                exists=exists,
                action=action,
            )
        )
    return plans
