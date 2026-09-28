"""T5: the attachment preview must not offer a mode that does nothing.

The preview dialog carried a 「引用方式」 radio pair (inline / standalone)
whose value no part of the send path ever read — attachments always went
inline. The pair is removed and the real behaviour is stated in its place.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QRadioButton

from src.application.ai_request_worker import AttachmentRecord
from src.dialogs.ai.attachment_bar import AttachmentPreviewDialog
from tests._qtapp import _App


def _text_record() -> AttachmentRecord:
    return AttachmentRecord(
        temp_path=Path("/tmp/notes.txt"),
        original_name="notes.txt",
        content={"type": "text", "text": "merhaba dünya"},
    )


class AttachmentPreviewDialogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        _App.get()

    def _dialog(self) -> AttachmentPreviewDialog:
        dlg = AttachmentPreviewDialog(_text_record())
        self.addCleanup(dlg.deleteLater)
        return dlg

    def test_no_reference_mode_radios(self) -> None:
        dlg = self._dialog()
        self.assertEqual(dlg.findChildren(QRadioButton), [])

    def test_no_dead_mode_attribute(self) -> None:
        dlg = self._dialog()
        self.assertFalse(hasattr(dlg, "_reference_mode"))
        self.assertFalse(hasattr(dlg, "inline_radio"))
        self.assertFalse(hasattr(dlg, "standalone_radio"))

    def test_states_the_real_send_behaviour(self) -> None:
        dlg = self._dialog()
        texts = [lbl.text() for lbl in dlg.findChildren(__import__(
            "PySide6.QtWidgets", fromlist=["QLabel"]
        ).QLabel)]
        self.assertTrue(
            any("随当前消息" in t for t in texts),
            f"expected the inline behaviour to be stated, saw {texts}",
        )

    def test_preview_still_shows_the_extracted_content(self) -> None:
        dlg = self._dialog()
        edits = dlg.findChildren(__import__(
            "PySide6.QtWidgets", fromlist=["QPlainTextEdit"]
        ).QPlainTextEdit)
        self.assertEqual(len(edits), 1)
        self.assertIn("merhaba dünya", edits[0].toPlainText())


if __name__ == "__main__":
    unittest.main()
