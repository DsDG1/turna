"""Tests for the main application window behavior."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtCore import QSettings
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QMessageBox

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import copy_turkish_course  # noqa: E402

from src.app import MainWindow  # noqa: E402
from src.backend.ai_generator import AiApiConfig  # noqa: E402
from src.backend.course_adapter import SaveResult  # noqa: E402
from tests._qtapp import _App as _TestApp  # noqa: E402


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


class AiEditConflictTest(unittest.TestCase):
    """_detect_ai_edit_conflicts + _on_ai_edit id-conflict three-way choice
    (overwrite / rename-append / cancel) for unit and lesson edits."""

    def setUp(self) -> None:
        _TestApp.get()
        import shutil
        import tempfile

        from PySide6.QtGui import QUndoStack

        from src.backend.course_adapter import CourseAdapter

        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_aiconf_"))
        course_dir = self.tmp / "turkish"
        copy_turkish_course(course_dir)
        self.adapter = CourseAdapter()
        self.adapter.load(course_dir)
        self.win = _build_main_window()
        self.win.adapter = self.adapter
        self.win.course_dir = course_dir
        self.win.undo_stack = QUndoStack()
        self.section = self.adapter.sections[0]
        self.unit = self.section["units"][0]
        self.lesson = self.unit["lessons"][0]

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_detect_unit_no_conflict_when_id_preserved(self) -> None:
        new_unit = dict(self.unit)
        new_unit["name"] = "Edited"
        conflicts = self.win._detect_ai_edit_conflicts(
            "unit", self.unit["id"], new_unit
        )
        self.assertEqual(conflicts, [])

    def test_detect_unit_conflict_when_ai_changed_id(self) -> None:
        new_unit = dict(self.unit)
        new_unit["id"] = "changed-by-ai"
        conflicts = self.win._detect_ai_edit_conflicts(
            "unit", self.unit["id"], new_unit
        )
        self.assertTrue(any(c[1] == "changed-by-ai" for c in conflicts))

    def test_detect_lesson_conflict_when_ai_changed_id(self) -> None:
        new_lesson = dict(self.lesson)
        new_lesson["id"] = "changed-by-ai"
        conflicts = self.win._detect_ai_edit_conflicts(
            "lesson", self.lesson["id"], new_lesson
        )
        self.assertTrue(any(c[1] == "changed-by-ai" for c in conflicts))

    def _patch_dialog(self, new_section):
        patcher = patch("src.dialogs.ai_generator_dialog.AiGeneratorDialog")
        mock = patcher.start()
        mock.return_value.exec.return_value = True
        mock.return_value.section_json.return_value = new_section
        self.addCleanup(patcher.stop)
        return mock

    def test_on_ai_edit_unit_overwrite_pins_id_back(self) -> None:
        new_section = {
            "id": self.section["id"],
            "name": self.section["name"],
            "units": [dict(self.unit, id="changed-by-ai", name="Edited by AI")],
        }
        self._patch_dialog(new_section)
        with patch.object(self.win, "_show_beta_warning_once"),                 patch.object(
                    self.win, "_ask_ai_edit_conflict_resolution",
                    return_value="overwrite"):
            self.win._on_ai_edit("unit", self.unit["id"])
        _s, u = self.adapter.find_unit(self.unit["id"])
        self.assertEqual(u["id"], self.unit["id"])  # pinned back
        self.assertEqual(u["name"], "Edited by AI")

    def test_on_ai_edit_unit_rename_appends_copy(self) -> None:
        before = len(self.section["units"])
        new_section = {
            "id": self.section["id"],
            "name": self.section["name"],
            "units": [dict(self.unit, id="changed-by-ai", name="Edited by AI")],
        }
        self._patch_dialog(new_section)
        with patch.object(self.win, "_show_beta_warning_once"),                 patch.object(
                    self.win, "_ask_ai_edit_conflict_resolution",
                    return_value="rename"):
            self.win._on_ai_edit("unit", self.unit["id"])
        self.assertEqual(len(self.section["units"]), before + 1)
        # Original unit unchanged.
        _s, u = self.adapter.find_unit(self.unit["id"])
        self.assertNotEqual(u["name"], "Edited by AI")

    def test_on_ai_edit_unit_cancel_no_change(self) -> None:
        before = len(self.section["units"])
        new_section = {
            "id": self.section["id"],
            "name": self.section["name"],
            "units": [dict(self.unit, id="changed-by-ai", name="Edited by AI")],
        }
        self._patch_dialog(new_section)
        with patch.object(self.win, "_show_beta_warning_once"),                 patch.object(
                    self.win, "_ask_ai_edit_conflict_resolution",
                    return_value="cancel"):
            self.win._on_ai_edit("unit", self.unit["id"])
        self.assertEqual(len(self.section["units"]), before)

    def test_on_ai_edit_lesson_rename_appends_copy(self) -> None:
        unit = self.unit
        before = len(unit["lessons"])
        new_section = {
            "id": self.section["id"],
            "name": self.section["name"],
            "units": [
                dict(unit, lessons=[dict(self.lesson, id="changed-by-ai", name="Edited")])
            ],
        }
        self._patch_dialog(new_section)
        with patch.object(self.win, "_show_beta_warning_once"),                 patch.object(
                    self.win, "_ask_ai_edit_conflict_resolution",
                    return_value="rename"):
            self.win._on_ai_edit("lesson", self.lesson["id"])
        self.assertEqual(len(unit["lessons"]), before + 1)


class WorkshopImportTargetTest(unittest.TestCase):
    """Workshop 'import into existing section/unit' paths: draft units/lessons
    are appended with fresh ids + resources merged (and rolled back on undo)."""

    def setUp(self) -> None:
        _TestApp.get()
        import shutil
        import tempfile

        from PySide6.QtGui import QUndoStack

        from src.backend.course_adapter import CourseAdapter

        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_ws_"))
        course_dir = self.tmp / "turkish"
        copy_turkish_course(course_dir)
        self.adapter = CourseAdapter()
        self.adapter.load(course_dir)
        self.win = _build_main_window()
        self.win.adapter = self.adapter
        self.win.course_dir = course_dir
        self.win.undo_stack = QUndoStack()
        self.section = self.adapter.sections[0]

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_import_draft_into_section_appends_units_and_resources(self) -> None:
        sid = self.section["id"]
        before = len(self.section["units"])
        draft = {
            "id": "draft",
            "name": "Draft",
            "units": [
                {
                    "id": "d-u1",
                    "name": "DU1",
                    "lessons": [
                        {
                            "id": "d-l1",
                            "name": "DL1",
                            "template": "intro",
                            "content": {"subLessons": []},
                        }
                    ],
                }
            ],
            "words": [
                {"id": "w-draft", "term": "x", "translation": "y", "tags": []}
            ],
        }
        self.win._import_draft_into_section(draft, sid)
        self.assertEqual(len(self.section["units"]), before + 1)
        self.assertIn("w-draft", {w.get("id") for w in self.adapter.vocab})
        # Undo removes the appended unit + rolls back the merged resource.
        self.win.undo_stack.undo()
        self.assertEqual(len(self.section["units"]), before)
        self.assertNotIn("w-draft", {w.get("id") for w in self.adapter.vocab})

    def test_import_draft_into_unit_appends_lessons_and_resources(self) -> None:
        unit = self.section["units"][0]
        uid = unit["id"]
        before = len(unit["lessons"])
        draft = {
            "id": "draft",
            "name": "Draft",
            "units": [
                {
                    "id": "d-u1",
                    "lessons": [
                        {
                            "id": "d-l1",
                            "name": "DL1",
                            "template": "intro",
                            "content": {"subLessons": []},
                        }
                    ],
                }
            ],
            "expressions": [
                {"id": "e-draft", "term": "x", "translation": "y", "tags": []}
            ],
        }
        self.win._import_draft_into_unit(draft, uid)
        self.assertEqual(len(unit["lessons"]), before + 1)
        self.assertIn("e-draft", {e.get("id") for e in self.adapter.expressions})
        self.win.undo_stack.undo()
        self.assertEqual(len(unit["lessons"]), before)
        self.assertNotIn("e-draft", {e.get("id") for e in self.adapter.expressions})

    def test_import_draft_into_section_records_import_on_project(self) -> None:
        """The draft-import paths must persist import state to the project so
        the workshop's 已导入 checklist mark + locate button survive a close
        + reopen (fix for the un-recorded draft-import bug)."""
        sid = self.section["id"]
        draft = {"id": "draft-src", "name": "Draft", "units": [
            {"id": "d-u1", "name": "DU1", "lessons": []}
        ]}
        project = MagicMock()
        project.imported_section_ids = []
        project.import_map = {}
        project.current_step = 0
        workshop = MagicMock()
        workshop.current_project.return_value = project
        self.win._workshop_window = workshop
        try:
            self.win._import_draft_into_section(draft, sid)
        finally:
            self.win._workshop_window = None
        self.assertIn(sid, project.imported_section_ids)
        self.assertEqual(project.import_map.get("draft-src"), sid)

    def test_import_draft_into_unit_records_import_on_project(self) -> None:
        unit = self.section["units"][0]
        uid = unit["id"]
        sid = self.section["id"]
        draft = {"id": "draft-src", "name": "Draft", "units": [
            {"id": "d-u1", "lessons": [
                {"id": "d-l1", "name": "DL1", "template": "intro",
                 "content": {"subLessons": []}}
            ]}
        ]}
        project = MagicMock()
        project.imported_section_ids = []
        project.import_map = {}
        project.current_step = 0
        workshop = MagicMock()
        workshop.current_project.return_value = project
        self.win._workshop_window = workshop
        try:
            self.win._import_draft_into_unit(draft, uid)
        finally:
            self.win._workshop_window = None
        self.assertIn(sid, project.imported_section_ids)
        self.assertEqual(project.import_map.get("draft-src"), sid)

    def test_offer_teacher_after_import_skips_when_hidden(self) -> None:
        """Headless/hidden window must not block on the post-import dialog."""
        from PySide6.QtWidgets import QMessageBox

        with unittest.mock.patch.object(QMessageBox, "question") as q:
            self.win._offer_open_teacher_after_import(self.section["id"])
            q.assert_not_called()

    def test_offer_teacher_after_import_when_visible(self) -> None:
        from PySide6.QtWidgets import QMessageBox

        self.win.show()
        try:
            with unittest.mock.patch.object(
                QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes
            ), unittest.mock.patch.object(
                self.win, "_on_workshop_locate"
            ) as locate:
                self.win._offer_open_teacher_after_import(self.section["id"])
                locate.assert_called_once_with(self.section["id"])
            self.assertTrue(self.win.teacher_mode)
        finally:
            self.win.hide()


if __name__ == "__main__":
    unittest.main()
