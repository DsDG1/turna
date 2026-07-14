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
from src.backend.lesson_content import (  # noqa: E402
    add_item,
    add_listening_phase,
    add_stage,
    add_sub_lesson,
    new_lesson_from_template,
)

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


def _run_lint(course_dir: Path) -> list[dict]:
    proc = subprocess.run(
        [sys.executable, str(_CLI), "--course-dir", str(course_dir), "lint"],
        capture_output=True, text=True, encoding="utf-8",
    )
    problems: list[dict] = []
    for line in (proc.stdout or "").splitlines():
        line = line.strip()
        if line.startswith("ERROR:"):
            problems.append({"level": "error", "message": line[6:].strip()})
        elif line.startswith("WARNING:"):
            problems.append({"level": "warning", "message": line[8:].strip()})
    return problems


class FullLifecycleRoundTripTest(unittest.TestCase):
    """M5.1: a full GUI-authored course lifecycle through CourseAdapter must
    end with CLI validate ok + lint producing no errors (warnings acceptable).

    These drive the GUI write path without PySide6: CourseAdapter + lesson_content
    helpers mutate the in-memory tree, save() writes JSON + runs validate, then a
    fresh CLI subprocess re-validates from disk. No Qt import -> sandbox-safe.
    """

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_full_"))
        self.course_dir = self.tmp / "turkish"
        shutil.copytree(COURSE_SRC, self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _adapter(self) -> CourseAdapter:
        a = CourseAdapter()
        a.load(self.course_dir)
        return a

    def test_every_template_lesson_saves_and_validates(self) -> None:
        """Create one lesson of each of the 6 templates in section1 unit1,
        wire real wordId where needed, save, and assert CLI validate ok."""
        templates = ("intro", "practice", "review", "listening", "reading", "mastery")
        a = self._adapter()
        unit = a.sections[0]["units"][0]
        for tmpl in templates:
            lesson = new_lesson_from_template(tmpl, unit)
            content = lesson["content"]
            if tmpl in ("intro", "practice", "review"):
                stage = content["subLessons"][0]["stages"][0]
                for item in stage["items"]:
                    if item.get("runtimeType") == "showWord":
                        item["wordId"] = "w-merhaba"
            elif tmpl == "listening":
                phase = content["listeningPhases"][0]
                item = add_item(phase, "listenAndPick")
                item["audioAsset"] = "sounds/example/test.mp3"
                item["options"] = ["A", "B"]
                item["correctIndex"] = 0
            elif tmpl == "reading":
                content["readingPassage"]["title"] = "T"
                content["readingPassage"]["paragraphs"] = ["P1"]
                stage = content["stages"][0]
                add_item(stage, "readingMcq")
            elif tmpl == "mastery":
                stage = content["stages"][0]
                add_item(stage, "multipleChoice")
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")
        cli = _run_validate(self.course_dir)
        self.assertTrue(cli["ok"], f"CLI validate failed: {cli}")

    def test_resource_edit_csv_round_trip_validates(self) -> None:
        """Export vocab to CSV, import it back unchanged, save, and validate."""
        a = self._adapter()
        csv_path = self.tmp / "vocab_export.csv"
        a.export_csv("vocab", csv_path)
        problems = a.import_csv("vocab", csv_path)
        errors = [p for p in problems if p["level"] == "error"]
        self.assertEqual(errors, [], f"import_csv errors: {errors}")
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")
        cli = _run_validate(self.course_dir)
        self.assertTrue(cli["ok"], f"CLI validate failed: {cli}")

    def test_add_and_delete_unit_then_validate(self) -> None:
        a = self._adapter()
        section = a.sections[0]
        new_uid = a.new_unit(section["id"], "Round-trip unit")
        self.assertIsNotNone(new_uid)
        unit = a.find_unit(new_uid)[1]
        lesson = new_lesson_from_template("intro", unit)
        stage = lesson["content"]["subLessons"][0]["stages"][0]
        for item in stage["items"]:
            if item.get("runtimeType") == "showWord":
                item["wordId"] = "w-merhaba"
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")

        a.delete_unit(new_uid)
        result2 = a.save()
        self.assertTrue(result2.ok, f"{result2.message} errors={result2.errors}")
        cli = _run_validate(self.course_dir)
        self.assertTrue(cli["ok"], f"CLI validate failed after delete: {cli}")

    def test_lint_produces_no_errors_after_clean_save(self) -> None:
        """A noop save must leave lint with zero ERROR-level problems."""
        a = self._adapter()
        a.save()
        problems = _run_lint(self.course_dir)
        errors = [p for p in problems if p["level"] == "error"]
        self.assertEqual(errors, [], f"lint errors after clean save: {errors}")

    def test_second_save_is_stable_noop(self) -> None:
        """Saving twice in a row must not change the on-disk JSON (idempotent)."""
        a = self._adapter()
        a.save()
        first = {p: _load_json(self.course_dir / p) for p in (
            "index.json", "vocab.json", "expressions.json", "grammar_points.json")}
        first.update({p.name: _load_json(p) for p in (self.course_dir / "sections").glob("*.json")})
        a.save()
        second = {p: _load_json(self.course_dir / p) for p in (
            "index.json", "vocab.json", "expressions.json", "grammar_points.json")}
        second.update({p.name: _load_json(p) for p in (self.course_dir / "sections").glob("*.json")})
        self.assertEqual(first, second, "second save mutated files")

    def test_orphan_section_file_removed_after_section_delete(self) -> None:
        """Deleting the last section must remove its section file so the loader
        does not pick up an orphan (CourseAdapter._replace_course_files_with)."""
        a = self._adapter()
        last_section = a.sections[-1]
        sid = last_section["id"]
        a.sections.remove(last_section)
        a.index["sections"] = [s for s in a.index.get("sections", []) if s.get("id") != sid]
        result = a.save()
        self.assertTrue(result.ok, f"{result.message} errors={result.errors}")
        removed_file = self.course_dir / "sections" / f"{sid}.json"
        self.assertFalse(removed_file.exists(), f"orphan section file remains: {removed_file}")
        cli = _run_validate(self.course_dir)
        self.assertTrue(cli["ok"], f"CLI validate failed: {cli}")

    def test_validate_fail_rolls_back_and_files_unchanged(self) -> None:
        """Constructing an invalid course (duplicate wordId dangling) must
        cause save() to roll back so on-disk files match the pre-save snapshot."""
        a = self._adapter()
        before = _load_json(self.course_dir / "index.json")
        a.index["version"] = 999
        a.index["sections"] = "not-a-list"  # invalid structure
        result = a.save()
        self.assertFalse(result.ok, "save should have failed for invalid index")
        after = _load_json(self.course_dir / "index.json")
        self.assertEqual(before, after, "invalid save mutated index.json despite rollback")


if __name__ == "__main__":
    unittest.main()
