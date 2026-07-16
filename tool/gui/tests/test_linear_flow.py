"""Tests for LinearFlowWidget and SubLessonFlowWidget usability features.

Covers drag-and-drop reordering and the live preview sidebar.
"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PySide6.QtCore import QPoint
from PySide6.QtWidgets import QApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.teacher.linear_flow import LinearFlowWidget  # noqa: E402
from src.teacher.sublesson_flow import SubLessonFlowWidget  # noqa: E402


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _sample_lesson() -> dict:
    return {
        "id": "l-test",
        "name": "Test Lesson",
        "description": "",
        "type": "normal",
        "template": "intro",
        "prerequisiteLessonIds": [],
        "content": {
            "subLessons": [
                {
                    "id": "sl-1",
                    "name": "First",
                    "stages": [
                        {
                            "id": "st-1",
                            "name": "Stage 1",
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
                {
                    "id": "sl-2",
                    "name": "Second",
                    "stages": [],
                },
                {
                    "id": "sl-3",
                    "name": "Third",
                    "stages": [],
                },
            ]
        },
    }


class LinearFlowDragDropTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.lesson = _sample_lesson()
        self.widget = LinearFlowWidget(
            self.adapter,
            {"id": "s-test", "name": "Section"},
            {"id": "u-test", "name": "Unit"},
            self.lesson,
        )
        self.widget.show()
        QApplication.processEvents()

    def test_sub_lesson_drag_drop_moves_to_end(self) -> None:
        # Bypass geometry by forcing the drop target index.
        self.widget._drop_target_index = lambda _y, _frames: 3  # type: ignore[method-assign]
        ids_before = [sl["id"] for sl in self.lesson["content"]["subLessons"]]
        self.assertEqual(ids_before, ["sl-1", "sl-2", "sl-3"])
        self.widget._handle_drop("sublesson", "sl-1", self.widget.mapToGlobal(QPoint(0, 0)))
        ids_after = [sl["id"] for sl in self.lesson["content"]["subLessons"]]
        self.assertEqual(ids_after, ["sl-2", "sl-3", "sl-1"])

    def test_sub_lesson_drag_drop_moves_to_front(self) -> None:
        self.widget._drop_target_index = lambda _y, _frames: 0  # type: ignore[method-assign]
        self.widget._handle_drop("sublesson", "sl-3", self.widget.mapToGlobal(QPoint(0, 0)))
        ids_after = [sl["id"] for sl in self.lesson["content"]["subLessons"]]
        self.assertEqual(ids_after, ["sl-3", "sl-1", "sl-2"])

    def test_sub_lesson_drag_drop_no_op_when_target_adjacent(self) -> None:
        # Dropping sl-1 at index 1 (just after itself) should be a no-op.
        self.widget._drop_target_index = lambda _y, _frames: 1  # type: ignore[method-assign]
        self.widget._handle_drop("sublesson", "sl-1", self.widget.mapToGlobal(QPoint(0, 0)))
        ids_after = [sl["id"] for sl in self.lesson["content"]["subLessons"]]
        self.assertEqual(ids_after, ["sl-1", "sl-2", "sl-3"])

    def test_unknown_kind_is_ignored(self) -> None:
        ids_before = [sl["id"] for sl in self.lesson["content"]["subLessons"]]
        self.widget._handle_drop("unknown", "sl-1", self.widget.mapToGlobal(QPoint(0, 0)))
        ids_after = [sl["id"] for sl in self.lesson["content"]["subLessons"]]
        self.assertEqual(ids_after, ids_before)


class SubLessonLivePreviewTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.adapter = CourseAdapter()
        self.lesson = _sample_lesson()
        self.widget = SubLessonFlowWidget(
            self.adapter,
            {"id": "s-test", "name": "Section"},
            {"id": "u-test", "name": "Unit"},
            self.lesson,
        )
        self.widget.show()
        QApplication.processEvents()

    def test_preview_container_hidden_by_default(self) -> None:
        self.assertFalse(self.widget._preview_container.isVisible())

    def test_toggle_preview_shows_container_and_cards(self) -> None:
        self.widget._on_toggle_preview(True)
        self.assertTrue(self.widget._preview_container.isVisible())
        from src.teacher.preview_window import _PreviewCard

        cards = self.widget._preview_container.findChildren(_PreviewCard)
        self.assertEqual(len(cards), 1)

    def test_refresh_preview_updates_after_content_change(self) -> None:
        self.widget._on_toggle_preview(True)
        from src.teacher.preview_window import _PreviewCard

        # Add a second item to the stage.
        stage = self.lesson["content"]["subLessons"][0]["stages"][0]
        stage["items"].append(
            {
                "runtimeType": "multipleChoice",
                "id": "i-2",
                "prompt": "Q2",
                "options": ["C", "D"],
                "correctIndex": 0,
                "imageAsset": "",
                "grammarPointId": "",
            }
        )
        self.widget._refresh_preview()
        cards = self.widget._preview_container.findChildren(_PreviewCard)
        self.assertEqual(len(cards), 2)


if __name__ == "__main__":
    unittest.main()
