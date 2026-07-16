"""Tests for teacher template editors using the undo stack."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication, QComboBox, QInputDialog, QMessageBox
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtGui import QUndoStack  # noqa: E402

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_content import default_interaction  # noqa: E402
from src.teacher.template_editors import (  # noqa: E402
    ListeningTeacherWidget,
    MasteryTeacherWidget,
    ReadingTeacherWidget,
)


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _sample_lesson(template: str) -> dict:
    if template == "listening":
        return {
            "id": "l-listen",
            "name": "Listening",
            "template": "listening",
            "content": {
                "listeningPhases": [
                    {
                        "id": "lp-1",
                        "name": "Phase 1",
                        "type": "wordPairing",
                        "items": [
                            {
                                "runtimeType": "multipleChoice",
                                "id": "i-1",
                                "prompt": "Q1",
                                "options": ["A", "B"],
                                "correctIndex": 0,
                                "imageAsset": "",
                                "grammarPointId": "",
                            }
                        ],
                    }
                ]
            },
        }
    if template == "reading":
        return {
            "id": "l-read",
            "name": "Reading",
            "template": "reading",
            "content": {
                "readingPassage": {"title": "T", "paragraphs": ["P1"]},
                "stages": [
                    {
                        "id": "st-1",
                        "name": "Comprehension",
                        "items": [
                            {
                                "runtimeType": "multipleChoice",
                                "id": "i-1",
                                "prompt": "Q1",
                                "options": ["A", "B"],
                                "correctIndex": 0,
                                "imageAsset": "",
                                "grammarPointId": "",
                            }
                        ],
                    }
                ],
            },
        }
    # mastery
    return {
        "id": "l-mastery",
        "name": "Mastery",
        "template": "mastery",
        "content": {
            "stages": [
                {
                    "id": "st-1",
                    "name": "Quiz",
                    "items": [
                        {
                            "runtimeType": "multipleChoice",
                            "id": "i-1",
                            "prompt": "Q1",
                            "options": ["A", "B"],
                            "correctIndex": 0,
                            "imageAsset": "",
                            "grammarPointId": "",
                        }
                    ],
                }
            ]
        },
    }


class TemplateEditorUndoTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.section = {"id": "s-test", "name": "S"}
        self.unit = {"id": "u-test", "name": "U"}
        self.stack = QUndoStack()

    def _make_widget(self, template: str):
        lesson = _sample_lesson(template)
        if template == "listening":
            cls = ListeningTeacherWidget
        elif template == "reading":
            cls = ReadingTeacherWidget
        else:
            cls = MasteryTeacherWidget
        widget = cls(
            self.adapter,
            self.section,
            self.unit,
            lesson,
            undo_stack=self.stack,
        )
        widget.show()
        QApplication.processEvents()
        return widget, lesson

    def test_listening_add_item_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        phase = lesson["content"]["listeningPhases"][0]
        stage = phase
        combo = widget._item_type_combo("multipleChoice")
        widget._on_add_item(stage, combo)
        self.assertEqual(len(stage["items"]), 2)
        self.stack.undo()
        self.assertEqual(len(stage["items"]), 1)

    def test_listening_delete_item_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        phase = lesson["content"]["listeningPhases"][0]
        item = phase["items"][0]
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes):
            widget._delete_item(phase, item)
        self.assertEqual(len(phase["items"]), 0)
        self.stack.undo()
        self.assertEqual(len(phase["items"]), 1)

    def test_listening_change_item_type_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        phase = lesson["content"]["listeningPhases"][0]
        item = phase["items"][0]
        widget._change_item_type(phase, item, "fillBlank")
        self.assertEqual(phase["items"][0]["runtimeType"], "fillBlank")
        self.stack.undo()
        self.assertEqual(phase["items"][0]["runtimeType"], "multipleChoice")

    def test_listening_move_item_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        phase = lesson["content"]["listeningPhases"][0]
        phase["items"].append(default_interaction("multipleChoice"))
        phase["items"][-1]["id"] = "i-2"
        widget._move_item(phase, phase["items"][0], 1)
        ids = [it["id"] for it in phase["items"]]
        self.assertEqual(ids, ["i-2", "i-1"])
        self.stack.undo()
        ids = [it["id"] for it in phase["items"]]
        self.assertEqual(ids, ["i-1", "i-2"])

    def test_listening_add_phase_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        widget._on_add_phase()
        self.assertEqual(len(lesson["content"]["listeningPhases"]), 2)
        self.stack.undo()
        self.assertEqual(len(lesson["content"]["listeningPhases"]), 1)

    def test_listening_delete_phase_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        phase = lesson["content"]["listeningPhases"][0]
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes):
            widget._on_delete_phase(phase)
        self.assertEqual(len(lesson["content"]["listeningPhases"]), 0)
        self.stack.undo()
        self.assertEqual(len(lesson["content"]["listeningPhases"]), 1)

    def test_listening_rename_phase_uses_undo(self) -> None:
        widget, lesson = self._make_widget("listening")
        phase = lesson["content"]["listeningPhases"][0]
        with patch.object(QInputDialog, "getText", return_value=("Renamed", True)):
            widget._on_rename_phase(phase)
        self.assertEqual(phase["name"], "Renamed")
        self.stack.undo()
        self.assertEqual(phase["name"], "Phase 1")

    def test_mastery_add_item_uses_undo(self) -> None:
        widget, lesson = self._make_widget("mastery")
        stage = lesson["content"]["stages"][0]
        combo = widget._item_type_combo("multipleChoice")
        widget._on_add_item(stage, combo)
        self.assertEqual(len(stage["items"]), 2)
        self.stack.undo()
        self.assertEqual(len(stage["items"]), 1)

    def test_reading_add_item_uses_undo(self) -> None:
        widget, lesson = self._make_widget("reading")
        stage = lesson["content"]["stages"][0]
        combo = widget._item_type_combo("multipleChoice")
        widget._on_add_item(stage, combo)
        self.assertEqual(len(stage["items"]), 2)
        self.stack.undo()
        self.assertEqual(len(stage["items"]), 1)


if __name__ == "__main__":
    unittest.main()
