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

from PySide6.QtCore import QEvent, Qt  # noqa: E402
from PySide6.QtGui import QMouseEvent  # noqa: E402
from PySide6.QtWidgets import QApplication, QLineEdit, QPushButton  # noqa: E402

from src.infrastructure import user_action_filter as uaf_mod  # noqa: E402
from src.infrastructure import operations_log  # noqa: E402
from src.infrastructure.telemetry import Telemetry  # noqa: E402


class _App:
    _app = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class UserActionFilterTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_filter_"))
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
        return [json.loads(l) for l in self.log_file.read_text(encoding="utf-8").splitlines() if l.strip()]

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
        clicks = [l for l in self._lines() if l["event"] == "ui.click"]
        self.assertTrue(clicks)
        self.assertEqual(clicks[-1]["payload"]["target"], "保存")

    def test_password_field_is_redacted(self) -> None:
        app = _App.get()
        flt = uaf_mod.UserActionFilter(app)
        app.installEventFilter(flt)
        try:
            edit = QLineEdit()
            edit.setEchoMode(QLineEdit.EchoMode.Password)
            edit.setObjectName("ai_key_edit")
            edit.setText("sk-secret-value")
            edit.show()
            app.processEvents()
            # Fire a FocusOut event to trigger input commit.
            from PySide6.QtGui import QFocusEvent

            app.notify(edit, QFocusEvent(QEvent.Type.FocusOut))
        finally:
            app.removeEventFilter(flt)
        commits = [l for l in self._lines() if l["event"] == "ui.input.commit"]
        self.assertTrue(commits)
        body = json.dumps(commits[-1], ensure_ascii=False)
        self.assertNotIn("sk-secret-value", body)
        self.assertEqual(commits[-1]["payload"]["text"], "<redacted>")

    def test_filter_never_raises(self) -> None:
        app = _App.get()
        flt = uaf_mod.UserActionFilter(app)
        # A non-widget object passed to MouseButtonPress must not raise.
        class Bad:
            def text(self):  # noqa: D401
                raise RuntimeError("boom")

        result = flt.eventFilter(Bad(), QEvent(QEvent.Type.MouseButtonPress))
        self.assertFalse(result)
        result2 = flt.eventFilter(Bad(), QEvent(QEvent.Type.KeyPress))
        self.assertFalse(result2)


if __name__ == "__main__":
    unittest.main()