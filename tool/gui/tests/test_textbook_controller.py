"""Tests for TextbookImportController.

These tests exercise the import pipeline logic without starting a QApplication
or spawning real worker threads.
"""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_generator import AiApiConfig
from src.backend.knowledge_schema import KnowledgePoints, coerce_knowledge_points
from src.dialogs.textbook_import_controller import TextbookImportController


def _sample_md() -> str:
    return (
        "## 1 Merhaba\n"
        "merhaba means hello\ngünaydın means good morning\n\n"
        "## 2 Aile\n"
        "aile means family\nanne means mother\n"
    )


def _sample_kp() -> KnowledgePoints:
    return coerce_knowledge_points(
        {
            "words": [
                {"term": "merhaba", "translation": "hello", "tags": ["greeting"]},
                {"term": "günaydın", "translation": "good morning"},
            ],
            "expressions": [{"term": "Selam!", "translation": "Hi!", "tags": ["greeting"]}],
            "grammarPoints": [{"title": "Greetings", "explanation": "common greetings"}],
        }
    )


class _FakeSignal:
    """Qt-signal stand-in that stores connected callbacks."""

    def __init__(self) -> None:
        self._callbacks: list[Any] = []

    def connect(self, callback: Any) -> None:
        self._callbacks.append(callback)

    def emit(self, *args: Any, **kwargs: Any) -> None:
        for cb in self._callbacks:
            cb(*args, **kwargs)


class _FakeWorker:
    """Fake background worker that immediately emits the configured result."""

    def __init__(self, result: KnowledgePoints | Exception | None) -> None:
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self._result = result
        self._cancelled = False

    def start(self) -> None:
        if isinstance(self._result, Exception):
            self.error_occurred.emit(str(self._result))
        elif self._result is not None:
            self.result_ready.emit(self._result)
        # None => no emission (used to simulate cancellation/hang in e2e tests).

    def cancel(self) -> None:
        self._cancelled = True


class _DeferredFakeWorker:
    """Fake worker that records ``start`` but does not emit until asked.

    Used by the concurrency / usage tests to control the order of completion
    so multiple workers can be observed in flight simultaneously.
    """

    def __init__(self) -> None:
        self.result_ready = _FakeSignal()
        self.error_occurred = _FakeSignal()
        self.chunk_ready = _FakeSignal()
        self.usage_ready = _FakeSignal()
        self.started = False
        self._cancelled = False
        self.kwargs: dict[str, Any] = {}

    def start(self) -> None:
        self.started = True

    def emit_result(self, kp: KnowledgePoints) -> None:
        self.result_ready.emit(kp)

    def emit_usage(self, usage: dict[str, int]) -> None:
        self.usage_ready.emit(usage)

    def cancel(self) -> None:
        self._cancelled = True


class _RecordingController(TextbookImportController):
    """Controller subclass that records step changes and log messages."""

    def __init__(self, **kwargs: Any) -> None:
        self.step_changes: list[tuple[int, Any]] = []
        self.log_messages: list[str] = []
        self.sections: list[dict[str, Any]] = []
        super().__init__(
            on_step_changed=lambda step, result: self.step_changes.append((step, result)),
            on_extract_log=lambda msg: self.log_messages.append(msg),
            on_sections_ready=lambda sections: self.sections.extend(sections),
            **kwargs,
        )


def _fake_worker_factory(result: KnowledgePoints | Exception | None) -> Any:
    """Return a factory that produces workers with the given result."""

    def factory(_target, *_args, **_kwargs):
        return _FakeWorker(result)

    return factory


