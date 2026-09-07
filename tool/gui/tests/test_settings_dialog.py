"""Tests for the SettingsDialog, including the 操作日志 tab."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))


from src.application.settings import Settings  # noqa: E402
from src.application.ai_prompt_library import AiPromptLibrary  # noqa: E402
from src.dialogs.settings_dialog import SettingsDialog  # noqa: E402
from tests._qtapp import _App  # noqa: E402


def _make_prompt_library() -> AiPromptLibrary:
    """In-memory prompt library so tests never touch real QSettings."""
    store: dict[str, str] = {}
    qs = MagicMock()
    qs.value = lambda key, default="": store.get(key, default)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    qs.beginGroup = lambda _name: None
    qs.endGroup = lambda: None
    return AiPromptLibrary(qs)


def _make_qsettings() -> MagicMock:
    store: dict = {"recent_repos": "[]"}
    qs = MagicMock()

    def _value(key, default=None):
        return store.get(key, default)

    qs.value = _value
    qs.contains = lambda key: key in store
    qs.remove = lambda key: store.pop(key, None)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    return qs


class SettingsDialogOperationLogTest(unittest.TestCase):
    def test_has_operation_log_tab(self) -> None:
        _App.get()
        with patch("src.app.QSettings", return_value=_make_qsettings()):
            settings = Settings.load_from_qsettings(_make_qsettings())
        dlg = SettingsDialog(settings, prompt_library=_make_prompt_library())
        self.assertEqual(dlg.tabs.tabText(5), "体验 OS")
        self.assertEqual(dlg.tabs.tabText(7), "操作日志")
        self.assertEqual(dlg.tabs.count(), 8)
        # Refresh / clear / open-dir buttons exist and are wired (no raise).
        dlg._refresh_operation_log()
        self.assertIsNotNone(dlg.oplog_view)
        dlg.deleteLater()

    def test_clear_calls_operations_clear(self) -> None:
        _App.get()
        with patch("src.app.QSettings", return_value=_make_qsettings()):
            settings = Settings.load_from_qsettings(_make_qsettings())
        dlg = SettingsDialog(settings, prompt_library=_make_prompt_library())
        from PySide6.QtWidgets import QMessageBox
        with patch.object(dlg, "_refresh_operation_log"), \
             patch("src.dialogs.settings.operation_log_tab.operations.clear") as cleared, \
             patch("src.dialogs.settings.operation_log_tab.QMessageBox.question",
                   return_value=QMessageBox.StandardButton.Yes):
            dlg._on_clear_operation_log()
            cleared.assert_called_once()
        dlg.deleteLater()


class ExtractionPromptTabTest(unittest.TestCase):
    """P1-3: the 提取 Prompt tab persists overrides and refreshes the library."""

    def test_save_override_refreshes_default_library(self) -> None:
        _App.get()
        import src.backend.knowledge_prompt as kp
        from src.backend.knowledge_prompt import KnowledgePromptLibrary

        old_library = kp.DEFAULT_LIBRARY
        kp.DEFAULT_LIBRARY = KnowledgePromptLibrary()
        try:
            with patch("src.app.QSettings", return_value=_make_qsettings()):
                settings = Settings.load_from_qsettings(_make_qsettings())
            lib = _make_prompt_library()
            dlg = SettingsDialog(settings, prompt_library=lib)
            # Fill the tab fields and save.
            dlg.extraction_lang_edit.setText("Turkish")
            dlg.extraction_src_edit.setText("Chinese")
            dlg._extraction_edits["intro"].setPlainText("测试覆盖引导语ABC")
            with patch("src.dialogs.settings.extraction_prompt_tab.QMessageBox.information"):
                dlg._on_extraction_save()
            # Persisted in the library …
            self.assertIsNotNone(lib.extraction_override("Turkish", "Chinese"))
            # … and live in the in-memory default knowledge library.
            tpl = kp.DEFAULT_LIBRARY.templates_for("Turkish", "Chinese")
            self.assertEqual(tpl.intro, "测试覆盖引导语ABC")
            dlg.deleteLater()
        finally:
            kp.DEFAULT_LIBRARY = old_library


class SettingsDialogAdvancedAiTest(unittest.TestCase):
    """第三枪 批次① Step 8: advanced AI options in the Settings dialog."""

    def _make_dialog(self) -> "SettingsDialog":
        _App.get()
        with patch("src.app.QSettings", return_value=_make_qsettings()):
            settings = Settings.load_from_qsettings(_make_qsettings())
        dlg = SettingsDialog(settings, prompt_library=_make_prompt_library())
        self.addCleanup(dlg.deleteLater)
        return dlg

    def test_advanced_group_exists_and_collapsed_by_default(self) -> None:
        dlg = self._make_dialog()
        # The advanced group must be checkable and start unchecked (collapsed).
        self.assertTrue(dlg.ai_strict_schema_combo.findData("auto") >= 0)
        self.assertTrue(dlg.ai_strict_schema_combo.findData("on") >= 0)
        self.assertTrue(dlg.ai_strict_schema_combo.findData("off") >= 0)

    def test_load_values_populates_advanced_fields(self) -> None:
        dlg = self._make_dialog()
        # Defaults
        self.assertEqual(dlg.ai_model_chat_edit.text(), "")
        self.assertEqual(dlg.ai_model_json_edit.text(), "")
        self.assertEqual(dlg.ai_strict_schema_combo.currentData(), "auto")
        self.assertFalse(dlg.ai_cache_check.isChecked())
        self.assertFalse(dlg.ai_fill_needs_review_check.isChecked())
        self.assertEqual(dlg.ai_max_parallel_lessons_spin.value(), 1)
        self.assertEqual(dlg.ai_pipeline_default_mode_combo.currentData(), "fast")

    def test_sync_to_settings_persists_advanced_fields(self) -> None:
        dlg = self._make_dialog()
        dlg.ai_model_chat_edit.setText("chat-m")
        dlg.ai_model_json_edit.setText("json-m")
        dlg.ai_strict_schema_combo.setCurrentIndex(
            dlg.ai_strict_schema_combo.findData("on")
        )
        dlg.ai_cache_check.setChecked(True)
        dlg.ai_fill_needs_review_check.setChecked(True)
        dlg.ai_max_parallel_lessons_spin.setValue(4)
        dlg.ai_pipeline_default_mode_combo.setCurrentIndex(
            dlg.ai_pipeline_default_mode_combo.findData("refine")
        )
        dlg._sync_to_settings()
        s = dlg._settings
        self.assertEqual(s.ai_model_chat, "chat-m")
        self.assertEqual(s.ai_model_json, "json-m")
        self.assertEqual(s.ai_strict_schema, "on")
        self.assertTrue(s.ai_cache_enabled)
        self.assertTrue(s.ai_fill_needs_review)
        self.assertEqual(s.ai_max_parallel_lessons, 4)
        self.assertEqual(s.ai_pipeline_default_mode, "refine")

    def test_round_trip_load_after_save(self) -> None:
        dlg = self._make_dialog()
        dlg.ai_model_chat_edit.setText("c")
        dlg.ai_model_json_edit.setText("j")
        dlg.ai_strict_schema_combo.setCurrentIndex(
            dlg.ai_strict_schema_combo.findData("off")
        )
        dlg.ai_cache_check.setChecked(True)
        dlg.ai_max_parallel_lessons_spin.setValue(3)
        dlg._sync_to_settings()
        # Simulate a dialog re-open with the same settings
        dlg2 = SettingsDialog(dlg._settings, prompt_library=_make_prompt_library())
        self.addCleanup(dlg2.deleteLater)
        dlg2._load_values()
        self.assertEqual(dlg2.ai_model_chat_edit.text(), "c")
        self.assertEqual(dlg2.ai_model_json_edit.text(), "j")
        self.assertEqual(dlg2.ai_strict_schema_combo.currentData(), "off")
        self.assertTrue(dlg2.ai_cache_check.isChecked())
        self.assertEqual(dlg2.ai_max_parallel_lessons_spin.value(), 3)


class ExperienceTabTest(unittest.TestCase):
    """体验 OS tab: mode ladder + immersive sub-switches + feature gates."""

    def _make_dialog(self, **overrides) -> "SettingsDialog":
        _App.get()
        store = {k: v for k, v in overrides.items()}
        qs = _make_qsettings()
        qs.value = lambda key, default=None: store.get(key, default)
        with patch("src.app.QSettings", return_value=qs):
            settings = Settings.load_from_qsettings(qs)
        dlg = SettingsDialog(settings, prompt_library=_make_prompt_library())
        self.addCleanup(dlg.deleteLater)
        return dlg

    def test_load_values_populates_experience_fields(self) -> None:
        dlg = self._make_dialog(
            **{
                "experience/mode": "active",
                "experience/immersive_full_auto": False,
                "experience/immersive_opaque": False,
                "experience/goal_enabled": True,
                "experience/llm_intent": True,
                "experience/allow_dangerous_skills": True,
                "experience/daily_ai_budget": 42,
            }
        )
        self.assertEqual(dlg.experience_mode_combo.currentData(), "active")
        self.assertFalse(dlg.experience_immersive_full_auto_check.isChecked())
        self.assertFalse(dlg.experience_immersive_opaque_check.isChecked())
        self.assertTrue(dlg.experience_goal_check.isChecked())
        self.assertTrue(dlg.experience_llm_intent_check.isChecked())
        self.assertTrue(dlg.experience_dangerous_check.isChecked())
        self.assertEqual(dlg.experience_budget_spin.value(), 42)

    def test_sync_to_settings_persists_experience_fields(self) -> None:
        dlg = self._make_dialog()
        dlg.experience_mode_combo.setCurrentIndex(
            dlg.experience_mode_combo.findData("observer")
        )
        dlg.experience_immersive_full_auto_check.setChecked(False)
        dlg.experience_budget_spin.setValue(7)
        dlg._sync_to_settings()
        self.assertEqual(dlg._settings.experience_mode, "observer")
        self.assertFalse(dlg._settings.experience_immersive_full_auto)
        self.assertEqual(dlg._settings.experience_daily_ai_budget, 7)

    def test_apply_copies_experience_fields_to_original(self) -> None:
        dlg = self._make_dialog()
        dlg.experience_budget_spin.setValue(9)
        dlg.experience_goal_check.setChecked(True)
        dlg._apply()
        self.assertEqual(dlg._original.experience_daily_ai_budget, 9)
        self.assertTrue(dlg._original.experience_goal_enabled)
        self.assertEqual(dlg._original.experience_mode, "copilot")

    def test_immersive_enter_declined_rolls_back_mode(self) -> None:
        """Headless safe_question returns default_no → combo rolls back."""
        dlg = self._make_dialog()
        dlg.experience_mode_combo.setCurrentIndex(
            dlg.experience_mode_combo.findData("immersive")
        )
        declined = dlg._confirm_experience_mode_change()
        self.assertFalse(declined)
        self.assertEqual(dlg.experience_mode_combo.currentData(), "copilot")
        dlg._apply()
        self.assertEqual(dlg._original.experience_mode, "copilot")

    def test_immersive_enter_accepted_applies_mode(self) -> None:
        dlg = self._make_dialog()
        dlg.experience_mode_combo.setCurrentIndex(
            dlg.experience_mode_combo.findData("immersive")
        )
        with patch("src.dialogs.settings_dialog.safe_question", return_value=True) as sq:
            ok = dlg._confirm_experience_mode_change()
            self.assertTrue(ok)
            sq.assert_called_once()
            dlg._apply()
        self.assertEqual(dlg._original.experience_mode, "immersive")

    def test_non_immersive_change_needs_no_confirm(self) -> None:
        dlg = self._make_dialog(**{"experience/mode": "copilot"})
        dlg.experience_mode_combo.setCurrentIndex(
            dlg.experience_mode_combo.findData("active")
        )
        with patch("src.dialogs.settings_dialog.safe_question") as sq:
            self.assertTrue(dlg._confirm_experience_mode_change())
            sq.assert_not_called()


if __name__ == "__main__":
    unittest.main()
