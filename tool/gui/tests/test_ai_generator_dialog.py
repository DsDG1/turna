"""Tests for AI generator dialog async worker and UI state handling."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from PySide6.QtWidgets import QMessageBox

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._qtapp import qt_app  # noqa: E402

from PySide6.QtCore import Qt

from src.backend.ai import AiApiConfig
from src.application.ai_request_worker import AiRequestWorker
from src.dialogs.ai.section_ai_dialog import AiGeneratorDialog


class TestAiRequestWorker(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = qt_app()

    @classmethod
    def _run_worker(cls, worker: AiRequestWorker) -> None:
        """Start the worker thread and drain queued signals before assertions."""
        worker.start()
        cls.app.processEvents()
        worker.wait(5000)
        cls.app.processEvents()

    def test_worker_emits_result(self) -> None:
        worker = AiRequestWorker(lambda: "hello")
        results: list[object] = []
        errors: list[str] = []
        completed = []
        worker.result_ready.connect(results.append)
        worker.error_occurred.connect(errors.append)
        worker.completed.connect(lambda: completed.append(True))
        self._run_worker(worker)
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
        self._run_worker(worker)
        self.assertEqual(results, [])
        self.assertEqual(errors, ["boom"])
        self.assertEqual(len(completed), 1)

    def test_worker_injects_on_chunk_and_usage_callback(self) -> None:
        """A target declaring on_chunk/usage_callback receives them via kwargs."""
        captured: dict = {}

        def target(config, spec, messages, on_chunk=None, usage_callback=None):
            captured["on_chunk"] = on_chunk
            captured["usage_callback"] = usage_callback
            on_chunk("frag1")
            on_chunk("frag2")
            usage_callback({"total_tokens": 42})
            return "done"

        chunks: list[str] = []
        usages: list[object] = []
        worker = AiRequestWorker(target, None, None, [])
        worker.chunk_ready.connect(chunks.append)
        worker.usage_ready.connect(usages.append)
        self._run_worker(worker)
        self.assertIsNotNone(captured["on_chunk"])
        self.assertIsNotNone(captured["usage_callback"])
        self.assertEqual(chunks, ["frag1", "frag2"])
        self.assertEqual(usages, [{"total_tokens": 42}])

    def test_worker_injects_cancel_check_when_accepted(self) -> None:
        captured: dict = {}

        def target(cancel_check=None):
            captured["cancel_check"] = cancel_check
            return "ok"

        worker = AiRequestWorker(target)
        self._run_worker(worker)
        self.assertIsNotNone(captured["cancel_check"])


class TestAiGeneratorDialogAsync(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = qt_app()

    def setUp(self) -> None:
        self._dialogs: list[AiGeneratorDialog] = []

    def tearDown(self) -> None:
        # Close and delete top-level dialogs to avoid offscreen segfaults on exit.
        import gc

        for dlg in self._dialogs:
            try:
                dlg.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
                dlg.close()
            except Exception:
                pass
        self._dialogs.clear()
        self.app.processEvents()
        gc.collect()
        self.app.processEvents()

    def _make_dialog(self, adapter=None) -> AiGeneratorDialog:
        if adapter is None:
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
        self._dialogs.append(dlg)
        return dlg

    def _sync_start(self, worker: AiRequestWorker) -> None:
        """Run the worker synchronously for tests instead of spawning a thread."""
        worker.run()

    def test_normal_generation_updates_ui(self) -> None:
        dlg = self._make_dialog()
        dlg.topic_edit.setText("Travel")
        course = {"id": "ai-travel", "name": "Travel", "units": []}

        with patch(
            "src.dialogs.ai.generator_flows.request_course_with_retry", return_value=course
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
            "src.dialogs.ai.generator_flows.request_course_with_retry",
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
            "src.dialogs.ai.generator_flows.request_alignment_reply",
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
            "src.dialogs.ai.generator_flows.generate_from_chat", return_value=course
        ):
            with patch(
                "src.dialogs.ai.generator_flows.explain_course",
                return_value="This course teaches food vocabulary.",
            ):
                with patch.object(
                    AiRequestWorker, "start", lambda self: self.run()
                ):
                    with patch.object(dlg, "_update_mode_ui") as mock_update:
                        with patch.object(
                            QMessageBox, "information", return_value=None
                        ):
                            dlg._on_wish_generate()

        self.assertEqual(dlg._generated, course)
        self.assertIn(
            "This course teaches food vocabulary.",
            dlg.explain_label.toPlainText(),
        )
        self.assertFalse(dlg.explain_group.isHidden())
        self.assertTrue(dlg.wish_btn.isEnabled())
        mock_update.assert_called_once()

    def test_duration_since_request_start_is_zero_when_none(self) -> None:
        """B7: with no live _request_start, duration must not raise/inherit stale."""
        dlg = self._make_dialog()
        dlg._request_start = None
        # Must be 0 (not a TypeError, not a huge stale value).
        self.assertEqual(dlg._duration_since_request_start(), 0.0)

    def test_request_start_reset_after_normal_generation(self) -> None:
        """B7: _request_start is cleared to None after a worker finishes."""
        dlg = self._make_dialog()
        dlg.topic_edit.setText("Travel")
        course = {"id": "ai-travel", "name": "Travel", "units": []}
        with patch(
            "src.dialogs.ai.generator_flows.request_course_with_retry", return_value=course
        ):
            with patch.object(AiRequestWorker, "start", lambda self: self.run()):
                dlg._on_generate_normal()
        # The normal worker's completed handler clears _request_start.
        self.assertIsNone(dlg._request_start)

    def test_wizard_generation_does_not_call_ai(self) -> None:
        word = {
            "id": "w-hello",
            "term": "hello",
            "translation": "你好",
            "pronunciation": None,
            "audioAsset": None,
            "tags": [],
        }
        adapter = MagicMock()
        adapter.sections = []
        adapter.index = {"sections": []}
        adapter.vocab = [word]
        adapter.vocab_options.return_value = [("w-hello", "hello — 你好")]
        adapter.validate_section_json.return_value = []
        dlg = self._make_dialog(adapter)

        dlg.wizard_name_edit.setText("Greetings")
        for i in range(dlg.wizard_word_list.count()):
            item = dlg.wizard_word_list.item(i)
            if item.data(Qt.ItemDataRole.UserRole) == "w-hello":
                item.setCheckState(Qt.CheckState.Checked)

        with patch(
            "src.dialogs.ai.generator_flows.generate_from_chat"
        ) as mock_ai_generate:
            dlg._on_wizard_generate()

        mock_ai_generate.assert_not_called()
        self.assertIsNotNone(dlg._generated)
        self.assertEqual(dlg._generated.get("name"), "Greetings")
        self.assertEqual(len(dlg._generated["units"][0]["lessons"]), 1)

    def test_wish_generation_populates_wish_json_edit(self) -> None:
        """P3.3: wish generation writes the section into the wish JSON editor."""
        dlg = self._make_dialog()
        dlg._mode = "wish"
        dlg._update_mode_ui()
        course = {"id": "ai-food", "name": "Food", "units": []}
        with patch(
            "src.dialogs.ai.generator_flows.explain_course",
            return_value="This course teaches food vocabulary.",
        ):
            with patch.object(
                AiRequestWorker, "start", lambda self: self.run()
            ):
                with patch.object(dlg, "_update_mode_ui"):
                    with patch.object(
                        QMessageBox, "information", return_value=None
                    ):
                        dlg._on_wish_generation_ready(course)
        self.assertIn("ai-food", dlg.wish_json_edit.toPlainText())

    def test_current_json_reads_wish_editor_not_generated(self) -> None:
        """B1 regression: wish-mode import reads the editor, not the cached dict."""
        dlg = self._make_dialog()
        dlg._mode = "wish"
        dlg._update_mode_ui()
        dlg._generated = {"id": "ai-orig", "name": "Orig", "units": []}
        dlg.wish_json_edit.set_json({"id": "EDITED", "name": "X", "units": []})
        self.assertEqual(dlg._current_json()["id"], "EDITED")

    def test_current_json_normal_reads_editor(self) -> None:
        """Normal mode import reads the editor (unchanged behavior, regression guard)."""
        dlg = self._make_dialog()
        dlg._mode = "normal"
        dlg.json_edit.set_json({"id": "N1", "name": "N", "units": []})
        self.assertEqual(dlg._current_json()["id"], "N1")

    def test_normal_panel_has_two_column_splitter(self) -> None:
        """Change 1: normal mode is laid out as a horizontal 2-column splitter."""
        dlg = self._make_dialog()
        dlg._mode = "normal"
        dlg._update_mode_ui()
        self.assertTrue(hasattr(dlg, "_normal_splitter"))
        self.assertEqual(dlg._normal_splitter.orientation(), Qt.Orientation.Horizontal)
        self.assertEqual(dlg._normal_splitter.count(), 2)

    def test_wish_panel_has_two_column_splitter(self) -> None:
        """Change 1: wish mode is laid out as a horizontal 2-column splitter."""
        dlg = self._make_dialog()
        dlg._mode = "wish"
        dlg._update_mode_ui()
        self.assertTrue(hasattr(dlg, "wish_splitter"))
        self.assertEqual(dlg.wish_splitter.orientation(), Qt.Orientation.Horizontal)
        self.assertEqual(dlg.wish_splitter.count(), 2)

    def test_json_window_toggle_reparents_editor(self) -> None:
        """Change 1: toggling the JSON window reparents the editor and
        _current_json() still reads its text after reparent."""
        dlg = self._make_dialog()
        dlg._mode = "normal"
        dlg._update_mode_ui()
        dlg.json_edit.set_json({"id": "REParent", "name": "X", "units": []})
        editor = dlg.json_edit
        # Open the JSON independent window — editor should be reparented into it.
        dlg._json_window_btn.setChecked(True)
        self.assertIsNotNone(dlg._json_window)
        self.assertIs(editor.parent(), dlg._json_window)
        # _current_json reads the editor reference, which is parent-agnostic.
        self.assertEqual(dlg._current_json()["id"], "REParent")
        # Close the window — editor returns to the in-dialog host.
        dlg._json_window_btn.setChecked(False)
        self.assertIsNone(dlg._json_window)
        self.assertEqual(dlg._current_json()["id"], "REParent")

    def test_close_dialog_closes_json_window(self) -> None:
        """Change 1: closing the dialog tears down the JSON window."""
        dlg = self._make_dialog()
        dlg._mode = "normal"
        dlg._update_mode_ui()
        dlg._json_window_btn.setChecked(True)
        win = dlg._json_window
        self.assertIsNotNone(win)
        dlg.close()
        self.assertIsNone(dlg._json_window)


if __name__ == "__main__":
    unittest.main()