class LoadFileTest(unittest.TestCase):
    def test_md_file_splits_into_chapters(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(_sample_md())
            path = Path(f.name)
        try:
            ctrl = _RecordingController(ai_config_fn=AiApiConfig)
            result = ctrl.load_file(path)
            self.assertEqual(result.outcome, "success")
            self.assertEqual(len(ctrl.chapters), 2)
            self.assertEqual(ctrl.chapters[0].chapter.title, "1 Merhaba")
        finally:
            path.unlink()

    def test_missing_file_returns_error(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        result = ctrl.load_file(Path("/nonexistent/file.md"))
        self.assertEqual(result.outcome, "error")
        self.assertIn("不存在", result.message)

    def test_unsupported_extension_returns_error(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".docx", delete=False) as f:
            path = Path(f.name)
        try:
            ctrl = _RecordingController(ai_config_fn=AiApiConfig)
            result = ctrl.load_file(path)
            self.assertEqual(result.outcome, "error")
            self.assertIn("不支持", result.message)
            self.assertTrue(result.recoverable)
        finally:
            path.unlink()


class LoadFileAsyncTest(unittest.TestCase):
    def test_async_md_file_splits_into_chapters(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(_sample_md())
            path = Path(f.name)
        try:
            ctrl = _RecordingController(
                ai_config_fn=AiApiConfig,
                worker_factory=_fake_worker_factory(_sample_md()),
            )
            called: list[ImportStepResult] = []
            result = ctrl.load_file_async(path, on_done=lambda r: called.append(r))
            self.assertIsNone(result)
            self.assertEqual(len(ctrl.chapters), 2)
            self.assertEqual(called[0].outcome, "success")
            self.assertEqual(ctrl.step_changes[-1][0], ctrl.STEP_CHAPTERS)
        finally:
            path.unlink()

    def test_async_missing_file_returns_error_immediately(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        called: list[ImportStepResult] = []
        result = ctrl.load_file_async(
            Path("/nonexistent/file.md"), on_done=lambda r: called.append(r)
        )
        self.assertIsNotNone(result)
        self.assertEqual(result.outcome, "error")
        self.assertEqual(len(called), 1)

    def test_async_pdf_parse_error_is_recoverable(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".pdf", delete=False) as f:
            f.write("dummy")
            path = Path(f.name)
        try:
            ctrl = _RecordingController(
                ai_config_fn=AiApiConfig,
                worker_factory=_fake_worker_factory(RuntimeError("PDF failed")),
            )
            called: list[ImportStepResult] = []
            result = ctrl.load_file_async(path, on_done=lambda r: called.append(r))
            self.assertIsNone(result)
            self.assertEqual(called[0].outcome, "error")
            self.assertTrue(called[0].recoverable)
            self.assertIn("PDF failed", called[0].message)
        finally:
            path.unlink()

    def test_stale_load_result_is_ignored(self) -> None:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write(_sample_md())
            path = Path(f.name)
        try:
            workers: list[_DeferredFakeWorker] = []

            def factory(_target, *_args, **_kwargs):
                w = _DeferredFakeWorker()
                workers.append(w)
                return w

            ctrl = _RecordingController(
                ai_config_fn=AiApiConfig, worker_factory=factory
            )
            ctrl.load_file_async(path)
            ctrl.load_file_async(path)
            self.assertEqual(len(workers), 2)
            workers[0].emit_result(_sample_md())
            self.assertEqual(len(ctrl.chapters), 0)
            workers[1].emit_result(_sample_md())
            self.assertEqual(len(ctrl.chapters), 2)
        finally:
            path.unlink()


class ChapterSelectionTest(unittest.TestCase):
    def test_kept_flags_round_trip(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl.set_chapter_kept(0, False)
        self.assertFalse(ctrl.chapters[0].keep)
        self.assertTrue(ctrl.chapters[1].keep)

    def test_invert_toggles_all(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl.set_all_chapters_kept(True)
        self.assertTrue(all(cr.keep for cr in ctrl.chapters))
        ctrl.invert_chapter_kept()
        self.assertFalse(any(cr.keep for cr in ctrl.chapters))


class ExtractionTest(unittest.TestCase):
    def test_extraction_runs_for_kept_chapters(self) -> None:
        ctrl = _RecordingController(
            ai_config_fn=lambda: AiApiConfig(base_url="http://x", api_key="k", model="m"),
            worker_factory=_fake_worker_factory(_sample_kp()),
        )
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        result = ctrl.start_extraction()
        self.assertEqual(result.outcome, "success")
        self.assertTrue(all(cr.knowledge is not None for cr in ctrl.chapters))
        self.assertTrue(any("Merhaba" in msg for msg in ctrl.log_messages))

    def test_no_kept_chapters_returns_error(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl.set_all_chapters_kept(False)
        result = ctrl.start_extraction()
        self.assertEqual(result.outcome, "error")
        self.assertIn("至少勾选", result.message)

    def test_incomplete_ai_config_returns_error(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        result = ctrl.start_extraction()
        self.assertEqual(result.outcome, "error")
        self.assertIn("配置 AI", result.message)

    def test_extraction_error_is_recorded(self) -> None:
        ctrl = _RecordingController(
            ai_config_fn=lambda: AiApiConfig(base_url="http://x", api_key="k", model="m"),
            worker_factory=_fake_worker_factory(RuntimeError("LLM failed")),
        )
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl.start_extraction()
        self.assertTrue(all(cr.error for cr in ctrl.chapters))


class ReviewAndBuildTest(unittest.TestCase):
    def test_build_sections_emits_only_kept_non_empty(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._chapters[0].knowledge = _sample_kp()
        ctrl._chapters[1].knowledge = coerce_knowledge_points({})
        ctrl.set_chapter_kept(1, False)
        ctrl.build_sections()
        self.assertEqual(len(ctrl.sections), 1)
        self.assertEqual(ctrl.sections[0]["id"], "ch-1-merhaba-1")

    def test_apply_review_edits_filters_unchecked_rows(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._chapters[0].knowledge = _sample_kp()
        # Keep only "günaydın".
        kept = ctrl._chapters[0].knowledge.words[1]
        ctrl.apply_review_edits(
            vocab_rows=[(0, kept)],
            expr_rows=[],
            grammar_rows=[],
        )
        self.assertEqual(len(ctrl._chapters[0].knowledge.words), 1)
        self.assertEqual(ctrl._chapters[0].knowledge.words[0]["term"], "günaydın")

    def test_empty_sections_returns_error(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl.set_all_chapters_kept(False)
        result = ctrl.build_sections()
        self.assertEqual(result.outcome, "error")
        self.assertIn("没有可导入", result.message)


class _FakeAdapter:
    """Minimal adapter stub for preview/merge tests."""

    def __init__(self, sections=None, vocab=None, expressions=None, grammar_points=None):
        self.sections = sections or []
        self.index = {"sections": []}
        self.vocab = vocab or []
        self.expressions = expressions or []
        self.grammar_points = grammar_points or []


class PreviewAndMergeTest(unittest.TestCase):
    """bookplan2 Phase 4: controller preview_import + merge_knowledge."""

    def _controller_with_two_chapters(self) -> _RecordingController:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._chapters[0].knowledge = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": "hello"}]}
        )
        ctrl._chapters[1].knowledge = coerce_knowledge_points(
            {"words": [{"term": "aile", "translation": "family"}]}
        )
        return ctrl

    def test_preview_import_shows_append_for_new_sections(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        ctrl = self._controller_with_two_chapters()
        previews = ctrl.preview_import(_FakeAdapter(), ImportStrategy.MERGE.value)
        self.assertEqual(len(previews), 2)
        self.assertTrue(all(p.action == "append" for p in previews))
        self.assertTrue(all(p.duplicate_words == 0 for p in previews))
        self.assertEqual(previews[0].new_words, 1)
        self.assertEqual(previews[0].word_count, 1)
        # Section ids follow the ch-{slug}-{1-based-idx} scheme.
        self.assertEqual(previews[0].source_id, "ch-1-merhaba-1")
        self.assertEqual(previews[1].source_id, "ch-2-aile-2")

    def test_preview_import_flags_course_collision(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        ctrl = self._controller_with_two_chapters()
        adapter = _FakeAdapter(
            vocab=[{"id": "course-merhaba", "term": "merhaba", "translation": "hello"}]
        )
        previews = ctrl.preview_import(adapter, ImportStrategy.MERGE.value)
        # Chapter 0's "merhaba" collides with the course.
        self.assertEqual(previews[0].duplicate_words, 1)
        self.assertEqual(previews[0].new_words, 0)
        # Chapter 1 is unaffected.
        self.assertEqual(previews[1].duplicate_words, 0)
        self.assertEqual(previews[1].new_words, 1)

    def test_preview_import_append_new_strategy_assigns_target_id(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        ctrl = self._controller_with_two_chapters()
        # First chapter's section id already exists in the course.
        adapter = _FakeAdapter(sections=[{"id": "ch-1-merhaba-1"}])
        previews = ctrl.preview_import(adapter, ImportStrategy.APPEND_AS_NEW.value)
        self.assertEqual(previews[0].action, "append_new")
        self.assertEqual(previews[0].target_id, "ch-1-merhaba-1-2")
        self.assertTrue(previews[0].exists)
        # Second chapter is free -> append as-is.
        self.assertEqual(previews[1].action, "append")

    def test_preview_import_empty_when_no_kept(self) -> None:
        from src.backend.import_strategy import ImportStrategy

        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl.set_all_chapters_kept(False)
        self.assertEqual(ctrl.preview_import(None, ImportStrategy.MERGE.value), [])

    def test_preview_import_does_not_mutate_knowledge(self) -> None:
        # preview is read-only: running it must not rewrite ids.
        from src.backend.import_strategy import ImportStrategy

        ctrl = self._controller_with_two_chapters()
        adapter = _FakeAdapter(
            vocab=[{"id": "course-merhaba", "term": "merhaba", "translation": "hello"}]
        )
        before_id = ctrl._chapters[0].knowledge.words[0]["id"]
        ctrl.preview_import(adapter, ImportStrategy.MERGE.value)
        self.assertEqual(ctrl._chapters[0].knowledge.words[0]["id"], before_id)

    def test_merge_knowledge_unifies_intra_project_duplicates(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        # Distinct per-chapter ids, mirroring the extractor's
        # ``ch-{slug}-`` prefix; without it coerce would assign the same id.
        ctrl._chapters[0].knowledge = coerce_knowledge_points(
            {"words": [{"id": "ch1-merhaba", "term": "merhaba", "translation": "hello"}]}
        )
        ctrl._chapters[1].knowledge = coerce_knowledge_points(
            {"words": [{"id": "ch2-merhaba", "term": "merhaba", "translation": "hello"}]}
        )
        report = ctrl.merge_knowledge(_FakeAdapter())
        self.assertEqual(report.intra_project_count, 1)
        first_id = ctrl._chapters[0].knowledge.words[0]["id"]
        self.assertEqual(ctrl._chapters[1].knowledge.words[0]["id"], first_id)

    def test_merge_knowledge_is_idempotent(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._chapters[0].knowledge = coerce_knowledge_points(
            {"words": [{"id": "ch1-merhaba", "term": "merhaba", "translation": "hello"}]}
        )
        ctrl._chapters[1].knowledge = coerce_knowledge_points(
            {"words": [{"id": "ch2-merhaba", "term": "merhaba", "translation": "hello"}]}
        )
        first = ctrl.merge_knowledge(_FakeAdapter())
        second = ctrl.merge_knowledge(_FakeAdapter())
        self.assertEqual(first.intra_project_count, 1)
        self.assertEqual(second.intra_project_count, 0)


class ConcurrencyAndUsageTest(unittest.TestCase):
    """bookplan2 Phase 5: concurrent extraction + token-usage tracking + preset."""

    def _controller(
        self,
        *,
        max_concurrent: int = 1,
        preset: Any = None,
        on_usage_update: Any = None,
    ) -> tuple[_RecordingController, list]:
        created: list[_DeferredFakeWorker] = []

        def factory(_target, *_args, **kwargs):
            w = _DeferredFakeWorker()
            w.kwargs = kwargs
            created.append(w)
            return w

        ctrl = _RecordingController(
            ai_config_fn=lambda: AiApiConfig(base_url="http://x", api_key="k", model="m"),
            worker_factory=factory,
            max_concurrent=max_concurrent,
            preset=preset,
            on_usage_update=on_usage_update,
        )
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        return ctrl, created

    def test_concurrency_runs_multiple_workers_in_flight(self) -> None:
        ctrl, created = self._controller(max_concurrent=2)
        ctrl.start_extraction()
        # Two chapters, concurrency 2 -> both launched immediately.
        self.assertEqual(len(ctrl._active_workers), 2)
        self.assertEqual(len(created), 2)
        # Finish the first -> one still in flight, no new worker (queue empty).
        created[0].emit_result(_sample_kp())
        self.assertEqual(len(ctrl._active_workers), 1)
        # Finish the second -> all done, step advances to REVIEW.
        created[1].emit_result(_sample_kp())
        self.assertEqual(len(ctrl._active_workers), 0)
        self.assertEqual(ctrl.step_changes[-1][0], ctrl.STEP_REVIEW)

    def test_serial_concurrency_one_at_a_time(self) -> None:
        ctrl, created = self._controller(max_concurrent=1)
        ctrl.start_extraction()
        # Only one worker in flight at a time.
        self.assertEqual(len(ctrl._active_workers), 1)
        self.assertEqual(len(created), 1)
        # The second is not launched until the first finishes.
        created[0].emit_result(_sample_kp())
        self.assertEqual(len(created), 2)

    def test_usage_accumulates_per_chapter_and_project(self) -> None:
        updates: list = []
        ctrl, created = self._controller(
            max_concurrent=1,
            on_usage_update=lambda idx, chap, proj: updates.append((idx, chap, proj)),
        )
        ctrl.start_extraction()
        created[0].emit_usage({"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150})
        created[0].emit_result(_sample_kp())
        self.assertEqual(ctrl.usage_for_chapter(0)["total_tokens"], 150)
        self.assertEqual(ctrl.project_usage["total_tokens"], 150)

        created[1].emit_usage({"prompt_tokens": 200, "completion_tokens": 100, "total_tokens": 300})
        created[1].emit_result(_sample_kp())
        self.assertEqual(ctrl.usage_for_chapter(1)["total_tokens"], 300)
        self.assertEqual(ctrl.project_usage["total_tokens"], 450)
        # on_usage_update fired for each emission with the running project total.
        self.assertTrue(updates)
        self.assertEqual(updates[-1][2]["total_tokens"], 450)

    def test_preset_params_forwarded_to_worker(self) -> None:
        from src.backend.textbook_presets import preset_for

        reading = preset_for("reading")  # vocab_only, larger max_chapter_chars
        ctrl, created = self._controller(preset=reading)
        ctrl.start_extraction()
        self.assertEqual(created[0].kwargs["strategy"], "vocab_only")
        self.assertEqual(created[0].kwargs["temperature"], reading.temperature)
        self.assertEqual(created[0].kwargs["max_chapter_chars"], reading.max_chapter_chars)
        self.assertIsNone(created[0].kwargs["max_tokens"])  # reading has no cap

    def test_grammar_preset_forwards_max_tokens(self) -> None:
        from src.backend.textbook_presets import preset_for

        grammar = preset_for("grammar")
        ctrl, created = self._controller(preset=grammar)
        ctrl.start_extraction()
        self.assertEqual(created[0].kwargs["max_tokens"], grammar.max_tokens)


class CancelTest(unittest.TestCase):
    def test_cancel_sets_flag(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        fake = _FakeWorker(None)
        ctrl._active_workers[0] = fake
        ctrl.cancel()
        self.assertTrue(ctrl._cancelled)
        self.assertTrue(fake._cancelled)

    def test_cancel_cancels_all_active_workers(self) -> None:
        # bookplan2 Phase 5: concurrency means cancel must reach every worker.
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        fake_a = _FakeWorker(None)
        fake_b = _FakeWorker(None)
        ctrl._active_workers[0] = fake_a
        ctrl._active_workers[1] = fake_b
        ctrl.cancel()
        self.assertTrue(fake_a._cancelled)
        self.assertTrue(fake_b._cancelled)


class ProjectSerializationTest(unittest.TestCase):
    def test_to_project_round_trip(self) -> None:
        ctrl = _RecordingController(ai_config_fn=AiApiConfig)
        ctrl._source_path = Path("/tmp/sample.md")
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._chapters[0].knowledge = _sample_kp()

        project = ctrl.to_project(name="Sample")
        self.assertEqual(project.name, "Sample")
        self.assertEqual(project.current_step, 4)  # review step
        self.assertEqual(len(project.get_chapters()), 2)

        restored = _RecordingController(ai_config_fn=AiApiConfig)
        restored.apply_project(project)
        self.assertEqual(len(restored.chapters), 2)
        self.assertEqual(restored.chapters[0].chapter.title, "1 Merhaba")
        self.assertIsNotNone(restored.chapters[0].knowledge)
        self.assertEqual(restored._project_id, project.project_id)

    def test_autosave_callback_fires(self) -> None:
        saved: list = []
        ctrl = TextbookImportController(
            ai_config_fn=AiApiConfig,
            on_autosave=lambda p: saved.append(p),
        )
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._autosave()
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].name, "未命名项目")

    def test_autosave_disabled_skips_callback(self) -> None:
        saved: list = []
        ctrl = TextbookImportController(
            ai_config_fn=AiApiConfig,
            on_autosave=lambda p: saved.append(p),
        )
        ctrl.autosave_enabled = False
        ctrl._md = _sample_md()
        ctrl._split_into_chapters()
        ctrl._autosave()
        self.assertEqual(saved, [])


class AutoCascadeTest(unittest.TestCase):
    """第三枪 批次③ P4-2: standard failure auto-cascades to vocab_only."""

    def _controller(
        self, *, auto_cascade: bool = True
    ) -> tuple[_RecordingController, list]:
        created: list[_DeferredFakeWorker] = []

        def factory(_target, *_args, **kwargs):
            w = _DeferredFakeWorker()
            w.kwargs = kwargs
            created.append(w)
            return w

        ctrl = _RecordingController(
            ai_config_fn=lambda: AiApiConfig(base_url="http://x", api_key="k", model="m"),
            worker_factory=factory,
            auto_cascade=auto_cascade,
        )
        ctrl._md = "## 1 Merhaba\nmerhaba means hello\n"
        ctrl._split_into_chapters()
        return ctrl, created

    def test_standard_failure_cascades_to_vocab_only(self) -> None:
        ctrl, created = self._controller()
        ctrl.start_extraction()
        self.assertEqual(created[0].kwargs["strategy"], "standard")
        created[0].error_occurred.emit("boom")
        # The same chapter was relaunched as vocab_only, without an error yet.
        self.assertEqual(len(created), 2)
        self.assertEqual(created[1].kwargs["strategy"], "vocab_only")
        self.assertFalse(ctrl.chapters[0].error)
        self.assertTrue(any("自动降级" in m for m in ctrl.log_messages))
        # The cascaded worker succeeds -> knowledge restored, usage same chapter.
        created[1].emit_result(_sample_kp())
        self.assertIsNotNone(ctrl.chapters[0].knowledge)
        self.assertFalse(ctrl.chapters[0].error)

    def test_vocab_only_failure_after_cascade_marks_error(self) -> None:
        ctrl, created = self._controller()
        ctrl.start_extraction()
        created[0].error_occurred.emit("boom")
        created[1].error_occurred.emit("boom2")
        self.assertEqual(ctrl.chapters[0].error, "boom2")
        self.assertTrue(any("跳过本章" in m for m in ctrl.log_messages))

    def test_cascade_disabled_records_error_directly(self) -> None:
        ctrl, created = self._controller(auto_cascade=False)
        ctrl.start_extraction()
        created[0].error_occurred.emit("boom")
        self.assertEqual(len(created), 1)
        self.assertEqual(ctrl.chapters[0].error, "boom")
        self.assertFalse(any("自动降级" in m for m in ctrl.log_messages))

    def test_cascade_does_not_loop_on_manual_retry(self) -> None:
        ctrl, created = self._controller()
        ctrl.start_extraction()
        created[0].error_occurred.emit("boom")  # standard -> cascade
        created[1].error_occurred.emit("boom2")  # vocab_only -> error state
        self.assertEqual(ctrl.chapters[0].error, "boom2")
        # Manual standard retry: vocab_only already attempted -> no cascade.
        workers_before = len(created)
        ctrl.retry_chapter(0, mode="standard")
        self.assertEqual(created[-1].kwargs["strategy"], "standard")
        created[-1].error_occurred.emit("boom3")
        self.assertEqual(len(created), workers_before + 1)
        self.assertEqual(ctrl.chapters[0].error, "boom3")

    def test_window_params_forwarded_to_worker(self) -> None:
        # P4-1: preset window sizes reach the extraction entry point.
        ctrl, created = self._controller()
        ctrl.start_extraction()
        self.assertEqual(
            created[0].kwargs["max_window_chars"], ctrl.preset.window_chars
        )
        self.assertEqual(
            created[0].kwargs["overlap_chars"], ctrl.preset.overlap_chars
        )
        self.assertEqual(
            created[0].kwargs["max_chapter_chars"], ctrl.preset.max_chapter_chars
        )


class TargetedReextractTest(unittest.TestCase):
    """第三枪 批次③ P4-4: quality-driven targeted re-extraction."""

    def _controller(self) -> tuple[_RecordingController, list]:
        created: list[_DeferredFakeWorker] = []

        def factory(_target, *_args, **kwargs):
            w = _DeferredFakeWorker()
            w.kwargs = kwargs
            created.append(w)
            return w

        ctrl = _RecordingController(
            ai_config_fn=lambda: AiApiConfig(base_url="http://x", api_key="k", model="m"),
            worker_factory=factory,
        )
        ctrl._md = "## 1 Merhaba\nmerhaba means hello\n"
        ctrl._split_into_chapters()
        return ctrl, created

    def _kp_with_empty_translation(self) -> KnowledgePoints:
        return coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": ""}]}
        )

    def test_no_knowledge_returns_error_without_worker(self) -> None:
        ctrl, created = self._controller()
        result = ctrl.reextract_chapter_targeted(0)
        self.assertEqual(result.outcome, "error")
        self.assertEqual(created, [])

    def test_no_issues_skips_reextract(self) -> None:
        ctrl, created = self._controller()
        ctrl._chapters[0].knowledge = _sample_kp()
        ctrl.compute_quality_report()
        result = ctrl.reextract_chapter_targeted(0)
        self.assertEqual(result.outcome, "error")
        self.assertIn("无需", result.message)
        self.assertEqual(created, [])

    def test_reextract_replaces_knowledge_and_recomputes_quality(self) -> None:
        ctrl, created = self._controller()
        ctrl._chapters[0].knowledge = self._kp_with_empty_translation()
        ctrl.compute_quality_report()
        # Empty translation -> a lang_check issue exists before the re-extract.
        cq_before = ctrl.quality_report.chapter_quality(0)
        self.assertTrue(
            any(i.field == "translation" for i in cq_before.issues)
        )
        result = ctrl.reextract_chapter_targeted(0)
        self.assertEqual(result.outcome, "success")
        self.assertEqual(len(created), 1)
        fixed = coerce_knowledge_points(
            {"words": [{"term": "merhaba", "translation": "hello"}]},
            id_prefix="ch-1-merhaba-",
        )
        created[0].emit_result(fixed)
        self.assertEqual(
            ctrl.chapters[0].knowledge.words[0]["translation"], "hello"
        )
        self.assertFalse(ctrl.chapters[0].error)
        # Quality scores were recomputed against the corrected extraction.
        cq_after = ctrl.quality_report.chapter_quality(0)
        self.assertFalse(any(i.field == "translation" for i in cq_after.issues))

    def test_reextract_failure_keeps_original_knowledge(self) -> None:
        ctrl, created = self._controller()
        original = self._kp_with_empty_translation()
        ctrl._chapters[0].knowledge = original
        ctrl.compute_quality_report()
        ctrl.reextract_chapter_targeted(0)
        created[0].error_occurred.emit("boom")
        # A failed re-extract must not turn the chapter into a failed one.
        self.assertIs(ctrl.chapters[0].knowledge, original)
        self.assertFalse(ctrl.chapters[0].error)
        self.assertTrue(any("保留原抽取结果" in m for m in ctrl.log_messages))


if __name__ == "__main__":
    unittest.main()
