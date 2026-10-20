"""Background extraction of chat/AI attachments.

Adding an attachment to the AI panels used to run entirely on the GUI
thread: read the whole file, copy it to a temp path, extract its text (PDF
text extraction reads every page), and base64-encode images. For a
text-native PDF that is hundreds of pages — the window froze for seconds
with no feedback, and the user could not tell whether the app had hung.

This module runs that work on a worker thread and reports back through Qt
signals, so the UI stays responsive. The extraction itself stays in
``src.backend.attachment_extractor`` (pure, no Qt); this is the
orchestration the UI layer needs.

Used by:
- ``src/dialogs/ai/design_panel.py``
- ``src/dialogs/ai/generator_chat_coordinator.py``
"""
from __future__ import annotations

import logging
import shutil
import tempfile
import uuid
from pathlib import Path
from typing import Any

from PySide6.QtCore import QObject, Signal

from src.application.ai_request_worker import AiRequestWorker, AttachmentRecord
from src.backend.attachment_extractor import extract_attachment

logger = logging.getLogger(__name__)

__all__ = [
    "AttachmentExtractor",
    "AttachmentRecord",
    "extract_attachment",
]


def _temp_path_for(path: Path, prefix: str) -> Path:
    """Allocate a unique temp path that keeps the original file name."""
    return Path(tempfile.gettempdir()) / f"{prefix}{uuid.uuid4().hex[:8]}_{path.name}"


class AttachmentExtractor(QObject):
    """Extract attachments off the GUI thread, one file at a time.

    Signals:
        ``extracted(record)`` — one attachment is ready to show.
        ``failed(path, message)`` — one attachment could not be read.
        ``finished()`` — the whole batch is done.

    The worker is kept alive by this object (``_worker``) so it is never
    garbage collected mid-run.
    """

    extracted = Signal(object)
    failed = Signal(str, str, str)
    finished = Signal()

    def __init__(
        self,
        parent: QObject | None = None,
        *,
        worker_factory: Any = None,
    ) -> None:
        super().__init__(parent)
        self._worker: AiRequestWorker | None = None
        self._queue: list[Path] = []
        self._temp_paths: list[Path] = []
        self._prefix = "turna_attach"
        # Test/offscreen hook: inject a factory that runs the target inline
        # (no real QThread). Production uses the real worker. Mirrors the
        # ``_goal_fill_worker_factory`` seam in experience_skills_mixin.
        self._worker_factory = worker_factory or (lambda target, *a, **k: AiRequestWorker(target, *a, **k))

    def extract_paths(self, paths: list[Path], *, prefix: str = "turna_attach") -> None:
        """Start extracting *paths* in the background.

        Nothing happens on the GUI thread except queueing the paths.
        """
        self._queue = [Path(p) for p in paths]
        self._temp_paths = []
        self._prefix = prefix
        if not self._queue:
            self.finished.emit()
            return
        self._start_next()

    def _start_next(self) -> None:
        if not self._queue:
            self.finished.emit()
            return
        path = self._queue.pop(0)
        worker = self._worker_factory(self._extract_one, path)
        worker.result_ready.connect(self._on_extracted)
        worker.error_occurred.connect(self._on_error)
        self._worker = worker
        worker.start()

    def _extract_one(self, path: Path) -> tuple[tuple[Path, str] | None, Any]:
        """Worker side: copy to temp and extract. Never raises.

        Returns ``((temp_path, original_name), content)`` on success. On
        failure returns ``((temp_path, original_name), error_message)`` when
        the copy succeeded (the caller may still want the temp path — the
        OCR fallback needs it), or ``(None, error_message)`` when the copy
        itself failed.
        """
        temp_path = _temp_path_for(path, self._prefix)
        try:
            shutil.copy(str(path), str(temp_path))
        except OSError as exc:
            return None, f"无法复制文件 {path.name}: {exc}"
        self._temp_paths.append(temp_path)
        result = extract_attachment(temp_path)
        if not result.ok or result.content is None:
            return (temp_path, path.name), f"{path.name}: {result.error or '未知错误'}"
        return (temp_path, path.name), result.content

    def _on_extracted(self, payload: object) -> None:
        self._worker = None
        pair, content = payload  # type: ignore[misc]
        if pair is None:
            self.failed.emit("", "", str(content))
            self._start_next()
            return
        temp_path, original_name = pair
        if isinstance(content, str):
            # Extraction failed, but the temp copy exists — the OCR fallback
            # needs it.
            self.failed.emit(str(temp_path), original_name, content)
            self._start_next()
            return
        self.extracted.emit(
            AttachmentRecord(
                temp_path=Path(temp_path),
                original_name=original_name,
                content=content or {},
            )
        )
        self._start_next()

    def _on_error(self, message: str) -> None:
        self._worker = None
        self.failed.emit("", "", message)
        self._start_next()

    def cancel(self) -> None:
        """Stop the current extraction and drop the queue."""
        self._queue = []
        worker = self._worker
        self._worker = None
        if worker is not None:
            try:
                worker.cancel()
            except Exception:
                logger.debug(
                    "application/attachment_service.py:cancel best-effort step failed",
                    exc_info=True,
                )
