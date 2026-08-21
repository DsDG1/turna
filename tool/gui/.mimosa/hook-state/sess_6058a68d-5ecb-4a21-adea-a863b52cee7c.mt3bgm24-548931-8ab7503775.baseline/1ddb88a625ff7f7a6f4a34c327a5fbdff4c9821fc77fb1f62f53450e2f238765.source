"""SavePipeline — single orchestration for menu / palette / close save (E5-A / O-10 base).

All write-to-disk entry points should call :func:`run_save_pipeline` so Soft
Autopilot, adapter.save, and post-hooks share one order and one failure policy.

Hard rules (experienceai §6 / §9.6):
- Soft / brief failures **never** block a structurally valid save.
- Structural red (adapter validation) blocks disk write (adapter already
  rolls back memory + leaves files untouched).
- This module must **not** call close / quit / open another course (no
  recursion with closeEvent).
- UI side-effects are injected via callbacks so pure tests need no Qt.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Protocol


# Known save entry reasons (documentation / telemetry). Unknown strings are OK.
REASON_MENU = "menu"
REASON_PALETTE = "palette"
REASON_CLOSE_AUTO = "close_auto"
REASON_CLOSE_PROMPT = "close_prompt"
REASON_TEST = "test"

CLOSE_REASONS = frozenset({REASON_CLOSE_AUTO, REASON_CLOSE_PROMPT})


@dataclass(frozen=True)
class SaveRequest:
    """Inputs controlling one save attempt."""

    reason: str = REASON_MENU
    run_soft: bool = True
    """When True, invoke Soft Autopilot before adapter.save (policy still gates Soft)."""
    want_ai_brief: bool = False
    """O-10 / v4.28: optional post-save brief via ``build_brief`` (local by default)."""
    show_validation_ui: bool = True
    """When False (typical close paths), host uses modal error instead of panel."""


@dataclass
class SaveOutcome:
    """Result of one pipeline run (always returned; never raises for Soft/save)."""

    ok: bool
    message: str
    soft_count: int = 0
    errors: list[dict[str, Any]] = field(default_factory=list)
    yellow_summary: str | None = None
    soft_error: str | None = None
    reason: str = REASON_MENU
    brief: str | None = None
    blocked_reason: str | None = None

    @property
    def is_close(self) -> bool:
        return self.reason in CLOSE_REASONS


class SaveResultLike(Protocol):
    """Minimal shape of CourseAdapter.SaveResult (duck-typed for tests)."""

    ok: bool
    message: str
    errors: list


def run_save_pipeline(
    request: SaveRequest,
    *,
    do_save: Callable[[], SaveResultLike],
    apply_soft: Callable[[], int] | None = None,
    on_soft_error: Callable[[BaseException], None] | None = None,
    after_success: Callable[[SaveOutcome], None] | None = None,
    after_failure: Callable[[SaveOutcome], None] | None = None,
    on_triggered: Callable[[SaveRequest], None] | None = None,
    build_success_message: Callable[[SaveOutcome], str] | None = None,
    build_brief: Callable[[SaveOutcome], str | None] | None = None,
) -> SaveOutcome:
    """Run Soft (optional) → adapter.save → brief (optional) → hooks.

    Order is fixed. Soft / brief exceptions are reported and **do not**
    abort the save. ``do_save`` exceptions propagate (disk bugs should
    surface); Soft and brief are failure-isolated.

    The pipeline never calls close/quit and never opens modal dialogs itself.
    """
    if on_triggered is not None:
        try:
            on_triggered(request)
        except Exception:
            pass

    soft_n = 0
    soft_error: str | None = None
    if request.run_soft and apply_soft is not None:
        try:
            soft_n = int(apply_soft() or 0)
        except Exception as exc:
            soft_error = str(exc) or exc.__class__.__name__
            if on_soft_error is not None:
                try:
                    on_soft_error(exc)
                except Exception:
                    pass

    result = do_save()
    ok = bool(getattr(result, "ok", False))
    errors = list(getattr(result, "errors", None) or [])
    raw_msg = str(getattr(result, "message", "") or "")
    if ok:
        message = raw_msg or "保存成功"
        blocked = None
    else:
        message = raw_msg or "保存失败（已回滚）"
        blocked = "validation" if errors else (raw_msg or "save_failed")

    outcome = SaveOutcome(
        ok=ok,
        message=message,
        soft_count=soft_n,
        errors=errors,
        soft_error=soft_error,
        reason=str(request.reason or REASON_MENU),
        blocked_reason=blocked,
    )

    if ok:
        # O-10: optional brief after successful disk write; never blocks.
        if request.want_ai_brief and build_brief is not None:
            try:
                brief = build_brief(outcome)
                if brief:
                    outcome.brief = str(brief).strip() or None
            except Exception:
                # Brief failure must not change ok / blocked_reason.
                pass
        if build_success_message is not None:
            try:
                outcome.message = build_success_message(outcome) or outcome.message
            except Exception:
                pass
        if after_success is not None:
            after_success(outcome)
    else:
        if after_failure is not None:
            after_failure(outcome)

    return outcome


def compose_status_message(
    *,
    base: str,
    soft_count: int = 0,
    yellow_summary: str | None = None,
    brief: str | None = None,
) -> str:
    """Build the author-visible status line after a successful save."""
    msg = (yellow_summary or "").strip() or (base or "保存成功")
    if soft_count:
        msg = f"{msg} · 规则规范化 {soft_count} 项"
    b = (brief or "").strip()
    if b and b not in msg:
        msg = f"{msg} · {b}"
    return msg
