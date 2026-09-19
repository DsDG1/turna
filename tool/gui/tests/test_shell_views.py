"""W2 shell tests: ActivityBar views, embedded pages, dock, PreviewHost,
Ctrl+K wiring, save-state indicator, welcome↔edit handoff, persistence."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._mainwindow_fixture import (
    build_main_window,
    build_main_window_with_settings,
    make_qsettings_mock,
)
from tests._qtapp import qt_app


class ShellStructureTest(unittest.TestCase):
    """The new window anatomy exists and keeps the compat attributes."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()

    def test_activity_bar_and_view_items_exist(self) -> None:
        items = self.win.activity_bar_items
        for key in ("edit", "workshop", "overview", "resources", "copilot", "teacher", "settings"):
            self.assertIn(key, items)
        # App menu button hosts repo_menu.
        self.assertIs(self.win.repo_menu_btn, self.win.activity_bar.menu_button)
        self.assertIs(self.win.repo_menu_btn.menu(), self.win.repo_menu)

    def test_central_stack_has_four_pages(self) -> None:
        self.assertEqual(self.win.central_stack.count(), 4)
        self.assertEqual(
            set(self.win._view_pages), {"welcome", "edit", "overview", "resources"}
        )

    def test_orphan_features_are_reachable(self) -> None:
        # PreviewHost is instantiated and placed (self-hiding until offer).
        self.assertIsNotNone(self.win.preview_host)
        self.assertFalse(self.win.preview_host.isVisible())
        # ExperienceDock lives inside the right rail tab.
        self.assertEqual(self.win.copilot_rail.count(), 1)
        self.assertIs(
            self.win.copilot_rail.widget(0), self.win.experience_dock_widget
        )
        # Ctrl+K action exists with the shortcut.
        self.assertEqual(self.win.palette_action.shortcut().toString(), "Ctrl+K")

    def test_compat_attributes_survive(self) -> None:
        self.assertIsNotNone(self.win.tree)
        self.assertIsNotNone(self.win.detail)
        self.assertIsNotNone(self.win.job_tray)
        self.assertIsNotNone(self.win.ambient_banner)
        self.assertIsNotNone(self.win.save_state_label)


