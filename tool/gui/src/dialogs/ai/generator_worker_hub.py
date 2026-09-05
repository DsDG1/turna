"""Worker lifecycle, streaming buffer, usage and error tracking for AI dialog.

Decoupled from AiGeneratorDialog.
"""
from __future__ import annotations

import logging
import time
from typing import Any

from PySide6.QtCore import QObject, QTimer, Signal

from src.backend.ai_generator import (
    AiApiConfig,
    AiCourseSpec,
    generate_edit,
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
)
from src.backend.ai_usage import format_usage_line
from src.dialogs.ai.worker import AiRequestWorker
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)

_STREAM_TEXT_LIVE_LIMIT = 4000
_STREAM_FLUSH_INTERVAL_MS = 120


def record_cache_stats() -> None:
    """Record AI cache stats to telemetry after each request."""
    try:
        from src.backend.ai_cache import cache_stats

        stats = cache_stats()
        telemetry.record_event("ai.cache.stats", payload=stats)
    except Exception:
        logger.debug("dialogs/ai/generator_worker_hub.py:cache_stats best-effort failed", exc_info=True)


class GeneratorWorkerHub(QObject):
    """Coordinates async AI request workers, streaming chunks, and token usage."""

    chunk_rendered = Signal(str, bool)  # text, is_final
    usage_updated = Signal(str, dict)   # formatted_line, usage_dict
    error_occurred = Signal(str, bool)  # error_message, is_cancelled
    stage_changed = Signal(str)

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._current_worker: AiRequestWorker | None = None
        self._request_start: float | None = None

        self._stream_buffer: str = ""
        self._stream_dirty: bool = False
        self._stream_target: str | None = None
        self._stream_flush_timer = QTimer(self)
        self._stream_flush_timer.setInterval(_STREAM_FLUSH_INTERVAL_MS)
        self._stream_flush_timer.timeout.connect(self._flush_stream_view)

    @property
    def current_worker(self) -> AiRequestWorker | None:
        return self._current_worker

    @property
    def request_start(self) -> float | None:
        return self._request_start

    @request_start.setter
    def request_start(self, value: float | None) -> None:
        self._request_start = value

    @property
    def stream_buffer(self) -> str:
        return self._stream_buffer

    @property
    def stream_target(self) -> str | None:
        return self._stream_target

    def mark_request_started(self) -> None:
        self._request_start = time.perf_counter()

    def duration_since_request_start(self) -> float:
        start = self._request_start
        if start is None:
            return 0.0
        return (time.perf_counter() - start) * 1000

    def begin_stream(self, target: str) -> None:
        self._stream_flush_timer.stop()
        self._stream_dirty = False
        self._stream_buffer = ""
        self._stream_target = target

    def on_worker_chunk(self, fragment: str) -> None:
        if not fragment:
            return
        self._stream_buffer += fragment
        self._stream_dirty = True
        if not self._stream_flush_timer.isActive():
            self._stream_flush_timer.start()

    def _flush_stream_view(self, final: bool = False) -> None:
        if not self._stream_dirty and not final:
            return
        self._stream_dirty = False
        self.chunk_rendered.emit(self._stream_buffer, final)

    def finish_stream(self) -> None:
        if self._stream_dirty:
            self._flush_stream_view(final=True)
        self._stream_flush_timer.stop()
        self._stream_buffer = ""
        self._stream_target = None

    def on_worker_usage(self, usage: object, model: str = "") -> str:
        usage_dict = dict(usage) if isinstance(usage, dict) else {}
        line = format_usage_line(usage_dict, model)
        try:
            telemetry.record_event(
                "ai.usage",
                payload={
                    "model": model,
                    "prompt_tokens": usage_dict.get("prompt_tokens", 0),
                    "completion_tokens": usage_dict.get("completion_tokens", 0),
                    "total_tokens": usage_dict.get("total_tokens", 0),
                },
            )
        except Exception:
            logger.debug("dialogs/ai/generator_worker_hub.py:on_worker_usage telemetry failed", exc_info=True)
        self.usage_updated.emit(line, usage_dict)
        return line

    def cancel_current_worker(self) -> None:
        worker = self._current_worker
        if worker is not None and worker.isRunning():
            worker.cancel()
            self.stage_changed.emit("正在取消…")

    def disconnect_worker_signals(self, worker: AiRequestWorker | None) -> None:
        if worker is None:
            return
        import warnings
        for sig_name in ("result_ready", "error_occurred", "completed", "chunk_ready", "usage_ready", "finished"):
            try:
                sig = getattr(worker, sig_name, None)
                if sig is not None:
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore")
                        sig.disconnect()
            except (TypeError, RuntimeError):
                logger.debug("dialogs/ai/generator_worker_hub.py:disconnect_worker_signals safe skip", exc_info=True)

    def register_worker(self, worker: AiRequestWorker) -> None:
        self._current_worker = worker
        worker.finished.connect(self._forget_worker)

    def _forget_worker(self) -> None:
        worker = self.sender()
        if worker is self._current_worker:
            self._current_worker = None

    def handle_worker_error(
        self,
        message: str,
        mode: str,
        dialog: Any,
    ) -> bool:
        duration_ms = self.duration_since_request_start()
        cancelled = "取消" in message or "cancelled" in message.lower()
        telemetry.record_duration(
            "ai.generate",
            duration_ms,
            payload={
                "mode": mode,
                "success": False,
                "cancelled": cancelled,
                "error": message if not cancelled else "cancelled",
            },
        )
        record_cache_stats()
        self.error_occurred.emit(message, cancelled)
        if not cancelled:
            self.offer_error_analysis(dialog, message, context={"action": "ai.generate", "mode": mode})
        return cancelled

    @staticmethod
    def offer_error_analysis(parent: Any, message: str, context: dict[str, Any]) -> None:
        from src.dialogs.ai_error_analyzer import offer_ai_analysis
        if offer_ai_analysis(parent, "请求失败", message):
            import traceback
            from src.dialogs.ai_error_analyzer import AiErrorAnalyzerDialog
            AiErrorAnalyzerDialog(
                traceback.format_exc(),
                context=context,
                parent=parent,
            ).exec()

    @staticmethod
    def make_edit_worker(
        config: AiApiConfig | None,
        spec: AiCourseSpec,
        edit_mode: dict[str, Any],
        instruction: str | None = None,
        **kwargs: Any,
    ) -> AiRequestWorker:
        scope = edit_mode.get("scope", "section")
        scope_id = edit_mode.get("scope_id", "")
        existing = edit_mode["existing_section"]

        if scope == "lesson" and scope_id:
            return AiRequestWorker(
                regenerate_lesson_in_section,
                config,
                spec,
                existing,
                scope_id,
                instruction=instruction,
                **kwargs,
            )
        if scope == "unit" and scope_id:
            return AiRequestWorker(
                regenerate_unit_in_section,
                config,
                spec,
                existing,
                scope_id,
                instruction=instruction,
                **kwargs,
            )

        if instruction:
            spec.extra_instructions = (spec.extra_instructions or "") + f"\n\n编辑指令：\n{instruction}"

        return AiRequestWorker(
            generate_edit,
            config,
            spec,
            existing,
            scope,
            scope_id,
            **kwargs,
        )
