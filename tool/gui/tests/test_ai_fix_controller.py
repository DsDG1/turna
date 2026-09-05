"""Unit tests for AiFixController."""
import unittest
from unittest.mock import MagicMock, patch
from PySide6.QtWidgets import QApplication, QDialog

from src.application.ai_fix_controller import AiFixController

app = QApplication.instance() or QApplication([])


class FakeAdapter:
    def __init__(self):
        self.sections = [{"id": "s1", "units": [{"id": "u1", "lessons": [{"id": "l1"}]}]}]
        self.vocab = [{"id": "v1"}]
        self.expressions = [{"id": "e1"}]
        self.grammar_points = [{"id": "g1"}]
        self.index = {"language": "en"}

    def find_section(self, section_id):
        if section_id == "s1":
            return {"id": "s1", "title": "Sec 1"}
        raise KeyError(section_id)

    def find_unit(self, unit_id):
        if unit_id == "u1":
            return ({"id": "s1"}, {"id": "u1", "title": "Unit 1"})
        raise KeyError(unit_id)

    def find_lesson(self, lesson_id):
        if lesson_id == "l1":
            return ({"id": "s1"}, {"id": "u1"}, {"id": "l1", "title": "Lesson 1"})
        raise KeyError(lesson_id)

    def plan_section_merge(self, section_id, corrected):
        return MagicMock()


class FakeTree:
    def __init__(self):
        self.select_section = MagicMock()
        self.refresh_incremental = MagicMock()


class FakeStatusBar:
    def __init__(self):
        self.showMessage = MagicMock()


class FakeWindow:
    def __init__(self):
        self.adapter = FakeAdapter()
        self.tree = FakeTree()
        self._status_bar = FakeStatusBar()
        self.undo_stack = MagicMock()
        self._ai_config = MagicMock()
        self._current_node_ref = ("lesson", "l1")
        self._on_node_selected = MagicMock()
        self._on_ai_edit_applied = MagicMock()
        self._on_ai_batch_fix_requested = MagicMock()
        self._validate_node = MagicMock(return_value=[])

    def statusBar(self):
        return self._status_bar


class TestAiFixController(unittest.TestCase):
    def setUp(self):
        self.controller = AiFixController()
        self.win = FakeWindow()

    @patch("src.application.ai_fix_controller.QMessageBox.warning")
    def test_handle_ai_fix_from_tree_key_error(self, mock_warn):
        self.controller.handle_ai_fix_from_tree(self.win, "lesson", "unknown_id")
        mock_warn.assert_called_once()
        self.win._on_ai_batch_fix_requested.assert_not_called()

    @patch("src.application.ai_fix_controller.QMessageBox.information")
    def test_handle_ai_fix_from_tree_no_problems(self, mock_info):
        self.win._validate_node.return_value = []
        self.controller.handle_ai_fix_from_tree(self.win, "lesson", "l1")
        mock_info.assert_called_once()
        self.win._on_ai_batch_fix_requested.assert_not_called()

    def test_handle_ai_fix_from_tree_with_problems(self):
        prob = {"path": "title", "message": "Too short"}
        self.win._validate_node.return_value = [prob]
        self.controller.handle_ai_fix_from_tree(self.win, "lesson", "l1")
        self.win._on_ai_batch_fix_requested.assert_called_once_with(
            [(prob, ("lesson", "l1"))]
        )

    @patch("src.application.ai_fix_controller.QMessageBox.information")
    def test_run_ai_fix_batch_empty_pairs(self, mock_info):
        self.controller.run_ai_fix_batch(self.win, [])
        mock_info.assert_called_once()

    def test_run_ai_fix_batch_success(self):
        self.win._apply_ai_fix_for_node = MagicMock(return_value=True)
        prob = {"path": "sections/s1/units/u1/lessons/l1", "message": "err"}
        pairs = [(prob, ("lesson", "l1"))]

        self.controller.run_ai_fix_batch(self.win, pairs)
        self.win._apply_ai_fix_for_node.assert_called_once_with("lesson", "l1", [prob])
        self.win._on_node_selected.assert_called_once_with(("lesson", "l1"))
        self.win._status_bar.showMessage.assert_called_once()

    @patch("src.dialogs.ai_fix_dialog.AiFixDialog")
    def test_apply_ai_fix_for_node_lesson_success(self, mock_dialog_cls):
        mock_dlg = MagicMock()
        mock_dlg.exec.return_value = QDialog.DialogCode.Accepted
        mock_dlg.corrected_node.return_value = {"id": "l1", "title": "Fixed"}
        mock_dialog_cls.return_value = mock_dlg

        self.win._validate_node.return_value = []  # No post-fix errors

        result = self.controller.apply_ai_fix_for_node(
            self.win, "lesson", "l1", [{"path": "title", "message": "err"}]
        )
        self.assertTrue(result)
        self.win.undo_stack.push.assert_called_once()
        self.win.tree.refresh_incremental.assert_called_once()


if __name__ == "__main__":
    unittest.main()
