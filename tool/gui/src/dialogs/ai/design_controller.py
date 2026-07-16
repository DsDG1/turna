"""Pure-Python controller for grounded course design (connectplan §4.3 / P3-2).

Owns the design parameters, wish-mode chat history, and the in-flight draft;
orchestrates alignment chat + grounded generation through an injectable
worker factory. Qt-free, mirroring ``TextbookImportController``: all progress
is reported via plain callbacks so the logic is unit-testable without a
QApplication event loop.

Generation paths:
- No chat yet → one-shot ``request_course_with_retry`` (validate-and-repair).
- Chat present → ``generate_from_chat`` with the running draft fed back so the
  model revises instead of starting over.

When a resource pool is set (``set_resource_pool``), the spec is grounded:
the model must pick words from the pool and copy them verbatim (§3.4).
"""
from __future__ import annotations

from typing import Any, Callable

from src.backend.ai_generator import (
    AiCourseSpec,
    ChatMessage,
    generate_from_chat,
    request_alignment_reply,
    request_course_with_retry,
)
from src.backend.textbook_to_course import _rewrite_ids_deterministic

#: Usage dict shape: {"prompt_tokens", "completion_tokens", "total_tokens"}.
UsageDict = dict[str, int]


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
        on_chat_updated: Callable[[], None] | None = None,
        on_chat_stream_chunk: Callable[[str], None] | None = None,
        on_draft_ready: Callable[[dict], None] | None = None,
        on_stream_chunk: Callable[[str], None] | None = None,
        on_error: Callable[[str], None] | None = None,
        on_busy_changed: Callable[[bool, str], None] | None = None,
        on_usage_update: Callable[[UsageDict], None] | None = None,
        on_design_changed: Callable[[], None] | None = None,
    ) -> None:
        self._ai_config_fn = ai_config_fn
        self._worker_factory = worker_factory or self._default_worker_factory
        self._validator = validator
        self._on_chat_updated = on_chat_updated or (lambda: None)
        self._on_chat_stream_chunk = on_chat_stream_chunk or (lambda _t: None)
        self._on_draft_ready = on_draft_ready or (lambda _s: None)
        self._on_stream_chunk = on_stream_chunk or (lambda _t: None)
        self._on_error = on_error or (lambda _m: None)
        self._on_busy_changed = on_busy_changed or (lambda _b, _s: None)
        self._on_usage_update = on_usage_update or (lambda _u: None)
        self._on_design_changed = on_design_changed or (lambda: None)

        self._params: dict[str, Any] = {
            "topic": "",
            "level": "A1",
            "unit_count": 1,
            "lessons_per_unit": 3,
            "template": "mixed",
            "use_genre_batch": False,
            "extra_instructions": "",
        }
        self._design_brief = ""
        self._language = "Turkish"
        self._source_language = "Chinese"
        self._resource_pool: list[dict] = []
        self._chat: list[ChatMessage] = []
        self._draft: dict[str, Any] | None = None
        self._worker: Any | None = None
        self._usage: UsageDict = {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
        }

    # ------------------------------------------------------------------ state
    @property
    def chat(self) -> list[ChatMessage]:
        return list(self._chat)

    @property
    def draft(self) -> dict[str, Any] | None:
        return self._draft

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
        return AiCourseSpec(
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

    # ------------------------------------------------------------------ chat
    def send_chat(self, text: str) -> bool:
        """Append a user message and request an alignment reply."""
        text = text.strip()
        if not text or self.is_busy:
            return False
        config = self._ai_config_fn()
        if not getattr(config, "is_complete", False):
            self._on_error("请先在设置中配置 AI API（base_url / api_key / model）。")
            return False
        self._chat.append(ChatMessage(role="user", content=text))
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
            )
        else:
            if not spec.topic.strip():
                self._on_error("请先填写主题，或先与 AI 对话描述课程。")
                return False
            self._start_worker(
                request_course_with_retry,
                config,
                spec,
                self._validator or (lambda _s: []),
                max_retries=2,
                on_result=self._on_draft_generated,
                on_chunk=self._on_stream_chunk,
                stage="生成课程中…",
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

    def set_draft(self, section: dict | None) -> None:
        """Replace the draft (e.g. after manual JSON edits in the panel)."""
        self._draft = section
        self._on_design_changed()

    # ------------------------------------------------------------------ cancel
    def cancel(self) -> None:
        if self._worker is not None and hasattr(self._worker, "cancel"):
            self._worker.cancel()

    # ------------------------------------------------------------------ worker plumbing
    def _start_worker(
        self,
        target: Callable,
        *args: Any,
        on_result: Callable[[Any], None],
        on_chunk: Callable[[str], None],
        stage: str,
        **worker_kwargs: Any,
    ) -> None:
        worker = self._worker_factory(target, *args, **worker_kwargs)
        if hasattr(worker, "result_ready"):
            worker.result_ready.connect(
                lambda result: self._finish_worker(worker, on_result, result)
            )
        if hasattr(worker, "error_occurred"):
            worker.error_occurred.connect(
                lambda msg: self._fail_worker(worker, msg)
            )
        if hasattr(worker, "chunk_ready"):
            worker.chunk_ready.connect(on_chunk)
        if hasattr(worker, "usage_ready"):
            worker.usage_ready.connect(self._accumulate_usage)
        self._worker = worker
        self._on_busy_changed(True, stage)
        worker.start()

    def _finish_worker(
        self, worker: Any, on_result: Callable[[Any], None], result: Any
    ) -> None:
        if worker is not self._worker:
            return  # stale worker from a cancelled/superseded request
        self._worker = None
        self._on_busy_changed(False, "")
        on_result(result)

    def _fail_worker(self, worker: Any, message: str) -> None:
        if worker is not self._worker:
            return
        self._worker = None
        self._on_busy_changed(False, "")
        self._on_error(message)

    def _accumulate_usage(self, usage: UsageDict) -> None:
        if not isinstance(usage, dict):
            return
        for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
            self._usage[key] += int(usage.get(key, 0) or 0)
        self._on_usage_update(dict(self._usage))

    @staticmethod
    def _default_worker_factory(target: Callable, *args: Any, **kwargs: Any) -> Any:
        from src.dialogs.ai.worker import AiRequestWorker

        return AiRequestWorker(target, *args, **kwargs)

    # ------------------------------------------------------------------ persistence
    def to_design_dict(self) -> dict[str, Any]:
        """Serialize into ``project.design`` (connectplan D4)."""
        return {
            "chat_history": [
                {"role": m.role, "content": m.content, "timestamp": m.timestamp}
                for m in self._chat
            ],
            "params": {**self._params, "design_brief": self._design_brief},
            "draft_sections": [self._draft] if self._draft else [],
            "explanation": "",
        }

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
        self._on_chat_updated()
        if self._draft:
            self._on_draft_ready(self._draft)
