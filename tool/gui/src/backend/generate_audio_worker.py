"""Background worker for TTS listening-audio generation.

Runs ``generate_audio_client.run_generate`` (a blocking subprocess) on a
QThread and forwards per-file progress + a final summary to the UI thread via
signals. Mirrors ``AiRequestWorker``'s ``_LIVE_WORKERS`` keepalive registry and
cooperative ``cancel()`` pattern.
"""
from __future__ import annotations

from PySide6.QtCore import QThread, Signal

from src.backend import generate_audio_client
from src.backend.generate_audio_client import TtsOptions
import logging
logger = logging.getLogger(__name__)


class GenerateAudioWorker(QThread):
    """Synthesize listening audio in a background thread."""

    # (files_done, total) — files_done increments on each "Generated" line.
    progress = Signal(int, int)
    # (generated, skipped, total)
    finished_ok = Signal(int, int, int)
    failed = Signal(str)

    def __init__(
        self,
        course_dir,
        sounds_dir,
        opts: TtsOptions,
        api_key: str,
        parent=None,
    ) -> None:
        super().__init__(parent)
        self._course_dir = course_dir
        self._sounds_dir = sounds_dir
        self._opts = opts
        self._api_key = api_key
        self._cancelled = False

    def cancel(self) -> None:
        """Request cooperative cancellation of the in-flight run."""
        self._cancelled = True

    def start(self, *args, **kwargs) -> None:
        # Keep a strong reference until the thread finishes so a closed owner
        # cannot destroy a still-running QThread ("QThread: Destroyed while
        # thread is still running").
        _LIVE_WORKERS.add(self)
        self.finished.connect(self._release_keepalive)
        super().start(*args, **kwargs)

    def _release_keepalive(self) -> None:
        _LIVE_WORKERS.discard(self)

    def run(self) -> None:
        done = 0
        total = 0

        def _on_line(line: str) -> None:
            nonlocal done, total
            stripped = line.strip()
            if stripped.startswith("Generated "):
                done += 1
                self.progress.emit(done, total or -1)
            elif stripped.startswith("{"):
                import json

                try:
                    counts = json.loads(stripped)
                    total = int(counts.get("total", total))
                    self.progress.emit(done, total)
                except ValueError:
                    logger.debug("backend/generate_audio_worker.py:_on_line best-effort step failed", exc_info=True)

        try:
            result = generate_audio_client.run_generate(
                self._course_dir,
                self._sounds_dir,
                self._opts,
                self._api_key,
                on_line=_on_line,
                cancel_check=lambda: self._cancelled,
            )
        except Exception as exc:  # noqa: BLE001
            if not self._cancelled:
                self.failed.emit(str(exc))
            return
        if self._cancelled:
            return
        self.finished_ok.emit(result.generated, result.skipped, result.total)


# Strong references to running workers (see AiRequestWorker._LIVE_WORKERS).
_LIVE_WORKERS: set[GenerateAudioWorker] = set()
