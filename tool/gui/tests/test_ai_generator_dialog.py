"""Tests for AI generator dialog async worker and UI state handling."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtWidgets import QApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig
from src.dialogs.ai_generator_dialog import AiGeneratorDialog, AiRequestWorker


class TestAiRequestWorker(unittest.TestCase):
    def test_worker_emits_result(self) -> None:
        worker = AiRequestWorker(lambda: "hello")
        results: list[object] = []
        errors: list[str] = []
        completed = []
        worker.result_ready.connect(results.append)
        worker.error_occurred.connect(errors.append)
        worker.completed.connect(lambda: completed.append(True))
        worker.run()
        self.assertEqual(results, ["hello"])
        self.assertEqual(errors, [])
        self.assertEqual(len(completed), 1)

    def test_worker_emits_error_on_exception(self) -> None:
        def _fail() -> None:
            raise RuntimeError("boom")

        worker = AiRequestWorker(_fail)
        results: list[object] = []
        errors: list[str] = []
        completed = []
        worker.result_ready.connect(results.append)
        worker.error_occurred.connect(errors.append)
        worker.completed.connect(lambda: completed.append(True))
        worker.run()
        self.assertEqual(results, [])
        self.assertEqual(errors, ["boom"])
        self.assertEqual(len(completed), 1)


class TestAiGeneratorDialogAsync(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def _make_dialog(self) -> AiGeneratorDialog:
        adapter = MagicMock()
        adapter.sections = []
        adapter.index = {"sections": []}
        adapter.validate_section_json.return_value = []
        dlg = AiGeneratorDialog(adapter)
        dlg._config = AiApiConfig(
            base_url="https://api.example.com/v1",
            api_key="sk-test",
            model="gpt-test",
        )
        return dlg

    def _sync_start(self, worker: AiRequestWorker) -> None:
        """Run the worker synchronously for tests instead of spawning a thread."""
        worker.run()

    def test_normal_generation_updates_ui(self) -> None:
        dlg = self._make_dialog()
        dlg.topic_edit.setText("Travel")
        course = {"id": "ai-travel", "name": "Travel", "units": []}

        with patch(
            "src.dialogs.ai_generator_dialog.generate_from_chat", return_value=course
        ):
            with patch.object(
                AiRequestWorker, "start", lambda self: self.run()
            ):
                dlg._on_generate_normal()

        self.assertEqual(dlg._generated, course)
        self.assertIn("ai-travel", dlg.json_edit.toPlainText())
        self.assertTrue(dlg.generate_btn.isEnabled())
        self.assertFalse(dlg.progress.isVisible())

    def test_normal_generation_error_shows_message(self) -> None:
        dlg = self._make_dialog()
        dlg.topic_edit.setText("Travel")

        with patch(
            "src.dialogs.ai_generator_dialog.generate_from_chat",
            side_effect=RuntimeError("network down"),
        ):
            with patch.object(
                AiRequestWorker, "start", lambda self: self.run()
            ):
                with patch.object(
                    dlg, "_on_worker_error"
                ) as mock_error:
                    dlg._on_generate_normal()

        mock_error.assert_called_once_with("network down")
        self.assertTrue(dlg.generate_btn.isEnabled())
        self.assertFalse(dlg.progress.isVisible())

    def test_alignment_reply_appends_message(self) -> None:
        dlg = self._make_dialog()
        dlg.input_edit.setText("I want a travel course")

        with patch(
            "src.dialogs.ai_generator_dialog.request_alignment_reply",
            return_value="Sure, here is the plan.",
        ):
            with patch.object(
                AiRequestWorker, "start", lambda self: self.run()
            ):
                dlg._on_send_message()

        roles = [m.role for m in dlg._messages]
        self.assertEqual(roles, ["user", "assistant"])
        self.assertEqual(dlg._messages[-1].content, "Sure, here is the plan.")
        self.assertTrue(dlg.send_btn.isEnabled())

    def test_wish_generation_chain_updates_explanation(self) -> None:
        dlg = self._make_dialog()
        dlg._messages.append(MagicMock(role="user", content="hi"))
        course = {"id": "ai-food", "name": "Food", "units": []}

        with patch(
            "src.dialogs.ai_generator_dialog.generate_from_chat", return_value=course
        ):
            with patch(
                "src.dialogs.ai_generator_dialog.explain_course",
                return_value="This course teaches food vocabulary.",
            ):
                with patch.object(
                    AiRequestWorker, "start", lambda self: self.run()
                ):
                    with patch.object(
                        dlg, "_update_mode_ui"
                    ) as mock_update:
                        dlg._on_wish_generate()

        self.assertEqual(dlg._generated, course)
        self.assertIn(
            "This course teaches food vocabulary.",
            dlg.explain_label.text(),
        )
        self.assertTrue(dlg.explain_label.isVisible())
        self.assertTrue(dlg.wish_btn.isEnabled())
        mock_update.assert_called_once()


if __name__ == "__main__":
    unittest.main()
