"""Pure-Python controller for the textbook-import workflow.

The controller owns the import state and orchestrates the pipeline:
  pick file → parse markdown → split chapters → extract knowledge →
  review → build sections.

It is intentionally Qt-free: it returns ``ImportStepResult`` objects and uses
plain callbacks to notify the view of asynchronous progress. This makes the
majority of the import logic unit-testable without a QApplication event loop.
"""
from __future__ import annotations

import functools
import logging
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal

# Ensure ``tool/gui`` is on sys.path when this module is imported directly.
_GUI = Path(__file__).resolve().parents[2]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.extraction_quality import (
    ExtractionQualityReport,
    compute_quality_report,
)
from src.backend.import_step_result import ImportStepResult
from src.backend.import_strategy import SectionImportPreview
from src.backend.knowledge_merger import MergeReport
from src.backend.knowledge_schema import KnowledgePoints
from src.backend.markdown_chopper import Chapter
from src.backend.textbook_presets import TextbookPreset, preset_for
from src.backend.textbook_project import TextbookProject
from src.dialogs.textbook_import.extraction_pipeline import (
    UsageDict,
    _ZERO_USAGE,
    accumulate_usage,
    apply_reviewed_rows,
    estimate_remaining_seconds,
    make_extraction_worker,
    make_targeted_reextract_worker,
)
from src.dialogs.textbook_import.persistence import (
    execute_autosave,
    serialize_to_project,
)
from src.dialogs.textbook_import.section_builder import (
    build_raw_sections,
    compute_import_previews,
    merge_knowledge_in_place,
)
from src.dialogs.textbook_import.source_loader import (
    read_source_text,
    split_markdown_into_chapters,
    validate_source_path,
)
from src.infrastructure.telemetry import telemetry

