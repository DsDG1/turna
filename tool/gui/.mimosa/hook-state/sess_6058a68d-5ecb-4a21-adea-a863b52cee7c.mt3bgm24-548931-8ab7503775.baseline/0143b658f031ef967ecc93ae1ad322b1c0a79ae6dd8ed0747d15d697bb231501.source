"""Global dedup + course-collision detection for textbook knowledge points.

bookplan2 Phase 3/4. The per-chapter extractor synthesises resource ids with a
per-chapter prefix (``ch-{chapter.slug}-w-{slugify(term)}``), so the **same**
term extracted from two different chapters gets two different ids. Because
``CourseAdapter.merge_section_resources`` dedups by ``id`` only, those two
entries would both land in ``vocab.json`` as duplicate terms.

``KnowledgeMerger`` closes that gap with two read-only / mutating passes:

- **Intra-project duplicates**: entries that share a resource key
  (``term``+``translation`` for words/expressions, ``title`` for grammar) across
  chapters. ``apply`` rewrites every later occurrence's ``id`` to the first
  occurrence's id, so both chapters' lessons still teach the word but the global
  resource list gains it only once.
- **Course collisions**: a project entry whose key already exists in the loaded
  course. ``apply`` rewrites the project entry's ``id`` to the existing course
  entry's id, so ``merge_section_resources`` skips it instead of creating a
  duplicate term.

Both passes are idempotent: re-running ``apply`` on already-merged knowledge
records no collisions. ``analyze`` is the read-only twin of ``apply`` and feeds
the bulk-import preview without mutating review state.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any, Literal

from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter

ResourceType = Literal["word", "expression", "grammarPoint"]
CollisionKind = Literal["intra_project", "course"]


def resource_key(resource_type: ResourceType, entry: dict[str, Any]) -> tuple:
    """Identity key for duplicate detection.

    Words/expressions match on (term, translation); grammar points on title.
    Mirrors ``extraction_quality._resource_key`` so the two modules agree on
    what counts as a duplicate.
    """
    if resource_type == "grammarPoint":
        return (resource_type, _normalise(entry.get("title", "")))
    return (
        resource_type,
        _normalise(entry.get("term", "")),
        _normalise(entry.get("translation", "")),
    )


def _normalise(text: str) -> str:
    """Lower-case, strip whitespace/punctuation for fuzzy duplicate checks."""
    return re.sub(r"[^\w\s]", "", str(text).lower()).strip()


@dataclass(frozen=True)
class MergeCollision:
    """One resource whose id will change (or would change) during merge."""

    chapter_index: int
    resource_type: ResourceType
    resource_index: int
    entry_id: str
    target_id: str
    kind: CollisionKind


@dataclass
class MergeReport:
    """Result of a merge analysis/apply pass."""

    intra_project: list[MergeCollision] = field(default_factory=list)
    course_collisions: list[MergeCollision] = field(default_factory=list)

    @property
    def intra_project_count(self) -> int:
        return len(self.intra_project)

    @property
    def course_collision_count(self) -> int:
        return len(self.course_collisions)

    @property
    def total_count(self) -> int:
        return len(self.intra_project) + len(self.course_collisions)

    def collisions_for_chapter(self, chapter_index: int) -> list[MergeCollision]:
        return [
            c
            for c in (*self.intra_project, *self.course_collisions)
            if c.chapter_index == chapter_index
        ]


def _collect_resources(
    chapters: list[tuple[Chapter, KnowledgePoints | None]],
) -> list[tuple[int, ResourceType, int, dict[str, Any]]]:
    """Flatten kept-chapter resources into (chapter_index, type, index, entry)."""
    out: list[tuple[int, ResourceType, int, dict[str, Any]]] = []
    for ci, (_ch, kp) in enumerate(chapters):
        if kp is None:
            continue
        for i, w in enumerate(kp.words):
            out.append((ci, "word", i, w))
        for i, e in enumerate(kp.expressions):
            out.append((ci, "expression", i, e))
        for i, g in enumerate(kp.grammarPoints):
            out.append((ci, "grammarPoint", i, g))
    return out


def _course_key_to_id(adapter: Any) -> dict[tuple, str]:
    """Map each course resource key -> its id (for collision alignment)."""
    mapping: dict[tuple, str] = {}
    if adapter is None:
        return mapping
    for w in getattr(adapter, "vocab", []) or []:
        if isinstance(w, dict):
            mapping.setdefault(resource_key("word", w), str(w.get("id", "")).strip())
    for e in getattr(adapter, "expressions", []) or []:
        if isinstance(e, dict):
            mapping.setdefault(resource_key("expression", e), str(e.get("id", "")).strip())
    for g in getattr(adapter, "grammar_points", []) or []:
        if isinstance(g, dict):
            mapping.setdefault(resource_key("grammarPoint", g), str(g.get("id", "")).strip())
    return mapping


def _course_keys(adapter: Any) -> dict[ResourceType, set[tuple]]:
    keys: dict[ResourceType, set[tuple]] = {
        "word": set(),
        "expression": set(),
        "grammarPoint": set(),
    }
    if adapter is None:
        return keys
    for w in getattr(adapter, "vocab", []) or []:
        if isinstance(w, dict):
            keys["word"].add(resource_key("word", w))
    for e in getattr(adapter, "expressions", []) or []:
        if isinstance(e, dict):
            keys["expression"].add(resource_key("expression", e))
    for g in getattr(adapter, "grammar_points", []) or []:
        if isinstance(g, dict):
            keys["grammarPoint"].add(resource_key("grammarPoint", g))
    return keys


def analyze(
    chapters: list[tuple[Chapter, KnowledgePoints | None]],
    adapter: Any | None = None,
) -> MergeReport:
    """Compute a merge report without mutating ``chapters``.

    A resource can be a course collision (key matches an existing course entry)
    or an intra-project duplicate (same key as an earlier chapter), never both:
    course collision is group-level, so when it applies every occurrence points
    at the course id and there is nothing left to unify intra-project.
    """
    resources = _collect_resources(chapters)
    course_keys = _course_keys(adapter)
    course_key_to_id = _course_key_to_id(adapter)

    groups: dict[tuple, list[tuple[int, ResourceType, int, dict[str, Any]]]] = {}
    for ci, rtype, ri, entry in resources:
        groups.setdefault(resource_key(rtype, entry), []).append((ci, rtype, ri, entry))

    report = MergeReport()
    for key, occurrences in groups.items():
        rtype = occurrences[0][1]
        if key in course_keys.get(rtype, set()):
            target_id = course_key_to_id.get(key, "")
            if not target_id:
                # Course entry has no id to align to; record the collision for
                # display but leave the project entry unchanged on apply.
                for ci, _rt, ri, entry in occurrences:
                    report.course_collisions.append(
                        MergeCollision(ci, rtype, ri, str(entry.get("id", "")), "", "course")
                    )
                continue
            for ci, _rt, ri, entry in occurrences:
                eid = str(entry.get("id", "")).strip()
                if eid != target_id:
                    report.course_collisions.append(
                        MergeCollision(ci, rtype, ri, eid, target_id, "course")
                    )
            continue
        if len(occurrences) > 1:
            canonical_id = str(occurrences[0][3].get("id", "")).strip()
            if not canonical_id:
                continue
            for ci, _rt, ri, entry in occurrences[1:]:
                eid = str(entry.get("id", "")).strip()
                if eid != canonical_id:
                    report.intra_project.append(
                        MergeCollision(ci, rtype, ri, eid, canonical_id, "intra_project")
                    )
    return report


def apply(
    chapters: list[tuple[Chapter, KnowledgePoints | None]],
    adapter: Any | None = None,
) -> MergeReport:
    """Mutate each chapter's ``KnowledgePoints`` to dedup ids, return the report.

    Rewrites the ``id`` field of colliding entries in place. Idempotent: a second
    call records no collisions because every target id already matches.
    """
    report = analyze(chapters, adapter)
    for collision in (*report.intra_project, *report.course_collisions):
        if not collision.target_id:
            continue
        if not (0 <= collision.chapter_index < len(chapters)):
            continue
        _ch, kp = chapters[collision.chapter_index]
        if kp is None:
            continue
        entry = _entry_at(kp, collision.resource_type, collision.resource_index)
        if entry is not None:
            entry["id"] = collision.target_id
    return report


def _entry_at(
    kp: KnowledgePoints, resource_type: ResourceType, index: int
) -> dict[str, Any] | None:
    if resource_type == "word":
        return kp.words[index] if 0 <= index < len(kp.words) else None
    if resource_type == "expression":
        return kp.expressions[index] if 0 <= index < len(kp.expressions) else None
    return kp.grammarPoints[index] if 0 <= index < len(kp.grammarPoints) else None
