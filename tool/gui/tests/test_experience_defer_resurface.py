"""A3 ② defer/resurface integration (v4.66 P2).

Covers the corrected batch defer logic (hide during cooldown, re-tag on
resurface) and the ``_on_ambient_archived`` defer-vs-session split.
"""
from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone, UTC
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app

from src.backend.experience.context_bus import ExperienceContext
from src.backend.experience.defer_store import MAX_DISMISS, DeferStore
from src.backend.experience.proactive import (
    AmbientProposal,
    evaluate_ambient_batch,
    proposal_id_for,
)

NOW = datetime(2026, 7, 24, 12, 0, tzinfo=UTC)


def _ctx(**kwargs) -> ExperienceContext:
    defaults = {
        "healthy": False,
        "validate_error_count": 2,
        "empty_lesson_count": 1,
        "empty_lessons": ["l-empty"],
        "hygiene": {"placeholder_count": 0},
        "quality_by_section": {},
    }
    defaults.update(kwargs)
    return ExperienceContext(**defaults)


def _sug(priority: int, action_id: str, scope: dict | None = None) -> dict:
    return {
        "priority": priority,
        "title": action_id,
        "action_id": action_id,
        "scope": scope or {},
    }


class BatchDeferLogicTest(unittest.TestCase):
    def test_not_cooled_defer_is_hidden(self) -> None:
        store = DeferStore()
        pid = proposal_id_for("validate.open_and_fix", {"error_count": 2})
        store.add(pid, "validate.open_and_fix", now=NOW)  # cools at +15m
        sugs = [_sug(0, "validate.open_and_fix", {"error_count": 2})]
        # At NOW the proposal is in cooldown -> hidden (not shown, not archived).
        props = evaluate_ambient_batch(
            _ctx(), suggestions=sugs, defer_store=store, now=NOW
        )
        self.assertEqual(props, [])

    def test_cooled_defer_resurfaces_with_tag(self) -> None:
        store = DeferStore()
        pid = proposal_id_for("validate.open_and_fix", {"error_count": 2})
        store.add(pid, "validate.open_and_fix", now=NOW)
        sugs = [_sug(0, "validate.open_and_fix", {"error_count": 2})]
        later = NOW + timedelta(minutes=16)
        props = evaluate_ambient_batch(
            _ctx(), suggestions=sugs, defer_store=store, now=later
        )
        self.assertEqual(len(props), 1)
        self.assertEqual(props[0].source, "deferred_resurface")
        self.assertEqual(props[0].action_id, "validate.open_and_fix")
        # Real priority retained (P0), not a synthetic 98.
        self.assertEqual(props[0].priority, 0)

    def test_resolved_issue_does_not_resurface(self) -> None:
        store = DeferStore()
        pid = proposal_id_for("validate.open_and_fix", {"error_count": 2})
        store.add(pid, "validate.open_and_fix", now=NOW)
        later = NOW + timedelta(minutes=16)
        # No matching suggestion -> issue resolved -> nothing surfaces.
        props = evaluate_ambient_batch(
            _ctx(), suggestions=[], defer_store=store, now=later
        )
        self.assertEqual(props, [])

    def test_permanent_archive_after_max_dismiss(self) -> None:
        store = DeferStore()
        pid = proposal_id_for("validate.open_and_fix", {"error_count": 2})
        # T10: MAX_DISMISS defers now (15/30/60min, then permanent).
        for _ in range(MAX_DISMISS - 1):
            record = store.add(pid, "validate.open_and_fix", now=NOW)
            self.assertNotEqual(record.re_surface_after_iso, "")
        final = store.add(pid, now=NOW)
        self.assertEqual(final.re_surface_after_iso, "")
        self.assertIsNone(store.get(pid))  # dropped from store
        # Caller moves pid to session archive; batch then excludes it.
        sugs = [_sug(0, "validate.open_and_fix", {"error_count": 2})]
        props = evaluate_ambient_batch(
            _ctx(), suggestions=sugs, archived_ids=[pid], defer_store=store, now=NOW
        )
        self.assertEqual(props, [])


class AmbientDiscardControllerTest(unittest.TestCase):
    """T10: ✕ archives without spending one of the escalating defers."""

    def setUp(self) -> None:
        qt_app()
        self.messages: list[str] = []
        self.archived: set[str] = set()
        self.store = DeferStore()
        self.host = SimpleNamespace(
            _defer_store=self.store,
            _ambient_archived=self.archived,
            statusBar=lambda: SimpleNamespace(
                showMessage=lambda msg, *_a: self.messages.append(msg)
            ),
            experience_metrics=SimpleNamespace(inc_ambient=lambda *_a, **_k: None),
            ambient_banner=SimpleNamespace(proposals=lambda: []),
        )
        # refresh_ambient() would need a real banner; the archive decision
        # happens before it.
        patcher = patch(
            "src.application.ambient_controller.refresh_ambient",
            lambda *_a, **_k: None,
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_discard_archives_without_touching_the_defer_store(self) -> None:
        from src.application.ambient_controller import on_ambient_discarded

        on_ambient_discarded(self.host, "p-1")
        self.assertIn("p-1", self.archived)
        self.assertEqual(len(self.store), 0)  # no defer record created
        self.assertTrue(any("归档" in m for m in self.messages))

    def test_defer_then_discard_still_archives(self) -> None:
        from src.application.ambient_controller import (
            on_ambient_archived,
            on_ambient_discarded,
        )

        on_ambient_archived(self.host, "p-1")  # not in the banner queue -> legacy archive
        on_ambient_discarded(self.host, "p-1")
        self.assertIn("p-1", self.archived)

    def test_empty_pid_is_ignored(self) -> None:
        from src.application.ambient_controller import on_ambient_discarded

        on_ambient_discarded(self.host, "")
        self.assertEqual(self.archived, set())


if __name__ == "__main__":
    unittest.main()
