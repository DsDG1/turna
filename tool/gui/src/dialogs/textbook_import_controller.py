"""Pure-Python controller for the textbook-import workflow.

The controller owns the import state and orchestrates the pipeline:
  pick file → parse markdown → split chapters → extract knowledge →
  review → build sections.

It is intentionally Qt-free: it returns ``ImportStepResult`` objects and uses
plain callbacks to notify the view of asynchronous progress. This makes the
majority of the import logic unit-testable without a QApplication event loop.
"""
from __future__ import annotations

import logging
logger = logging.getLogger(__name__)


import functools
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal

# Ensure ``tool/gui`` is on sys.path when this module is imported directly.
_GUI = Path(__file__).resolve().parents[2]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.attachment_extractor import extract_attachment
from src.backend.extraction_quality import (
    ExtractionQualityReport,
    compute_quality_report,
)
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import SectionImportPreview, plan_bulk_import
from src.backend.knowledge_extractor import (
    extract_knowledge_points_windowed,
    reextract_knowledge_targeted,
)
from src.backend.knowledge_merger import MergeReport, apply as merge_knowledge_points
from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter, split_chapters
from src.backend.textbook_presets import TextbookPreset, preset_for
from src.backend.textbook_project import TextbookProject
from src.backend.textbook_project_store import _new_project_id
from src.backend.textbook_to_course import build_section_from_chapter
from src.infrastructure.telemetry import telemetry

#: Usage dict shape: {"prompt_tokens", "completion_tokens", "total_tokens"}.
UsageDict = dict[str, int]
_ZERO_USAGE: UsageDict = {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}


@dataclass
class _ChapterResult:
    """Internal state for one chapter across the whole workflow."""

    chapter: Chapter
    keep: bool = True
    knowledge: KnowledgePoints | None = None
    error: str = ""