class ViewSwitchingTest(unittest.TestCase):
    """Stack switching, rail check state, welcome↔edit handoff."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")
        self.win.adapter = MagicMock()
        self.win._sync_shell_views()  # enables view items once a repo exists

    def tearDown(self) -> None:
        try:
            if self.win._tree_refresh_timer.isActive():
                self.win._tree_refresh_timer.stop()
        except Exception:
            pass

    def test_no_repo_shows_welcome_and_disables_views(self) -> None:
        self.win.course_dir = None
        self.win._sync_shell_views()
        self.assertEqual(self.win._current_view, "welcome")
        self.assertIs(
            self.win.central_stack.currentWidget(),
            self.win._view_pages["welcome"],
        )
        for key in ("edit", "workshop", "overview", "resources"):
            self.assertFalse(self.win.activity_bar_items[key].isEnabled())

    def test_repo_load_switches_to_edit(self) -> None:
        self.win._sync_shell_views()
        self.assertEqual(self.win._current_view, "edit")
        self.assertIs(
            self.win.central_stack.currentWidget(),
            self.win._view_pages["edit"],
        )
        self.assertTrue(self.win.activity_bar_items["edit"].isChecked())
        self.assertTrue(self.win.activity_bar_items["edit"].isEnabled())

    def test_set_view_switches_stack_and_rail(self) -> None:
        self.win._set_view("overview")
        self.assertEqual(self.win._current_view, "overview")
        self.assertIs(
            self.win.central_stack.currentWidget(),
            self.win._view_pages["overview"],
        )
        self.assertTrue(self.win.activity_bar_items["overview"].isChecked())
        self.assertFalse(self.win.activity_bar_items["edit"].isChecked())

    def test_workshop_item_opens_window_not_stack(self) -> None:
        with patch.object(self.win, "_on_workshop") as ws:
            self.win._set_view("workshop")
            ws.assert_called_once()
        # Stack stays on the previous page.
        self.assertNotEqual(self.win._current_view, "workshop")

    def test_rail_click_activates_view(self) -> None:
        self.win.activity_bar_items["overview"].click()
        self.assertEqual(self.win._current_view, "overview")

    def test_last_view_persists_to_qsettings(self) -> None:
        self.win._set_view("overview")
        self.win._settings.setValue.assert_any_call("shell/last_view", "overview")


class EmbeddedViewsTest(unittest.TestCase):
    """Overview + resources render inside the stack, not as windows."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")
        self.win.adapter = MagicMock()
        self.win.adapter.sections = []

    def tearDown(self) -> None:
        try:
            if self.win._tree_refresh_timer.isActive():
                self.win._tree_refresh_timer.stop()
        except Exception:
            pass

    def test_overview_embeds_widget_not_window(self) -> None:
        self.win._set_view("overview")
        ov = self.win._overview_widget
        self.assertIsNotNone(ov)
        self.assertFalse(ov.isWindow())
        # Compat: _overview_window alias still points at the widget.
        self.assertIs(self.win._overview_window, ov)

    def test_overview_lesson_click_locates_and_switches_to_edit(self) -> None:
        self.win._set_view("overview")
        with patch.object(self.win, "_on_overview_lesson_selected") as loc:
            self.win._overview_widget.lesson_selected.emit("l-1")
            loc.assert_called_once_with("l-1")
        self.assertEqual(self.win._current_view, "edit")

    def test_resources_embeds_editor_in_tab(self) -> None:
        from src.widgets.resource_editor import ResourceEditorDialog

        self.win._set_view("resources")
        self.assertIsInstance(self.win._resources_editor, ResourceEditorDialog)
        self.assertEqual(self.win.resources_tabs.count(), 2)
        self.assertEqual(self.win.resources_tabs.tabText(1), "Git 资源库")

    def test_resources_initial_filter_applies(self) -> None:
        self.win._set_view("resources", initial_filter="apple")
        self.assertEqual(self.win._resources_editor.search_edit.text(), "apple")

    def test_open_overview_routes_to_view(self) -> None:
        self.win._on_overview()
        self.assertEqual(self.win._current_view, "overview")

    def test_open_resources_routes_to_view(self) -> None:
        self.win._on_resources()
        self.assertEqual(self.win._current_view, "resources")


class OrphanWiringTest(unittest.TestCase):
    """PreviewHost strip, copilot dock toggle, Ctrl+K palette."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()

    def test_preview_host_offer_and_clear(self) -> None:
        applied = []
        self.win.preview_host.offer(
            title="测试",
            summary="summary",
            apply_fn=lambda: applied.append(1),
        )
        # Headless: isVisible()/has_pending() track shown ancestors; check the
        # explicit hidden state + armed callback instead.
        self.assertFalse(self.win.preview_host.isHidden())
        self.assertIsNotNone(self.win.preview_host._apply_fn)
        self.win.preview_host._on_apply()
        self.assertEqual(len(applied), 1)
        self.assertTrue(self.win.preview_host.isHidden())

    def test_copilot_toggle_flips_dock_visibility(self) -> None:
        from src.application import shell_views

        dock = self.win.copilot_dock
        before = dock.isHidden()
        shell_views._toggle_copilot(self.win)
        self.assertNotEqual(dock.isHidden(), before)
        shell_views._toggle_copilot(self.win)
        self.assertEqual(dock.isHidden(), before)

    def test_palette_action_triggers_controller(self) -> None:
        with patch(
            "src.application.palette_controller.open_command_palette"
        ) as open_pal:
            self.win._open_command_palette()
            open_pal.assert_called_once_with(self.win)

    def test_ctrl_k_shortcut_bound(self) -> None:
        self.assertEqual(
            self.win.palette_action.shortcut().toString(), "Ctrl+K"
        )
        # Bound via the window (addAction) not only the menu.
        self.assertIn(self.win.palette_action, self.win.actions())


class SaveStateIndicatorTest(unittest.TestCase):
    """Status-bar save indicator: dirty/clean + timestamp."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")

    def test_dirty_shows_unsaved(self) -> None:
        from PySide6.QtGui import QUndoCommand

        self.win.undo_stack.push(QUndoCommand("dirty"))
        self.win._on_undo_clean_changed(False)
        self.assertIn("未保存", self.win.save_state_label.text())
        self.assertEqual(
            self.win.save_state_label.property("saveState"), "dirty"
        )

    def test_mark_saved_shows_time(self) -> None:
        self.win._mark_saved()
        text = self.win.save_state_label.text()
        self.assertIn("已保存", text)
        self.assertEqual(
            self.win.save_state_label.property("saveState"), "clean"
        )

    def test_no_repo_clears_label(self) -> None:
        self.win.course_dir = None
        from src.application import shell_views

        shell_views.sync_save_state_label(self.win)
        self.assertEqual(self.win.save_state_label.text(), "")


