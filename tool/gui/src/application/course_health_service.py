"""Application facade for the course health audit (P0-1).

The dialog layer must not import ``src.backend`` directly: ``guard-gui`` pins
``max_ui_backend_imports`` as a ratchet, so new UI code would either break the
gate or eat into an unrelated budget. This module is the single seam between
the overview dialog and the pure audit module.
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from src.backend.course_health import audit_course, build_repair_plan
from src.backend.experience import get_action

logger = logging.getLogger(__name__)

_DATA_ERRORS = (AttributeError, IndexError, KeyError, TypeError, ValueError)


def _action_title(action_id: str) -> str:
    """Human label for an existing action id; empty id stays empty."""
    if not action_id:
        return ""
    spec = get_action(action_id)
    if spec is None:
        return action_id
    return str(getattr(spec, "title", "") or action_id)


class CourseHealthService:
    """Read the adapter once and produce a JSON-friendly audit report."""

    def __init__(self, adapter: Any) -> None:
        self._adapter = adapter

    def build_report(self) -> dict[str, Any]:
        """Run the audit; never raises for a malformed course.

        The report is plain data so the dialog can render it without importing
        backend types.
        """
        sections = list(getattr(self._adapter, "sections", None) or [])
        vocab = list(getattr(self._adapter, "vocab", None) or [])
        expressions = list(getattr(self._adapter, "expressions", None) or [])
        grammar_points = list(getattr(self._adapter, "grammar_points", None) or [])
        index = getattr(self._adapter, "index", None) or {}

        duplicates: list[dict[str, Any]] = []
        try:
            detect = getattr(self._adapter, "detect_duplicates", None)
            if callable(detect):
                duplicates = list(detect() or [])
        except _DATA_ERRORS:
            logger.debug(
                "course_health_service: duplicate scan failed", exc_info=True
            )

        from src.backend.experience.term_conflict_skill import (
            evaluate_term_conflicts,
        )

        term_conflicts = evaluate_term_conflicts(self._adapter)

        findings = audit_course(
            sections,
            vocab=vocab,
            expressions=expressions,
            grammar_points=grammar_points,
            default_level=str(index.get("level") or "A1"),
            duplicates=duplicates,
            term_conflicts=term_conflicts,
        )
        steps = build_repair_plan(findings)

        counts = {"error": 0, "warning": 0, "info": 0}
        for item in findings:
            if item.severity in counts:
                counts[item.severity] += 1

        finding_dicts = []
        for item in findings:
            data = item.to_dict()
            data["action_title"] = _action_title(item.action_id)
            finding_dicts.append(data)
        step_dicts = []
        for step in steps:
            data = step.to_dict()
            data["action_title"] = _action_title(step.action_id)
            step_dicts.append(data)

        completion_findings = [
            item for item in finding_dicts if item.get("kind") == "section_planned"
        ]
        completion_ids = {
            (item.get("section_id"), item.get("finding_id"))
            for item in completion_findings
        }
        technical_findings = [
            item
            for item in finding_dicts
            if (item.get("section_id"), item.get("finding_id")) not in completion_ids
        ]
        nonempty_sections = sum(bool(section.get("units")) for section in sections)
        return {
            "findings": finding_dicts,
            "technical_findings": technical_findings,
            "completion_findings": completion_findings,
            "coverage": {
                "sections": len(sections),
                "nonempty_sections": nonempty_sections,
                "planned_sections": len(sections) - nonempty_sections,
            },
            "steps": step_dicts,
            "counts": counts,
            "estimated_calls": sum(step.estimated_calls for step in steps),
            "scanned_at": datetime.now().isoformat(timespec="seconds"),
        }
