"""E1.5 / C-08 / C-09: Patch protocol + undo adapter."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.patch import (  # noqa: E402
    FieldPatch,
    ItemPatch,
    LessonPatch,
    PatchError,
    apply_field_patch,
    apply_item_patch,
    apply_lesson_patch,
    apply_resolved_batch,
    field_diff_lines,
    batch_patch,
    field_patch,
    item_patch_from_replace,
    lesson_patch_from_replace,
    lesson_patches_from_section_diff,
    revert_field_patch,
    revert_item_patch,
    revert_lesson_patch,
    revert_resolved_batch,
)


class FieldPatchTest(unittest.TestCase):
    def test_field_patch_captures_old_and_applies(self) -> None:
        target = {"id": "i1", "prompt": "old"}
        patch = field_patch(target, "prompt", "new")
        self.assertEqual(patch.old_value, "old")
        self.assertEqual(patch.new_value, "new")
        apply_field_patch(target, patch)
        self.assertEqual(target["prompt"], "new")
        revert_field_patch(target, patch)
        self.assertEqual(target["prompt"], "old")

    def test_id_field_forbidden(self) -> None:
        target = {"id": "i1", "prompt": "x"}
        with self.assertRaises(PatchError):
            field_patch(target, "id", "other")
        patch = FieldPatch("item", "i1", "id", "i1", "other")
        with self.assertRaises(PatchError):
            apply_field_patch(target, patch)

    def test_summary_shortens(self) -> None:
        patch = FieldPatch("item", "i1", "prompt", "a" * 100, "b")
        text = patch.summary()
        self.assertIn("prompt", text)
        self.assertLessEqual(len(text), 200)


class ItemPatchTest(unittest.TestCase):
    def test_forces_id_preservation(self) -> None:
        old = {"id": "q1", "runtimeType": "multipleChoice", "prompt": "A"}
        new = {"id": "HACKED", "runtimeType": "multipleChoice", "prompt": "B"}
        patch = item_patch_from_replace(old, new)
        self.assertEqual(patch.item_id, "q1")
        self.assertEqual(patch.new_item["id"], "q1")
        self.assertEqual(patch.new_item["prompt"], "B")

    def test_apply_and_revert_in_stage(self) -> None:
        stage = {
            "id": "st1",
            "items": [
                {"id": "q1", "prompt": "A"},
                {"id": "q2", "prompt": "X"},
            ],
        }
        old = stage["items"][0]
        patch = item_patch_from_replace(old, {"id": "q1", "prompt": "B"}, stage_id="st1")
        idx = apply_item_patch(stage, patch)
        self.assertEqual(idx, 0)
        self.assertEqual(stage["items"][0]["prompt"], "B")
        self.assertEqual(stage["items"][0]["id"], "q1")
        self.assertEqual(stage["items"][1]["prompt"], "X")
        revert_item_patch(stage, patch)
        self.assertEqual(stage["items"][0]["prompt"], "A")

    def test_missing_item_raises(self) -> None:
        stage = {"items": [{"id": "other", "prompt": "z"}]}
        patch = ItemPatch(
            item_id="q1",
            old_item={"id": "q1", "prompt": "A"},
            new_item={"id": "q1", "prompt": "B"},
        )
        with self.assertRaises(PatchError):
            apply_item_patch(stage, patch)

    def test_missing_old_id_raises(self) -> None:
        with self.assertRaises(PatchError):
            item_patch_from_replace({"prompt": "no-id"}, {"prompt": "x"})

    def test_summary_uses_prompt(self) -> None:
        patch = item_patch_from_replace(
            {"id": "q1", "prompt": "hello"},
            {"id": "q1", "prompt": "world"},
        )
        self.assertIn("hello", patch.summary())
        self.assertIn("world", patch.summary())


class ApplyItemPatchCommandTest(unittest.TestCase):
    def test_undo_redo_roundtrip(self) -> None:
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import qt_app
        from src.application.commands import ApplyItemPatchCommand

        qt_app()
        stage = {"id": "st", "items": [{"id": "q1", "prompt": "A"}]}
        patch = item_patch_from_replace(
            stage["items"][0], {"id": "q1", "prompt": "B"}
        )
        stack = QUndoStack()
        cmd = ApplyItemPatchCommand(stage, patch)
        stack.push(cmd)
        self.assertEqual(stage["items"][0]["prompt"], "B")
        self.assertEqual(stage["items"][0]["id"], "q1")
        stack.undo()
        self.assertEqual(stage["items"][0]["prompt"], "A")
        stack.redo()
        self.assertEqual(stage["items"][0]["prompt"], "B")

    def test_replace_item_command_forces_id(self) -> None:
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import qt_app
        from src.application.commands import ReplaceItemCommand

        qt_app()
        stage = {"items": [{"id": "q1", "prompt": "A"}]}
        stack = QUndoStack()
        stack.push(
            ReplaceItemCommand(stage, "q1", {"id": "HACK", "prompt": "B"})
        )
        self.assertEqual(stage["items"][0]["id"], "q1")
        self.assertEqual(stage["items"][0]["prompt"], "B")

    def test_multi_item_patch_undo_replay(self) -> None:
        """T-12: multi-item batch patches replay cleanly through one undo stack."""
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import qt_app
        from src.application.commands import ApplyItemPatchCommand

        qt_app()
        stage = {
            "id": "st1",
            "items": [
                {"id": "q1", "prompt": "A1"},
                {"id": "q2", "prompt": "B1"},
                {"id": "q3", "prompt": "C1"},
            ],
        }
        stack = QUndoStack()
        for i, new_prompt in enumerate(("A2", "B2", "C2")):
            old = stage["items"][i]
            patch = item_patch_from_replace(
                old, {"id": old["id"], "prompt": new_prompt}, stage_id="st1"
            )
            stack.push(ApplyItemPatchCommand(stage, patch))
        self.assertEqual(
            [it["prompt"] for it in stage["items"]], ["A2", "B2", "C2"]
        )
        self.assertEqual(stack.count(), 3)
        while stack.canUndo():
            stack.undo()
        self.assertEqual(
            [it["prompt"] for it in stage["items"]], ["A1", "B1", "C1"]
        )
        self.assertEqual(
            [it["id"] for it in stage["items"]], ["q1", "q2", "q3"]
        )


class ApplyFieldPatchCommandTest(unittest.TestCase):
    def test_field_command_undo(self) -> None:
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import qt_app
        from src.application.commands import ApplyFieldPatchCommand

        qt_app()
        target = {"id": "i1", "name": "old"}
        patch = field_patch(target, "name", "new", target_kind="stage")
        stack = QUndoStack()
        stack.push(ApplyFieldPatchCommand(target, patch))
        self.assertEqual(target["name"], "new")
        stack.undo()
        self.assertEqual(target["name"], "old")


class LessonPatchTest(unittest.TestCase):
    def test_forces_lesson_id(self) -> None:
        old = {"id": "l1", "name": "Empty", "content": {}}
        new = {"id": "HACKED", "name": "Filled", "content": {"stages": []}}
        patch = lesson_patch_from_replace(old, new)
        self.assertEqual(patch.lesson_id, "l1")
        self.assertEqual(patch.new_lesson["id"], "l1")
        self.assertEqual(patch.new_lesson["name"], "Filled")

    def test_missing_old_id_raises(self) -> None:
        with self.assertRaises(PatchError):
            lesson_patch_from_replace({"name": "x"}, {"name": "y"})

    def test_apply_and_revert_in_unit(self) -> None:
        unit = {
            "id": "u1",
            "lessons": [
                {"id": "l1", "name": "A", "content": {}},
                {"id": "l2", "name": "Keep", "content": {"x": 1}},
            ],
        }
        patch = lesson_patch_from_replace(
            unit["lessons"][0],
            {"id": "l1", "name": "B", "content": {"stages": [{"id": "st"}]}},
        )
        idx = apply_lesson_patch(unit, patch)
        self.assertEqual(idx, 0)
        self.assertEqual(unit["lessons"][0]["name"], "B")
        self.assertEqual(unit["lessons"][0]["id"], "l1")
        self.assertEqual(unit["lessons"][1]["name"], "Keep")
        revert_lesson_patch(unit, patch)
        self.assertEqual(unit["lessons"][0]["name"], "A")
        self.assertEqual(unit["lessons"][0].get("content"), {})

    def test_missing_lesson_raises(self) -> None:
        unit = {"lessons": [{"id": "other", "name": "z"}]}
        patch = LessonPatch(
            lesson_id="l1",
            old_lesson={"id": "l1", "name": "A"},
            new_lesson={"id": "l1", "name": "B"},
        )
        with self.assertRaises(PatchError):
            apply_lesson_patch(unit, patch)

    def test_summary(self) -> None:
        patch = lesson_patch_from_replace(
            {"id": "l1", "name": "Empty"},
            {"id": "l1", "name": "Greetings"},
        )
        text = patch.summary()
        self.assertIn("l1", text)
        self.assertIn("Empty", text)


class BatchPatchTest(unittest.TestCase):
    def test_empty_batch_rejected(self) -> None:
        with self.assertRaises(PatchError):
            batch_patch([])

    def test_resolved_batch_transaction(self) -> None:
        unit = {
            "id": "u1",
            "lessons": [
                {"id": "l1", "name": "A"},
                {"id": "l2", "name": "B"},
            ],
        }
        p1 = lesson_patch_from_replace(
            unit["lessons"][0], {"id": "l1", "name": "A2"}
        )
        p2 = lesson_patch_from_replace(
            unit["lessons"][1], {"id": "l2", "name": "B2"}
        )
        batch = batch_patch([p1, p2], label="两课")
        self.assertEqual(len(batch.patches), 2)
        steps = [
            ("lesson", unit, p1),
            ("lesson", unit, p2),
        ]
        apply_resolved_batch(steps)
        self.assertEqual(unit["lessons"][0]["name"], "A2")
        self.assertEqual(unit["lessons"][1]["name"], "B2")
        revert_resolved_batch(steps)
        self.assertEqual(unit["lessons"][0]["name"], "A")
        self.assertEqual(unit["lessons"][1]["name"], "B")

    def test_batch_mid_failure_rolls_back(self) -> None:
        unit = {"id": "u1", "lessons": [{"id": "l1", "name": "A"}]}
        p_ok = lesson_patch_from_replace(
            unit["lessons"][0], {"id": "l1", "name": "CHANGED"}
        )
        p_bad = LessonPatch(
            lesson_id="missing",
            old_lesson={"id": "missing"},
            new_lesson={"id": "missing", "name": "x"},
        )
        with self.assertRaises(PatchError):
            apply_resolved_batch(
                [
                    ("lesson", unit, p_ok),
                    ("lesson", unit, p_bad),
                ]
            )
        # First step must be rolled back.
        self.assertEqual(unit["lessons"][0]["name"], "A")

    def test_mixed_field_and_lesson(self) -> None:
        unit = {"id": "u1", "lessons": [{"id": "l1", "name": "A", "template": "intro"}]}
        lesson = unit["lessons"][0]
        fp = field_patch(lesson, "template", "practice", target_kind="lesson")
        lp = lesson_patch_from_replace(
            lesson, {"id": "l1", "name": "A2", "template": "intro"}
        )
        # Field first then lesson replace overwrites whole dict — order matters.
        # Apply field only then check.
        apply_resolved_batch([("field", lesson, fp)])
        self.assertEqual(unit["lessons"][0]["template"], "practice")
        revert_resolved_batch([("field", lesson, fp)])
        self.assertEqual(unit["lessons"][0]["template"], "intro")
        apply_resolved_batch([("lesson", unit, lp)])
        self.assertEqual(unit["lessons"][0]["name"], "A2")


class ApplyLessonPatchCommandTest(unittest.TestCase):
    def test_undo_redo_via_adapter(self) -> None:
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import qt_app
        from src.application.commands import ApplyLessonPatchCommand
        from src.backend.course_adapter import CourseAdapter

        qt_app()
        adapter = CourseAdapter()
        adapter.sections = [
            {
                "id": "s1",
                "name": "S1",
                "units": [
                    {
                        "id": "u1",
                        "lessons": [
                            {"id": "l1", "name": "Empty", "content": {}},
                        ],
                    }
                ],
            }
        ]
        adapter.invalidate_node_index()
        _s, _u, old = adapter.find_lesson("l1")
        patch = lesson_patch_from_replace(
            old,
            {
                "id": "l1",
                "name": "Filled",
                "content": {"stages": [{"id": "st1", "items": []}]},
            },
            section_id="s1",
            unit_id="u1",
        )
        stack = QUndoStack()
        stack.push(ApplyLessonPatchCommand(adapter, patch))
        _s2, _u2, after = adapter.find_lesson("l1")
        self.assertEqual(after["name"], "Filled")
        self.assertEqual(after["id"], "l1")
        stack.undo()
        _s3, _u3, back = adapter.find_lesson("l1")
        self.assertEqual(back["name"], "Empty")
        stack.redo()
        _s4, _u4, again = adapter.find_lesson("l1")
        self.assertEqual(again["name"], "Filled")


class ApplyBatchPatchCommandTest(unittest.TestCase):
    def test_batch_lesson_undo(self) -> None:
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import qt_app
        from src.application.commands import ApplyBatchPatchCommand
        from src.backend.course_adapter import CourseAdapter

        qt_app()
        adapter = CourseAdapter()
        adapter.sections = [
            {
                "id": "s1",
                "units": [
                    {
                        "id": "u1",
                        "lessons": [
                            {"id": "l1", "name": "A"},
                            {"id": "l2", "name": "B"},
                        ],
                    }
                ],
            }
        ]
        adapter.invalidate_node_index()
        p1 = lesson_patch_from_replace(
            adapter.find_lesson("l1")[2], {"id": "l1", "name": "A2"}
        )
        p2 = lesson_patch_from_replace(
            adapter.find_lesson("l2")[2], {"id": "l2", "name": "B2"}
        )
        batch = batch_patch([p1, p2], label="两课改名")
        stack = QUndoStack()
        stack.push(ApplyBatchPatchCommand(adapter=adapter, batch=batch))
        self.assertEqual(adapter.find_lesson("l1")[2]["name"], "A2")
        self.assertEqual(adapter.find_lesson("l2")[2]["name"], "B2")
        stack.undo()
        self.assertEqual(adapter.find_lesson("l1")[2]["name"], "A")
        self.assertEqual(adapter.find_lesson("l2")[2]["name"], "B")


class SectionDiffLessonPatchesTest(unittest.TestCase):
    """C-08 / v4.57: lesson_patches_from_section_diff."""

    def _sec(self, lessons: list) -> dict:
        return {
            "id": "s1",
            "units": [{"id": "u1", "lessons": lessons}],
        }

    def test_extracts_changed_lesson_forces_id(self) -> None:
        old = self._sec(
            [
                {"id": "l1", "name": "A", "content": {}},
                {"id": "l2", "name": "B", "content": {}},
            ]
        )
        new = self._sec(
            [
                {"id": "HACK", "name": "A2", "content": {"stages": []}},
                {"id": "l2", "name": "B", "content": {}},
            ]
        )
        # Align by position only if ids differ — our index is by id, so HACK
        # won't match l1. Proper new section keeps id:
        new = self._sec(
            [
                {"id": "l1", "name": "A2", "content": {"stages": []}},
                {"id": "l2", "name": "B", "content": {}},
            ]
        )
        patches = lesson_patches_from_section_diff(old, new)
        self.assertEqual(len(patches), 1)
        self.assertEqual(patches[0].lesson_id, "l1")
        self.assertEqual(patches[0].new_lesson["id"], "l1")
        self.assertEqual(patches[0].new_lesson["name"], "A2")

    def test_only_lesson_ids_filter(self) -> None:
        old = self._sec(
            [
                {"id": "l1", "name": "A"},
                {"id": "l2", "name": "B"},
            ]
        )
        new = self._sec(
            [
                {"id": "l1", "name": "A2"},
                {"id": "l2", "name": "B2"},
            ]
        )
        patches = lesson_patches_from_section_diff(
            old, new, only_lesson_ids={"l2"}
        )
        self.assertEqual(len(patches), 1)
        self.assertEqual(patches[0].lesson_id, "l2")

    def test_unchanged_empty(self) -> None:
        sec = self._sec([{"id": "l1", "name": "A"}])
        self.assertEqual(lesson_patches_from_section_diff(sec, sec), [])

    def test_garbage_safe(self) -> None:
        self.assertEqual(lesson_patches_from_section_diff(None, None), [])
        self.assertEqual(lesson_patches_from_section_diff({}, {"units": 1}), [])


class FieldDiffLinesTest(unittest.TestCase):
    """A2: field_diff_lines pure helper for PreviewHost per-field diff."""

    def test_field_patch_single_line(self) -> None:
        p = FieldPatch(
            target_kind="vocab", target_id="w1",
            field="translation", old_value="", new_value="你好",
        )
        self.assertEqual(field_diff_lines([p]), ["translation:  → 你好"])

    def test_item_patch_changed_keys_skip_id_and_unchanged(self) -> None:
        p = ItemPatch(
            item_id="i1",
            old_item={"id": "i1", "prompt": "old", "options": ["a"], "same": 1},
            new_item={"id": "i1", "prompt": "new", "options": ["a"], "same": 1},
            stage_id="s1",
        )
        lines = field_diff_lines([p])
        self.assertEqual(lines, ["prompt: old → new"])  # id/options/same skipped

    def test_item_patch_multiple_changed_keys(self) -> None:
        p = ItemPatch(
            item_id="i1",
            old_item={"id": "i1", "prompt": "old", "hint": "x"},
            new_item={"id": "i1", "prompt": "new", "hint": "y", "extra": "z"},
        )
        lines = field_diff_lines([p])
        self.assertIn("prompt: old → new", lines)
        self.assertIn("hint: x → y", lines)
        self.assertIn("extra: ∅ → z", lines)
        self.assertNotIn("id", " ".join(lines))

    def test_accepts_single_patch_and_garbage(self) -> None:
        p = FieldPatch(
            target_kind="vocab", target_id="w1",
            field="pos", old_value=None, new_value="noun",
        )
        self.assertEqual(field_diff_lines(p), ["pos: ∅ → noun"])
        self.assertEqual(field_diff_lines(None), [])
        self.assertEqual(field_diff_lines("junk"), [])
        self.assertEqual(field_diff_lines([None, "x", {}]), [])


if __name__ == "__main__":
    unittest.main()
