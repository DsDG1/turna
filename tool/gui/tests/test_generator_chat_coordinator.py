"""Unit tests for GeneratorChatCoordinator."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from PySide6.QtWidgets import QWidget
from tests._qtapp import qt_app

from src.dialogs.ai.generator_chat_coordinator import (
    GeneratorChatCoordinator,
    escape_html,
)
from src.dialogs.ai.worker import AttachmentRecord


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


if __name__ == "__main__":
    unittest.main()
