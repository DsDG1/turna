"""Lightweight generation pipeline state machine (aiEnhance Phase 5 / P5-1..6).

State machine::

    Plan → Extract?(optional) → Outline → Generate(units/lessons)
      → Validate → QualityScore → Fix(loop≤N) → Explain → ReadyImport

Design rules (§1.3 / §7):

- Pure Python, no Qt. The workshop wires it via ``DesignController``.
- Reuses existing components instead of forking logic: generation goes
  through ``ai_generator.generate_with_validate_loop`` (fast path) and
  ``ai_phased`` outline → per-lesson fill (refine path); validation goes
  through the caller-supplied ``CourseAdapter`` validator; quality scoring
  through ``content_quality.score_section``; the Fix step applies rule-based
  repairs first (``_normalize_resources`` / ``_auto_fix_resources``, both
  id-preserving) and only feeds *remaining* errors to the LLM corrector.
- Never auto-imports or writes to disk: the machine stops at
  ``READY_IMPORT`` and hands the draft back to the existing import flow
  (diff/merge preview + human confirmation).
- ``mode="fast"`` degrades to the current single-shot path (generate with
  validate loop + validate + quality) sharing the same components.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass, field
from typing import Any, Callable, Literal

from src.backend.ai_fixer import build_correction_prompt
from src.backend.ai import (
    AiApiConfig,
    AiCancelled,
    AiCourseSpec,
    auto_fix_resources,
    coerce_problem_messages,
    explain_course,
    normalize_resources,
    request_correction,
    request_course_with_retry,
    structural_diff,
)
from src.backend.ai_phased import fill_lessons_from_outline, request_outline
from src.backend.content_quality import score_section


class PipelineStep:
    """Step ids of the generation pipeline (string constants for JSON safety)."""

    PLAN = "plan"
    EXTRACT = "extract"
    OUTLINE = "outline"
    GENERATE = "generate"
    VALIDATE = "validate"
    QUALITY = "quality"
    FIX = "fix"
    EXPLAIN = "explain"
    READY_IMPORT = "ready_import"


#: Full machine order (Extract included for forward-compat with Phase 4; it is
#: skipped unless the workshop supplies extracted knowledge upstream).
PIPELINE_STEPS: tuple[str, ...] = (
    PipelineStep.PLAN,
    PipelineStep.EXTRACT,
    PipelineStep.OUTLINE,
    PipelineStep.GENERATE,
    PipelineStep.VALIDATE,
    PipelineStep.QUALITY,
    PipelineStep.FIX,
    PipelineStep.EXPLAIN,
    PipelineStep.READY_IMPORT,
)

#: Steps rendered by the workshop checklist (Extract omitted: optional and
#: currently always skipped; ReadyImport is the terminal marker).
CHECKLIST_STEPS: tuple[str, ...] = (
    PipelineStep.PLAN,
    PipelineStep.OUTLINE,
    PipelineStep.GENERATE,
    PipelineStep.VALIDATE,
    PipelineStep.QUALITY,
    PipelineStep.FIX,
    PipelineStep.EXPLAIN,
)

#: Step status values for the UI checklist.
STATUS_PENDING = "pending"
STATUS_RUNNING = "running"
STATUS_DONE = "done"
STATUS_SKIPPED = "skipped"
STATUS_FAILED = "failed"

_USAGE_KEYS = ("prompt_tokens", "completion_tokens", "total_tokens")


@dataclass
class PipelineState:
    """Mutable pipeline snapshot; serialisable enough for project drafts."""

    step: str = PipelineStep.PLAN
    mode: str = "refine"
    draft: dict[str, Any] | None = None
    outline: dict[str, Any] | None = None
    problems: list[dict[str, Any]] = field(default_factory=list)
    quality: dict[str, Any] | None = None
    explanation: str = ""
    usage_total: dict[str, int] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    skipped_steps: list[str] = field(default_factory=list)
    #: step id -> pending/running/done/skipped/failed (checklist rendering).
    step_statuses: dict[str, str] = field(default_factory=dict)
    cancelled: bool = False

    @property
    def ready_for_import(self) -> bool:
        return self.step == PipelineStep.READY_IMPORT and self.draft is not None

    def status_of(self, step: str) -> str:
        return self.step_statuses.get(step, STATUS_PENDING)


def _error_problems(problems: list[Any]) -> list[dict[str, Any]]:
    """Keep only error-level problems as dicts (warnings never block)."""
    out: list[dict[str, Any]] = []
    for p in problems or []:
        if isinstance(p, dict):
            if p.get("level", "error") != "error":
                continue
            out.append(p)
        elif p:
            out.append({"level": "error", "message": str(p)})
    return out


def run_pipeline(
    config: AiApiConfig,
    spec: AiCourseSpec,
    *,
    mode: Literal["fast", "refine"] = "refine",
    existing_section: dict[str, Any] | None = None,
    validator: Callable[[dict], list] | None = None,
    skip_steps: tuple[str, ...] | list[str] = (),
    max_fix_loops: int = 1,
    fill_needs_review: bool = False,
    resume_state: PipelineState | None = None,
    on_progress: Callable[[PipelineState], None] | None = None,
    cancel_check: Callable[[], bool] | None = None,
    usage_callback: Callable[[dict[str, int]], None] | None = None,
    timeout: float = 120.0,
    temperature: float = 0.4,
    max_retries: int = 1,
    on_chunk: Callable[[str], None] | None = None,
    max_parallel_lessons: int = 1,
) -> PipelineState:
    """Run the generation pipeline and return the final ``PipelineState``.

    Args:
        mode: ``fast`` = single-shot generate+validate loop (skips Outline and
            Fix); ``refine`` = outline → per-lesson fill → validate → quality
            → fix loop → explain.
        validator: ``(section_json) -> list[dict|str]``; typically
            ``CourseAdapter.validate_section_json``. ``None`` means the
            Validate step reports no problems and Fix has nothing to chew on.
        skip_steps: step ids to skip (typically ``fix`` / ``explain``).
        max_fix_loops: upper bound of LLM correction rounds in the Fix step.
        resume_state: snapshot from a previous (e.g. cancelled) run; a stored
            outline/draft is reused so the pipeline continues where it stopped.
        on_progress: called after every step status change.
        cancel_check: cooperative cancellation; the machine stops gracefully
            at the current step, records it, and returns the partial state.
        usage_callback: per-request token usage; accumulated into
            ``state.usage_total`` in addition to being forwarded.
    """
    mode = "refine" if mode == "refine" else "fast"
    skip = set(skip_steps or ())
    state = PipelineState(mode=mode)
    state.step_statuses = {s: STATUS_PENDING for s in PIPELINE_STEPS}

    # --- Resume: reuse a stored outline/draft from a previous run. ---
    if resume_state is not None:
        if resume_state.outline and mode == "refine":
            state.outline = copy.deepcopy(resume_state.outline)
            state.step_statuses[PipelineStep.PLAN] = STATUS_DONE
            state.step_statuses[PipelineStep.OUTLINE] = STATUS_DONE
        if resume_state.draft:
            state.draft = copy.deepcopy(resume_state.draft)
            state.step_statuses[PipelineStep.GENERATE] = STATUS_DONE
        for key in _USAGE_KEYS:
            state.usage_total[key] = int(resume_state.usage_total.get(key, 0) or 0)

    def _usage(usage: dict[str, int]) -> None:
        if isinstance(usage, dict):
            for key in _USAGE_KEYS:
                state.usage_total[key] = state.usage_total.get(key, 0) + int(
                    usage.get(key, 0) or 0
                )
        if usage_callback:
            usage_callback(usage)

    def _progress() -> None:
        if on_progress:
            on_progress(state)

    def _cancelled() -> bool:
        return bool(cancel_check and cancel_check())

    def _skip(step: str) -> None:
        state.step_statuses[step] = STATUS_SKIPPED
        if step not in state.skipped_steps:
            state.skipped_steps.append(step)
        _progress()

    def _run(step: str, fn: Callable[[], None]) -> bool:
        """Run one step with cancel/error plumbing; False stops the machine."""
        if _cancelled():
            state.cancelled = True
            state.step = step
            state.errors.append("请求已取消。")
            state.step_statuses[step] = STATUS_FAILED
            _progress()
            return False
        state.step = step
        if state.step_statuses.get(step) == STATUS_DONE:
            # Restored from resume_state; nothing to do.
            _progress()
            return True
        state.step_statuses[step] = STATUS_RUNNING
        _progress()
        try:
            fn()
        except AiCancelled:
            state.cancelled = True
            state.errors.append("请求已取消。")
            state.step_statuses[step] = STATUS_FAILED
            _progress()
            return False
        except Exception as exc:  # noqa: BLE001 — pipeline records, UI decides
            state.errors.append(f"{step}: {exc}")
            state.step_statuses[step] = STATUS_FAILED
            _progress()
            return False
        state.step_statuses[step] = STATUS_DONE
        _progress()
        return True

    # ------------------------------------------------------------------ Plan
    def _plan() -> None:
        # Pure bookkeeping: what the machine is about to do. Extraction is a
        # workshop knowledge-stage concern (Phase 4), so it is skipped here.
        state.step_statuses[PipelineStep.EXTRACT] = STATUS_SKIPPED
        if PipelineStep.EXTRACT not in state.skipped_steps:
            state.skipped_steps.append(PipelineStep.EXTRACT)

    if not _run(PipelineStep.PLAN, _plan):
        return state

    # ------------------------------------------------------------------ Outline
    if mode == "fast" or PipelineStep.OUTLINE in skip:
        _skip(PipelineStep.OUTLINE)
    else:
        def _outline() -> None:
            state.outline = request_outline(
                config,
                spec,
                timeout=timeout,
                temperature=min(temperature, 0.35),
                max_retries=max_retries,
                cancel_check=cancel_check,
                usage_callback=_usage,
            )

        if not _run(PipelineStep.OUTLINE, _outline):
            return state

    # ------------------------------------------------------------------ Generate
    def _generate() -> None:
        if mode == "fast" or state.outline is None:
            # Fast path: single-shot generate + validate retry loop (现状).
            def _noop(_s: dict) -> list:
                return []

            state.draft = request_course_with_retry(
                config,
                spec,
                validator if validator is not None else _noop,
                timeout=timeout,
                max_retries=max_retries if validator is not None else 0,
                temperature=temperature,
                cancel_check=cancel_check,
                on_chunk=on_chunk,
                usage_callback=_usage,
            )
        else:
            state.draft = fill_lessons_from_outline(
                config,
                spec,
                state.outline,
                timeout=timeout,
                temperature=temperature,
                cancel_check=cancel_check,
                usage_callback=_usage,
                on_lesson_done=(lambda _lid, _i, _n: _progress()),
                max_parallel=max(1, min(8, int(max_parallel_lessons or 1))),
            )

    if not _run(PipelineStep.GENERATE, _generate):
        return state

    # ------------------------------------------------------------------ Validate
    def _validate() -> None:
        problems = list(validator(state.draft) or []) if validator else []
        state.problems = problems

    if not _run(PipelineStep.VALIDATE, _validate):
        return state

    # ------------------------------------------------------------------ Quality
    def _quality() -> None:
        report = score_section(
            state.draft,
            level=spec.level,
            resource_pool=spec.resource_pool,
            structural_errors=coerce_problem_messages(_error_problems(state.problems)),
        )
        state.quality = {
            "scores": dict(report.scores),
            "mean": report.mean,
            "badge": report.badge(),
            "error_count": report.error_count,
            "warning_count": report.warning_count,
        }

    if not _run(PipelineStep.QUALITY, _quality):
        return state

    # ------------------------------------------------------------------ Fix
    if PipelineStep.FIX in skip or (mode == "fast" and not _error_problems(state.problems)):
        _skip(PipelineStep.FIX)
    else:
        def _fix() -> None:
            _fix_step(
                config,
                spec,
                state,
                validator,
                existing_section=existing_section,
                max_fix_loops=max_fix_loops,
                fill_needs_review=fill_needs_review,
                cancel_check=cancel_check,
                usage=_usage,
                timeout=timeout,
            )

        # Fix failures are non-fatal: keep the (rule-fixed) draft and continue.
        if not _run(PipelineStep.FIX, _fix):
            if state.cancelled:
                return state

    # ------------------------------------------------------------------ Explain
    if PipelineStep.EXPLAIN in skip:
        _skip(PipelineStep.EXPLAIN)
    else:
        def _explain() -> None:
            state.explanation = explain_course(
                config,
                spec,
                state.draft,
                timeout=timeout,
                cancel_check=cancel_check,
                usage_callback=_usage,
            )

        # Explanation is a nice-to-have: a failure must not kill the draft.
        if not _run(PipelineStep.EXPLAIN, _explain):
            if state.cancelled:
                return state

    # ------------------------------------------------------------------ ReadyImport
    state.step = PipelineStep.READY_IMPORT
    state.step_statuses[PipelineStep.READY_IMPORT] = (
        STATUS_DONE if state.draft is not None else STATUS_FAILED
    )
    _progress()
    return state


def _fix_step(
    config: AiApiConfig,
    spec: AiCourseSpec,
    state: PipelineState,
    validator: Callable[[dict], list] | None,
    *,
    existing_section: dict[str, Any] | None,
    max_fix_loops: int,
    fill_needs_review: bool,
    cancel_check: Callable[[], bool] | None,
    usage: Callable[[dict[str, int]], None],
    timeout: float,
) -> None:
    """Rule-based repairs first; LLM correction only for remaining errors.

    Id preservation (§1.3.3): rule fixes never remove ids (they only add
    stub entries / normalize fields); an LLM fix that would drop ids present
    in ``existing_section`` (or the pre-fix draft) is rolled back.
    """
    draft = state.draft
    if not isinstance(draft, dict):
        return

    # --- Rule-based pass (no LLM): normalize + dangling-ref stubs. ---
    normalize_resources(draft)
    auto_fix_resources(draft)

    if fill_needs_review:
        from src.backend.ai import fill_needs_review_resources

        draft = fill_needs_review_resources(
            config,
            draft,
            language=spec.language,
            source_language=spec.source_language,
            timeout=min(timeout, 90.0),
            cancel_check=cancel_check,
            usage_callback=usage,
        )
        state.draft = draft

    problems = _error_problems(list(validator(draft) or []) if validator else [])

    # --- LLM loop: only the remaining errors are fed to the corrector. ---
    loops = 0
    while problems and loops < max(0, max_fix_loops):
        if cancel_check and cancel_check():
            raise AiCancelled("请求已取消。")
        loops += 1
        prompt = build_correction_prompt(
            problems,
            draft,
            {
                "language": spec.language,
                "source_language": spec.source_language,
                "node_kind": "section",
            },
        )
        fixed = request_correction(
            config,
            prompt,
            timeout=timeout,
            cancel_check=cancel_check,
            usage_callback=usage,
        )
        if not isinstance(fixed, dict) or "units" not in fixed:
            state.errors.append("fix: 修正结果不是有效的 section，已保留原稿。")
            break
        # Id-preservation guard: a fix that silently drops existing unit /
        # lesson / resource ids is rejected and the pre-fix draft kept.
        base = existing_section if isinstance(existing_section, dict) else draft
        diff = structural_diff(base, fixed)
        removed = {k: sorted(v) for k, v in diff.items() if v}
        if removed:
            state.errors.append(f"fix: 修正试图删除既有 id（{removed}），已回滚。")
            break
        normalize_resources(fixed)
        auto_fix_resources(fixed)
        draft = fixed
        state.draft = draft
        problems = _error_problems(list(validator(draft) or []) if validator else [])

    state.problems = list(validator(draft) or []) if validator else []


__all__ = [
    "CHECKLIST_STEPS",
    "PIPELINE_STEPS",
    "PipelineState",
    "PipelineStep",
    "STATUS_DONE",
    "STATUS_FAILED",
    "STATUS_PENDING",
    "STATUS_RUNNING",
    "STATUS_SKIPPED",
    "run_pipeline",
]
