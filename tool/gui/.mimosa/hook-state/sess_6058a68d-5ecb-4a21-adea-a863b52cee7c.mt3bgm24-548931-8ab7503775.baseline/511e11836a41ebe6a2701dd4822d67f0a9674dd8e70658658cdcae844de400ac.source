"""Structured result object for textbook-import steps.

The controller returns ``ImportStepResult`` instead of raising or printing
messages, so the view can decide how to surface success / warning / error /
cancelled states.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

StepKind = Literal["pick", "parse", "chapters", "extract", "review", "import"]
Outcome = Literal["success", "warning", "error", "cancelled"]


@dataclass
class ImportStepResult:
    """Outcome of a single textbook-import step.

    Attributes:
        step: Which pipeline step produced this result.
        outcome: ``success``, ``warning``, ``error`` or ``cancelled``.
        message: Human-readable summary (kept short for UI labels).
        details: Structured extra data, e.g. validation problem list or
            outcome metadata. Callers should put lists under a key like
            ``"problems"`` rather than using a top-level list.
        recoverable: If True, the view may offer recovery actions.
        recovery_options: Short action labels like ``["重试", "跳过"]``.
    """

    step: StepKind
    outcome: Outcome
    message: str = ""
    details: dict[str, Any] = field(default_factory=dict)
    recoverable: bool = False
    recovery_options: list[str] = field(default_factory=list)

    @staticmethod
    def success(
        step: StepKind, message: str = "", details: dict[str, Any] | None = None
    ) -> "ImportStepResult":
        return ImportStepResult(
            step=step, outcome="success", message=message, details=details or {}
        )

    @staticmethod
    def error(
        step: StepKind,
        message: str,
        *,
        recoverable: bool = False,
        recovery_options: list[str] | None = None,
        details: dict[str, Any] | None = None,
    ) -> "ImportStepResult":
        return ImportStepResult(
            step=step,
            outcome="error",
            message=message,
            recoverable=recoverable,
            recovery_options=recovery_options or [],
            details=details or {},
        )

    @staticmethod
    def cancelled(step: StepKind, message: str = "已取消") -> "ImportStepResult":
        return ImportStepResult(step=step, outcome="cancelled", message=message)
