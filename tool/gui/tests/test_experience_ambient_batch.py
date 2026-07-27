"""A3 ① companion Ambient - batch evaluation + queue banner (v4.66 P1).

Covers:
- ``evaluate_ambient_batch`` (N<=3, sort, archive-skip, dedup, mute, None ctx)
- ``evaluate_ambient`` thin-wrapper backward compatibility
- ``AmbientBanner`` queue rendering (expanded top + collapsed rest), signals,
  and the no-setFocus source contract (D27).
- ``_refresh_ambient`` wiring (batch -> show_proposals) via the shared window.
"""
from __future__ import annotations

import inspect
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402

from src.backend.experience.context_bus import ExperienceContext  # noqa: E402
from src.backend.experience.proactive import (  # noqa: E402
    AmbientProposal,
    evaluate_ambient,
    evaluate_ambient_batch,
    make_mute,
    proposal_id_for,
    MUTE_PERMANENT,
)


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


# ---------------------------------------------------------------------------
# evaluate_ambient_batch - pure
# ---------------------------------------------------------------------------


class EvaluateAmbientBatchTest(unittest.TestCase):
    def test_none_ctx_returns_empty(self) -> None:
        self.assertEqual(evaluate_ambient_batch(None), [])

    def test_mute_returns_empty(self) -> None:
        self.assertEqual(
            evaluate_ambient_batch(_ctx(), mute=make_mute(MUTE_PERMANENT)),
            [],
        )

    def test_limit_and_priority_sort(self) -> None:
        sugs = [
            _sug(3, "quality.campaign_worst_n", {"section_id": "s1"}),
            _sug(0, "validate.open_and_fix", {"error_count": 2}),
            _sug(1, "lesson.fill_empty", {"empty_count": 1}),
            _sug(2, "resource.fill_stubs"),
        ]
        props = evaluate_ambient_batch(_ctx(), suggestions=sugs, limit=3)
        self.assertEqual(len(props), 3)
        # P0 first, then P1, then P2 (sorted ascending by priority).
        self.assertEqual(props[0].action_id, "validate.open_and_fix")
        self.assertEqual(props[1].action_id, "lesson.fill_empty")
        self.assertEqual(props[2].action_id, "resource.fill_stubs")

    def test_archive_skips(self) -> None:
        sugs = [_sug(0, "validate.open_and_fix", {"error_count": 2})]
        pid = proposal_id_for("validate.open_and_fix", sugs[0]["scope"])
        props = evaluate_ambient_batch(
            _ctx(), suggestions=sugs, archived_ids=[pid]
        )
        self.assertEqual(props, [])

    def test_dedup_by_id(self) -> None:
        # Two suggestions with the same stable id collapse to one proposal.
        sugs = [
            _sug(0, "validate.open_and_fix", {"error_count": 2}),
            _sug(0, "validate.open_and_fix", {"error_count": 2}),
        ]
        props = evaluate_ambient_batch(_ctx(), suggestions=sugs, limit=3)
        self.assertEqual(len(props), 1)

    def test_evaluate_ambient_wrapper_compat(self) -> None:
        # Old single-proposal API: returns first or None.
        sugs = [
            _sug(1, "lesson.fill_empty", {"empty_count": 1}),
            _sug(0, "validate.open_and_fix", {"error_count": 2}),
        ]
        prop = evaluate_ambient(_ctx(), suggestions=sugs)
        self.assertIsNotNone(prop)
        assert prop is not None
        self.assertEqual(prop.action_id, "validate.open_and_fix")
        self.assertIsNone(evaluate_ambient(None))
        self.assertIsNone(
            evaluate_ambient(_ctx(), mute=make_mute(MUTE_PERMANENT))
        )


# ---------------------------------------------------------------------------
# AmbientBanner - Qt (offscreen)
# ---------------------------------------------------------------------------


class AmbientBannerQueueTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def setUp(self) -> None:
        from src.widgets.ambient_banner import AmbientBanner

        self.banner = AmbientBanner()
        self.p0 = AmbientProposal(
            id="validate.open_and_fix|error_count=2",
            title="校验错误",
            body="2 个错误",
            action_id="validate.open_and_fix",
            scope={"error_count": 2},
            priority=0,
        )
        self.p1 = AmbientProposal(
            id="lesson.fill_empty|first_lesson_id=l-empty",
            title="空课",
            body="1 节空课",
            action_id="lesson.fill_empty",
            scope={"empty_count": 1},
            priority=1,
        )
        self.p2 = AmbientProposal(
            id="quality.campaign_worst_n|section_id=s1",
            title="低质",
            body="节 s1 偏低",
            action_id="quality.campaign_worst_n",
            scope={"section_id": "s1"},
            priority=3,
        )

    def test_empty_or_none_hides(self) -> None:
        self.banner.show_proposals(None)
        self.assertFalse(self.banner.isVisible())
        self.assertEqual(self.banner.proposals(), [])
        self.banner.show_proposals([])
        self.assertFalse(self.banner.isVisible())

    def test_renders_expanded_top_and_collapsed_rest(self) -> None:
        self.banner.show_proposals([self.p0, self.p1, self.p2])
        self.assertTrue(self.banner.isVisible())
        props = self.banner.proposals()
        self.assertEqual(len(props), 3)
        self.assertEqual(self.banner.proposal().id, self.p0.id)
        # Collapsed box visible only when queue > 1.
        self.assertTrue(self.banner._collapsed_box.isVisible())

    def test_single_proposal_hides_collapsed(self) -> None:
        self.banner.show_proposals([self.p0])
        self.assertTrue(self.banner.isVisible())
        self.assertEqual(len(self.banner.proposals()), 1)
        self.assertFalse(self.banner._collapsed_box.isVisible())

    def test_dedup_by_id_in_banner(self) -> None:
        self.banner.show_proposals([self.p0, self.p0])
        self.assertEqual(len(self.banner.proposals()), 1)

    def test_accept_emits_top_proposal(self) -> None:
        self.banner.show_proposals([self.p0, self.p1])
        received: list[object] = []
        self.banner.accepted.connect(lambda p: received.append(p))
        self.banner._accept_btn.click()
        self.assertEqual(len(received), 1)
        self.assertEqual(received[0].id, self.p0.id)

    def test_archive_top_emits_pid(self) -> None:
        self.banner.show_proposals([self.p0, self.p1])
        received: list[str] = []
        self.banner.archived.connect(lambda pid: received.append(pid))
        self.banner._later_btn.click()
        self.assertEqual(received, [self.p0.id])

    def test_collapsed_row_archive_emits_pid(self) -> None:
        self.banner.show_proposals([self.p0, self.p1, self.p2])
        received: list[str] = []
        self.banner.archived.connect(lambda pid: received.append(pid))
        self.banner._render()  # ensure collapsed rows built
        # The second collapsed row's ✕ button archives p2 (queue[2]).
        collapsed = self.banner._collapsed_rows
        self.assertEqual(len(collapsed), 2)
        xbtn = collapsed[-1].findChild(type(collapsed[-1].__class__))
        # Find the ✕ QPushButton inside the last collapsed row.
        from PySide6.QtWidgets import QPushButton

        buttons = collapsed[-1].findChildren(QPushButton)
        self.assertTrue(buttons, "collapsed row should have an archive button")
        buttons[0].click()
        self.assertEqual(received, [self.p2.id])

    def test_no_setfocus_source_contract(self) -> None:
        """D27: the banner must never steal focus."""
        from src.widgets.ambient_banner import AmbientBanner

        src = inspect.getsource(AmbientBanner)
        self.assertNotIn("setFocus", src)


# ---------------------------------------------------------------------------
# _refresh_ambient wiring - shared MainWindow
# ---------------------------------------------------------------------------


class RefreshAmbientWiringTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        from tests._mainwindow_fixture import build_main_window

        cls.win = build_main_window()

    def setUp(self) -> None:
        from tests._mainwindow_fixture import reset_main_window

        reset_main_window(self.win)

    def test_refresh_ambient_renders_queue_from_suggestions(self) -> None:
        """Copilot mode + 3 stubbed suggestions -> banner shows the queue."""
        self.win._settings_obj.experience_mode = "copilot"
        self.win._settings_obj.experience_mute_json = ""  # not muted
        self.win._ambient_archived.clear()
        # Stub the shell's retained context + suggestions so evaluate_ambient_batch
        # sees three ranked proposals without running the full build pipeline.
        self.win.experience._ctx = _ctx()
        self.win.experience._suggestions = [
            _sug(3, "quality.campaign_worst_n", {"section_id": "s1"}),
            _sug(0, "validate.open_and_fix", {"error_count": 2}),
            _sug(1, "lesson.fill_empty", {"empty_count": 1}),
        ]
        self.win._refresh_ambient()
        props = self.win.ambient_banner.proposals()
        self.assertEqual(len(props), 3)
        self.assertEqual(props[0].action_id, "validate.open_and_fix")  # P0 first
        # The banner retained the top proposal (isVisible() is unreliable
        # under offscreen when the parent window is not shown).
        self.assertIsNotNone(self.win.ambient_banner.proposal())


if __name__ == "__main__":
    unittest.main()
