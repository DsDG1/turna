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

from PySide6.QtWidgets import QApplication  # noqa: E402

from src.application.settings import Settings  # noqa: E402
from src.backend.ai_prompt_library import AiPromptLibrary  # noqa: E402
from src.dialogs.settings_dialog import SettingsDialog  # noqa: E402


def _make_prompt_library() -> AiPromptLibrary:
    """In-memory prompt library so tests never touch real QSettings."""
    store: dict[str, str] = {}
    qs = MagicMock()
    qs.value = lambda key, default="": store.get(key, default)
    qs.setValue = lambda key, value: store.__setitem__(key, value)
    qs.beginGroup = lambda _name: None
    qs.endGroup = lambda: None
    return AiPromptLibrary(qs)


class _App:
    _app = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


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
        self.assertEqual(dlg.tabs.tabText(5), "操作日志")
        self.assertEqual(dlg.tabs.count(), 6)
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
             patch("src.dialogs.settings_dialog.operations.clear") as cleared, \
             patch("src.dialogs.settings_dialog.QMessageBox.question",
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
            with patch("src.dialogs.settings_dialog.QMessageBox.information"):
                dlg._on_extraction_save()
            # Persisted in the library …
            self.assertIsNotNone(lib.extraction_override("Turkish", "Chinese"))
            # … and live in the in-memory default knowledge library.
            tpl = kp.DEFAULT_LIBRARY.templates_for("Turkish", "Chinese")
            self.assertEqual(tpl.intro, "测试覆盖引导语ABC")
            dlg.deleteLater()
        finally:
            kp.DEFAULT_LIBRARY = old_library


if __name__ == "__main__":
    unittest.main()