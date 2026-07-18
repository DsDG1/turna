"""Tests for the main application window behavior."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtCore import QSettings
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QApplication, QMessageBox

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.app import MainWindow  # noqa: E402
from src.backend.ai_generator import AiApiConfig  # noqa: E402
from src.backend.course_adapter import SaveResult  # noqa: E402


def _build_main_window_with_ai_settings(ai_values: dict) -> MainWindow:
    """Create a MainWindow with mocked QSettings returning the given AI values."""
    fake_settings = MagicMock()
    _store = dict(ai_values)

    def _value(key, default=None):
        return _store.get(key, default)

    def _contains(key: str) -> bool:
        return key in _store

    def _remove(key: str) -> None:
        _store.pop(key, None)

    fake_settings.value = _value
    fake_settings.contains = _contains
    fake_settings.remove = _remove
    with patch("src.app.QSettings", return_value=fake_settings):
        return MainWindow(), fake_settings


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


def _build_main_window() -> MainWindow:
    """Create a MainWindow with QSettings and recent-repo prompts suppressed."""
    fake_settings = MagicMock()
    fake_settings.value.return_value = "[]"
    with patch("src.app.QSettings", return_value=fake_settings):
        return MainWindow()


class CloseEventTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.win = _build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")
        self.adapter = MagicMock()
        self.win.adapter = self.adapter

    def test_no_changes_accepts_close(self) -> None:
        self.adapter.detect_changes.return_value = {
            "index": False,
            "sections": False,
            "vocab": False,
            "expressions": False,
            "grammar_points": False,
        }
        event = QCloseEvent()
        with patch.object(QMessageBox, "question") as mock_question:
            self.win.closeEvent(event)
            mock_question.assert_not_called()
        self.assertTrue(event.isAccepted())

    def test_dirty_save_accepts_close(self) -> None:
        self.adapter.detect_changes.return_value = {"index": True}
        self.adapter.save.return_value = SaveResult(ok=True)
        event = QCloseEvent()
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Save):
            self.win.closeEvent(event)
        self.adapter.save.assert_called_once()
        self.assertTrue(event.isAccepted())

    def test_dirty_discard_accepts_close(self) -> None:
        self.adapter.detect_changes.return_value = {"vocab": True}
        event = QCloseEvent()
        with patch.object(
            QMessageBox, "question", return_value=QMessageBox.StandardButton.Discard
        ):
            self.win.closeEvent(event)
        self.adapter.save.assert_not_called()
        self.assertTrue(event.isAccepted())

    def test_dirty_cancel_ignores_close(self) -> None:
        self.adapter.detect_changes.return_value = {"sections": True}
        event = QCloseEvent()
        with patch.object(
            QMessageBox, "question", return_value=QMessageBox.StandardButton.Cancel
        ):
            self.win.closeEvent(event)
        self.adapter.save.assert_not_called()
        self.assertFalse(event.isAccepted())

    def test_dirty_save_failure_ignores_close_and_warns(self) -> None:
        self.adapter.detect_changes.return_value = {"index": True}
        self.adapter.save.return_value = SaveResult(
            ok=False, errors=[{"level": "error", "message": "bad"}]
        )
        event = QCloseEvent()
        with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Save):
            with patch.object(QMessageBox, "warning") as mock_warning:
                self.win.closeEvent(event)
        self.assertFalse(event.isAccepted())
        mock_warning.assert_called_once()

    def test_close_clears_api_key(self) -> None:
        self.adapter.detect_changes.return_value = {
            "index": False,
            "sections": False,
            "vocab": False,
            "expressions": False,
            "grammar_points": False,
        }
        self.win._ai_config.api_key = "sk-secret"
        self.win._settings_obj.ai_api_key = "sk-secret"
        event = QCloseEvent()
        with patch.object(QMessageBox, "question") as mock_question:
            self.win.closeEvent(event)
            mock_question.assert_not_called()
        self.assertTrue(event.isAccepted())
        self.assertEqual(self.win._ai_config.api_key, "")
        self.assertEqual(self.win._settings_obj.ai_api_key, "")


class AiConfigPersistenceTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()

    def test_loads_ai_config_from_settings(self) -> None:
        win, _settings = _build_main_window_with_ai_settings(
            {
                "ai/base_url": "https://api.example.com/v1",
                "ai/api_key": "sk-test",
                "ai/model": "gpt-test",
                "recent_repos": "[]",
            }
        )
        self.assertEqual(win._ai_config.base_url, "https://api.example.com/v1")
        # API key is memory-only and must not be loaded from storage.
        self.assertEqual(win._ai_config.api_key, "")
        self.assertEqual(win._ai_config.model, "gpt-test")

    def test_loads_api_key_only_from_memory(self) -> None:
        win, _settings = _build_main_window_with_ai_settings(
            {"recent_repos": "[]"}
        )
        win._ai_config.api_key = "sk-memory"
        # Re-loading settings must not overwrite the in-memory API key.
        win._ai_config = win._load_ai_config()
        self.assertEqual(win._ai_config.api_key, "")

    def test_saves_ai_config_to_settings(self) -> None:
        win, settings = _build_main_window_with_ai_settings({"recent_repos": "[]"})
        win._ai_config = AiApiConfig(
            base_url="https://api.save.com/v1",
            api_key="sk-save",
            model="m-save",
        )
        win._save_ai_config(win._ai_config)
        settings.setValue.assert_any_call("ai/base_url", "https://api.save.com/v1")
        # API key must never be persisted.
        for call in settings.setValue.call_args_list:
            args, _ = call
            self.assertNotEqual(args[0], "ai/api_key")
        settings.setValue.assert_any_call("ai/model", "m-save")


class ToolbarMenuTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()

    def test_course_repo_menu_replaces_old_entries(self) -> None:
        win = _build_main_window()
        # The old standalone actions should be gone.
        self.assertFalse(hasattr(win, "new_action"))
        self.assertFalse(hasattr(win, "open_action"))
        self.assertFalse(hasattr(win, "recent_btn"))
        # The merged menu button and its submenu should exist.
        self.assertTrue(hasattr(win, "repo_menu_btn"))
        self.assertTrue(hasattr(win, "repo_menu"))
        self.assertTrue(hasattr(win, "recent_menu"))
        # The wizard action should be gone (wizard is now inside AI dialog).
        self.assertFalse(hasattr(win, "wizard_action"))

    def test_settings_action_exists(self) -> None:
        win = _build_main_window()
        self.assertTrue(hasattr(win, "settings_action"))
        self.assertEqual(win.settings_action.text(), "设置")


class AutoSaveOnCloseTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()

    def test_auto_save_on_close_saves_without_prompt(self) -> None:
        win = _build_main_window()
        win.course_dir = Path("/tmp/fake-course")
        win._settings_obj.auto_save_on_close = True
        adapter = MagicMock()
        adapter.detect_changes.return_value = {"index": True}
        adapter.save.return_value = SaveResult(ok=True)
        win.adapter = adapter

        event = QCloseEvent()
        with patch.object(QMessageBox, "question") as mock_question:
            win.closeEvent(event)
            mock_question.assert_not_called()
        adapter.save.assert_called_once()
        self.assertTrue(event.isAccepted())

    def test_auto_save_failure_ignores_close(self) -> None:
        win = _build_main_window()
        win.course_dir = Path("/tmp/fake-course")
        win._settings_obj.auto_save_on_close = True
        adapter = MagicMock()
        adapter.detect_changes.return_value = {"index": True}
        adapter.save.return_value = SaveResult(
            ok=False, errors=[{"level": "error", "message": "bad"}]
        )
        win.adapter = adapter

        event = QCloseEvent()
        with patch.object(QMessageBox, "warning") as mock_warning:
            win.closeEvent(event)
        adapter.save.assert_called_once()
        self.assertFalse(event.isAccepted())
        mock_warning.assert_called_once()


class SettingsIntegrationTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()

    def test_settings_object_loaded_at_init(self) -> None:
        win = _build_main_window()
        self.assertTrue(hasattr(win, "_settings_obj"))
        self.assertEqual(win._settings_obj.theme, "dark")

    def test_undo_limit_taken_from_settings(self) -> None:
        fake_settings = MagicMock()
        fake_settings.value = lambda key, default=None: {
            "recent_repos": "[]",
            "editor/undo_limit": 250,
        }.get(key, default)
        with patch("src.app.QSettings", return_value=fake_settings):
            win = MainWindow()
        self.assertEqual(win.undo_stack.undoLimit(), 250)


def _real_lookup_adapter():
    """Mock adapter whose find_lesson/sections behave like the real one."""
    adapter = MagicMock()
    adapter.sections = [
        {
            "id": "section1",
            "name": "Section 1",
            "units": [
                {
                    "id": "u-1",
                    "name": "Unit 1",
                    "lessons": [
                        {"id": "s1-l1", "name": "Lesson 1", "template": "intro"},
                        {"id": "s1-l2", "name": "Lesson 2", "template": "practice"},
                    ],
                },
            ],
        },
    ]

    def find_lesson(lesson_id):
        for s in adapter.sections:
            for u in s.get("units", []):
                for l in u.get("lessons", []):
                    if l.get("id") == lesson_id:
                        return s, u, l
        raise KeyError(lesson_id)

    adapter.find_lesson.side_effect = find_lesson
    return adapter


class TeacherModeToggleTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.win = _build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")
        self.adapter = _real_lookup_adapter()
        self.win.adapter = self.adapter

    def test_no_floating_teacher_window_attr(self) -> None:
        # The floating TeacherWindow was removed; teacher mode renders inline.
        self.assertFalse(hasattr(self.win, "_teacher_window"))

    def test_toggle_on_renders_first_lesson_inline(self) -> None:
        from src.teacher.sublesson_flow import SubLessonFlowWidget

        self.win.mode_action.setChecked(True)
        self.assertTrue(self.win.teacher_mode)
        # Defaults to the first lesson when nothing is selected.
        self.assertEqual(self.win._current_node_ref, ("lesson", "s1-l1"))
        # The right detail pane hosts the teacher authoring widget inline.
        self.assertIsInstance(
            self.win.detail._current_content_widget, SubLessonFlowWidget
        )

    def test_toggle_on_with_lesson_selected_keeps_it(self) -> None:
        from src.teacher.sublesson_flow import SubLessonFlowWidget

        self.win._current_node_ref = ("lesson", "s1-l2")
        self.win.mode_action.setChecked(True)
        # A selected lesson is preserved rather than reset to the first.
        self.assertEqual(self.win._current_node_ref, ("lesson", "s1-l2"))
        self.assertIsInstance(
            self.win.detail._current_content_widget, SubLessonFlowWidget
        )

    def test_toggle_off_returns_to_expert_view(self) -> None:
        self.win.mode_action.setChecked(True)
        self.win.mode_action.setChecked(False)
        self.assertFalse(self.win.teacher_mode)
        self.assertEqual(self.win.mode_action.text(), "教师模式")
        # Detail pane cleared the inline teacher widget (show_node -> clear).
        self.assertIsNone(self.win.detail._current_content_widget)


if __name__ == "__main__":
    unittest.main()
