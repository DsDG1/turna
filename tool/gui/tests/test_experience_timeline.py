"""E1.7 S-13: ExperienceTimeline ring buffer."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.timeline import (  # noqa: E402
    ExperienceTimeline,
    make_event,
)


class TimelineTest(unittest.TestCase):
    def test_append_and_recent_order(self) -> None:
        tl = ExperienceTimeline(maxlen=10)
        tl.record("a", "first", action_id="x")
        tl.record("b", "second", action_id="y")
        recent = tl.recent(2)
        self.assertEqual([e.summary for e in recent], ["first", "second"])

    def test_maxlen_evicts_oldest(self) -> None:
        tl = ExperienceTimeline(maxlen=3)
        for i in range(5):
            tl.record("k", f"e{i}")
        self.assertEqual(len(tl), 3)
        self.assertEqual([e.summary for e in tl.all()], ["e2", "e3", "e4"])

    def test_clear(self) -> None:
        tl = ExperienceTimeline()
        tl.record("k", "x")
        tl.clear()
        self.assertEqual(len(tl), 0)
        self.assertEqual(tl.recent(), [])

    def test_dict_append(self) -> None:
        tl = ExperienceTimeline()
        tl.append({"kind": "chip.apply", "summary": "ok", "action_id": "item.rewrite"})
        self.assertEqual(tl.recent(1)[0].kind, "chip.apply")

    def test_make_event_and_to_dict(self) -> None:
        e = make_event("t", "sum", action_id="a", scope={"lesson_id": "l1"}, ts=1.0)
        d = e.to_dict()
        self.assertEqual(d["action_id"], "a")
        self.assertEqual(d["scope"]["lesson_id"], "l1")

    def test_replayable_skips_app_actions(self) -> None:
        tl = ExperienceTimeline()
        tl.record("p", "save", action_id="app.save")
        tl.record("p", "fix", action_id="validate.open_and_fix")
        tl.record("p", "fill", action_id="lesson.fill_empty")
        rep = tl.replayable(5)
        self.assertEqual(len(rep), 2)
        self.assertEqual(rep[0].action_id, "validate.open_and_fix")


if __name__ == "__main__":
    unittest.main()
