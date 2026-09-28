"""Unit tests for GeneratorChatCoordinator."""
from __future__ import annotations

import tempfile
import unittest
from typing import ClassVar
from pathlib import Path
from unittest.mock import MagicMock

from PySide6.QtWidgets import QWidget
from tests._qtapp import qt_app

from src.dialogs.ai.generator_chat_coordinator import (
    GeneratorChatCoordinator,
    escape_html,
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
