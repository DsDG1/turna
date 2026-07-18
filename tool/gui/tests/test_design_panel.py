"""Tests for DesignPanel (connectplan P3-3).

The panel is driven by an injected ``DesignController`` with a fake worker
factory, so no network/threads are involved.
"""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from PySide6.QtWidgets import QApplication  # noqa: E402

from src.backend.ai_generator import (  # noqa: E402
    AiApiConfig,
    generate_from_chat,
    request_alignment_reply,
)
from src.backend.knowledge_schema import coerce_knowledge_points  # noqa: E402
from src.backend.markdown_chopper import split_chapters  # noqa: E402
from src.backend.textbook_project_store import TextbookProjectStore  # noqa: E402
from src.dialogs.ai.design_controller import DesignController  # noqa: E402
from src.dialogs.ai.design_panel import DesignPanel  # noqa: E402


class _App:
    _app = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list = []

    def connect(self, callback) -> None:
        self._callbacks.append(callback)

    def emit(self, *args) -> None:
        for cb in self._callbacks:
            cb(*args)


class _FakeWorker:
    def __init__(self, target, *args, result=None, **kwargs):
        self.target = target
        self.args = args
        self.result = result
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self.usage_ready = _FakeSignal()

    def start(self) -> None:
        self.result_ready.emit(self.result)

    def cancel(self) -> None:
        pass


def _section() -> dict:
    return {
        "id": "greetings",
        "name": "Greetings",
        "units": [{"id": "u", "name": "U1", "lessons": [
            {"id": "l", "name": "L1", "template": "intro",
             "content": {"subLessons": []}},
        ]}],
        "words": [{"id": "w-1", "term": "merhaba", "translation": "hello"}],
    }


def _factory(results: dict):
    def factory(target, *args, **kwargs):
        return _FakeWorker(target, *args, result=results.get(target), **kwargs)

    return factory


class DesignPanelTest(unittest.TestCase):
    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.project = self.store.create_project(name="Book", source_path=None)
        ch = split_chapters("## 1 Merhaba\nhello\n")
        kp = coerce_knowledge_points(
            {
                "words": [{"term": "merhaba", "translation": "hello"}],
                "expressions": [{"term": "Selam!", "translation": "Hi!"}],
            }
        )
        self.project.set_chapters([(ch[0], True, kp, "")])
        self.project.update_resource_pool()
        self.store.save_project(self.project)

        controller = DesignController(
            ai_config_fn=lambda: AiApiConfig(
                base_url="http://localhost", api_key="k", model="m"
            ),
            worker_factory=_factory(
                {
                    request_alignment_reply: "建议先做问候主题。",
                    generate_from_chat: _section(),
                }
            ),
        )
        self.panel = DesignPanel(None, None, controller=controller)
        self.panel.set_project(self.project, self.store)

    def tearDown(self) -> None:
        self.panel.deleteLater()
        self.tmp.cleanup()

    def test_pool_summary_and_grounding(self) -> None:
        self.assertIn("1 词", self.panel._pool_label.text())
        self.assertIn("1 表达", self.panel._pool_label.text())
        pool = self.panel._controller.resource_pool
        self.assertEqual({e["_kind"] for e in pool}, {"word", "expression"})

    def test_chat_then_generate_then_import(self) -> None:
        self.panel._chat_input.setText("做一课土耳其语问候")
        self.panel._on_send_chat()
        self.assertEqual(len(self.panel._controller.chat), 2)
        self.assertEqual(self.panel._chat_input.text(), "")

        self.panel._on_generate()
        draft = self.panel._controller.draft
        self.assertIsNotNone(draft)
        # Draft shown in the JSON editor; deterministic ids applied.
        self.assertEqual(draft["units"][0]["id"], "greetings-u1")
        self.assertTrue(self.panel._import_btn.isEnabled())

        captured: list = []
        self.panel.sections_ready.connect(lambda s, st: captured.append((s, st)))
        self.panel._on_import()
        self.assertEqual(len(captured), 1)
        sections, strategy = captured[0]
        self.assertEqual(sections[0]["id"], "greetings")
        self.assertEqual(strategy, "merge")

    def test_design_autosaved_to_project(self) -> None:
        self.panel._chat_input.setText("做问候课")
        self.panel._on_send_chat()
        loaded = self.store.load_project(self.project.project_id)
        self.assertEqual(len(loaded.design["chat_history"]), 2)
        self.assertEqual(
            loaded.design["chat_history"][0]["content"], "做问候课"
        )

    def test_project_design_restored_on_bind(self) -> None:
        # Simulate a previous session leaving design state behind.
        self.project.design = {
            "chat_history": [
                {"role": "user", "content": "旧对话", "timestamp": "10:00"}
            ],
            "params": {"topic": "旧主题", "level": "B1", "design_brief": "旧意图"},
            "draft_sections": [],
            "explanation": "旧解释",
        }
        self.store.save_project(self.project)
        controller = DesignController(
            ai_config_fn=lambda: AiApiConfig(
                base_url="http://localhost", api_key="k", model="m"
            ),
            worker_factory=_factory({}),
        )
        panel = DesignPanel(None, None, controller=controller)
        panel.set_project(self.project, self.store)
        self.assertEqual(panel._topic_edit.text(), "旧主题")
        self.assertEqual(panel._brief_edit.text(), "旧意图")
        self.assertEqual(panel._level_combo.currentText(), "B1")
        self.assertEqual(len(panel._controller.chat), 1)
        # Explanation restored into the collapsible group.
        self.assertFalse(panel._explain_group.isHidden())
        self.assertIn("旧解释", panel._explain_browser.toPlainText())
        panel.deleteLater()


