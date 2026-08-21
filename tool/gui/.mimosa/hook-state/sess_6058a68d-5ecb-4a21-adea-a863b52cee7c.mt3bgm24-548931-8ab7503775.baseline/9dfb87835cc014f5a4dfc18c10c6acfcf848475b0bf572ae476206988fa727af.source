"""E5/M3 workshop_draft pure helpers + Context injection."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.workshop_draft import (  # noqa: E402
    WORKSHOP_DRAFT_KEYS,
    build_workshop_draft,
    format_workshop_draft_line,
    normalize_workshop_draft,
)
from src.backend.experience import build_experience_context  # noqa: E402


class WorkshopDraftBuildTest(unittest.TestCase):
    def test_idle_without_project(self) -> None:
        self.assertIsNone(build_workshop_draft(open=False))
        self.assertIsNone(build_workshop_draft(open=False, project_id=""))

    def test_open_without_project_still_snapshots(self) -> None:
        d = build_workshop_draft(open=True)
        self.assertIsNotNone(d)
        assert d is not None
        self.assertTrue(d["open"])
        self.assertIsNone(d["project_id"])

    def test_project_closed_still_has_id(self) -> None:
        d = build_workshop_draft(
            open=False,
            project_id="p1",
            project_name="Greetings",
            has_draft=True,
            draft_section_count=2,
            imported_section_ids=["s1", "s1", ""],
        )
        self.assertIsNotNone(d)
        assert d is not None
        self.assertEqual(d["project_id"], "p1")
        self.assertEqual(d["project_name"], "Greetings")
        self.assertEqual(d["draft_section_count"], 2)
        self.assertEqual(d["imported_section_ids"], ["s1"])
        self.assertTrue(d["has_imported"])
        self.assertEqual(set(d.keys()), WORKSHOP_DRAFT_KEYS)

    def test_normalize_round_trip(self) -> None:
        raw = {
            "open": 1,
            "project_id": "x",
            "ui_stage": "2",
            "has_material": "yes",
            "draft_section_count": -1,
            "imported_section_ids": ["a"],
            "extra_ignored": True,
        }
        d = normalize_workshop_draft(raw)
        self.assertIsNotNone(d)
        assert d is not None
        self.assertTrue(d["open"])
        self.assertEqual(d["project_id"], "x")
        self.assertEqual(d["ui_stage"], 2)
        self.assertTrue(d["has_material"])
        self.assertEqual(d["draft_section_count"], 0)
        self.assertNotIn("extra_ignored", d)

    def test_normalize_none_and_bad(self) -> None:
        self.assertIsNone(normalize_workshop_draft(None))
        self.assertIsNone(normalize_workshop_draft({}))  # idle

    def test_format_line(self) -> None:
        d = build_workshop_draft(
            open=True,
            project_id="p",
            project_name="Demo",
            has_material=True,
            has_draft=True,
            draft_section_count=3,
        )
        line = format_workshop_draft_line(d)
        self.assertIn("工坊", line)
        self.assertIn("Demo", line)
        self.assertIn("草稿3", line)
        self.assertEqual(format_workshop_draft_line(None), "")


class WorkshopDraftContextTest(unittest.TestCase):
    def test_build_context_carries_draft(self) -> None:
        adapter = SimpleNamespace(
            sections=[],
            vocab=[],
            expressions=[],
            grammar_points=[],
            index={"language": "tr"},
            course_dir=None,
        )
        draft = build_workshop_draft(
            open=True, project_id="p1", project_name="N", has_knowledge=True
        )
        ctx = build_experience_context(
            adapter,
            include_quality=False,
            include_hygiene=False,
            workshop_draft=draft,
        )
        self.assertIsNotNone(ctx.workshop_draft)
        assert ctx.workshop_draft is not None
        self.assertEqual(ctx.workshop_draft["project_id"], "p1")
        self.assertTrue(ctx.workshop_draft["has_knowledge"])


if __name__ == "__main__":
    unittest.main()
