"""Unit tests for GeneratorWorkerHub."""
from __future__ import annotations

import unittest
from unittest.mock import MagicMock

from tests._qtapp import qt_app

from src.backend.ai_generator import AiApiConfig, AiCourseSpec
from src.dialogs.ai.generator_worker_hub import GeneratorWorkerHub
from src.dialogs.ai.worker import AiRequestWorker


class TestGeneratorWorkerHub(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = qt_app()

    def setUp(self):
        self.hub = GeneratorWorkerHub()

    def test_duration_since_request_start(self):
        self.assertIsNone(self.hub.request_start)
        self.assertEqual(self.hub.duration_since_request_start(), 0.0)

        self.hub.mark_request_started()
        self.assertIsNotNone(self.hub.request_start)
        d = self.hub.duration_since_request_start()
        self.assertGreaterEqual(d, 0.0)

    def test_streaming_buffer_and_finish(self):
        self.hub.begin_stream("explain")
        self.assertEqual(self.hub.stream_target, "explain")
        self.assertEqual(self.hub.stream_buffer, "")

        rendered = []
        self.hub.chunk_rendered.connect(lambda text, final: rendered.append((text, final)))

        self.hub.on_worker_chunk("Hello ")
        self.hub.on_worker_chunk("World!")
        self.assertEqual(self.hub.stream_buffer, "Hello World!")

        self.hub.finish_stream()
        self.assertEqual(self.hub.stream_buffer, "")
        self.assertIsNone(self.hub.stream_target)
        self.assertTrue(any(item[0] == "Hello World!" and item[1] is True for item in rendered))

    def test_on_worker_usage(self):
        updates = []
        self.hub.usage_updated.connect(lambda line, data: updates.append((line, data)))

        usage = {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30}
        line = self.hub.on_worker_usage(usage, model="test-model")
        self.assertIn("30", line)
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0][1]["total_tokens"], 30)

    def test_register_and_forget_worker(self):
        worker = AiRequestWorker(lambda: "ok")
        self.hub.register_worker(worker)
        self.assertIs(self.hub.current_worker, worker)

        # Disconnect worker signals
        self.hub.disconnect_worker_signals(worker)

    def test_make_edit_worker(self):
        spec = AiCourseSpec(language="en", source_language="zh", topic="travel")
        config = AiApiConfig(base_url="https://example.com", api_key="sk", model="gpt")
        existing = {"id": "sec-1", "name": "Sec 1", "units": [{"id": "u-1", "lessons": [{"id": "l-1"}]}]}

        # Section scope
        w1 = self.hub.make_edit_worker(config, spec, {"scope": "section", "existing_section": existing})
        self.assertIsInstance(w1, AiRequestWorker)

        # Unit scope
        w2 = self.hub.make_edit_worker(config, spec, {"scope": "unit", "scope_id": "u-1", "existing_section": existing})
        self.assertIsInstance(w2, AiRequestWorker)

        # Lesson scope
        w3 = self.hub.make_edit_worker(config, spec, {"scope": "lesson", "scope_id": "l-1", "existing_section": existing})
        self.assertIsInstance(w3, AiRequestWorker)


if __name__ == "__main__":
    unittest.main()