class DesignPanelPhaseCTest(unittest.TestCase):
    """Phase C: attachments, restore-raw, template bar sync, explain view."""

    def setUp(self) -> None:
        _App.get()
        self.tmp = tempfile.TemporaryDirectory()
        self.store = TextbookProjectStore(base_dir=Path(self.tmp.name))
        self.project = self.store.create_project(name="Blank", source_path=None)
        controller = DesignController(
            ai_config_fn=lambda: AiApiConfig(
                base_url="http://localhost", api_key="k", model="m"
            ),
            worker_factory=_factory(
                {
                    request_alignment_reply: "好的。",
                    generate_from_chat: _section(),
                }
            ),
        )
        self.panel = DesignPanel(None, None, controller=controller)
        self.panel.set_project(self.project, self.store)

    def tearDown(self) -> None:
        self.panel.deleteLater()
        self.tmp.cleanup()

    def _make_txt(self) -> Path:
        path = Path(self.tmp.name) / "note.txt"
        path.write_text("merhaba = hello", encoding="utf-8")
        return path

    def test_attachment_add_and_cleanup(self) -> None:
        self.panel._add_attachment_paths([self._make_txt()])
        records = self.panel._attachment_bar.attachments()
        self.assertEqual(len(records), 1)
        temp_path = records[0].temp_path
        self.assertTrue(temp_path.exists())
        self.assertEqual(records[0].content["type"], "text")
        self.panel.cleanup_attachments()
        self.assertEqual(self.panel._attachment_bar.attachments(), [])
        self.assertFalse(temp_path.exists())

    def test_send_chat_clears_bar_and_deletes_temp(self) -> None:
        self.panel._add_attachment_paths([self._make_txt()])
        temp_path = self.panel._attachment_bar.attachments()[0].temp_path
        self.panel._chat_input.setText("参考附件做课")
        self.panel._on_send_chat()
        self.assertEqual(self.panel._attachment_bar.attachments(), [])
        self.assertFalse(temp_path.exists())
        # The message carried the attachment content piece.
        content = self.panel._controller.chat[0].content
        self.assertIsInstance(content, list)
        self.assertEqual(content[0]["text"], "参考附件做课")

    def test_restore_raw_output(self) -> None:
        self.panel._on_draft_chunk('{"id": "raw-partial"')
        self.panel._on_draft_ready(_section())
        self.assertTrue(self.panel._restore_raw_btn.isEnabled())
        self.panel._json_editor.setPlainText('{"id": "hand-edited"}')
        self.panel._on_restore_raw()
        self.assertEqual(
            self.panel._json_editor.toPlainText(), '{"id": "raw-partial"'
        )

    def test_template_bar_two_way_sync(self) -> None:
        self.panel._template_bar.select_template("listening")
        self.assertEqual(self.panel._template_combo.currentText(), "listening")
        self.panel._template_combo.setCurrentText("reading")
        self.assertEqual(self.panel._template_bar.selected_template(), "reading")

    def test_genre_toggle_flows_into_params(self) -> None:
        self.panel._template_bar.set_genre_enabled(True)
        self.panel._extra_edit.setText("[intro] 全部 intro")
        self.panel._sync_params()
        params = self.panel._controller.params
        self.assertTrue(params["use_genre_batch"])
        self.assertEqual(params["extra_instructions"], "[intro] 全部 intro")

    def test_explanation_rendered_and_streamed(self) -> None:
        self.assertTrue(self.panel._explain_group.isHidden())
        self.panel._on_explanation_chunk("这门课")
        self.panel._on_explanation_chunk("先学问候。")
        # Streaming renders are throttled; flush explicitly for the assertion.
        self.panel._flush_stream_views()
        self.assertFalse(self.panel._explain_group.isHidden())
        self.assertIn("先学问候", self.panel._explain_browser.toPlainText())

    def test_explanation_error_shows_inline(self) -> None:
        self.panel._on_explanation_error("网络错误")
        self.assertFalse(self.panel._explain_group.isHidden())
        self.assertIn("网络错误", self.panel._explain_browser.toPlainText())


if __name__ == "__main__":
    unittest.main()
