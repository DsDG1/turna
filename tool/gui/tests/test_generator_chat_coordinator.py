"""Unit tests for GeneratorChatCoordinator."""
from __future__ import annotations

import tempfile
import unittest
from typing import ClassVar
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QLabel,
    QLineEdit,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QTextBrowser,
    QWidget,
)
from tests._qtapp import qt_app

from src.dialogs.ai.generator_chat_coordinator import (
    GeneratorChatCoordinator,
    escape_html,
)
from src.dialogs.ai.generator_view_state import (
    on_chunk_rendered,
    set_busy,
    set_stage_label,
)
from src.application.ai_request_worker import AttachmentRecord


class TestGeneratorChatCoordinator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = qt_app()

    def setUp(self):
        self.coordinator = GeneratorChatCoordinator()

    def test_escape_html(self):
        self.assertEqual(escape_html("<b>hello</b>\nworld"), "&lt;b&gt;hello&lt;/b&gt;<br>world")

    def test_add_messages(self):
        events = []
        self.coordinator.messages_updated.connect(lambda: events.append(True))

        msg1 = self.coordinator.add_user_message("hello")
        self.assertEqual(msg1.role, "user")
        self.assertEqual(msg1.content, "hello")

        msg2 = self.coordinator.add_assistant_message("hi there")
        self.assertEqual(msg2.role, "assistant")
        self.assertEqual(msg2.content, "hi there")

        self.assertEqual(len(self.coordinator.messages), 2)
        self.assertEqual(len(events), 2)

    def test_cleanup_attachments(self):
        tmp = Path(tempfile.gettempdir()) / "test_wish_att.txt"
        tmp.write_text("dummy", encoding="utf-8")
        self.assertTrue(tmp.exists())

        rec = AttachmentRecord(temp_path=tmp, original_name="test.txt", content={})
        self.coordinator.attachments.append(rec)

        self.coordinator.cleanup_attachments()
        self.assertEqual(len(self.coordinator.attachments), 0)
        self.assertFalse(tmp.exists())


class _FakeSignal:
    def __init__(self):
        self.slots = []

    def connect(self, slot):
        self.slots.append(slot)

    def emit(self, *args):
        for slot in list(self.slots):
            slot(*args)


class _FakeWorker:
    instances: ClassVar[list] = []

    def __init__(self, target, *args, **kwargs):
        self.target = target
        self.args = args
        self.kwargs = kwargs
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self.usage_ready = _FakeSignal()
        self.completed = _FakeSignal()
        self.started = False
        _FakeWorker.instances.append(self)

    def start(self):
        self.started = True

    def isRunning(self):
        return False


class WishExplainRetryTest(unittest.TestCase):
    """#9: 「重试解释」must regenerate ONLY the explanation, not the course."""

    def test_retry_runs_explain_worker_on_existing_draft(self):
        from src.backend.ai import explain_course, generate_from_chat
        from src.dialogs.ai.generator_flows import on_wish_explain_retry

        draft = {"id": "s1", "units": []}
        dlg = _SimpleDlg(draft)
        _FakeWorker.instances = []
        with unittest.mock.patch(
            "src.application.ai_request_worker.AiRequestWorker", _FakeWorker
        ), unittest.mock.patch("src.infrastructure.telemetry.telemetry"):
            on_wish_explain_retry(dlg)

        self.assertEqual(len(_FakeWorker.instances), 1)
        worker = _FakeWorker.instances[0]
        self.assertIs(worker.target, explain_course)
        self.assertIsNot(worker.target, generate_from_chat)
        # The explain input is the EXISTING draft object — untouched identity.
        self.assertIs(worker.args[2], draft)
        self.assertIs(dlg._draft_json, draft)
        self.assertIn("explain", dlg.streams)
        self.assertTrue(all(b for b, _s in dlg.busy))

    def test_retry_without_draft_informs_instead_of_generating(self):
        from src.dialogs.ai.generator_flows import on_wish_explain_retry

        dlg = _SimpleDlg(None)
        _FakeWorker.instances = []
        with unittest.mock.patch(
            "src.application.ai_request_worker.AiRequestWorker", _FakeWorker
        ), unittest.mock.patch(
            "src.dialogs.ai.generator_flows.QMessageBox.information"
        ) as info, unittest.mock.patch("src.infrastructure.telemetry.telemetry"):
            on_wish_explain_retry(dlg)
        info.assert_called_once()
        self.assertEqual(_FakeWorker.instances, [])  # no request at all


class _ViewDlg:
    """Duck-typed SectionAiDialog for the view-state helpers under test.

    Real Qt widgets so ``isEnabled()`` assertions mean what they say; every
    side effect is recorded instead of performed.
    """

    _STREAM_TEXT_LIVE_LIMIT = 200

    def __init__(self, mode: str = "wish") -> None:
        self._mode = mode
        self._stream_target = "json"
        self._busy_normal = False
        self._busy_wish = False
        self._generated = None
        self.chat_rendered: list[str] = []
        self.reconnects: list[str] = []
        self._chat_coord = SimpleNamespace(chat_expand_window=None)
        self.mode_combo = QComboBox()
        self.generate_btn = QPushButton("生成课程")
        self.validate_btn = QPushButton()
        self.reset_btn = QPushButton()
        self.send_btn = QPushButton("发送")
        self.wish_btn = QPushButton()
        self.attach_btn = QPushButton()
        self.input_edit = QLineEdit()
        self.progress = QProgressBar()
        self.wish_progress = QProgressBar()
        self.stage_label = QLabel()
        self.wish_stage_label = QLabel()
        self.json_edit = QPlainTextEdit()
        self.explain_label = QTextBrowser()  # real dialog renders HTML here
        self.explain_group = QWidget()
        self._result_toggle = QCheckBox()
        # Slots set_busy wires the buttons to (never invoked in these tests).
        self._cancel_current_worker = lambda: None
        self._on_generate_normal = lambda: None
        self._on_send_message = lambda: None

    def _reconnect(self, btn, slot) -> None:
        self.reconnects.append(btn.text())

    def _render_streaming_chat(self, text: str) -> None:
        self.chat_rendered.append(text)

    def _set_stage_label(self, stage: str) -> None:
        set_stage_label(self, stage)


