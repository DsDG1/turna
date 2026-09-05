"""Unit tests for AiEditController (Phase 3)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.ai_edit_controller import AiEditController


class TestAiEditController(unittest.TestCase):
    def setUp(self):
        self.controller = AiEditController()

    def test_extract_unit(self):
        sec = {
            "id": "s1",
            "units": [
                {"id": "u1", "name": "Unit 1"},
                {"id": "u2", "name": "Unit 2"},
            ],
        }
        self.assertEqual(self.controller.extract_unit(sec, "u1"), {"id": "u1", "name": "Unit 1"})
        self.assertEqual(self.controller.extract_unit(sec, "u2"), {"id": "u2", "name": "Unit 2"})
        self.assertIsNone(self.controller.extract_unit(sec, "u3"))
        self.assertIsNone(self.controller.extract_unit({}, "u1"))

    def test_extract_lesson(self):
        sec = {
            "id": "s1",
            "units": [
                {
                    "id": "u1",
                    "lessons": [
                        {"id": "l1", "name": "Lesson 1"},
                    ],
                },
                {
                    "id": "u2",
                    "lessons": [
                        {"id": "l2", "name": "Lesson 2"},
                    ],
                },
            ],
        }
        self.assertEqual(self.controller.extract_lesson(sec, "l1"), {"id": "l1", "name": "Lesson 1"})
        self.assertEqual(self.controller.extract_lesson(sec, "l2"), {"id": "l2", "name": "Lesson 2"})
        self.assertIsNone(self.controller.extract_lesson(sec, "l3"))
        self.assertIsNone(self.controller.extract_lesson({}, "l1"))

    def test_detect_conflicts_id_changed(self):
        adapter = MagicMock()
        adapter.sections = []
        conflicts = self.controller.detect_conflicts(
            adapter, "lesson", "l1", {"id": "l1_renamed"}
        )
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0][0], "lesson")
        self.assertEqual(conflicts[0][1], "l1_renamed")

    def test_detect_conflicts_unit_lesson_overlap(self):
        adapter = MagicMock()
        # Course has l1 in u1, and l2 in u2
        adapter.sections = [
            {
                "id": "s1",
                "units": [
                    {"id": "u1", "lessons": [{"id": "l1"}]},
                    {"id": "u2", "lessons": [{"id": "l2"}]},
                ],
            }
        ]
        adapter.find_unit.return_value = ({}, {"id": "u1", "lessons": [{"id": "l1"}]})

        # New u1 keeps id "u1", but tries to introduce lesson "l2" which exists in u2!
        new_node = {
            "id": "u1",
            "lessons": [
                {"id": "l1"},  # fine (in current unit)
                {"id": "l2"},  # conflict with u2!
            ],
        }
        conflicts = self.controller.detect_conflicts(adapter, "unit", "u1", new_node)
        self.assertEqual(len(conflicts), 1)
        self.assertEqual(conflicts[0][1], "l2")

    def test_handle_ai_edit_no_course_dir_warns(self):
        window = SimpleNamespace(course_dir=None)
        with patch("src.application.ai_edit_controller.QMessageBox.warning") as mock_warn:
            self.controller.handle_ai_edit(window, "lesson", "l1")
            mock_warn.assert_called_once()
            self.assertIn("未加载课程目录", mock_warn.call_args[0][1])


if __name__ == "__main__":
    unittest.main()
