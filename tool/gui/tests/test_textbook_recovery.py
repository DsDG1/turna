"""Tests for textbook-import extraction recovery (retry / vocab-only / skip)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig
from src.backend.knowledge_schema import coerce_knowledge_points
from src.dialogs.textbook_import_controller import TextbookImportController


def _sample_kp():
    return coerce_knowledge_points(
        {
            "words": [{"term": "merhaba", "translation": "hello"}],
            "expressions": [{"term": "Selam!", "translation": "Hi!"}],
            "grammarPoints": [{"title": "Greetings", "explanation": "hi"}],
        }
    )


def _vocab_only_kp():
    return coerce_knowledge_points(
        {"words": [{"term": "merhaba", "translation": "hello"}]}
    )


class _FakeSignal:
    def __init__(self) -> None:
        self._callbacks: list = []

    def connect(self, callback) -> None:
        self._callbacks.append(callback)

    def emit(self, *args, **kwargs) -> None:
        for cb in self._callbacks:
            cb(*args, **kwargs)


class _FakeWorker:
    def __init__(self, result=None, error=None) -> None:
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self._result = result
        self._error = error

    def start(self) -> None:
        if self._error is not None:
            self.error_occurred.emit(self._error)
        else:
            self.result_ready.emit(self._result)

    def cancel(self) -> None:
        pass


class TextbookRecoveryTest(unittest.TestCase):
    def _controller(self, worker_factory) -> TextbookImportController:
        return TextbookImportController(
            ai_config_fn=lambda: AiApiConfig(
                base_url="http://localhost", api_key="key", model="model"
            ),
            worker_factory=worker_factory,
        )

    def test_retry_chapter_after_failure(self) -> None:
        """A failed chapter can be retried and its knowledge restored."""
        fail_then_succeed = [_FakeWorker(error="boom"), _FakeWorker(result=_sample_kp())]
        factory_iter = iter(fail_then_succeed)

        def factory(_target, *_args, **_kwargs):
            return next(factory_iter)

        ctrl = self._controller(factory)
        ctrl._md = "## 1 Merhaba\nhello\n"
        ctrl._split_into_chapters()
        ctrl._chapters[0].keep = True
        ctrl.start_extraction()
        self.assertTrue(ctrl.chapters[0].error)

        ctrl.retry_chapter(0, mode="standard")
        self.assertFalse(ctrl.chapters[0].error)
        self.assertIsNotNone(ctrl.chapters[0].knowledge)
        self.assertEqual(len(ctrl.chapters[0].knowledge.words), 1)

    def test_vocab_only_retry_leaves_expressions_empty(self) -> None:
        worker = _FakeWorker(result=_vocab_only_kp())

        def factory(_target, *_args, **_kwargs):
            return worker

        ctrl = self._controller(factory)
        ctrl._md = "## 1 Merhaba\nhello\n"
        ctrl._split_into_chapters()
        ctrl._chapters[0].keep = True
        ctrl._chapters[0].error = "previous failure"
        ctrl.retry_chapter(0, mode="vocab_only")
        self.assertIsNotNone(ctrl.chapters[0].knowledge)
        self.assertEqual(len(ctrl.chapters[0].knowledge.words), 1)
        self.assertEqual(len(ctrl.chapters[0].knowledge.expressions), 0)

    def test_skip_chapter_marks_not_kept(self) -> None:
        ctrl = self._controller(lambda *_a, **_kw: _FakeWorker())
        ctrl._md = "## 1 Merhaba\nhello\n"
        ctrl._split_into_chapters()
        ctrl._chapters[0].keep = True
        ctrl.skip_chapter(0)
        self.assertFalse(ctrl.chapters[0].keep)


if __name__ == "__main__":
    unittest.main()
