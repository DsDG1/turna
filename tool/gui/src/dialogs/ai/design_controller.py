"""Pure-Python controller for grounded course design (connectplan §4.3 / P3-2).

Owns the design parameters, wish-mode chat history, and the in-flight draft;
orchestrates alignment chat + grounded generation through an injectable
worker factory. Qt-free, mirroring ``TextbookImportController``: all progress
is reported via plain callbacks so the logic is unit-testable without a
QApplication event loop.

Generation paths:
- No chat yet, mode ``fast`` → ``request_course`` single shot (validate-and-
  repair loop).
- No chat yet, mode ``phased``/``refine`` → ``ai_pipeline.run_pipeline``
  (Plan→Outline→Generate→Validate→Quality→Fix→Explain→ReadyImport; Phase 5).
  Per-step progress rides the worker's ``progress_ready`` signal; incomplete
  snapshots persist into ``project.design["pipeline"]`` for resume.
- Chat present → ``generate_from_chat`` with the running draft fed back so the
  model revises instead of starting over.

When a resource pool is set (``set_resource_pool``), the spec is grounded:
the model must pick words from the pool and copy them verbatim (§3.4).

Phase C additions: attachments on chat messages (OpenAI content pieces),
``explain_course`` auto-chained after each draft (persisted to
``design.explanation``), genre batch application, and Settings-driven
timeout/temperature/retry injection.
"""
from __future__ import annotations

import logging
from typing import Any, Callable

import copy

from src.backend.ai_generator import (
    AiCourseSpec,
    ChatMessage,
    apply_genre_to_spec,
    explain_course,
    generate_from_chat,
    regenerate_lesson_in_section,
    regenerate_unit_in_section,
    request_alignment_reply,
)
from src.backend.ai_phased import request_course
from src.backend.ai_pipeline import PipelineState, PipelineStep, run_pipeline
from src.backend.textbook_to_course import _rewrite_ids_deterministic

logger = logging.getLogger(__name__)

#: Usage dict shape: {"prompt_tokens", "completion_tokens", "total_tokens"}.
UsageDict = dict[str, int]


def _serialize_content(content: Any) -> Any:
    """Make chat content JSON-safe for ``project.design`` persistence.

    Image pieces carry base64 payloads that must not land in the project
    file (connectplan D4: 附件引用可存，base64 本体不存); they degrade to a
    text placeholder. Text pieces pass through verbatim.
    """
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return str(content)
    pieces: list[dict] = []
    for piece in content:
        if isinstance(piece, dict) and piece.get("type") == "text":
            pieces.append(piece)
        else:
            pieces.append({"type": "text", "text": "[图片附件]"})
    return pieces