logger = logging.getLogger(__name__)


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

    STEP_PICK, STEP_PARSE, STEP_CHAPTERS, STEP_EXTRACT, STEP_REVIEW, STEP_IMPORT = range(6)
    _AUTOSAVE_INTERVAL = 2.0  # seconds between throttled autosave writes

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
        self._auto_cascade = bool(auto_cascade)
        self._attempted_strategies: dict[int, set[str]] = {}

        self._source_path: Path | None = None
        self._md: str = ""
        self._chapters: list[_ChapterResult] = []
        self._extract_queue: list[int] = []
        self._active_workers: dict[int, Any] = {}
        self._cancelled = False
        self._autosave_enabled = True
        self._load_id: int = 0
        self._load_worker: Any | None = None
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
            if self._active_workers or self._extract_queue:
                return self.STEP_EXTRACT
            return self.STEP_REVIEW
        return self.STEP_CHAPTERS

    def _emit_step(self, step: int, result: ImportStepResult | None = None) -> None:
        self._on_step_changed(step, result)

    # ------------------------------------------------------------------ helpers
    @staticmethod
    def _read_source_text(path: Path) -> str:
        """Read text from a .md/.txt file or extract it from a text PDF."""
        return read_source_text(path)

    # ------------------------------------------------------------------ ① pick / ② parse
    def load_file(self, path: Path) -> ImportStepResult:
        """Load and parse the source file synchronously."""
        self._cancelled = False
        val_error = validate_source_path(path)
        if val_error is not None:
            return val_error

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
        """Load and parse the source file in a background worker."""
        self._cancelled = False
        val_error = validate_source_path(path)
        if val_error is not None:
            if on_done is not None:
                on_done(val_error)
            return val_error

        self._load_id += 1
        load_id = self._load_id
        self._load_path = path
        worker = self._worker_factory(self._read_source_text, path)
        slot_ready = functools.partial(self._on_load_worker_result, load_id, path, on_done)
        slot_error = functools.partial(self._on_load_worker_error, load_id, path, on_done)
        worker.result_ready.connect(slot_ready)
        worker.error_occurred.connect(slot_error)
        self._load_worker = worker
        worker.start()
        return None

    def _on_load_worker_result(
        self,
        load_id: int,
        path: Path,
        on_done: Callable[[ImportStepResult], None] | None,
        text: str,
    ) -> None:
        self._apply_loaded_text(path, text, load_id, on_done)

    def _on_load_worker_error(
        self,
        load_id: int,
        path: Path,
        on_done: Callable[[ImportStepResult], None] | None,
        msg: str,
    ) -> None:
        self._on_load_error(path, msg, load_id, on_done)

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
        msg: str,
        load_id: int,
        on_done: Callable[[ImportStepResult], None] | None,
    ) -> None:
        """UI-thread callback for an async file load error."""
        if load_id != self._load_id:
            return
        result = ImportStepResult.error(
            "parse",
            msg,
            recoverable=True,
            recovery_options=["重新选择"],
        )
        self._emit_step(self.STEP_PICK, result)
        if on_done is not None:
            on_done(result)

    def _split_into_chapters(self) -> None:
        chapters = split_markdown_into_chapters(self._md)
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
        """Fill the active-worker pool up to ``max_concurrent`` from the queue."""
        if self._cancelled:
            if not self._active_workers:
                self._autosave(force=True)
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
            self._autosave(force=True)
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
        """Create + connect + start an extraction worker for chapter ``idx``."""
        cr = self._chapters[idx]
        self._attempted_strategies.setdefault(idx, set()).add(strategy)
        worker = make_extraction_worker(
            self._worker_factory,
            self._ai_config_fn(),
            self._language,
            self._source_language,
            cr.chapter,
            self._preset,
            strategy,
            idx,
        )
        self._connect_and_start(idx, worker)

    def _connect_and_start(
        self,
        idx: int,
        worker: Any,
        *,
        on_ready: Callable[[Any], None] | None = None,
        on_error: Callable[[str], None] | None = None,
    ) -> None:
        """Wire AiRequestWorker-compatible signals and start the worker."""
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
        """Accumulate per-chapter + project token usage."""
        merged, project_usage = accumulate_usage(self._usage_by_chapter, idx, usage)
        self._project_usage = project_usage
        self._on_usage_update(idx, dict(merged), dict(self._project_usage))

    def _estimate_remaining_seconds(self, completed: int) -> int | None:
        """Linear estimate of remaining extraction time, or None if unknown."""
        return estimate_remaining_seconds(self._extract_start_time, completed, self._extract_total)

    def _on_extract_chunk(self, fragment: str) -> None:
        if fragment:
            self._on_extract_log(fragment)

    def _on_extract_ready(self, idx: int, kp: KnowledgePoints, worker: object) -> None:
        if not self._is_active(idx, worker):
            return
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
            return
        if (
            self._auto_cascade
            and not self._cancelled
            and strategy == "standard"
            and "vocab_only" not in self._attempted_strategies.get(idx, set())
        ):
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
        """Replace each chapter's knowledge with the curated rows."""
        apply_reviewed_rows(self._chapters, rows)
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
        """Retry extraction for a single failed chapter."""
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
        """Re-extract one chapter guided by its quality issues."""
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
        worker = make_targeted_reextract_worker(
            self._worker_factory,
            config,
            self._language,
            self._source_language,
            cr.chapter,
            cr.knowledge,
            issues,
            self._preset,
            index,
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
            return
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
            self.compute_quality_report(adapter=None)
        self._autosave()
        self._finish_worker(idx)

    def _on_reextract_error(self, idx: int, message: str, worker: object) -> None:
        if not self._is_active(idx, worker):
            return
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
        """Build ``(0-based chapter index, section dict)`` for kept, non-empty chapters."""
        return build_raw_sections(
            self._chapters, lesson_template=self._preset.lesson_template
        )

    def _chapters_tuples(self) -> list[tuple[Chapter, KnowledgePoints | None]]:
        """ ``(chapter, knowledge)`` pairs for merger / quality analysis."""
        return [(cr.chapter, cr.knowledge) for cr in self._chapters]

    def merge_knowledge(self, adapter: Any | None) -> MergeReport:
        """Dedup intra-project ids and align course-collision ids in place."""
        report = merge_knowledge_in_place(self._chapters_tuples(), adapter)
        self._autosave(force=True)
        return report

    def preview_import(
        self,
        adapter: Any | None,
        strategy: str,
    ) -> list[SectionImportPreview]:
        """Compute a read-only per-section import plan for the preview panel."""
        built = self._build_section_list()
        return compute_import_previews(
            self._chapters_tuples(), built, self._chapters, adapter, strategy
        )

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
        project = serialize_to_project(
            project_id=project_id,
            project_name=project_name,
            source_path=self._source_path,
            markdown=self._md,
            language=self._language,
            source_language=self._source_language,
            chapters=self._chapters,
            current_step=self.current_step,
        )
        self._project_id = project.project_id
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
        self._emit_step(project.current_step)

    def _autosave(self, *, force: bool = False) -> None:
        """Build a project snapshot and forward it to the autosave callback."""
        if not self._autosave_enabled or self._on_autosave is None:
            return
        now = time.monotonic()
        if not force and now - self._last_autosave_at < self._AUTOSAVE_INTERVAL:
            self._autosave_dirty = True
            return
        self._autosave_dirty = False
        self._last_autosave_at = now
        execute_autosave(
            self._on_autosave,
            self.to_project(),
            status_hook=getattr(self, "_status_hook", None),
        )

    def flush_autosave(self) -> None:
        """Force-write any throttled autosave state (close/interrupt safety)."""
        if self._autosave_dirty:
            self._autosave(force=True)

    # ------------------------------------------------------------------ cancel
    def cancel(self) -> None:
        """Cancel all in-flight extraction workers."""
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
