#!/usr/bin/env python3
"""GUI -> CLI round-trip tests (guiplan §9 M5.1, §11 acceptance criterion 2).

Verifies that a course loaded and re-saved by CourseAdapter (the GUI's write
path) remains semantically equivalent to the original and still passes CLI
validate + lint. Uses the real Turkish course as the fixture so the test
exercises production content rather than a synthetic minimal tree.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
sys.path.insert(0, str(ROOT / "tool" / "gui"))

import course_cli  # noqa: E402
from src.backend.course_adapter import CourseAdapter  # noqa: E402

COURSE_SRC = ROOT / "assets" / "courses" / "turkish"
_CLI = ROOT / "tool" / "course_cli.py"


def _run_validate(course_dir: Path) -> dict:
    """Run `course_cli validate --format json` and parse stdout (mirrors adapter)."""
    proc = subprocess.run(
        [sys.executable, str(_CLI), "--course-dir", str(course_dir),
         "validate", "--format", "json"],
        capture_output=True, text=True, encoding="utf-8",
    )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"ok": False, "problems": [
            {"level": "error", "message": f"invalid output: {proc.stderr or proc.stdout}", "path": ""}]}


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _id_set(data: dict, key: str) -> set[str]:
    if key == "vocab":
        entries = data.get("words", [])
    elif key == "expressions":
        entries = data.get("expressions", []) or []
    elif key == "grammar_points":
        entries = data.get("grammarPoints", [])
    else:
        entries = []
    return {e.get("id", "") for e in entries if e.get("id")}


def _section_ids(index: dict) -> set[str]:
    return {s.get("id", "") for s in index.get("sections", []) if s.get("id")}


class GuiCliRoundTripTest(unittest.TestCase):
    """Fixed fixture (Turkish) -> GUI save -> CLI validate, results consistent."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_roundtrip_"))
        self.course_dir = self.tmp / "turkish"
        shutil.copytree(COURSE_SRC, self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_noop_save_passes_cli_validate_and_lint(self) -> None:
        """GUI load -> save (no edits) must pass CLI validate + lint."""
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        result = adapter.save()
        self.assertTrue(
            result.ok, f"save failed: {result.message} errors={result.errors}"
        )

    def test_id_sets_equivalent_after_round_trip(self) -> None:
        """After GUI save, resource id sets match the original fixture."""
        original = {
            "vocab": _id_set(_load_json(COURSE_SRC / "vocab.json"), "vocab"),
            "expressions": _id_set(_load_json(COURSE_SRC / "expressions.json"), "expressions"),
            "grammar_points": _id_set(
                _load_json(COURSE_SRC / "grammar_points.json"), "grammar_points"
            ),
            "sections": _section_ids(_load_json(COURSE_SRC / "index.json")),
        }

        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.save()

        rewritten = {
            "vocab": _id_set(_load_json(self.course_dir / "vocab.json"), "vocab"),
            "expressions": _id_set(
                _load_json(self.course_dir / "expressions.json"), "expressions"
            ),
            "grammar_points": _id_set(
                _load_json(self.course_dir / "grammar_points.json"), "grammar_points"
            ),
            "sections": _section_ids(_load_json(self.course_dir / "index.json")),
        }
        self.assertEqual(original, rewritten)

    def test_versions_preserved_on_noop_save(self) -> None:
        """A no-op save must not bump index/expressions version fields."""
        orig_index = _load_json(COURSE_SRC / "index.json")
        orig_expr = _load_json(COURSE_SRC / "expressions.json")

        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.save()

        new_index = _load_json(self.course_dir / "index.json")
        new_expr = _load_json(self.course_dir / "expressions.json")
        self.assertEqual(new_index.get("version"), orig_index.get("version"))
        self.assertEqual(new_expr.get("version"), orig_expr.get("version"))

    def test_cli_validate_result_consistent_before_and_after_gui_save(self) -> None:
        """§11 criterion 2: CLI validate result is the same before and after
        the GUI writes the course (both must be ok)."""
        before = _run_validate(COURSE_SRC)

        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.save()

        after = _run_validate(self.course_dir)
        self.assertTrue(before["ok"], "fixture must validate before GUI save")
        self.assertTrue(after["ok"], "must still validate after GUI save")
        self.assertEqual(before["ok"], after["ok"])

    def test_edit_then_save_still_validates(self) -> None:
        """A representative GUI edit (section rename) must keep CLI validate ok."""
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.sections[0]["name"] = "Renamed by GUI"
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message}")

        cli_result = _run_validate(self.course_dir)
        self.assertTrue(cli_result["ok"], "CLI validate must pass after GUI edit+save")


if __name__ == "__main__":
    unittest.main()
