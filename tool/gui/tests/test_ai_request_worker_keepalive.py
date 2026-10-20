"""Keepalive registry hygiene for background workers.

``src/application/ai_request_worker.py`` keeps a strong reference to every
started worker so a closed owner cannot destroy a running QThread (that
aborts the process). The entry must be released when the worker ends.

Two call sites used to disconnect *all* of a worker's signals when
superseding it — including ``finished``, the signal the release hangs on.
Every such worker then stayed in the registry forever: unbounded growth,
and the thread was never joined.
"""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app


class LiveWorkersRegistryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        qt_app()

    def test_finished_worker_is_released(self) -> None:
        from src.application.ai_request_worker import AiRequestWorker, _LIVE_WORKERS

        before = len(_LIVE_WORKERS)
        worker = AiRequestWorker(lambda: 42)
        worker.start()
        worker.wait(5000)
        # The release runs on the ``finished`` signal, delivered on the GUI
        # thread. Process the event loop so the queued slot runs.
        app = qt_app()
        for _ in range(20):
            app.processEvents()
            if len(_LIVE_WORKERS) <= before:
                break
        self.assertLessEqual(
            len(_LIVE_WORKERS),
            before,
            "a finished worker stayed in the keepalive registry",
        )

    def test_sweep_drops_finished_workers(self) -> None:
        from src.application.ai_request_worker import AiRequestWorker, _LIVE_WORKERS

        worker = AiRequestWorker(lambda: 1)
        worker.start()
        worker.wait(5000)
        _LIVE_WORKERS.add(worker)
        AiRequestWorker._sweep_finished_workers()
        self.assertNotIn(
            worker,
            _LIVE_WORKERS,
            "the sweep must drop workers whose thread already ended",
        )

    def test_hub_disconnect_keeps_finished_connected(self) -> None:
        """The disconnect lists must not drop ``finished``.

        ``finished`` carries the keepalive release; disconnecting it strands
        the worker in the registry.
        """
        import inspect

        from src.dialogs.ai.generator_worker_hub import GeneratorWorkerHub
        from src.dialogs.git_library.git_worker_hub import GitWorkerHub

        for cls, method in (
            (GeneratorWorkerHub, "disconnect_worker_signals"),
            (GitWorkerHub, "run_async"),
        ):
            source = inspect.getsource(getattr(cls, method))
            with self.subTest(cls=cls.__name__):
                self.assertNotIn(
                    '"finished"',
                    source,
                    f"{cls.__name__}.{method} must not disconnect 'finished'",
                )


if __name__ == "__main__":
    unittest.main()
