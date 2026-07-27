"""T-04 / P11: lesson.batch_set_template via Batch FieldPatch."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


class BatchSetTemplateLogicTest(unittest.TestCase):
    def test_batch_field_patches_and_undo(self) -> None:
        from PySide6.QtGui import QUndoStack
        from tests._qtapp import _App
        from src.application.commands import ApplyBatchPatchCommand
        from src.backend.course_adapter import CourseAdapter
        from src.backend.experience.patch import field_patch

        _App._ensure()
        adapter = CourseAdapter()
        adapter.sections = [
            {
                "id": "s1",
                "units": [
                    {
                        "id": "u1",
                        "lessons": [
                            {"id": "l1", "name": "A", "template": "intro"},
                            {"id": "l2", "name": "B", "template": "intro"},
                            {"id": "l3", "name": "C", "template": "practice"},
                        ],
                    }
                ],
            }
        ]
        adapter.invalidate_node_index()
        steps = []
        for lid in ("l1", "l2", "l3"):
            _s, _u, lesson = adapter.find_lesson(lid)
            if lesson.get("template") == "listening":
                continue
            steps.append(
                (
                    "field",
                    lesson,
                    field_patch(
                        lesson,
                        "template",
                        "listening",
                        target_kind="lesson",
                        target_id=lid,
                    ),
                )
            )
        stack = QUndoStack()
        stack.push(
            ApplyBatchPatchCommand(
                steps=steps, adapter=adapter, text="批量课型 → listening"
            )
        )
        for lid in ("l1", "l2", "l3"):
            self.assertEqual(adapter.find_lesson(lid)[2]["template"], "listening")
            self.assertEqual(adapter.find_lesson(lid)[2]["id"], lid)
        stack.undo()
        self.assertEqual(adapter.find_lesson("l1")[2]["template"], "intro")
        self.assertEqual(adapter.find_lesson("l2")[2]["template"], "intro")
        self.assertEqual(adapter.find_lesson("l3")[2]["template"], "practice")

    def test_action_registered(self) -> None:
        from src.backend.experience.actions import get_action

        spec = get_action("lesson.batch_set_template")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.needs_confirm)
        # v4.69: structural batch set-template is dangerous (set C member);
        # handler now confirms via safe_question (was a silent write — fixed).
        self.assertTrue(spec.dangerous)

    def test_intent_routes_batch_template(self) -> None:
        from src.backend.experience.intent_router import route_intent

        i = route_intent("/batch-template")
        self.assertIsNotNone(i)
        assert i is not None
        self.assertEqual(i.action_id, "lesson.batch_set_template")
        i2 = route_intent("批量课型")
        self.assertIsNotNone(i2)
        assert i2 is not None
        self.assertEqual(i2.action_id, "lesson.batch_set_template")


class BatchSetTemplateMixinSmokeTest(unittest.TestCase):
    def test_mixin_applies_on_scope(self) -> None:
        from unittest.mock import patch

        from tests._mainwindow_fixture import build_main_window

        win = build_main_window()
        win.adapter.sections = [
            {
                "id": "s1",
                "units": [
                    {
                        "id": "u1",
                        "lessons": [
                            {"id": "l1", "template": "intro", "name": "A"},
                            {"id": "l2", "template": "practice", "name": "B"},
                        ],
                    }
                ],
            }
        ]
        win.adapter.invalidate_node_index()
        win.course_dir = Path("/tmp/fake")
        with patch(
            "src.application.experience_handlers.resources.safe_question",
            return_value=True,
        ):
            win._experience_batch_set_template(
                {"lesson_ids": ["l1", "l2"], "template": "review"}
            )
        self.assertEqual(win.adapter.find_lesson("l1")[2]["template"], "review")
        self.assertEqual(win.adapter.find_lesson("l2")[2]["template"], "review")
        win.undo_stack.undo()
        self.assertEqual(win.adapter.find_lesson("l1")[2]["template"], "intro")
        self.assertEqual(win.adapter.find_lesson("l2")[2]["template"], "practice")

    def test_confirm_rejected_does_not_write(self) -> None:
        """v4.69 red line: handler must NOT silently write — confirm gate.

        Previously this handler pushed Undo with no ``safe_question`` (a silent
        write). Now it confirms; rejecting must leave the tree untouched.
        """
        from unittest.mock import patch

        from tests._mainwindow_fixture import build_main_window

        win = build_main_window()
        win.adapter.sections = [
            {
                "id": "s1",
                "units": [
                    {
                        "id": "u1",
                        "lessons": [
                            {"id": "l1", "template": "intro", "name": "A"},
                        ],
                    }
                ],
            }
        ]
        win.adapter.invalidate_node_index()
        win.course_dir = Path("/tmp/fake")
        with patch(
            "src.application.experience_handlers.resources.safe_question",
            return_value=False,
        ):
            win._experience_batch_set_template(
                {"lesson_ids": ["l1"], "template": "review"}
            )
        self.assertEqual(win.adapter.find_lesson("l1")[2]["template"], "intro")
        self.assertEqual(win.undo_stack.count(), 0)


if __name__ == "__main__":
    unittest.main()
