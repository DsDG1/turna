"""Single public entry for course generation (M2).

Callers (workshop DesignController, future CLI) should use
:func:`generate_course` instead of juggling ``request_course`` /
``run_pipeline`` / ``generate_from_chat`` directly.

Mode names:
- ``fast`` — single-shot section JSON (+ validate retry)
- ``refine`` — full pipeline (outline → lessons → validate → quality → fix → explain)
- ``phased`` — **alias** of ``refine`` (legacy UI / project params)

``EXTRACT`` is never part of the public checklist; the pipeline may mark it
skipped for forward-compat snapshots only.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, Callable, Literal

from src.backend.ai.config import AiApiConfig, AiCourseSpec, ChatMessage
from src.backend.ai.course_generate import generate_from_chat, request_course_with_retry

GenerationMode = Literal["fast", "refine"]

if TYPE_CHECKING:  # pragma: no cover
    from src.backend.ai_pipeline import PipelineState


# --- Lazy pipeline re-exports (public API surface) --------------------------
#
# ``run_pipeline`` / ``PipelineState`` / checklist constants live in
# ``src.backend.ai_pipeline``; ``request_course`` in ``src.backend.ai_phased``.
# They are re-exported here lazily (PEP 562) — never as module globals — so the
# ``ai_pipeline → ai_generator → ai package`` import cycle can never leave a
# half-imported placeholder behind, and UI callers get a single import point.
# Importing the pipeline modules directly from dialogs is blocked by the
# boundary gate (``tool/check_ai_boundaries.py --fail-dialogs-pipeline``).

_PIPELINE_EXPORTS = frozenset(
    {
        "run_pipeline",
        "PipelineState",
        "PipelineStep",
        "CHECKLIST_STEPS",
        "STATUS_PENDING",
        "STATUS_RUNNING",
        "STATUS_DONE",
        "STATUS_SKIPPED",
        "STATUS_FAILED",
    }
)


def __getattr__(name: str) -> Any:
    """Forward pipeline/phased API names lazily (PEP 562)."""
    if name in _PIPELINE_EXPORTS:
        from src.backend import ai_pipeline

        return getattr(ai_pipeline, name)
    if name == "request_course":
        from src.backend import ai_phased

        return getattr(ai_phased, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def normalize_generation_mode(mode: str | None) -> GenerationMode:
    """Map legacy / UI mode strings to ``fast`` or ``refine``.

    Accepts ``phased`` as a synonym of ``refine`` (pre-M2 combo data and
    project.design snapshots).
    """
    m = (mode or "fast").strip().lower()
    if m in ("refine", "phased"):
        return "refine"
    return "fast"


@dataclass
class PipelineOptions:
    """Options only used when ``mode=="refine"`` runs the full pipeline."""

    skip_steps: tuple[str, ...] = ()
    max_fix_loops: int = 1
    fill_needs_review: bool = False
    resume_state: PipelineState | None = None
    max_parallel_lessons: int = 1
    existing_section: dict[str, Any] | None = None
    max_retries: int = 1


@dataclass
class GenerateResult:
    """Normalized outcome of :func:`generate_course`."""

    draft: dict[str, Any] | None = None
    pipeline_state: PipelineState | None = None
    explanation: str = ""
    mode: GenerationMode = "fast"
    error: str = ""
    # Extra fields for telemetry / UI
    extras: dict[str, Any] = field(default_factory=dict)


def generate_course(
    config: AiApiConfig,
    spec: AiCourseSpec,
    *,
    mode: str = "fast",
    validator: Callable[[dict], Any] | None = None,
    chat_history: list[ChatMessage] | None = None,
    draft: dict[str, Any] | None = None,
    pipeline_options: PipelineOptions | None = None,
    timeout: float = 120.0,
    temperature: float = 0.4,
    cancel_check: Callable[[], bool] | None = None,
    on_chunk: Callable[[str], None] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    on_progress: Callable[[Any], None] | None = None,
    max_retries: int | None = None,
    fill_needs_review: bool = False,
) -> GenerateResult:
    """Generate a course section (or run the refine pipeline).

    Priority:
    1. Non-empty ``chat_history`` → multi-turn ``generate_from_chat``
       (ignores mode for the generation engine; still records mode in result).
    2. ``mode=refine`` → :func:`run_pipeline` (full checklist).
    3. ``mode=fast`` → :func:`request_course_with_retry`.

    Never writes to disk or auto-imports into a course.
    """
    norm = normalize_generation_mode(mode)
    opts = pipeline_options or PipelineOptions()

    # --- Chat / wish path ---
    if chat_history:
        section = generate_from_chat(
            config,
            spec,
            list(chat_history),
            draft_json=draft if isinstance(draft, dict) else None,
            timeout=timeout,
            temperature=temperature,
            cancel_check=cancel_check,
            on_chunk=on_chunk,
            usage_callback=usage_callback,
            validator=validator,
            max_retries=max_retries if max_retries is not None else 0,
            fill_needs_review=fill_needs_review or opts.fill_needs_review,
        )
        return GenerateResult(draft=section, mode=norm)

    # --- Refine pipeline ---
    if norm == "refine":
        from src.backend.ai_pipeline import run_pipeline

        retries = (
            max_retries
            if max_retries is not None
            else opts.max_retries
        )
        existing = opts.existing_section
        if existing is None and isinstance(draft, dict):
            existing = copy.deepcopy(draft)
        state = run_pipeline(
            config,
            spec,
            mode="refine",
            existing_section=existing,
            validator=validator,
            skip_steps=opts.skip_steps,
            max_fix_loops=opts.max_fix_loops,
            fill_needs_review=opts.fill_needs_review or fill_needs_review,
            resume_state=opts.resume_state,
            on_progress=on_progress,
            cancel_check=cancel_check,
            usage_callback=usage_callback,
            timeout=timeout,
            temperature=temperature,
            max_retries=retries,
            on_chunk=on_chunk,
            max_parallel_lessons=opts.max_parallel_lessons,
        )
        return GenerateResult(
            draft=state.draft if isinstance(state.draft, dict) else None,
            pipeline_state=state,
            explanation=str(state.explanation or ""),
            mode="refine",
        )

    # --- Fast single-shot ---
    def _noop(_s: dict) -> list:
        return []

    retries = max_retries if max_retries is not None else (1 if validator else 0)
    section = request_course_with_retry(
        config,
        spec,
        validator if validator is not None else _noop,
        timeout=timeout,
        max_retries=retries if validator is not None else 0,
        temperature=temperature,
        cancel_check=cancel_check,
        on_chunk=on_chunk,
        usage_callback=usage_callback,
        fill_needs_review=fill_needs_review or opts.fill_needs_review,
    )
    return GenerateResult(draft=section, mode="fast")
