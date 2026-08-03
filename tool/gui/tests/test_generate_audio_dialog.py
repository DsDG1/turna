"""Tests for the GenerateAudioDialog (build, defaults, preview, accept)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from PySide6.QtWidgets import QApplication, QDialog

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings  # noqa: E402
from src.dialogs.generate_audio_dialog import GenerateAudioDialog  # noqa: E402


class GenerateAudioDialogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._app = QApplication.instance()
        if cls._app is None:
            cls._app = QApplication([])

    def test_builds_and_defaults_reflect_settings(self) -> None:
        settings = Settings(
            tts_voice_id="v1", tts_model="m1", tts_speed=1.1, tts_force=True,
            tts_api_key="sk-k",
        )
        dlg = GenerateAudioDialog(settings, preview={"total": 5, "existing": 2})
        self.assertEqual(dlg.voice_id(), "v1")
        self.assertEqual(dlg.model(), "m1")
        self.assertEqual(dlg.speed(), 1.1)
        self.assertTrue(dlg.force())
        self.assertEqual(dlg.api_key(), "sk-k")

    def test_accept_syncs_settings(self) -> None:
        settings = Settings()
        dlg = GenerateAudioDialog(settings, preview={"total": 3, "existing": 1})
        dlg._voice_combo.setCurrentText("male-qn-jingying")
        dlg._model_edit.setText("speech-2.8-lite")
        dlg._speed_spin.setValue(0.75)
        dlg._force_check.setChecked(True)
        dlg._key_edit.setText("sk-new")
        dlg._on_accept()
        # Sync back into the in-memory settings (including the memory-only key).
        self.assertEqual(settings.tts_voice_id, "male-qn-jingying")
        self.assertEqual(settings.tts_model, "speech-2.8-lite")
        self.assertEqual(settings.tts_speed, 0.75)
        self.assertTrue(settings.tts_force)
        self.assertEqual(settings.tts_api_key, "sk-new")

    def test_getters_return_safe_defaults_when_blank(self) -> None:
        settings = Settings(tts_voice_id="", tts_model="")
        dlg = GenerateAudioDialog(settings, preview={"total": 0, "existing": 0})
        dlg._voice_combo.setCurrentText("   ")
        dlg._model_edit.setText("")
        self.assertEqual(dlg.voice_id(), "female-tianmei")
        self.assertEqual(dlg.model(), "speech-2.8-hd")

    def test_shows_preview_counts(self) -> None:
        dlg = GenerateAudioDialog(Settings(), preview={"total": 4, "existing": 2})
        self.assertIn("4", dlg._preview_label.text())
        self.assertIn("2", dlg._preview_label.text())


if __name__ == "__main__":
    unittest.main()
