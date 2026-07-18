"""Tests for duplicate + bulk lesson commands (workshop2 P1)."""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.commands import (  # noqa: E402
    BulkApplyPresetCommand,
    BulkDeleteLessonsCommand,
    BulkDuplicateLessonsCommand,
    BulkMoveLessonsCommand,
    DuplicateLessonCommand,
)
from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_content import (  # noqa: E402
    clone_lesson_with_fresh_ids,
    all_lesson_ids,
)
from src.backend.lesson_presets import apply_preset_to_lesson  # noqa: E402

_REPO = _GUI.parents[1]
COURSE_SRC = _REPO / "assets" / "courses" / "turkish"


def _load_adapter(tmp: Path) -> CourseAdapter:
    course_dir = tmp / "turkish"
    shutil.copytree(COURSE_SRC, course_dir)
    adapter = CourseAdapter()
    adapter.load(course_dir)
    return adapter


def _first_lessons(adapter: CourseAdapter, n: int) -> list[str]:
    ids = []
    for section in adapter.sections:
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                ids.append(lesson["id"])
                if len(ids) >= n:
                    return ids
    return ids


def _lesson_unit_id(adapter: CourseAdapter, lesson_id: str) -> str:
    _s, unit, _l = adapter.find_lesson(lesson_id)
    return unit["id"]


def _unit_lesson_ids(adapter: CourseAdapter, unit_id: str) -> list[str]:
    _section, unit = adapter.find_unit(unit_id)
    return [l["id"] for l in unit.get("lessons", [])]


class CloneLessonTest(unittest.TestCase):
    def test_clone_regenerates_structural_ids_and_preserves_refs(self) -> None:
        original = {
            "id": "l-orig",
            "name": "Orig",
            "template": "intro",
            "content": {
                "subLessons": [
                    {
                        "id": "sl-orig",
                        "name": "sub",
                        "stages": [
                            {
                                "id": "st-orig",
                                "name": "s",
                                "items": [
                                    {"id": "sw-orig", "runtimeType": "showWord",
                                     "wordId": "w-keep", "expressionId": "e-keep"}
                                ],
                            }
                        ],
                    }
                ],
                "stages": [
                    {"id": "st2-orig", "name": "flat", "items": [
                        {"id": "mc-orig", "runtimeType": "multipleChoice"}
                    ]}
                ],
                "listeningPhases": [
                    {"id": "lp-orig", "name": "p", "type": "wordPairing", "items": [
                        {"id": "lap-orig", "runtimeType": "listenAndPick"}
                    ]}
                ],
            },
            "prerequisiteLessonIds": ["l-other"],
        }
        clone = clone_lesson_with_fresh_ids(original, name="Copy")

        # New top-level id + name override.
        self.assertNotEqual(clone["id"], "l-orig")
        self.assertEqual(clone["name"], "Copy")
        # Structural ids all regenerated.
        new_ids = {
            clone["content"]["subLessons"][0]["id"],
            clone["content"]["subLessons"][0]["stages"][0]["id"],
            clone["content"]["subLessons"][0]["stages"][0]["items"][0]["id"],
            clone["content"]["stages"][0]["id"],
            clone["content"]["stages"][0]["items"][0]["id"],
            clone["content"]["listeningPhases"][0]["id"],
            clone["content"]["listeningPhases"][0]["items"][0]["id"],
        }
        self.assertFalse(new_ids & {"l-orig", "sl-orig", "st-orig", "sw-orig",
                                    "st2-orig", "mc-orig", "lp-orig", "lap-orig"})
        # References preserved.
        self.assertEqual(clone["content"]["subLessons"][0]["stages"][0]["items"][0]["wordId"], "w-keep")
        self.assertEqual(clone["prerequisiteLessonIds"], ["l-other"])
        # Original untouched.
        self.assertEqual(original["id"], "l-orig")


class DuplicateLessonCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_dup_"))
        self.adapter = _load_adapter(self.tmp)
        self.lesson_id = _first_lessons(self.adapter, 1)[0]
        self.unit_id = _lesson_unit_id(self.adapter, self.lesson_id)
        self.before = _unit_lesson_ids(self.adapter, self.unit_id)

    def test_redo_appends_clone_with_fresh_id(self) -> None:
        cmd = DuplicateLessonCommand(self.adapter, self.lesson_id)
        cmd.redo()
        after = _unit_lesson_ids(self.adapter, self.unit_id)
        self.assertEqual(len(after), len(self.before) + 1)
        new_id = cmd.new_lesson_id
        self.assertIsNotNone(new_id)
        self.assertIn(new_id, after)
        self.assertNotIn(new_id, self.before)
        # Clone name gets the 副本 suffix.
        _s, _u, lesson = self.adapter.find_lesson(new_id)
        self.assertIn("副本", lesson["name"])
        # Id is globally unique.
        self.assertIn(new_id, all_lesson_ids(self.adapter.sections))

    def test_undo_removes_clone(self) -> None:
        cmd = DuplicateLessonCommand(self.adapter, self.lesson_id)
        cmd.redo()
        new_id = cmd.new_lesson_id
        cmd.undo()
        after = _unit_lesson_ids(self.adapter, self.unit_id)
        self.assertEqual(after, self.before)
        self.assertNotIn(new_id, all_lesson_ids(self.adapter.sections))

    def test_redo_after_undo_regenerates(self) -> None:
        cmd = DuplicateLessonCommand(self.adapter, self.lesson_id)
        cmd.redo()
        first = cmd.new_lesson_id
        cmd.undo()
        cmd.redo()
        second = cmd.new_lesson_id
        self.assertNotEqual(first, second)
        self.assertIn(second, _unit_lesson_ids(self.adapter, self.unit_id))


class BulkDeleteLessonsCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_bulkdel_"))
        self.adapter = _load_adapter(self.tmp)
        self.lesson_ids = _first_lessons(self.adapter, 3)

    def test_redo_deletes_all_undo_restores(self) -> None:
        all_before = all_lesson_ids(self.adapter.sections)
        for lid in self.lesson_ids:
            self.assertIn(lid, all_before)

        cmd = BulkDeleteLessonsCommand(self.adapter, self.lesson_ids)
        cmd.redo()
        all_after = all_lesson_ids(self.adapter.sections)
        for lid in self.lesson_ids:
            self.assertNotIn(lid, all_after)

        cmd.undo()
        all_restored = all_lesson_ids(self.adapter.sections)
        for lid in self.lesson_ids:
            self.assertIn(lid, all_restored)

    def test_undo_restores_original_order_within_unit(self) -> None:
        # Pick two lessons from the same unit if available; else skip ordering check.
        unit_id = _lesson_unit_id(self.adapter, self.lesson_ids[0])
        same_unit = [lid for lid in self.lesson_ids
                     if _lesson_unit_id(self.adapter, lid) == unit_id]
        if len(same_unit) < 2:
            self.skipTest("need 2 lessons in one unit for ordering check")
        before = _unit_lesson_ids(self.adapter, unit_id)
        cmd = BulkDeleteLessonsCommand(self.adapter, same_unit)
        cmd.redo()
        cmd.undo()
        after = _unit_lesson_ids(self.adapter, unit_id)
        self.assertEqual(before, after)

    def test_dedupes_input_ids(self) -> None:
        lid = self.lesson_ids[0]
        cmd = BulkDeleteLessonsCommand(self.adapter, [lid, lid, lid])
        self.assertEqual(cmd.lesson_ids, [lid])
        cmd.redo()
        self.assertNotIn(lid, all_lesson_ids(self.adapter.sections))
        cmd.undo()
        self.assertIn(lid, all_lesson_ids(self.adapter.sections))


class BulkDuplicateLessonsCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_bulkdup_"))
        self.adapter = _load_adapter(self.tmp)
        self.lesson_ids = _first_lessons(self.adapter, 2)

    def test_redo_then_undo(self) -> None:
        before = all_lesson_ids(self.adapter.sections)
        cmd = BulkDuplicateLessonsCommand(self.adapter, self.lesson_ids)
        cmd.redo()
        self.assertEqual(len(cmd.new_ids), len(self.lesson_ids))
        for nid in cmd.new_ids:
            self.assertIn(nid, all_lesson_ids(self.adapter.sections))
            self.assertNotIn(nid, before)
        cmd.undo()
        after = all_lesson_ids(self.adapter.sections)
        self.assertEqual(set(after), set(before))


class BulkMoveLessonsCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_bulkmove_"))
        self.adapter = _load_adapter(self.tmp)
        # Find a target unit different from the source unit of the first lesson.
        first = _first_lessons(self.adapter, 1)[0]
        self.source_unit = _lesson_unit_id(self.adapter, first)
        self.target_unit = None
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                if unit["id"] != self.source_unit:
                    self.target_unit = unit["id"]
                    break
            if self.target_unit:
                break
        if self.target_unit is None:
            self.skipTest("course needs >=2 units for move test")
        self.moving = _first_lessons(self.adapter, 2)

    def test_redo_moves_lessons_to_target(self) -> None:
        target_before = set(_unit_lesson_ids(self.adapter, self.target_unit))
        cmd = BulkMoveLessonsCommand(self.adapter, self.moving, self.target_unit)
        cmd.redo()
        target_after = set(_unit_lesson_ids(self.adapter, self.target_unit))
        for lid in self.moving:
            self.assertIn(lid, target_after)
            self.assertNotIn(lid, target_before)
        cmd.undo()
        target_undone = set(_unit_lesson_ids(self.adapter, self.target_unit))
        self.assertEqual(target_undone, target_before)
        # Lessons back in their original unit.
        for lid in self.moving:
            self.assertEqual(_lesson_unit_id(self.adapter, lid), self.source_unit)

    def test_lessons_already_in_target_are_skipped(self) -> None:
        # Move a lesson that already lives in the target unit -> no-op snapshot.
        # First move it there, then "move" again.
        cmd1 = BulkMoveLessonsCommand(self.adapter, self.moving[:1], self.target_unit)
        cmd1.redo()
        # Now it's in target; a second move of the same id should skip.
        cmd2 = BulkMoveLessonsCommand(self.adapter, self.moving[:1], self.target_unit)
        cmd2.redo()
        self.assertEqual(cmd2.snapshots, [])
        cmd2.undo()  # no-op undo should not crash
        cmd1.undo()


class ApplyPresetTest(unittest.TestCase):
    def test_apply_preset_keeps_identity_replaces_content(self) -> None:
        lesson = {
            "id": "l-keep",
            "name": "Keep me",
            "description": "desc",
            "type": "normal",
            "template": "intro",
            "prerequisiteLessonIds": ["l-dep"],
            "content": {"subLessons": [{"id": "sl-1", "name": "x", "stages": []}]},
        }
        apply_preset_to_lesson(lesson, "listening-3phase")
        # Identity + metadata preserved.
        self.assertEqual(lesson["id"], "l-keep")
        self.assertEqual(lesson["name"], "Keep me")
        self.assertEqual(lesson["description"], "desc")
        self.assertEqual(lesson["prerequisiteLessonIds"], ["l-dep"])
        # Template + content replaced.
        self.assertEqual(lesson["template"], "listening")
        self.assertEqual(lesson["type"], "listening")
        self.assertIn("listeningPhases", lesson["content"])
        self.assertNotIn("subLessons", lesson["content"])
        # Fresh structural ids (not the old sublesson id).
        phase_ids = [p["id"] for p in lesson["content"]["listeningPhases"]]
        self.assertNotIn("sl-1", phase_ids)
        self.assertEqual(len(set(phase_ids)), len(phase_ids))


class BulkApplyPresetCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_bulkapply_"))
        self.adapter = _load_adapter(self.tmp)
        self.lesson_ids = _first_lessons(self.adapter, 3)

    def test_redo_applies_preset_undo_restores(self) -> None:
        # Snapshot originals.
        originals = {}
        for lid in self.lesson_ids:
            _s, _u, lesson = self.adapter.find_lesson(lid)
            originals[lid] = {
                "template": lesson.get("template"),
                "content": __import__("copy").deepcopy(lesson.get("content", {})),
            }
        cmd = BulkApplyPresetCommand(self.adapter, self.lesson_ids, "reading-3q")
        cmd.redo()
        for lid in self.lesson_ids:
            _s, _u, lesson = self.adapter.find_lesson(lid)
            self.assertEqual(lesson["template"], "reading")
            self.assertIn("readingPassage", lesson["content"])
        cmd.undo()
        for lid in self.lesson_ids:
            _s, _u, lesson = self.adapter.find_lesson(lid)
            self.assertEqual(lesson["template"], originals[lid]["template"])
            self.assertEqual(lesson["content"], originals[lid]["content"])


if __name__ == "__main__":
    unittest.main()
