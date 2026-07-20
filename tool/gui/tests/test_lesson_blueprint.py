"""Tests for the lesson blueprint widget (workshop2 P3)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import real_adapter_with_course  # noqa: E402


from src.backend.course_adapter import CourseAdapter  # noqa: E402
from src.backend.lesson_presets import FUNCTIONAL_PRESETS, build_preset_lesson  # noqa: E402
from src.teacher.question_cards import QuestionCard  # noqa: E402
from src.widgets.lesson_blueprint import LessonBlueprint  # noqa: E402
from tests._qtapp import _App  # noqa: E402


class _ComboStub:
    """Stand-in for the add-item QComboBox."""

    def __init__(self, rt: str = "multipleChoice") -> None:
        self._rt = rt

    def currentData(self):
        return self._rt


class BlueprintRenderTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()

    def test_each_preset_renders_read_only_and_edit(self) -> None:
        for preset in FUNCTIONAL_PRESETS:
            with self.subTest(preset=preset.id):
                lesson = build_preset_lesson(preset.id)
                LessonBlueprint(self.adapter, lesson, read_only=True)
                LessonBlueprint(self.adapter, lesson, read_only=False)

    def test_read_only_has_no_question_cards(self) -> None:
        lesson = build_preset_lesson("mastery-mix")
        bp = LessonBlueprint(self.adapter, lesson, read_only=True)
        self.assertEqual(len(bp.findChildren(QuestionCard)), 0)

    def test_edit_mode_has_question_cards_for_lesson_with_items(self) -> None:
        lesson = build_preset_lesson("mastery-mix")
        bp = LessonBlueprint(self.adapter, lesson, read_only=False)
        self.assertGreaterEqual(len(bp.findChildren(QuestionCard)), 1)

    def test_listening_blueprint_reflects_three_phases(self) -> None:
        lesson = build_preset_lesson("listening-3phase")
        bp = LessonBlueprint(self.adapter, lesson, read_only=True)
        # Three phase titles "阶段 1/2/3" should appear.
        from PySide6.QtWidgets import QLabel

        labels = [lbl.text() for lbl in bp.findChildren(QLabel)]
        phase_labels = [t for t in labels if t.startswith("阶段 ")]
        self.assertEqual(len(phase_labels), 3)

    def test_reading_blueprint_shows_passage_and_questions(self) -> None:
        lesson = build_preset_lesson("reading-3q")
        bp = LessonBlueprint(self.adapter, lesson, read_only=True)
        from PySide6.QtWidgets import QLabel

        labels = [lbl.text() for lbl in bp.findChildren(QLabel)]
        self.assertIn("阅读篇章", labels)
        self.assertIn("理解题", labels)


class BlueprintEditTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.adapter = CourseAdapter()

    def test_add_item_mutates_stage_without_undo_stack(self) -> None:
        lesson = build_preset_lesson("mastery-mix")
        stage = lesson["content"]["stages"][0]
        before = len(stage["items"])
        bp = LessonBlueprint(self.adapter, lesson, undo_stack=None, read_only=False)
        bp._on_add_item(stage, _ComboStub("fillBlank"))
        self.assertEqual(len(stage["items"]), before + 1)
        self.assertEqual(stage["items"][-1]["runtimeType"], "fillBlank")

    def test_add_phase_mutates_listening_lesson(self) -> None:
        lesson = build_preset_lesson("listening-3phase")
        before = len(lesson["content"]["listeningPhases"])
        bp = LessonBlueprint(self.adapter, lesson, undo_stack=None, read_only=False)
        bp._on_add_phase()
        self.assertEqual(len(lesson["content"]["listeningPhases"]), before + 1)

    def test_delete_item_mutates_stage(self) -> None:
        lesson = build_preset_lesson("mastery-mix")
        stage = lesson["content"]["stages"][0]
        before = len(stage["items"])
        target = stage["items"][0]
        bp = LessonBlueprint(self.adapter, lesson, undo_stack=None, read_only=False)
        # Avoid the modal confirm by calling the command path's direct fn via _push
        # with undo_stack=None: confirm is still shown. Patch QMessageBox.question.
        from PySide6.QtWidgets import QMessageBox
        from unittest.mock import patch

        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes):
            bp._on_delete_item(stage, target)
        self.assertEqual(len(stage["items"]), before - 1)

    def test_changed_signal_emitted_on_add_item(self) -> None:
        lesson = build_preset_lesson("mastery-mix")
        stage = lesson["content"]["stages"][0]
        bp = LessonBlueprint(self.adapter, lesson, undo_stack=None, read_only=False)
        fired = []
        bp.changed.connect(lambda: fired.append(True))
        bp._on_add_item(stage, _ComboStub("multipleChoice"))
        self.assertTrue(fired)


def _real_adapter_with_course():
    return real_adapter_with_course(prefix="varnamala_bp_dp_")


class DetailPanelLessonViewTest(unittest.TestCase):
    """DetailPanel 蓝图/高级编辑 toggle (workshop2 P3 integration)."""

    def setUp(self) -> None:
        _App.get()
        from PySide6.QtGui import QUndoStack

        from src.widgets.detail_panel import DetailPanel

        self.adapter, self.tmp = _real_adapter_with_course()
        self.detail = DetailPanel()
        self.detail.undo_stack = QUndoStack()
        # First lesson in the course.
        for section in self.adapter.sections:
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    self.lesson_id = lesson["id"]
                    break
                if hasattr(self, "lesson_id"):
                    break
            if hasattr(self, "lesson_id"):
                break

    def _inner_widget(self):
        return self.detail._current_content_widget

    def test_non_functional_defaults_to_advanced(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson_id))
        # Turkish first lesson is template "intro" -> advanced (LessonEditor).
        self.assertEqual(self.detail._lesson_view_mode, "advanced")
        from src.widgets.lesson_editor import LessonEditor

        self.assertIsInstance(self._inner_widget(), LessonEditor)

    def test_toggle_to_blueprint_then_back(self) -> None:
        self.detail.show_node(self.adapter, ("lesson", self.lesson_id))
        self.detail._set_lesson_view("blueprint")
        self.assertEqual(self.detail._lesson_view_mode, "blueprint")
        self.assertIsInstance(self._inner_widget(), LessonBlueprint)
        self.detail._set_lesson_view("advanced")
        self.assertEqual(self.detail._lesson_view_mode, "advanced")
        from src.widgets.lesson_editor import LessonEditor

        self.assertIsInstance(self._inner_widget(), LessonEditor)

    def test_functional_defaults_to_blueprint(self) -> None:
        # Force the lesson to a functional template + valid content, then show.
        _s, _u, lesson = self.adapter.find_lesson(self.lesson_id)
        lesson["template"] = "listening"
        lesson["content"] = {"listeningPhases": []}
        self.detail.show_node(self.adapter, ("lesson", self.lesson_id))
        self.assertEqual(self.detail._lesson_view_mode, "blueprint")
        self.assertIsInstance(self._inner_widget(), LessonBlueprint)


if __name__ == "__main__":
    unittest.main()
