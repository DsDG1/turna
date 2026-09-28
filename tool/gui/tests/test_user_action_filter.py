"""Tests for the global UserActionFilter (clicks + input commits + redaction)."""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtCore import QEvent, Qt
from PySide6.QtGui import QMouseEvent
from PySide6.QtWidgets import QLineEdit, QPushButton

from src.infrastructure import user_action_filter as uaf_mod
from src.infrastructure import operations_log
from src.infrastructure.telemetry import Telemetry
from tests._qtapp import _App


class UserActionFilterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_filter_"))
        self.log_file = self.tmp / "operations.log"
        # Redirect the module singleton so tests don't touch the real log dir.
        self._orig_ops = operations_log.operations
        self.ops = Telemetry(self.log_file)
        operations_log.operations = self.ops
        uaf_mod.operations = self.ops

    def tearDown(self) -> None:
        uaf_mod.operations = operations_log.operations
        operations_log.operations = self._orig_ops
        self.ops.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _lines(self) -> list[dict]:
        return [json.loads(item) for item in self.log_file.read_text(encoding="utf-8").splitlines() if item.strip()]

    def _press_button(self, btn: QPushButton) -> None:
        # Synthesize a MouseButtonPress on the button via QApplication.notify.
        app = _App.get()
        btn.show()
        pos = btn.rect().center()
        event = QMouseEvent(
            QEvent.Type.MouseButtonPress,
            pos,
            btn.mapToGlobal(pos),
            Qt.MouseButton.LeftButton,
            Qt.MouseButton.LeftButton,
            Qt.KeyboardModifier.NoModifier,
        )
        app.notify(btn, event)

    def test_click_records_ui_click_with_target(self) -> None:
        app = _App.get()
        flt = uaf_mod.UserActionFilter(app)
        app.installEventFilter(flt)
        try:
            btn = QPushButton("保存")
            self._press_button(btn)
        finally:
            app.removeEventFilter(flt)
        clicks = [item for item in self._lines() if item["event"] == "ui.click"]
        self.assertTrue(clicks)
        self.assertEqual(clicks[-1]["payload"]["target"], "保存")

    def _focus_out(self, edit) -> None:
        app = _App.get()
        edit.show()
        app.processEvents()
        from PySide6.QtGui import QFocusEvent

        app.notify(edit, QFocusEvent(QEvent.Type.FocusOut))

    def _commit(self, text: str, secret: bool = False, expect: bool = True) -> dict:
        """Drive one FocusOut commit through a freshly installed filter."""
        app = _App.get()
        flt = uaf_mod.UserActionFilter(app)
        app.installEventFilter(flt)
        try:
            edit = QLineEdit()
            if secret:
                edit.setEchoMode(QLineEdit.EchoMode.Password)
            edit.setText(text)
            self._focus_out(edit)
        finally:
            app.removeEventFilter(flt)
        commits = [item for item in self._lines() if item["event"] == "ui.input.commit"]
        if expect:
            self.assertTrue(commits, "expected an input.commit record")
        return commits[-1] if commits else {}

    def test_password_field_is_redacted(self) -> None:
        commit = self._commit("sk-secret-value", secret=True)
        body = json.dumps(commit, ensure_ascii=False)
        self.assertNotIn("sk-secret-value", body)
        self.assertEqual(commit["payload"]["text"], "<redacted>")

    def test_plain_input_content_is_not_recorded(self) -> None:
        """Course text / prompts must never reach operations.log verbatim.

        Two leak paths to cover: the ``payload`` fingerprint and the
        ``target`` label (which used to be the widget's own ``text()``).
        """
        secret_phrase = "kedi burada çok güzel bir ev var"
        commit = self._commit(secret_phrase)
        body = json.dumps(commit, ensure_ascii=False)
        self.assertNotIn(secret_phrase, body)
        self.assertNotIn("kedi", body)
        self.assertNotIn("text", commit["payload"])
        self.assertNotIn(secret_phrase, commit["payload"]["target"])
        self.assertEqual(commit["payload"]["chars"], len(secret_phrase))

    def test_fingerprint_shape_is_stable_and_content_sensitive(self) -> None:
        first = self._commit("hello world")["payload"]
        again = self._commit("hello world")["payload"]
        other = self._commit("goodbye world")["payload"]
        self.assertEqual(first["chars"], len("hello world"))
        self.assertEqual(first["sha"], again["sha"], "same input -> same digest")
        self.assertNotEqual(first["sha"], other["sha"], "different input -> different digest")
        self.assertRegex(first["sha"], r"^[0-9a-f]{8}$")

    def test_opt_in_env_records_text(self) -> None:
        original = uaf_mod._RECORD_TEXT
        uaf_mod._RECORD_TEXT = True
        try:
            commit = self._commit("visible text")
        finally:
            uaf_mod._RECORD_TEXT = original
        self.assertEqual(commit["payload"]["text"], "visible text")
        self.assertEqual(commit["payload"]["chars"], len("visible text"))

    def test_empty_input_is_not_recorded(self) -> None:
        self._commit("", expect=False)
        commits = [item for item in self._lines() if item["event"] == "ui.input.commit"]
        self.assertEqual(commits, [])

    def test_filter_never_raises(self) -> None:
        app = _App.get()
        flt = uaf_mod.UserActionFilter(app)
        # A non-widget object passed to MouseButtonPress must not raise.
        class Bad:
            def text(self):
                raise RuntimeError("boom")

        result = flt.eventFilter(Bad(), QEvent(QEvent.Type.MouseButtonPress))
        self.assertFalse(result)
        result2 = flt.eventFilter(Bad(), QEvent(QEvent.Type.KeyPress))
        self.assertFalse(result2)


if __name__ == "__main__":
    unittest.main()