class DesignController:
    """Controller for the workshop design stage.

    Args:
        ai_config_fn: Callable returning the current ``AiApiConfig``.
        worker_factory: ``(target, *args, **kwargs) -> worker``; defaults to
            ``AiRequestWorker``. Tests inject a fake factory.
        validator: Optional ``(section_json) -> list`` course validator used by
            the one-shot path's retry loop (e.g.
            ``CourseAdapter.validate_section_json``).
        on_chat_updated: Fired when the chat history changes.
        on_chat_stream_chunk: Fired per streamed alignment fragment.
        on_draft_ready: ``callback(section)`` when a new draft was generated.
        on_stream_chunk: Fired per streamed generation fragment.
        on_error: ``callback(message)`` for worker failures.
        on_busy_changed: ``callback(busy, stage_label)``.
        on_usage_update: ``callback(usage_dict)`` cumulative token usage.
        on_design_changed: Fired whenever persistable state changed (panel
            autosaves ``to_design_dict`` into the project).
    """

    def __init__(
        self,
        *,
        ai_config_fn: Callable[[], Any],
        worker_factory: Callable[..., Any] | None = None,
        validator: Callable[[dict], list] | None = None,
        settings_fn: Callable[[], Any] | None = None,
        on_chat_updated: Callable[[], None] | None = None,
        on_chat_stream_chunk: Callable[[str], None] | None = None,
        on_draft_ready: Callable[[dict], None] | None = None,
        on_stream_chunk: Callable[[str], None] | None = None,
        on_error: Callable[[str], None] | None = None,
        on_busy_changed: Callable[[bool, str], None] | None = None,
        on_usage_update: Callable[[UsageDict], None] | None = None,
        on_design_changed: Callable[[], None] | None = None,
        on_explanation: Callable[[str], None] | None = None,
        on_explanation_chunk: Callable[[str], None] | None = None,
        on_explanation_error: Callable[[str], None] | None = None,
        on_pipeline_step: Callable[[dict[str, str]], None] | None = None,
    ) -> None:
        self._ai_config_fn = ai_config_fn
        self._worker_factory = worker_factory or self._default_worker_factory
        self._validator = validator
        self._settings_fn = settings_fn
        self._on_chat_updated = on_chat_updated or (lambda: None)
        self._on_chat_stream_chunk = on_chat_stream_chunk or (lambda _t: None)
        self._on_draft_ready = on_draft_ready or (lambda _s: None)
        self._on_stream_chunk = on_stream_chunk or (lambda _t: None)
        self._on_error = on_error or (lambda _m: None)
        self._on_busy_changed = on_busy_changed or (lambda _b, _s: None)
        self._on_usage_update = on_usage_update or (lambda _u: None)
        self._on_design_changed = on_design_changed or (lambda: None)
        self._on_explanation = on_explanation or (lambda _t: None)
        self._on_explanation_chunk = on_explanation_chunk or (lambda _t: None)
        self._on_explanation_error = on_explanation_error or (lambda _m: None)
        self._on_pipeline_step = on_pipeline_step or (lambda _s: None)

        self._params: dict[str, Any] = {
            "topic": "",
            "level": "A1",
            "unit_count": 1,
            "lessons_per_unit": 3,
            "template": "mixed",
            "use_genre_batch": False,
            "extra_instructions": "",
            "dropped_bubbles": [],
            # aiEnhance P2-10: "fast" single-shot JSON vs "phased" outline→lessons
            "generation_mode": "fast",
            # aiEnhance Phase 5 (批次②): refine-pipeline step switches.
            "pipeline_skip_fix": False,
            "pipeline_skip_explain": False,
        }
        # Settings default (ai/pipeline_default_mode, 批次①) seeds the mode for
        # fresh projects; project params override it once persisted.
        if settings_fn is not None:
            default_mode = getattr(settings_fn(), "ai_pipeline_default_mode", "fast")
            if default_mode == "refine":
                self._params["generation_mode"] = "phased"
        self._design_brief = ""
        self._language = "Turkish"
        self._source_language = "Chinese"
        self._resource_pool: list[dict] = []
        self._chat: list[ChatMessage] = []
        self._draft: dict[str, Any] | None = None
        self._draft_checkpoint: dict[str, Any] | None = None
        self._explanation = ""
        self._worker: Any | None = None
        # Live pipeline snapshot (Phase 5): updated on every progress callback
        # and persisted into ``project.design`` so a cancelled refine run can
        # resume from its outline/draft after the project is reopened.
        self._pipeline_live: PipelineState | None = None
        self._usage: UsageDict = {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
        }
        # Perception U0-2: last generation's cache hit (delta of AiCache.hits).
        self._last_cache_hit: bool = False
        self._cache_hits_at_start: int = 0

    # ------------------------------------------------------------------ state
    def ai_config(self) -> Any:
        """Return the active AI config."""
        return self._ai_config_fn()

    @property
    def chat(self) -> list[ChatMessage]:
        return list(self._chat)

    @property
    def draft(self) -> dict[str, Any] | None:
        return self._draft

    @property
    def explanation(self) -> str:
        return self._explanation

    @property
    def is_busy(self) -> bool:
        return self._worker is not None

    @property
    def params(self) -> dict[str, Any]:
        return {**self._params, "design_brief": self._design_brief}

    @property
    def resource_pool(self) -> list[dict]:
        return list(self._resource_pool)

    @property
    def usage(self) -> UsageDict:
        return dict(self._usage)

    @property
    def last_cache_hit(self) -> bool:
        return bool(self._last_cache_hit)

    def set_languages(self, language: str, source_language: str) -> None:
        self._language = language or "Turkish"
        self._source_language = source_language or "Chinese"

    def set_resource_pool(self, pool: list[dict] | None) -> None:
        self._resource_pool = list(pool or [])

    def set_params(self, **kwargs: Any) -> None:
        for key, value in kwargs.items():
            if key == "design_brief":
                self._design_brief = str(value)
            elif key in self._params:
                self._params[key] = value
            elif key == "language":
                self._language = str(value)
            elif key == "source_language":
                self._source_language = str(value)
        self._on_design_changed()

    def build_spec(self) -> AiCourseSpec:
        """Assemble the generation spec, injecting pool + brief (§3.4)."""
        spec = AiCourseSpec(
            language=self._language,
            source_language=self._source_language,
            topic=self._params["topic"],
            level=self._params["level"],
            unit_count=int(self._params["unit_count"]),
            lessons_per_unit=int(self._params["lessons_per_unit"]),
            template=self._params["template"],
            use_genre_batch=bool(self._params["use_genre_batch"]),
            extra_instructions=self._params["extra_instructions"],
            resource_pool=list(self._resource_pool) or None,
            design_brief=self._design_brief,
        )
        if spec.use_genre_batch:
            # [genre] tags in topic/extra instructions steer per-unit
            # templates (mirrors the legacy dialog's _current_spec); the
            # helper returns a replaced spec when a single tag is present.
            spec = apply_genre_to_spec(spec)
        return spec

    # ------------------------------------------------------------------ chat
    def send_chat(self, text: str, attachments: list[Any] | None = None) -> bool:
        """Append a user message and request an alignment reply.

        ``attachments`` are duck-typed attachment records (``.content`` is an
        OpenAI content piece, see ``AttachmentRecord``); their content rides
        inside the user message, mirroring the legacy wish mode.
        """
        text = text.strip()
        if not text or self.is_busy:
            return False
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            self._on_error("请先在设置中配置 AI API（base_url / api_key / model）。")
            return False
        pieces = [
            getattr(att, "content", None) for att in (attachments or [])
        ]
        pieces = [p for p in pieces if isinstance(p, dict)]
        content: Any = (
            [{"type": "text", "text": text}] + pieces if pieces else text
        )
        self._chat.append(ChatMessage(role="user", content=content))
        # The topic defaults to the latest user message (mirrors the legacy
        # wish mode) so generation stays anchored to the conversation.
        self._params["topic"] = text
        self._on_chat_updated()
        self._on_design_changed()
        spec = self.build_spec()
        history = list(self._chat)
        self._start_worker(
            request_alignment_reply,
            config,
            spec,
            history,
            on_result=self._on_alignment_ready,
            on_chunk=self._on_chat_stream_chunk,
            stage="对话中…",
            **self._ai_kwargs(),
        )
        return True

    def _on_alignment_ready(self, reply: str) -> None:
        self._chat.append(ChatMessage(role="assistant", content=reply))
        self._on_chat_updated()
        self._on_design_changed()

    # ------------------------------------------------------------------ generate
    def generate(self) -> bool:
        """Generate (or revise) the draft section from params + chat."""
        if self.is_busy:
            return False
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            self._on_error("请先在设置中配置 AI API（base_url / api_key / model）。")
            return False
        # Checkpoint current draft so the author can restore after a bad regen.
        if self._draft is not None:
            self._draft_checkpoint = copy.deepcopy(self._draft)
        spec = self.build_spec()
        if self._chat:
            self._start_worker(
                generate_from_chat,
                config,
                spec,
                list(self._chat),
                self._draft,
                on_result=self._on_draft_generated,
                on_chunk=self._on_stream_chunk,
                stage="生成课程中…",
                **self._ai_kwargs(),
            )
        else:
            if not spec.topic.strip():
                self._on_error("请先填写主题，或先与 AI 对话描述课程。")
                return False
            mode = str(self._params.get("generation_mode") or "fast")
            if mode in ("phased", "refine"):
                # Phase 5 (批次②): the refine mode runs the full pipeline
                # state machine (Plan→Outline→Generate→Validate→Quality→Fix
                # →Explain→ReadyImport); fast mode keeps the single-shot path.
                skip: list[str] = []
                if self._params.get("pipeline_skip_fix"):
                    skip.append(PipelineStep.FIX)
                if self._params.get("pipeline_skip_explain"):
                    skip.append(PipelineStep.EXPLAIN)
                max_par = 1
                if self._settings_fn is not None:
                    max_par = int(
                        getattr(self._settings_fn(), "ai_max_parallel_lessons", 1)
                        or 1
                    )
                self._start_worker(
                    run_pipeline,
                    config,
                    spec,
                    mode="refine",
                    validator=self._validator or (lambda _s: []),
                    existing_section=(
                        copy.deepcopy(self._draft)
                        if isinstance(self._draft, dict)
                        else None
                    ),
                    skip_steps=tuple(skip),
                    max_fix_loops=1,
                    fill_needs_review=self._fill_needs_review(),
                    resume_state=self._pipeline_live,
                    max_retries=self._retry_max(),
                    max_parallel_lessons=max_par,
                    on_result=self._on_pipeline_done,
                    on_chunk=self._on_stream_chunk,
                    stage="精修流水线（大纲→分课→校验→质量）…",
                    **self._ai_kwargs(),
                )
                return True
            stage = "生成课程中…"
            self._start_worker(
                request_course,
                config,
                spec,
                self._validator or (lambda _s: []),
                mode=mode,
                max_retries=self._retry_max(),
                on_result=self._on_draft_generated,
                on_chunk=self._on_stream_chunk,
                stage=stage,
                **self._ai_kwargs(),
            )
        return True

    def _on_draft_generated(self, section: dict) -> None:
        if isinstance(section, dict):
            sid = section.get("id")
            if sid:
                # Deterministic structural ids keep draft iterations and
                # re-imports merge-friendly (reuses the textbook helper, §3.3).
                _rewrite_ids_deterministic(section, sid)
            self._draft = section
            self._on_draft_ready(section)
            self._on_design_changed()
            self._start_explain(section)

    def set_draft(self, section: dict | None) -> None:
        """Replace the draft (e.g. after manual JSON edits in the panel)."""
        self._draft = section
        self._on_design_changed()

    # ------------------------------------------------------------------ pipeline
    @property
    def pipeline_state(self) -> PipelineState | None:
        """Latest refine-pipeline snapshot (live or restored; None if idle)."""
        return self._pipeline_live

    def _fill_needs_review(self) -> bool:
        if self._settings_fn is None:
            return False
        return bool(getattr(self._settings_fn(), "ai_fill_needs_review", False))

    def _on_pipeline_progress(self, state: Any) -> None:
        """Handle per-step progress from ``run_pipeline`` (Phase 5 P5-2/P5-4).

        Intermediate states are kept in ``_pipeline_live`` and surfaced via
        ``on_design_changed`` so the panel's autosave persists them into the
        project draft; a cancelled run can then resume from its outline.
        Terminal states (ready_import / cancelled) finalize the run here
        because the worker drops its result when the user cancelled.
        """
        if not isinstance(state, PipelineState):
            return
        self._pipeline_live = state
        self._on_pipeline_step(dict(state.step_statuses))
        self._on_design_changed()
        if state.cancelled or state.step == PipelineStep.READY_IMPORT:
            worker = self._worker
            if worker is None:
                return
            self._worker = None
            self._on_busy_changed(False, "")
            self._finish_pipeline(state)

    def _on_pipeline_done(self, state: Any) -> None:
        """Worker result path (non-cancelled completion)."""
        if not isinstance(state, PipelineState):
            self._on_error("精修流水线返回了无法识别的结果。")
            return
        # If progress already finalized this run (cancel path), skip.
        if self._pipeline_live is state and state.step == PipelineStep.READY_IMPORT:
            return
        self._pipeline_live = state
        self._finish_pipeline(state)

    def _finish_pipeline(self, state: PipelineState) -> None:
        """Land the pipeline result: draft + explanation, or error surface.

        Import is *never* automatic (P5-6): the draft lands in the editor and
        the existing 导入 button flow (validate → target pick → merge preview)
        stays the only way into the course.
        """
        self._on_pipeline_step(dict(state.step_statuses))
        self._refresh_cache_hit_flag()
        if isinstance(state.draft, dict):
            sid = state.draft.get("id")
            if sid:
                _rewrite_ids_deterministic(state.draft, sid)
            self._draft = state.draft
            self._on_draft_ready(self._draft)
            if state.explanation:
                self._explanation = state.explanation
                self._on_explanation(self._explanation)
        if state.cancelled:
            # Graceful stop: partial outline/draft stay in _pipeline_live for
            # resume; no blocking popup (mirrors the fast-path cancel UX).
            self._on_design_changed()
            return
        if state.errors and state.draft is None:
            self._on_error("；".join(state.errors[:3]))
        elif state.errors:
            # Non-fatal step failures (e.g. fix rolled back) — draft still
            # usable; surface as explanation-channel info, not a popup.
            self._on_explanation_error("；".join(state.errors[:3]))
        # A fully-finished run clears the resume snapshot; an incomplete one
        # (errors but no draft) keeps it so the next generate() resumes.
        if state.step == PipelineStep.READY_IMPORT and not state.errors:
            self._pipeline_live = None
        self._on_design_changed()

    def restore_draft_checkpoint(self) -> bool:
        """Restore the pre-generation checkpoint if one exists."""
        if self._draft_checkpoint is None:
            return False
        self._draft = copy.deepcopy(self._draft_checkpoint)
        self._on_draft_ready(self._draft)
        self._on_design_changed()
        return True

    def regenerate_lesson(self, lesson_id: str, instruction: str | None = None) -> bool:
        """Locally regenerate one lesson inside the current draft (workshop P3)."""
        return self._regenerate_local(
            kind="lesson",
            node_id=lesson_id,
            instruction=instruction,
        )

    def regenerate_unit(self, unit_id: str, instruction: str | None = None) -> bool:
        """Locally regenerate every lesson in a unit of the current draft."""
        return self._regenerate_local(
            kind="unit",
            node_id=unit_id,
            instruction=instruction,
        )

    def _regenerate_local(
        self,
        *,
        kind: str,
        node_id: str,
        instruction: str | None,
    ) -> bool:
        if self.is_busy:
            return False
        if not isinstance(self._draft, dict):
            self._on_error("还没有草稿，请先生成课程。")
            return False
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            self._on_error("请先在设置中配置 AI API（base_url / api_key / model）。")
            return False
        self._draft_checkpoint = copy.deepcopy(self._draft)
        spec = self.build_spec()
        kwargs = self._ai_kwargs()
        # regenerate_* accept timeout/temperature via kwargs; cancel via worker.
        if kind == "lesson":
            self._start_worker(
                regenerate_lesson_in_section,
                config,
                spec,
                copy.deepcopy(self._draft),
                node_id,
                instruction,
                on_result=self._on_draft_generated,
                on_chunk=self._on_stream_chunk,
                stage=f"重生课时 {node_id}…",
                **kwargs,
            )
        else:
            self._start_worker(
                regenerate_unit_in_section,
                config,
                spec,
                copy.deepcopy(self._draft),
                node_id,
                instruction,
                on_result=self._on_draft_generated,
                on_chunk=self._on_stream_chunk,
                stage=f"重生育元 {node_id}…",
                **kwargs,
            )
        return True

    # ------------------------------------------------------------------ explain
    def _start_explain(self, section: dict) -> None:
        """Auto-chain the plain-language explanation after each draft (P-C)."""
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            return
        self._explanation = ""
        self._start_worker(
            explain_course,
            config,
            self.build_spec(),
            section,
            on_result=self._on_explain_ready,
            on_chunk=self._on_explain_chunk,
            on_error=self._on_explain_error,
            stage="通俗解释中…",
            **self._ai_kwargs(),
        )

    def _on_explain_ready(self, text: str) -> None:
        self._explanation = text or ""
        self._on_explanation(self._explanation)
        self._on_design_changed()

    def _on_explain_chunk(self, text: str) -> None:
        self._on_explanation_chunk(text)

    def _on_explain_error(self, message: str) -> None:
        # Explanation is a nice-to-have — never route to the blocking popup.
        self._on_explanation_error(message)

    # ------------------------------------------------------------------ cancel
    def cancel(self) -> None:
        if self._worker is not None:
            self._disconnect_worker(self._worker)
            if hasattr(self._worker, "cancel"):
                self._worker.cancel()

    # ------------------------------------------------------------------ worker plumbing
    def _ai_kwargs(self) -> dict[str, Any]:
        """Settings-driven worker kwargs (timeout/temperature); empty when no
        settings provider was injected (tests, defaults)."""
        if self._settings_fn is None:
            return {}
        s = self._settings_fn()
        return {
            "timeout": float(getattr(s, "ai_timeout", 120.0)),
            "temperature": float(getattr(s, "ai_temperature", 0.7)),
        }

    def _retry_max(self) -> int:
        if self._settings_fn is None:
            return 2
        return int(getattr(self._settings_fn(), "ai_retry_max", 2))

    def _start_worker(
        self,
        target: Callable,
        *args: Any,
        on_result: Callable[[Any], None],
        on_chunk: Callable[[str], None],
        stage: str,
        on_error: Callable[[str], None] | None = None,
        **worker_kwargs: Any,
    ) -> None:
        worker = self._worker_factory(target, *args, **worker_kwargs)
        self._worker = worker
        self._active_on_result = on_result
        self._active_on_chunk = on_chunk
        self._active_on_error = on_error or self._on_error
        if hasattr(worker, "result_ready"):
            worker.result_ready.connect(self._on_worker_result_ready)
        if hasattr(worker, "error_occurred"):
            worker.error_occurred.connect(self._on_worker_error_occurred)
        if hasattr(worker, "chunk_ready"):
            worker.chunk_ready.connect(self._on_worker_chunk_ready)
        if hasattr(worker, "usage_ready"):
            worker.usage_ready.connect(self._on_worker_usage_ready)
        if hasattr(worker, "progress_ready"):
            worker.progress_ready.connect(self._on_worker_progress_ready)
        self._snapshot_cache_hits()
        self._on_busy_changed(True, stage)
        worker.start()

    def _disconnect_worker(self, worker: Any) -> None:
        if worker is None:
            return
        for sig_name, slot in (
            ("result_ready", self._on_worker_result_ready),
            ("error_occurred", self._on_worker_error_occurred),
            ("chunk_ready", self._on_worker_chunk_ready),
            ("usage_ready", self._on_worker_usage_ready),
            ("progress_ready", self._on_worker_progress_ready),
        ):
            sig = getattr(worker, sig_name, None)
            if sig is not None and hasattr(sig, "disconnect"):
                try:
                    sig.disconnect(slot)
                except (AttributeError, TypeError, RuntimeError):
                    # Qt raises RuntimeError when the slot is not connected;
                    # test doubles may raise the others.
                    logger.debug("dialogs/ai/design_controller.py:_disconnect_worker safe skip", exc_info=True)

    def _on_worker_result_ready(self, result: Any) -> None:
        worker = self._worker
        cb = getattr(self, "_active_on_result", None)
        if worker is not None and cb is not None:
            self._finish_worker(worker, cb, result)

    def _on_worker_error_occurred(self, message: str) -> None:
        worker = self._worker
        cb = getattr(self, "_active_on_error", None) or self._on_error
        if worker is not None:
            self._fail_worker(worker, message, cb)

    def _on_worker_chunk_ready(self, chunk: str) -> None:
        worker = self._worker
        cb = getattr(self, "_active_on_chunk", None)
        if worker is not None and cb is not None:
            self._deliver_chunk(worker, cb, chunk)

    def _on_worker_usage_ready(self, usage: Any) -> None:
        worker = self._worker
        if worker is not None:
            self._deliver_usage(worker, usage)

    def _on_worker_progress_ready(self, progress: Any) -> None:
        worker = self._worker
        if worker is not None:
            self._deliver_progress(worker, progress)

    def _snapshot_cache_hits(self) -> None:
        """Record cache hit counter before a request (U0-2)."""
        self._last_cache_hit = False
        try:
            from src.backend.ai_cache import get_default_cache

            cache = get_default_cache()
            if cache is not None and cache.enabled:
                self._cache_hits_at_start = int(cache.stats().hits)
            else:
                self._cache_hits_at_start = 0
        except Exception:
            self._cache_hits_at_start = 0

    def _refresh_cache_hit_flag(self) -> None:
        try:
            from src.backend.ai_cache import get_default_cache

            cache = get_default_cache()
            if cache is not None and cache.enabled:
                hits = int(cache.stats().hits)
                self._last_cache_hit = hits > self._cache_hits_at_start
            else:
                self._last_cache_hit = False
        except Exception:
            self._last_cache_hit = False

    def _deliver_chunk(
        self, worker: Any, on_chunk: Callable[[str], None], chunk: str
    ) -> None:
        # Late fragments from a cancelled/superseded worker must not land in
        # the new request's stream buffer.
        if worker is self._worker:
            on_chunk(chunk)

    def _deliver_usage(self, worker: Any, usage: Any) -> None:
        if worker is self._worker:
            self._accumulate_usage(usage)

    def _deliver_progress(self, worker: Any, progress: Any) -> None:
        # Late progress from a cancelled/superseded worker must not finalize
        # or overwrite the new request's pipeline snapshot.
        if worker is self._worker:
            self._on_pipeline_progress(progress)

    def _finish_worker(
        self, worker: Any, on_result: Callable[[Any], None], result: Any
    ) -> None:
        if worker is not self._worker:
            return  # stale worker from a cancelled/superseded request
        self._disconnect_worker(worker)
        self._worker = None
        self._active_on_result = None
        self._active_on_chunk = None
        self._active_on_error = None
        self._refresh_cache_hit_flag()
        self._on_busy_changed(False, "")
        on_result(result)

    def _fail_worker(
        self, worker: Any, message: str, on_error: Callable[[str], None]
    ) -> None:
        if worker is not self._worker:
            return
        self._disconnect_worker(worker)
        self._worker = None
        self._active_on_result = None
        self._active_on_chunk = None
        self._active_on_error = None
        self._on_busy_changed(False, "")
        on_error(message)

    def _accumulate_usage(self, usage: UsageDict) -> None:
        if not isinstance(usage, dict):
            return
        for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
            self._usage[key] += int(usage.get(key, 0) or 0)
        self._on_usage_update(dict(self._usage))

    @staticmethod
    def _default_worker_factory(target: Callable, *args: Any, **kwargs: Any) -> Any:
        from src.application.ai_request_worker import AiRequestWorker

        return AiRequestWorker(target, *args, **kwargs)

    # ------------------------------------------------------------------ persistence
    def to_design_dict(self) -> dict[str, Any]:
        """Serialize into ``project.design`` (connectplan D4)."""
        data: dict[str, Any] = {
            "chat_history": [
                {
                    "role": m.role,
                    "content": _serialize_content(m.content),
                    "timestamp": m.timestamp,
                }
                for m in self._chat
            ],
            "params": {**self._params, "design_brief": self._design_brief},
            "draft_sections": [self._draft] if self._draft else [],
            "explanation": self._explanation,
        }
        # Phase 5 (P5-4): persist an incomplete pipeline snapshot so a
        # cancelled refine run resumes from its outline/draft on reopen.
        if self._pipeline_live is not None:
            snap = self._pipeline_live
            data["pipeline"] = {
                "step": snap.step,
                "mode": snap.mode,
                "outline": snap.outline,
                "skipped_steps": list(snap.skipped_steps),
                "usage_total": dict(snap.usage_total),
                "cancelled": snap.cancelled,
            }
        return data

    def apply_design_dict(self, data: dict[str, Any] | None) -> None:
        """Restore from ``project.design``; tolerates missing/partial data."""
        data = data or {}
        params = data.get("params") or {}
        for key in self._params:
            if key in params:
                self._params[key] = params[key]
        self._design_brief = params.get("design_brief", "")
        self._chat = [
            ChatMessage(
                role=m.get("role", "user"),
                content=m.get("content", ""),
                timestamp=m.get("timestamp", ""),
            )
            for m in data.get("chat_history", [])
            if isinstance(m, dict)
        ]
        drafts = data.get("draft_sections") or []
        self._draft = drafts[-1] if drafts and isinstance(drafts[-1], dict) else None
        self._explanation = data.get("explanation", "") or ""
        pipeline = data.get("pipeline")
        if isinstance(pipeline, dict) and (
            pipeline.get("outline") or pipeline.get("step")
        ):
            self._pipeline_live = PipelineState(
                step=str(pipeline.get("step") or PipelineStep.PLAN),
                mode=str(pipeline.get("mode") or "refine"),
                draft=self._draft,
                outline=pipeline.get("outline"),
                skipped_steps=list(pipeline.get("skipped_steps") or []),
                usage_total=dict(pipeline.get("usage_total") or {}),
                cancelled=bool(pipeline.get("cancelled")),
            )
            self._on_pipeline_step(dict(self._pipeline_live.step_statuses))
        else:
            self._pipeline_live = None
        self._on_chat_updated()
        if self._explanation:
            self._on_explanation(self._explanation)
        if self._draft:
            self._on_draft_ready(self._draft)
