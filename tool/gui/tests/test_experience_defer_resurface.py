"""A3 ② defer/resurface integration (v4.66 P2).

Covers the corrected batch defer logic (hide during cooldown, re-tag on
resurface) and the ``_on_ambient_archived`` defer-vs-session split.
"""
from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402

from src.backend.experience.context_bus import ExperienceContext  # noqa: E402
from src.backend.experience.defer_store import DeferStore  # noqa: E402
from src.backend.experience.proactive import (  # noqa: E402
    AmbientProposal,
    evaluate_ambient_batch,
    proposal_id_for,
)

NOW = datetime(2026, 7, 24, 12, 0, tzinfo=timezone.utc)


def _ctx(**kwargs) -> ExperienceContext:
    defaults = dict(
        healthy=False,
        validate_error_count=2,
        empty_lesson_count=1,
        empty_lessons=["l-empty"],
        hygiene={"placeholder_count": 0},
        quality_by_section={},
    )
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
        store.add(pid, "validate.open_and_fix", now=NOW)
        store.add(pid, now=NOW)
        r3 = store.add(pid, now=NOW)  # dismiss_count == 3 -> permanent
        self.assertEqual(r3.re_surface_after_iso, "")
        self.assertIsNone(store.get(pid))  # dropped from store
        # Caller moves pid to session archive; batch then excludes it.
        sugs = [_sug(0, "validate.open_and_fix", {"error_count": 2})]
        props = evaluate_ambient_batch(
            _ctx(), suggestions=sugs, archived_ids=[pid], defer_store=store, now=NOW
        )
        self.assertEqual(props, [])


@unittest.skip("Ambient banner and MainWindow.experience retired")
class ArchiveHandlerDeferSplitTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window

        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)
        # Stub a matching live suggestion so purge_resolved() in _refresh_ambient
        # does not treat the just-deferred proposal as resolved (empty current).
        self.win.experience._ctx = None
        self.win.experience._suggestions = [
            _sug(0, "validate.open_and_fix", {"error_count": 2})
        ]
        self.win._ambient_archived.clear()
        self.win._defer_store = DeferStore()
        self.prop = AmbientProposal(
            id=proposal_id_for("validate.open_and_fix", {"error_count": 2}),
            title="校验错误",
            body="2 个错误",
            action_id="validate.open_and_fix",
            scope={"error_count": 2},
            priority=0,
        )
        self.win.ambient_banner.show_proposals([self.prop])

    def test_setting_off_uses_session_archive(self) -> None:
        self.win._settings_obj.experience_defer_resurface = False
        self.win._on_ambient_archived(self.prop.id)
        self.assertIn(self.prop.id, self.win._ambient_archived)
        self.assertEqual(len(self.win._defer_store), 0)

    def test_setting_on_defers_to_store(self) -> None:
        self.win._settings_obj.experience_defer_resurface = True
        self.win._on_ambient_archived(self.prop.id)
        self.assertNotIn(self.prop.id, self.win._ambient_archived)
        self.assertEqual(len(self.win._defer_store), 1)
        self.assertIsNotNone(self.win._defer_store.get(self.prop.id))


if __name__ == "__main__":
    unittest.main()
