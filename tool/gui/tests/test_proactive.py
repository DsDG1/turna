"""E2.0 C-12: proactive ambient engine."""
from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.context_bus import ExperienceContext  # noqa: E402
from src.backend.experience.proactive import (  # noqa: E402
    MUTE_HOURS4,
    MUTE_OFF,
    MUTE_PERMANENT,
    MUTE_TODAY,
    AmbientProposal,
    evaluate_ambient,
    make_mute,
    proposal_id_for,
    suggestion_to_proposal,
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


class MuteStateTest(unittest.TestCase):
    def test_off_not_active(self) -> None:
        self.assertFalse(make_mute(MUTE_OFF).is_active())

    def test_permanent_active(self) -> None:
        self.assertTrue(make_mute(MUTE_PERMANENT).is_active())

    def test_today_active_same_day(self) -> None:
        now = datetime(2026, 7, 21, 12, 0, tzinfo=timezone.utc)
        m = make_mute(MUTE_TODAY, now=now)
        self.assertTrue(m.is_active(now))
        next_day = now + timedelta(days=1)
        self.assertFalse(m.is_active(next_day))

    def test_hours4_window(self) -> None:
        now = datetime(2026, 7, 21, 10, 0, tzinfo=timezone.utc)
        m = make_mute(MUTE_HOURS4, now=now)
        self.assertTrue(m.is_active(now + timedelta(hours=1)))
        self.assertFalse(m.is_active(now + timedelta(hours=5)))

    def test_round_trip_dict(self) -> None:
        from src.backend.experience.proactive import MuteState

        m = make_mute(MUTE_PERMANENT)
        m2 = MuteState.from_dict(m.to_dict())
        self.assertTrue(m2.is_active())


class EvaluateAmbientTest(unittest.TestCase):
    def test_none_ctx(self) -> None:
        self.assertIsNone(evaluate_ambient(None))

    def test_mute_blocks(self) -> None:
        prop = evaluate_ambient(_ctx(), mute=make_mute(MUTE_PERMANENT))
        self.assertIsNone(prop)

    def test_p0_errors_win(self) -> None:
        prop = evaluate_ambient(_ctx())
        self.assertIsNotNone(prop)
        assert prop is not None
        self.assertEqual(prop.action_id, "validate.open_and_fix")
        self.assertEqual(prop.priority, 0)

    def test_archive_skips(self) -> None:
        sug = {
            "priority": 0,
            "title": "fix",
            "action_id": "validate.open_and_fix",
            "scope": {"error_count": 2},
        }
        pid = proposal_id_for("validate.open_and_fix", sug["scope"])
        prop = evaluate_ambient(
            _ctx(),
            suggestions=[sug],
            archived_ids=[pid],
        )
        self.assertIsNone(prop)

    def test_empty_lesson_when_no_errors(self) -> None:
        prop = evaluate_ambient(
            _ctx(validate_error_count=0, validate_problems=[]),
        )
        self.assertIsNotNone(prop)
        assert prop is not None
        self.assertEqual(prop.action_id, "lesson.fill_empty")

    def test_suggestion_to_proposal(self) -> None:
        p = suggestion_to_proposal(
            {
                "priority": 3,
                "title": "低质",
                "action_id": "quality.campaign_worst_n",
                "scope": {"section_id": "s1"},
            }
        )
        self.assertIsInstance(p, AmbientProposal)
        self.assertIn("s1", p.body)


if __name__ == "__main__":
    unittest.main()
