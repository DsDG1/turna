"""Tests for the GenerateAudioWorker QThread (injectable fake run_generate)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from PySide6.QtCore import QCoreApplication

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.audio_worker import GenerateAudioWorker  # noqa: E402
from src.backend.generate_audio_client import GenerateResult, TtsOptions  # noqa: E402


class _WorkerRunner:
    """Run a worker synchronously, capturing emitted signals."""

    def __init__(self, worker: GenerateAudioWorker) -> None:
        self.progress = []
        self.ok = None
        self.failed = None
        worker.progress.connect(self._on_progress)
        worker.finished_ok.connect(self._on_ok)
        worker.failed.connect(self._on_failed)

    def _on_progress(self, done: int, total: int) -> None:
        self.progress.append((done, total))

    def _on_ok(self, generated: int, skipped: int, total: int) -> None:
        self.ok = (generated, skipped, total)

    def _on_failed(self, msg: str) -> None:
        self.failed = msg


class GenerateAudioWorkerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        # A QCoreApplication is required to emit/process queued signals.
        cls._app = QCoreApplication.instance()
        if cls._app is None:
            cls._app = QCoreApplication([])

    def test_emits_progress_and_finished_ok(self) -> None:
        def fake_run(course_dir, sounds_dir, opts, api_key, on_line=None, cancel_check=None):
            on_line("Generated a.mp3")
            on_line("Generated b.mp3")
            return GenerateResult(generated=2, skipped=1, total=3)

        with patch(
            "src.backend.generate_audio_client.run_generate",
            side_effect=fake_run,
        ):
            worker = GenerateAudioWorker(Path("/c"), Path("/s"), TtsOptions(), "k")
            runner = _WorkerRunner(worker)
            worker.start()
            worker.wait(5000)
            # Flush queued cross-thread signals into the runner's slots.
            QCoreApplication.processEvents()

        self.assertIsNone(runner.failed)
        self.assertEqual(runner.ok, (2, 1, 3))
        # one progress tick per "Generated" line
        self.assertEqual(len(runner.progress), 2)

    def test_emits_failed_on_exception(self) -> None:
        def fake_run(course_dir, sounds_dir, opts, api_key, on_line=None, cancel_check=None):
            raise RuntimeError("boom")

        with patch(
            "src.backend.generate_audio_client.run_generate",
            side_effect=fake_run,
        ):
            worker = GenerateAudioWorker(Path("/c"), Path("/s"), TtsOptions(), "k")
            runner = _WorkerRunner(worker)
            worker.start()
            worker.wait(5000)
            QCoreApplication.processEvents()

        self.assertIsNone(runner.ok)
        self.assertIsNotNone(runner.failed)
        self.assertIn("boom", runner.failed)

    def test_no_finished_signal_when_cancelled(self) -> None:
        def fake_run(course_dir, sounds_dir, opts, api_key, on_line=None, cancel_check=None):
            on_line("Generated a.mp3")
            return GenerateResult(generated=1, skipped=0, total=1)

        with patch(
            "src.backend.generate_audio_client.run_generate",
            side_effect=fake_run,
        ):
            worker = GenerateAudioWorker(Path("/c"), Path("/s"), TtsOptions(), "k")
            runner = _WorkerRunner(worker)
            worker.start()
            worker.cancel()  # cooperative cancel before it can finish
            worker.wait(5000)

        self.assertIsNone(runner.ok)
        self.assertIsNone(runner.failed)


if __name__ == "__main__":
    unittest.main()