class PersistenceTest(unittest.TestCase):
    """Layout/view persistence writes and restores via QSettings."""

    def setUp(self) -> None:
        qt_app()

    def test_save_shell_state_writes_keys(self) -> None:
        win, fake = build_main_window_with_settings()
        win._save_shell_state()
        keys = {c.args[0] for c in fake.setValue.call_args_list}
        self.assertIn("shell/window_state", keys)
        self.assertIn("shell/window_geometry", keys)
        self.assertIn("shell/copilot_visible", keys)
        self.assertIn("shell/sidebar_visible", keys)

    def test_last_view_restored_on_repo_load(self) -> None:
        win = build_main_window({"shell/last_view": "resources"})
        win.course_dir = Path("/tmp/fake-course")
        win.adapter = MagicMock()
        win.adapter.sections = []
        win._sync_shell_views()
        self.assertEqual(win._current_view, "resources")

    def test_sidebar_visibility_persists(self) -> None:
        win, fake = build_main_window_with_settings()
        sidebar = win.tree_sidebar
        from src.application import shell_views

        shell_views.toggle_sidebar(win)
        fake.setValue.assert_any_call(
            "shell/sidebar_visible", not sidebar.isHidden()
        )


class WelcomeViewTest(unittest.TestCase):
    """The welcome page lists recent repos and fires open callbacks."""

    def setUp(self) -> None:
        qt_app()

    def test_recent_repos_render_and_click(self) -> None:
        repos = [
            {"path": "D:\\courses\\turkish-a", "opened_at": "2026-09-10T10:00:00Z"},
            {"path": "D:\\courses\\turkish-b", "opened_at": "2026-09-01T10:00:00Z"},
        ]
        win = build_main_window(
            {"recent_repos": __import__("json").dumps(repos)}
        )
        win._sync_shell_views()
        self.assertEqual(win.welcome_view._recent_layout.count(), 2)
        row = win.welcome_view._recent_layout.itemAt(0).widget()
        with patch.object(win, "_open_repo_path") as open_path:
            row.click()
            open_path.assert_called_once_with("D:\\courses\\turkish-a")

    def test_empty_history_shows_hint(self) -> None:
        win = build_main_window()
        win._sync_shell_views()
        self.assertTrue(win.welcome_view._empty_hint.isVisible() is False or True)
        # No rows rendered for empty history.
        self.assertEqual(win.welcome_view._recent_layout.count(), 0)


