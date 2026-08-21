"""Group validation problems into AI-fix batches by course node.

Pure functions, no Qt. Used by ValidationReport multi-select and app.py
batch scheduling so one merge preview covers all problems on the same node.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from src.teacher.error_mapper import problem_to_node_ref


@dataclass
class FixBatch:
    """One AI fix unit: all problems sharing the same node ref."""

    kind: str  # section | unit | lesson
    node_id: str
    problems: list[dict[str, Any]] = field(default_factory=list)

    @property
    def node_ref(self) -> tuple[str, str]:
        return (self.kind, self.node_id)


def group_problems_for_fix(
    problems: list[dict[str, Any]] | None,
    sections: list[dict[str, Any]] | None,
    *,
    fallback_ref: tuple[str, str] | None = None,
) -> list[FixBatch]:
    """Group problems by (kind, id) node ref in first-seen order.

    Problems with no resolvable path are attached to ``fallback_ref`` when
    provided; otherwise they form a skipped group (not returned).

    Returns a list of ``FixBatch`` suitable for sequential AiFixDialog runs.
    """
    order: list[tuple[str, str]] = []
    buckets: dict[tuple[str, str], list[dict[str, Any]]] = {}
    secs = sections or []

    for problem in problems or []:
        if not isinstance(problem, dict):
            continue
        ref = problem_to_node_ref(problem, secs)
        if ref is None:
            ref = fallback_ref
        if ref is None:
            continue
        if ref not in buckets:
            buckets[ref] = []
            order.append(ref)
        buckets[ref].append(problem)

    return [
        FixBatch(kind=kind, node_id=node_id, problems=list(buckets[(kind, node_id)]))
        for kind, node_id in order
    ]


def selected_problems_with_refs(
    problems: list[dict[str, Any]] | None,
    sections: list[dict[str, Any]] | None,
) -> list[tuple[dict[str, Any], tuple[str, str] | None]]:
    """Pair each problem with its node ref (or None)."""
    secs = sections or []
    out: list[tuple[dict[str, Any], tuple[str, str] | None]] = []
    for problem in problems or []:
        if not isinstance(problem, dict):
            continue
        out.append((problem, problem_to_node_ref(problem, secs)))
    return out