class TextbookImportController:
    """Controller for the textbook import pipeline.

    Args:
        ai_config_fn: Callable returning the current ``AiApiConfig``.
        worker_factory: Callable ``(target, *args, **kwargs) -> worker`` used to
            run extraction in the background. Defaults to ``AiRequestWorker``.
            Tests inject a fake factory that returns a mock worker.
        on_step_changed: ``callback(step_index, result)`` fired whenever the
            active step changes or a step produces a result.
        on_extract_log: ``callback(message)`` fired for extraction progress text.
        on_sections_ready: ``callback(sections)`` fired when the user confirms
            import and sections have been built.
        language: Target language being taught (e.g. ``"Turkish"``).
        source_language: Source/explanation language (e.g. ``"Chinese"``).
    """

    def __init__(
        self,
        *,
        ai_config_fn: Callable[[], Any],
        worker_factory: Callable[..., Any] | None = None,
        on_step_changed: Callable[[int, ImportStepResult | None], None] | None = None,
        on_extract_log: Callable[[str], None] | None = None,
        on_extract_progress: Callable[[dict[str, Any]], None] | None = None,
        on_sections_ready: Callable[[list[dict[str, Any]]], None] | None = None,
        on_autosave: Callable[[TextbookProject], None] | None = None,
        on_quality_report_changed: Callable[[ExtractionQualityReport], None] | None = None,
        on_usage_update: Callable[[int, UsageDict, UsageDict], None] | None = None,
        language: str = "Turkish",
        source_language: str = "Chinese",
        project_name: str = "",
        preset: TextbookPreset | None = None,
        max_concurrent: int = 1,
        auto_cascade: bool = True,
    ) -> None:
        self._ai_config_fn = ai_config_fn
        self._worker_factory = worker_factory or self._default_worker_factory
        self._on_step_changed = on_step_changed or (lambda _step, _result: None)
        self._on_extract_log = on_extract_log or (lambda _msg: None)
        self._on_extract_progress = on_extract_progress or (lambda _p: None)
        self._on_sections_ready = on_sections_ready or (lambda _sections: None)
        self._on_autosave = on_autosave
        self._on_quality_report_changed = on_quality_report_changed or (lambda _r: None)
        self._on_usage_update = on_usage_update or (lambda _idx, _chap, _proj: None)
        self._language = language
        self._source_language = source_language
        self._project_name = project_name
        self._preset = preset or preset_for("general")
        self._max_concurrent = max(1, int(max_concurrent))
        # P4-2: when a ``standard`` extraction fails, automatically retry the
        # chapter once with ``vocab_only`` (disable via the
        # ``textbook/auto_cascade`` settings key).
        self._auto_cascade = bool(auto_cascade)
        # Strategies already tried per chapter (anti-loop guard for cascade).
        self._attempted_strategies: dict[int, set[str]] = {}

        self._source_path: Path | None = None
        self._md: str = ""
        self._chapters: list[_ChapterResult] = []
        self._extract_queue: list[int] = []
        self._active_workers: dict[int, Any] = {}
        self._cancelled = False
        self._autosave_enabled = True
        # Guard for asynchronous file loading: incremented on every new load so
        # late results from a superseded request are discarded.
        self._load_id: int = 0
        self._load_worker: Any | None = None
        # Autosave throttle: extraction fires _autosave() per completed
        # chapter; writes are coalesced to at most one per interval while
        # discrete transitions force an immediate save (force=True).
        self._autosave_dirty = False
        self._last_autosave_at = 0.0
        self._extract_start_time: float | None = None
        self._extract_total: int = 0
        self._started_count: int = 0
        self._completed_count: int = 0
        self._usage_by_chapter: dict[int, UsageDict] = {}
        self._project_usage: UsageDict = dict(_ZERO_USAGE)
        self._quality_report: ExtractionQualityReport | None = None

    # ------------------------------------------------------------------ state
    @property
    def source_path(self) -> Path | None:
        return self._source_path

    @property
    def markdown(self) -> str:
        return self._md

    @property
    def chapters(self) -> list[_ChapterResult]:
        return self._chapters

    @property
    def is_busy(self) -> bool:
        return bool(self._active_workers)

    @property
    def autosave_enabled(self) -> bool:
        return self._autosave_enabled

    @autosave_enabled.setter
    def autosave_enabled(self, value: bool) -> None:
        self._autosave_enabled = value

    @property
    def auto_cascade(self) -> bool:
        return self._auto_cascade

    @auto_cascade.setter
    def auto_cascade(self, value: bool) -> None:
        self._auto_cascade = bool(value)

    @property
    def preset(self) -> TextbookPreset:
        return self._preset

    @preset.setter
    def preset(self, value: TextbookPreset | None) -> None:
        self._preset = value or preset_for("general")

    @property
    def max_concurrent(self) -> int:
        return self._max_concurrent

    @max_concurrent.setter
    def max_concurrent(self, value: int) -> None:
        self._max_concurrent = max(1, int(value))

    @property
    def project_usage(self) -> UsageDict:
        return dict(self._project_usage)

    def usage_for_chapter(self, index: int) -> UsageDict:
        """Return the accumulated token usage for one chapter (zeros if none)."""
        return dict(self._usage_by_chapter.get(index, _ZERO_USAGE))

    @property
    def quality_report(self) -> ExtractionQualityReport | None:
        return self._quality_report

    def compute_quality_report(self, adapter: Any | None = None) -> ExtractionQualityReport:
        """Compute and cache a quality report from the current chapter results."""
        chapters = [
            (cr.chapter, cr.knowledge if cr.knowledge is not None else None)
            for cr in self._chapters
        ]
        self._quality_report = compute_quality_report(
            chapters,
            adapter=adapter,
            language=self._language,
            source_language=self._source_language,
        )
        telemetry.record_event(
            "textbook.quality.computed",
            payload=self._quality_report.overall,
        )
        self._on_quality_report_changed(self._quality_report)
        return self._quality_report

    @property
    def current_step(self) -> int:
        """Best-guess current step based on controller state."""
        if self._source_path is None:
            return self.STEP_PICK
        if not self._chapters:
            return self.STEP_PARSE
        if any(cr.knowledge is not None or cr.error for cr in self._chapters):
            # Extraction has started or finished.
            if self._active_workers or self._extract_queue:
                return self.STEP_EXTRACT
            return self.STEP_REVIEW
        return self.STEP_CHAPTERS

    # ------------------------------------------------------------------ steps
    STEP_PICK, STEP_PARSE, STEP_CHAPTERS, STEP_EXTRACT, STEP_REVIEW, STEP_IMPORT = range(6)

    def _emit_step(self, step: int, result: ImportStepResult | None = None) -> None:
        self._on_step_changed(step, result)

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def _read_source_text(path: Path) -> str:
        """Read text from a .md/.txt file or extract it from a text PDF.

        Raises ``OSError`` for filesystem errors and ``RuntimeError`` for
        parse/extraction errors so both sync and async callers can share the
        same message conversion.
        """
        suffix = path.suffix.lower()
        if suffix in (".md", ".txt"):
            return path.read_text(encoding="utf-8")

        result = extract_attachment(path)
        if not result.ok:
            raise RuntimeError(
                f"{result.error}\n建议改用 .md/.txt，或使用文本原生 PDF（扫描件暂不支持）。"
            )
        text = result.content.get("text", "") if result.content else ""
        if not text.strip():
            raise RuntimeError("PDF 未提取到文本（可能是扫描件）。")
        return text

    # ------------------------------------------------------------------ ① pick / ② parse
    def load_file(self, path: Path) -> ImportStepResult:
        """Load and parse the source file synchronously.

        Returns a ``parse`` step result. On success the controller moves to the
        ``chapters`` step internally; the view should observe ``on_step_changed``.
        """
        self._cancelled = False
        if not path.exists():
            return ImportStepResult.error("pick", f"文件不存在：{path}")
        suffix = path.suffix.lower()
        if suffix not in (".md", ".txt", ".pdf"):
            return ImportStepResult.error(
                "pick",
                "不支持的文件类型，请选择 .md / .txt / .pdf。",
                recoverable=True,
                recovery_options=["重新选择"],
            )

        self._source_path = path

        try:
            self._md = self._read_source_text(path)
        except OSError as exc:
            return ImportStepResult.error("parse", f"读取文件失败：{exc}")
        except RuntimeError as exc:
            return ImportStepResult.error(
                "parse",
                str(exc),
                recoverable=True,
                recovery_options=["重新选择"],
            )

        self._split_into_chapters()
        result = ImportStepResult.success(
            "chapters",
            f"解析完成，共 {len(self._chapters)} 章。",
            details={"chapter_count": len(self._chapters)},
        )
        self._emit_step(self.STEP_CHAPTERS, result)
        self._autosave(force=True)
        return result

    def load_file_async(
        self,
        path: Path,
        *,
        on_done: Callable[[ImportStepResult], None] | None = None,
    ) -> ImportStepResult | None:
        """Load and parse the source file in a background worker.

        Performs cheap validation synchronously and returns an
        ``ImportStepResult`` immediately on validation failure. Otherwise
        returns ``None`` and calls ``on_done`` on the UI thread when the worker
        finishes. Late results from a superseded request are discarded via
        ``self._load_id``.
        """
        self._cancelled = False
        if not path.exists():
            result = ImportStepResult.error("pick", f"文件不存在：{path}")
            if on_done is not None:
                on_done(result)
            return result
        suffix = path.suffix.lower()
        if suffix not in (".md", ".txt", ".pdf"):
            result = ImportStepResult.error(
                "pick",
                "不支持的文件类型，请选择 .md / .txt / .pdf。",
                recoverable=True,
                recovery_options=["重新选择"],
            )
            if on_done is not None:
                on_done(result)
            return result

        self._load_id += 1
        load_id = self._load_id
        self._load_path = path
        self._load_on_done = on_done
        worker = self._worker_factory(self._read_source_text, path)
        worker.result_ready.connect(self._on_load_result_ready)
        worker.error_occurred.connect(self._on_load_error_occurred)
        self._load_worker = worker
        worker.start()
        return None

    def _on_load_result_ready(self, text: str) -> None:
        path = getattr(self, "_load_path", None)
        load_id = getattr(self, "_load_id", 0)
        on_done = getattr(self, "_load_on_done", None)
        if path is not None:
            self._apply_loaded_text(path, text, load_id, on_done)

    def _on_load_error_occurred(self, msg: str) -> None:
        path = getattr(self, "_load_path", None)
        load_id = getattr(self, "_load_id", 0)
        on_done = getattr(self, "_load_on_done", None)
        if path is not None:
            self._on_load_error(path, msg, load_id, on_done)

    def _apply_loaded_text(
        self,
        path: Path,
        text: str,
        load_id: int,
        on_done: Callable[[ImportStepResult], None] | None,
    ) -> None:
        """UI-thread callback for a successful async file load."""
        if load_id != self._load_id:
            return
        self._source_path = path
        self._md = text
        self._split_into_chapters()
        result = ImportStepResult.success(
            "chapters",
            f"解析完成，共 {len(self._chapters)} 章。",
            details={"chapter_count": len(self._chapters)},
        )
        self._emit_step(self.STEP_CHAPTERS, result)
        self._autosave(force=True)
        if on_done is not None:
            on_done(result)

    def _on_load_error(
        self,
        path: Path,
        message: str,
        load_id: int,
        on_done: Callable[[ImportStepResult], None] | None,
    ) -> None:
        """UI-thread callback for a failed async file load."""
        if load_id != self._load_id:
            return
        self._source_path = path
        result = ImportStepResult.error(
            "parse",
            message,
            recoverable=True,
            recovery_options=["重新选择"],
        )
        if on_done is not None:
            on_done(result)

    def _split_into_chapters(self) -> None:
        chapters = split_chapters(self._md)
        self._chapters = [_ChapterResult(chapter=ch) for ch in chapters]

    # ------------------------------------------------------------------ ③ chapters
    def set_chapter_kept(self, index: int, kept: bool) -> None:
        if 0 <= index < len(self._chapters):
            self._chapters[index].keep = kept

    def set_all_chapters_kept(self, kept: bool) -> None:
        for cr in self._chapters:
            cr.keep = kept

    def invert_chapter_kept(self) -> None:
        for cr in self._chapters:
            cr.keep = not cr.keep

    # ------------------------------------------------------------------ ④ extract
    def start_extraction(self) -> ImportStepResult:
        """Begin extracting knowledge points for kept chapters."""
        kept = [i for i, cr in enumerate(self._chapters) if cr.keep]
        if not kept:
            return ImportStepResult.error(
                "chapters", "请至少勾选一个章节。", recoverable=True, recovery_options=["返回勾选"]
            )

        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            return ImportStepResult.error(
                "extract",
                "请先在设置中配置 AI API（base_url / api_key / model）后再提取。",
                recoverable=True,
                recovery_options=["打开设置"],
            )

        self._cancelled = False
        # Defensively cancel any workers still in flight from a prior run so
        # their eventual _finish_worker cannot double-process the new queue.
        for worker in list(self._active_workers.values()):
            if hasattr(worker, "cancel"):
                worker.cancel()
        self._active_workers = {}
        self._extract_queue = kept
        self._extract_total = len(kept)
        self._extract_start_time = time.monotonic()
        self._quality_report = None
        self._started_count = 0
        self._completed_count = 0
        self._usage_by_chapter = {}
        self._project_usage = dict(_ZERO_USAGE)
        self._attempted_strategies = {}
        self._emit_step(self.STEP_EXTRACT, ImportStepResult.success("extract", "开始提取知识点…"))
        self._extract_next()
        return ImportStepResult.success("extract", "开始提取知识点…")

    def _extract_next(self) -> None:
        """Fill the active-worker pool up to ``max_concurrent`` from the queue.

        Concurrency is configurable (bookplan2 Phase 5); default 1 preserves the
        historical serial behaviour. When the queue is drained and no workers
        remain in flight, the controller moves to the review step. If a cancel
        is in progress, the cancelled step is emitted only once the last worker
        finishes (or immediately if none were in flight).
        """
        if self._cancelled:
            if not self._active_workers:
                self._autosave(force=True)  # persist state before reporting cancel
                self._emit_step(
                    self.STEP_EXTRACT,
                    ImportStepResult.cancelled("extract", "提取已取消。"),
                )
            return

        while (
            len(self._active_workers) < self._max_concurrent
            and self._extract_queue
            and not self._cancelled
        ):
            idx = self._extract_queue.pop(0)
            self._start_worker(idx)

        if not self._active_workers and not self._extract_queue:
            self.compute_quality_report(adapter=None)
            self._autosave(force=True)  # extraction done — persist everything
            self._emit_step(
                self.STEP_REVIEW,
                ImportStepResult.success("extract", "提取完成，请审校结果。"),
            )

    def _start_worker(self, idx: int) -> None:
        """Launch the extraction worker for chapter ``idx`` and track it."""
        cr = self._chapters[idx]
        self._started_count += 1
        progress_msg = f"第 {self._started_count}/{self._extract_total} 章"
        remaining = self._estimate_remaining_seconds(self._completed_count)
        if remaining is not None:
            progress_msg += f"，预计剩余 {remaining} 秒"
        self._on_extract_log(f"\n- {progress_msg}：{cr.chapter.title} -")
        self._on_extract_progress(
            {"current": self._started_count, "total": self._extract_total,
             "remaining_seconds": remaining}
        )
        self._launch_worker(idx, strategy=self._preset.strategy)

    def _launch_worker(self, idx: int, *, strategy: str) -> None:
        """Create + connect + start an extraction worker for chapter ``idx``.

        Shared by the batch path (``_start_worker``) and single-chapter retry.
        ``strategy`` overrides the preset's strategy so retry can request
        ``vocab_only``. Other knobs (temperature/max_tokens/max_chars/window
        sizes) come from the active preset. The attempted strategy is recorded
        per chapter so the P4-2 auto-cascade cannot loop.
        """
        cr = self._chapters[idx]
        self._attempted_strategies.setdefault(idx, set()).add(strategy)
        worker = self._worker_factory(
            extract_knowledge_points_windowed,
            self._ai_config_fn(),
            self._language,
            self._source_language,
            cr.chapter,
            strategy=strategy,
            temperature=self._preset.temperature,
            max_tokens=self._preset.max_tokens,
            max_chapter_chars=self._preset.max_chapter_chars,
            max_window_chars=self._preset.window_chars,
            overlap_chars=self._preset.overlap_chars,
            max_retries=1,
        )
        worker._chapter_idx = idx
        worker._extract_strategy = strategy
        worker._worker_kind = "extract"
        self._connect_and_start(idx, worker)

    def _connect_and_start(
        self,
        idx: int,
        worker: Any,
        *,
        on_ready: Callable[[Any], None] | None = None,
        on_error: Callable[[str], None] | None = None,
    ) -> None:
        """Wire AiRequestWorker-compatible signals and start the worker.

        The worker identity is bound into every callback so signals arriving
        after this worker was dropped from ``_active_workers`` (cancelled run,
        superseded retry) can be recognised as stale and ignored.
        """
        if hasattr(worker, "result_ready"):
            slot_ready = on_ready if on_ready is not None else functools.partial(self._on_extract_ready_worker, idx, worker)
            worker.result_ready.connect(slot_ready)
        if hasattr(worker, "error_occurred"):
            slot_error = on_error if on_error is not None else functools.partial(self._on_extract_error_worker, idx, worker)
            worker.error_occurred.connect(slot_error)
        if hasattr(worker, "chunk_ready"):
            worker.chunk_ready.connect(self._on_extract_chunk)
        if hasattr(worker, "usage_ready"):
            worker.usage_ready.connect(functools.partial(self._on_usage_worker, idx, worker))
        self._active_workers[idx] = worker
        worker.start()

    def _on_extract_ready_worker(self, idx: int, worker: object, kp: KnowledgePoints) -> None:
        self._on_extract_ready(idx, kp, worker)

    def _on_extract_error_worker(self, idx: int, worker: object, message: str) -> None:
        strategy = getattr(worker, "_extract_strategy", "standard")
        self._on_extract_error(idx, message, worker, strategy=strategy)

    def _on_usage_worker(self, idx: int, worker: object, usage: Any) -> None:
        self._on_usage_guarded(idx, usage, worker)

    def _on_reextract_ready_worker(self, idx: int, worker: object, kp: KnowledgePoints) -> None:
        self._on_reextract_ready(idx, kp, worker)

    def _on_reextract_error_worker(self, idx: int, worker: object, message: str) -> None:
        self._on_reextract_error(idx, message, worker)

    def _is_active(self, idx: int, worker: object) -> bool:
        """True if ``worker`` is still the tracked worker for chapter ``idx``."""
        return self._active_workers.get(idx) is worker

    def _finish_worker(self, idx: int) -> None:
        """Drop a finished worker from the active pool and advance the queue."""
        self._active_workers.pop(idx, None)
        self._completed_count += 1
        self._extract_next()

    def _on_usage_guarded(self, idx: int, usage: UsageDict, worker: object) -> None:
        if self._is_active(idx, worker):
            self._on_usage(idx, usage)

    def _on_usage(self, idx: int, usage: UsageDict) -> None:
        """Accumulate per-chapter + project token usage (bookplan2 Phase 5)."""
        if not isinstance(usage, dict):
            return
        cur = self._usage_by_chapter.get(idx, _ZERO_USAGE)
        merged = {
            k: int(cur.get(k, 0)) + int(usage.get(k, 0) or 0)
            for k in ("prompt_tokens", "completion_tokens", "total_tokens")
        }
        self._usage_by_chapter[idx] = merged
        self._project_usage = {
            k: sum(c.get(k, 0) for c in self._usage_by_chapter.values())
            for k in ("prompt_tokens", "completion_tokens", "total_tokens")
        }
        self._on_usage_update(idx, dict(merged), dict(self._project_usage))

    def _estimate_remaining_seconds(self, completed: int) -> int | None:
        """Linear estimate of remaining extraction time, or None if unknown."""
        if self._extract_start_time is None or completed <= 0:
            return None
        elapsed = time.monotonic() - self._extract_start_time
        per_chapter = elapsed / completed
        remaining = self._extract_total - completed
        return max(1, int(round(per_chapter * remaining)))

    def _on_extract_chunk(self, fragment: str) -> None:
        if fragment:
            self._on_extract_log(fragment)

    def _on_extract_ready(self, idx: int, kp: KnowledgePoints, worker: object) -> None:
        if not self._is_active(idx, worker):
            return  # stale worker from a cancelled/superseded run
        if 0 <= idx < len(self._chapters):
            self._chapters[idx].knowledge = kp
            self._chapters[idx].error = ""
            w = len(kp.words)
            e = len(kp.expressions)
            g = len(kp.grammarPoints)
            self._on_extract_log(f"\n  ✓ 提取完成：{w} 词 / {e} 表达 / {g} 语法点")
            telemetry.record_event(
                "textbook.extract.chapter.success",
                payload={"chapter_index": idx},
            )
        self._autosave()
        self._finish_worker(idx)

    def _on_extract_error(
        self, idx: int, message: str, worker: object, *, strategy: str = "standard"
    ) -> None:
        if not self._is_active(idx, worker):
            return  # stale worker from a cancelled/superseded run
        if (
            self._auto_cascade
            and not self._cancelled
            and strategy == "standard"
            and "vocab_only" not in self._attempted_strategies.get(idx, set())
        ):
            # P4-2: standard extraction failed - automatically cascade to a
            # vocab_only retry of the same chapter (once; usage accumulates
            # under the same chapter index). Only a vocab_only failure leaves
            # the chapter in the error state.
            self._active_workers.pop(idx, None)
            self._on_extract_log(
                "\n  … 标准抽取失败，自动降级为仅词汇（vocab_only）重试本章…"
            )
            telemetry.record_event(
                "textbook.extract.chapter.cascade",
                payload={"chapter_index": idx, "from": "standard", "to": "vocab_only"},
            )
            self._launch_worker(idx, strategy="vocab_only")
            return
        if 0 <= idx < len(self._chapters):
            self._chapters[idx].error = message
            if strategy == "vocab_only":
                self._on_extract_log(
                    f"\n  ✗ 仅词汇抽取仍失败：{message}"
                    "（建议在审校页跳过本章，或稍后人工重试）"
                )
            else:
                self._on_extract_log(
                    f"\n  ✗ 失败：{message}（可在审校页选择重试/仅抽词汇/跳过）"
                )
            telemetry.record_event(
                "textbook.extract.chapter.failure",
                payload={"chapter_index": idx, "error": message},
            )
        self._autosave()
        self._finish_worker(idx)

    # ------------------------------------------------------------------ ⑤ review
    def apply_review_rows(
        self,
        rows: list[tuple[int, str, dict[str, Any]]],
    ) -> None:
        """Replace each chapter's knowledge with the curated rows.

        ``rows`` is a list of ``(chapter_index, resource_type, entry_dict)`` for
        kept entries. ``resource_type`` is one of ``word``/``expression``/
        ``grammarPoint``.
        """
        for cr in self._chapters:
            if cr.knowledge is not None:
                cr.knowledge.words = []
                cr.knowledge.expressions = []
                cr.knowledge.grammarPoints = []
        for ci, rtype, entry in rows:
            if not (0 <= ci < len(self._chapters)):
                continue
            cr = self._chapters[ci]
            if cr.knowledge is None:
                cr.knowledge = KnowledgePoints()
            if rtype == "word":
                cr.knowledge.words.append(entry)
            elif rtype == "expression":
                cr.knowledge.expressions.append(entry)
            elif rtype == "grammarPoint":
                cr.knowledge.grammarPoints.append(entry)
        self.compute_quality_report(adapter=None)
        self._autosave(force=True)

    def apply_review_edits(
        self,
        vocab_rows: list[tuple[int, dict[str, Any]]],
        expr_rows: list[tuple[int, dict[str, Any]]],
        grammar_rows: list[tuple[int, dict[str, Any]]],
    ) -> None:
        """Legacy helper retained for callers that pass three separate lists."""
        rows: list[tuple[int, str, dict[str, Any]]] = []
        rows.extend((ci, "word", e) for ci, e in vocab_rows)
        rows.extend((ci, "expression", e) for ci, e in expr_rows)
        rows.extend((ci, "grammarPoint", e) for ci, e in grammar_rows)
        self.apply_review_rows(rows)

    def retry_chapter(
        self,
        index: int,
        mode: Literal["standard", "vocab_only"] = "standard",
    ) -> ImportStepResult:
        """Retry extraction for a single failed chapter.

        ``mode="vocab_only"`` asks the model for words only, as a fallback when
        the full extraction keeps failing.
        """
        if not (0 <= index < len(self._chapters)):
            return ImportStepResult.error("extract", "章节索引无效。")
        if index in self._active_workers:
            return ImportStepResult.error(
                "extract", "该章节已有提取任务进行中。", recoverable=True
            )
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            return ImportStepResult.error(
                "extract",
                "请先在设置中配置 AI API 后再重试。",
                recoverable=True,
                recovery_options=["打开设置"],
            )

        self._cancelled = False
        cr = self._chapters[index]
        cr.error = ""
        self._on_extract_log(f"\n- 重试第 {index + 1} 章：{cr.chapter.title}（{mode}） -")
        self._launch_worker(index, strategy=mode)
        return ImportStepResult.success("extract", "开始重试抽取…")

    def reextract_chapter_targeted(self, index: int) -> ImportStepResult:
        """Re-extract one chapter guided by its quality issues (P4-4).

        The chapter must already hold extracted knowledge and the quality
        report must list issues for it; the worker asks the model for a
        complete corrected result which then replaces ``cr.knowledge`` and the
        quality scores are recomputed. Returns a recoverable error (and
        launches nothing) when there is nothing to fix.
        """
        if not (0 <= index < len(self._chapters)):
            return ImportStepResult.error("extract", "章节索引无效。")
        if index in self._active_workers:
            return ImportStepResult.error(
                "extract", "该章节已有提取任务进行中。", recoverable=True
            )
        cr = self._chapters[index]
        if cr.knowledge is None:
            return ImportStepResult.error(
                "extract", "该章尚未成功抽取，无法按质量重抽。", recoverable=True
            )
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            return ImportStepResult.error(
                "extract",
                "请先在设置中配置 AI API 后再重抽。",
                recoverable=True,
                recovery_options=["打开设置"],
            )
        report = self._quality_report or self.compute_quality_report(adapter=None)
        chapter_quality = report.chapter_quality(index)
        issues = chapter_quality.issues if chapter_quality else []
        if not issues:
            return ImportStepResult.error(
                "extract", "该章没有质量问题，无需按质量重抽。", recoverable=True
            )

        self._cancelled = False
        self._on_extract_log(
            f"\n- 按质量重抽第 {index + 1} 章：{cr.chapter.title}"
            f"（{len(issues)} 个质量问题） -"
        )
        telemetry.record_event(
            "textbook.extract.chapter.targeted_reextract",
            payload={"chapter_index": index, "issue_count": len(issues)},
        )
        worker = self._worker_factory(
            reextract_knowledge_targeted,
            config,
            self._language,
            self._source_language,
            cr.chapter,
            cr.knowledge,
            issues,
            temperature=self._preset.temperature,
            max_tokens=self._preset.max_tokens,
            max_retries=1,
        )
        self._connect_and_start(
            index,
            worker,
            on_ready=functools.partial(self._on_reextract_ready_worker, index, worker),
            on_error=functools.partial(self._on_reextract_error_worker, index, worker),
        )
        return ImportStepResult.success("extract", "开始按质量重抽…")

    def _on_reextract_ready(self, idx: int, kp: KnowledgePoints, worker: object) -> None:
        if not self._is_active(idx, worker):
            return  # stale worker from a cancelled/superseded run
        if 0 <= idx < len(self._chapters):
            self._chapters[idx].knowledge = kp
            self._chapters[idx].error = ""
            w = len(kp.words)
            e = len(kp.expressions)
            g = len(kp.grammarPoints)
            self._on_extract_log(f"\n  ✓ 按质量重抽完成：{w} 词 / {e} 表达 / {g} 语法点")
            telemetry.record_event(
                "textbook.extract.chapter.targeted_reextract.success",
                payload={"chapter_index": idx},
            )
            # Recompute quality scores against the corrected extraction.
            self.compute_quality_report(adapter=None)
        self._autosave()
        self._finish_worker(idx)

    def _on_reextract_error(self, idx: int, message: str, worker: object) -> None:
        if not self._is_active(idx, worker):
            return  # stale worker from a cancelled/superseded run
        # Keep the original extraction: a failed re-extract must not turn a
        # merely low-quality chapter into a failed one.
        self._on_extract_log(f"\n  ✗ 按质量重抽失败：{message}（已保留原抽取结果）")
        telemetry.record_event(
            "textbook.extract.chapter.targeted_reextract.failure",
            payload={"chapter_index": idx, "error": message},
        )
        self._finish_worker(idx)

    def skip_chapter(self, index: int) -> None:
        """Mark a chapter as not imported (used after extraction failure)."""
        if 0 <= index < len(self._chapters):
            self._chapters[index].keep = False
            self._autosave(force=True)

    # ------------------------------------------------------------------ ⑥ import
    def _build_section_list(self) -> list[tuple[int, dict[str, Any]]]:
        """Build ``(0-based chapter index, section dict)`` for every kept,
        non-empty chapter. Shared by ``build_sections`` and ``preview_import``
        so the preview's section ids match what import will actually emit.

        The section ``idx`` passed to ``build_section_from_chapter`` is the
        1-based position over **all** chapters (kept or not), matching the
        historical deterministic id scheme.
        """
        out: list[tuple[int, dict[str, Any]]] = []
        for ci, cr in enumerate(self._chapters, start=1):
            if not cr.keep or cr.knowledge is None:
                continue
            kp = cr.knowledge
            if not kp.words and not kp.expressions and not kp.grammarPoints:
                continue
            out.append(
                (
                    ci - 1,
                    build_section_from_chapter(
                        cr.chapter, kp, ci, lesson_template=self._preset.lesson_template
                    ),
                )
            )
        return out

    def _chapters_tuples(self) -> list[tuple[Chapter, KnowledgePoints | None]]:
        """ ``(chapter, knowledge)`` pairs for merger / quality analysis."""
        return [(cr.chapter, cr.knowledge) for cr in self._chapters]

    def merge_knowledge(self, adapter: Any | None) -> MergeReport:
        """Dedup intra-project ids and align course-collision ids in place.

        Idempotent. Call before ``build_sections`` so the emitted sections carry
        unified ids and ``CourseAdapter.merge_section_resources`` does not create
        duplicate terms. Returns the merger report for telemetry / display.
        """
        report = merge_knowledge_points(self._chapters_tuples(), adapter)
        telemetry.record_event(
            "textbook.merge.applied",
            payload={
                "intra_project": report.intra_project_count,
                "course_collisions": report.course_collision_count,
            },
        )
        self._autosave(force=True)
        return report

    def preview_import(
        self,
        adapter: Any | None,
        strategy: str,
    ) -> list[SectionImportPreview]:
        """Compute a read-only per-section import plan for the preview panel.

        Does not mutate chapter knowledge: the ``KnowledgeMerger`` is run in
        analyze-only mode so ``new_*`` / ``duplicate_*`` counts reflect the
        post-merge state the user will get on confirm. Section-id planning
        delegates to ``plan_bulk_import`` so the preview matches execution.
        """
        from src.backend.knowledge_merger import analyze as analyze_knowledge

        built = self._build_section_list()
        if not built:
            return []
        sections = [s for _, s in built]
        report = analyze_knowledge(self._chapters_tuples(), adapter)
        plans = plan_bulk_import(sections, adapter, strategy)

        previews: list[SectionImportPreview] = []
        for (chapter_index, section), plan in zip(built, plans):
            cr = self._chapters[chapter_index]
            kp = cr.knowledge
            words = len(kp.words) if kp else 0
            expressions = len(kp.expressions) if kp else 0
            grammar = len(kp.grammarPoints) if kp else 0
            dup_words = dup_expr = dup_gram = 0
            for col in report.collisions_for_chapter(chapter_index):
                # Skip collisions ``apply`` will not act on (e.g. a course entry
                # with an empty id has no target to align to); counting them as
                # duplicates would mislead the preview's new/duplicate split.
                if not col.target_id:
                    continue
                if col.resource_type == "word":
                    dup_words += 1
                elif col.resource_type == "expression":
                    dup_expr += 1
                else:
                    dup_gram += 1
            previews.append(
                SectionImportPreview(
                    chapter_index=chapter_index,
                    title=cr.chapter.title,
                    source_id=plan.source_id,
                    target_id=plan.target_id,
                    exists=plan.exists,
                    action=plan.action,
                    word_count=words,
                    expression_count=expressions,
                    grammar_count=grammar,
                    new_words=words - dup_words,
                    new_expressions=expressions - dup_expr,
                    new_grammar=grammar - dup_gram,
                    duplicate_words=dup_words,
                    duplicate_expressions=dup_expr,
                    duplicate_grammar=dup_gram,
                )
            )
        return previews

    def build_sections(self) -> ImportStepResult:
        """Build importable section dicts and notify via ``on_sections_ready``."""
        sections = [s for _, s in self._build_section_list()]
        if not sections:
            return ImportStepResult.error(
                "review",
                "没有可导入的章节（可能全部为空）。",
                recoverable=True,
                recovery_options=["返回审校"],
            )

        self._emit_step(
            self.STEP_IMPORT,
            ImportStepResult.success("import", f"已生成 {len(sections)} 个 section，等待导入。"),
        )
        self._autosave(force=True)
        self._on_sections_ready(sections)
        return ImportStepResult.success("import", f"已生成 {len(sections)} 个 section。")

    # ------------------------------------------------------------------ project serialization
    def to_project(self, name: str | None = None) -> TextbookProject:
        """Serialize current controller state into a ``TextbookProject``."""
        project_name = name or self._project_name or "未命名项目"
        project_id = getattr(self, "_project_id", "")
        if not project_id:
            project_id = _new_project_id(project_name)
            self._project_id = project_id
        project = TextbookProject.create(
            project_id=project_id,
            name=project_name,
            source_path=self._source_path,
            markdown=self._md,
            language=self._language,
            source_language=self._source_language,
        )
        project.set_chapters(
            [(cr.chapter, cr.keep, cr.knowledge, cr.error) for cr in self._chapters]
        )
        project.current_step = self.current_step
        # Snapshot the merged knowledge as the resource pool (connectplan §3.1);
        # dedup stays with the import-time KnowledgeMerger.
        project.update_resource_pool()
        return project

    def apply_project(self, project: TextbookProject) -> None:
        """Restore controller state from ``project`` and notify the view."""
        self._project_id = project.project_id
        self._project_name = project.name
        self._source_path = Path(project.source_path) if project.source_path else None
        self._md = project.markdown
        self._language = project.language
        self._source_language = project.source_language
        self._chapters = [
            _ChapterResult(chapter=ch, keep=keep, knowledge=kp, error=error)
            for ch, keep, kp, error in project.get_chapters()
        ]
        self._extract_queue = []
        self._active_workers = {}
        self._cancelled = False
        self._autosave_dirty = False
        self._last_autosave_at = 0.0
        self._attempted_strategies = {}
        # Notify the view so it can render the restored step.
        self._emit_step(project.current_step)

    _AUTOSAVE_INTERVAL = 2.0  # seconds between throttled autosave writes

    def _autosave(self, *, force: bool = False) -> None:
        """Build a project snapshot and forward it to the autosave callback.

        Throttled to one write per ``_AUTOSAVE_INTERVAL`` unless ``force``;
        skipped writes mark the state dirty so ``flush_autosave`` can persist
        them before closing. Serializing the full project (markdown +
        chapters) per completed chapter would otherwise stall the UI.
        """
        if not self._autosave_enabled or self._on_autosave is None:
            return
        now = time.monotonic()
        if not force and now - self._last_autosave_at < self._AUTOSAVE_INTERVAL:
            self._autosave_dirty = True
            return
        self._autosave_dirty = False
        self._last_autosave_at = now
        try:
            self._on_autosave(self.to_project())
        except Exception as exc:
            # Autosave must never break the workflow, but a permanently-failing
            # autosave (disk full, read-only project dir) used to lose all
            # extraction work silently. Record the error so the failure is at
            # least observable in telemetry, and surface it once to the user
            # via the status hook if available. (B9)
            telemetry.record_error(
                exc, context={"action": "textbook.autosave"}
            )
            try:
                status_hook = getattr(self, "_status_hook", None)
                if callable(status_hook):
                    status_hook(f"自动保存失败：{exc}")
            except Exception:  # noqa: BLE001 — never break on the error path
                logger.debug("dialogs/textbook_import_controller.py:1049 best-effort step failed", exc_info=True)

    def flush_autosave(self) -> None:
        """Force-write any throttled autosave state (close/interrupt safety)."""
        if self._autosave_dirty:
            self._autosave(force=True)

    # ------------------------------------------------------------------ cancel
    def cancel(self) -> None:
        """Cancel all in-flight extraction workers (bookplan2 Phase 5 concurrency).

        Sets the cancel flag and asks every active worker to abort. The
        cancelled step is emitted once the last worker reports back (via
        ``_extract_next``), or immediately if none were in flight.
        """
        self._cancelled = True
        telemetry.record_event("textbook.extract.cancel")
        for worker in list(self._active_workers.values()):
            if hasattr(worker, "cancel"):
                worker.cancel()
        if not self._active_workers:
            self._emit_step(
                self.STEP_EXTRACT,
                ImportStepResult.cancelled("extract", "提取已取消。"),
            )

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def _default_worker_factory(target, *args, **kwargs):
        from src.application.ai_request_worker import AiRequestWorker

        return AiRequestWorker(target, *args, **kwargs)