class ModeSwitchLockTest(unittest.TestCase):
    """T3: mode must not be switchable while a request is in flight.

    Switching mid-request routed the streaming chunks into the other mode's
    editors, so the JSON stream landed in the explanation box (and vice versa).
    """

    def setUp(self) -> None:
        qt_app()

    def test_normal_request_locks_the_mode_switch(self) -> None:
        dlg = _ViewDlg(mode="normal")
        self.assertTrue(dlg.mode_combo.isEnabled())
        set_busy(dlg, True, normal=True)
        self.assertFalse(dlg.mode_combo.isEnabled())
        set_busy(dlg, False, normal=True)
        self.assertTrue(dlg.mode_combo.isEnabled())

    def test_wish_request_locks_the_mode_switch(self) -> None:
        dlg = _ViewDlg(mode="wish")
        set_busy(dlg, True, normal=False)
        self.assertFalse(dlg.mode_combo.isEnabled())
        set_busy(dlg, False, normal=False)
        self.assertTrue(dlg.mode_combo.isEnabled())

    def test_other_mode_going_busy_also_keeps_the_switch_locked(self) -> None:
        # A wish request in flight must not re-enable the switch when the
        # normal lane finishes.
        dlg = _ViewDlg(mode="normal")
        set_busy(dlg, True, normal=False)
        set_busy(dlg, False, normal=True)
        self.assertFalse(dlg.mode_combo.isEnabled())


class StreamTargetRoutingTest(unittest.TestCase):
    """T4: chunks only reach the editor that owns their stream target."""

    def setUp(self) -> None:
        qt_app()

    def test_wish_json_stream_shows_a_live_character_count(self) -> None:
        # wish has no streaming JSON editor, but the stage label must still
        # move — otherwise 生成中（流式）… looks frozen for the whole request.
        dlg = _ViewDlg(mode="wish")
        dlg._stream_target = "json"
        dlg.json_edit.setPlainText("UNTOUCHED")
        on_chunk_rendered(dlg, "x" * 250, False)
        self.assertIn("生成中", dlg.wish_stage_label.text())
        self.assertIn("250", dlg.wish_stage_label.text())
        self.assertEqual(dlg.json_edit.toPlainText(), "UNTOUCHED")

    def test_normal_explain_stream_never_writes_to_the_json_editor(self) -> None:
        dlg = _ViewDlg(mode="normal")
        dlg._stream_target = "explain"
        dlg.json_edit.setPlainText('{"id": "sec-1"}')
        on_chunk_rendered(dlg, '{"id": "sec-2"}', True)
        self.assertEqual(dlg.json_edit.toPlainText(), '{"id": "sec-1"}')

    def test_normal_alignment_stream_never_writes_to_the_json_editor(self) -> None:
        dlg = _ViewDlg(mode="normal")
        dlg._stream_target = "alignment"
        dlg.json_edit.setPlainText("PRIOR")
        on_chunk_rendered(dlg, "late chunk", True)
        self.assertEqual(dlg.json_edit.toPlainText(), "PRIOR")

    def test_normal_json_stream_still_reaches_the_json_editor(self) -> None:
        # The guard must not break the normal path it is meant to protect.
        dlg = _ViewDlg(mode="normal")
        dlg._stream_target = "json"
        on_chunk_rendered(dlg, '{"id": "sec-1"}', True)
        self.assertEqual(dlg.json_edit.toPlainText(), '{"id": "sec-1"}')

    def test_wish_explain_stream_still_reaches_the_explain_box(self) -> None:
        dlg = _ViewDlg(mode="wish")
        dlg._stream_target = "explain"
        dlg._result_toggle.setChecked(True)
        on_chunk_rendered(dlg, "因为…", True)
        self.assertEqual(dlg.explain_label.toPlainText(), "因为…")


class _SimpleDlg:
    """Duck-typed SectionAiDialog for the flow functions under test."""

    def __init__(self, draft):
        self._current_worker = None
        self._draft_json = draft
        self._config = object()
        self._request_start = None
        self.streams = []
        self.busy = []
        self.registered = []

    def _current_spec(self):
        return "spec"

    def _ai_generation_kwargs(self):
        return {}

    def _begin_stream(self, target):
        self.streams.append(target)

    def _set_busy(self, busy, stage=""):
        self.busy.append((busy, stage))

    def _register_worker(self, worker):
        self.registered.append(worker)

    # Delegate slots the flow wiring touches (no-ops for this test).
    def _on_explain_ready(self, explanation):
        pass

    def _on_explain_error(self, message):
        pass

    def _on_worker_chunk(self, chunk):
        pass

    def _on_worker_usage(self, usage):
        pass

    def _on_explain_worker_done(self):
        pass


if __name__ == "__main__":
    unittest.main()