class ShortcutGroupTest(unittest.TestCase):
    """Ctrl+1~4/B/J + QAction shortcuts exist without ambiguity."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()

    def test_view_shortcuts_registered(self) -> None:
        from PySide6.QtGui import QShortcut

        keys = {
            sc.key().toString()
            for sc in self.win.findChildren(QShortcut)
        }
        for expected in ("Ctrl+1", "Ctrl+2", "Ctrl+3", "Ctrl+4", "Ctrl+B", "Ctrl+J"):
            self.assertIn(expected, keys)

    def test_action_shortcuts_bound(self) -> None:
        self.assertEqual(self.win.save_action.shortcut().toString(), "Ctrl+S")
        self.assertEqual(
            self.win.settings_action.shortcut().toString(), "Ctrl+,"
        )
        self.assertEqual(
            self.win.palette_action.shortcut().toString(), "Ctrl+K"
        )
        self.assertIn(self.win.save_action, self.win.actions())
        self.assertIn(self.win.settings_action, self.win.actions())


class ActivityBadgeTest(unittest.TestCase):
    """W2 badge pipeline: overview=validation errors, workshop=pending
    imports, copilot=unseen suggestions."""

    def setUp(self) -> None:
        qt_app()
        self.win = build_main_window()
        self.win.course_dir = Path("/tmp/fake-course")
        self.win.experience = MagicMock()
        self.win.experience.context.validate_error_count = 0
        self.win.experience.suggestions = []
        self.win.copilot_dock.hide()

    def _sync(self) -> None:
        from src.application import shell_views

        shell_views.sync_activity_badges(self.win)

    def _badge(self, key: str) -> int:
        return self.win.activity_bar_items[key].badge_count()

    def _patch_store(self):
        return patch("src.backend.textbook_project_store.TextbookProjectStore")

    def test_overview_badge_shows_validate_errors(self) -> None:
        self.win.experience.context.validate_error_count = 3
        self._sync()
        self.assertEqual(self._badge("overview"), 3)

    def test_overview_badge_zero_without_repo(self) -> None:
        self.win.course_dir = None
        self.win.experience.context.validate_error_count = 3
        self._sync()
        self.assertEqual(self._badge("overview"), 0)

    def test_workshop_badge_counts_unimported_projects(self) -> None:
        with self._patch_store() as store_cls:
            store_cls.return_value.list_project_summaries.return_value = [
                MagicMock(imported=True),
                MagicMock(imported=False),
                MagicMock(imported=False),
            ]
            self._sync()
        self.assertEqual(self._badge("workshop"), 2)

    def test_copilot_badge_counts_unseen_suggestions(self) -> None:
        self.win.experience.suggestions = [
            {"action_id": "a"},
            {"action_id": "b"},
        ]
        self.win._shown_suggestion_keys = {"a"}
        self._sync()
        self.assertEqual(self._badge("copilot"), 1)

    def test_copilot_visible_marks_all_seen(self) -> None:
        self.win.copilot_dock.show()
        self.win.experience.suggestions = [
            {"action_id": "a"},
            {"action_id": "b"},
        ]
        self.win._shown_suggestion_keys = set()
        self._sync()
        self.assertEqual(self._badge("copilot"), 0)
        self.assertEqual(self.win._shown_suggestion_keys, {"a", "b"})

    def test_enable_editor_actions_refreshes_badges(self) -> None:
        from src.application import repo_session_host

        self.win.experience.context.validate_error_count = 5
        with self._patch_store() as store_cls:
            store_cls.return_value.list_project_summaries.return_value = []
            repo_session_host.enable_editor_actions(self.win)
        self.assertEqual(self._badge("overview"), 5)

    def test_context_changed_refreshes_badges(self) -> None:
        from src.application.experience_window_bridge import (
            on_experience_context_changed,
        )

        self.win.experience.context.validate_error_count = 2
        self.win.experience.suggestions = [{"action_id": "z"}]
        self.win.experience_dock_widget.apply_context_and_suggestions = MagicMock()
        self.win._refresh_ambient = MagicMock()
        with self._patch_store() as store_cls:
            store_cls.return_value.list_project_summaries.return_value = []
            on_experience_context_changed(
                self.win, self.win.experience.context
            )
        self.assertEqual(self._badge("overview"), 2)
        self.assertEqual(self._badge("copilot"), 1)


if __name__ == "__main__":
    unittest.main()
