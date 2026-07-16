"""End-to-end test for the textbook import flow.

Uses a fake worker factory so no real LLM/network/thread is needed. The test
exercises the full pipeline through the view without entering ``app.exec()``.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

from PySide6.QtWidgets import QApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig
from src.backend.knowledge_schema import coerce_knowledge_points
from src.dialogs.textbook_import_dialog import TextbookImportDialog


def _sample_md() -> str:
    return (
        "## 1 Merhaba\n"
        "merhaba means hello\n\n"
        "## 2 Aile\n"
        "aile means family\n"
    )


def _sample_kp():
    return coerce_knowledge_points(
        {
            "words": [{"term": "merhaba", "translation": "hello"}],
            "expressions": [{"term": "Selam!", "translation": "Hi!"}],
            "grammarPoints": [{"title": "Greetings", "explanation": "hi"}],
        }
    )


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list[Any] = []

    def connect(self, callback: Any) -> None:
        self._callbacks.append(callback)

    def emit(self, *args: Any, **kwargs: Any) -> None:
        for cb in self._callbacks:
            cb(*args, **kwargs)


class _FakeWorker:
    def __init__(self, result: Any) -> None:
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self._result = result

    def start(self) -> None:
        self.result_ready.emit(self._result)

    def cancel(self) -> None:
        pass


def _fake_worker_factory(result: Any) -> Any:
    def factory(_target, *_args, **_kwargs):
        return _FakeWorker(result)

    return factory


class _TestApp:
    _app: QApplication | None = None

    @classmethod
    def get(cls) -> QApplication:
        if cls._app is None:
            cls._app = QApplication.instance() or QApplication([])
        return cls._app


class TextbookImportE2ETest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        self.dlg = TextbookImportDialog(None, None)
        # Inject fake worker and complete AI config.
        self.dlg._controller._worker_factory = _fake_worker_factory(_sample_kp())
        self.dlg._controller._ai_config_fn = lambda: AiApiConfig(
            base_url="http://localhost", api_key="key", model="model"
        )

    def test_full_flow_md_to_sections(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(_sample_md())
            path = Path(f.name)
        try:
            # ① pick / ② parse
            self.dlg._load_file(path)
            self.assertEqual(len(self.dlg._controller.chapters), 2)
            self.assertEqual(self.dlg._stack.currentIndex(), 2)  # chapters step

            # ③ chapters already all checked; ④ extract
            self.dlg._start_extraction()
            self.assertEqual(self.dlg._stack.currentIndex(), 4)  # review step
            self.assertTrue(all(cr.knowledge is not None for cr in self.dlg._controller.chapters))

            # ⑤ review / ⑥ import
            self.assertIsNotNone(self.dlg._controller.quality_report)
            self.assertEqual(self.dlg._review_table.row_count(), 6)
            self.assertEqual(self.dlg._chapter_quality_list.count(), 2)
            captured: list = []
            self.dlg.sections_ready.connect(lambda secs, _strat: captured.extend(secs))
            self.dlg._on_import()
            self.assertEqual(len(captured), 2)
            self.assertEqual(captured[0]["id"], "ch-1-merhaba-1")
            self.assertEqual(captured[1]["id"], "ch-2-aile-2")
        finally:
            path.unlink()


if __name__ == "__main__":
    unittest.main()
