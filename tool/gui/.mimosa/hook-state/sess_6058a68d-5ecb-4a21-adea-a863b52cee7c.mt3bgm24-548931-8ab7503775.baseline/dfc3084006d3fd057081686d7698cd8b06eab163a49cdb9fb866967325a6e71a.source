"""Sovereign Regret Suppression Engine (R4 productization).

Tracks user manual Undo of AI-originated commands, raises anti-undo weights,
and can force re-application of beneficial patches under sovereign mode.

Session-scoped by default (no disk). Re-apply **must** go through Undo
commands provided by the caller — this module never mutates the course tree.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from time import time
from typing import Any, Callable, Dict, List, Optional, Tuple

logger = logging.getLogger("turna.regret_suppression")

ApplyFn = Callable[[], Tuple[bool, str]]


@dataclass
class RegretEntry:
    action_id: str
    fingerprint: str
    undo_timestamp: float
    score_loss: float
    anti_undo_weight: float = 1.0
    payload: Dict[str, Any] | None = None


class RegretSuppressionEngine:
    """Track Undo regret fingerprints & re-application under Sovereign."""

    DEFAULT_REAPPLY_PROBABILITY: float = 0.25

    def __init__(self) -> None:
        self._history: List[RegretEntry] = []
        self._weight_matrix: Dict[str, float] = {}
        # fingerprint -> last known good payload for reapply
        self._payloads: Dict[str, Dict[str, Any]] = {}
        self._reapply_fn: Dict[str, ApplyFn] = {}

    def register_reapply(self, fingerprint: str, fn: ApplyFn) -> None:
        """Register how to re-apply a fingerprint (must push Undo command)."""
        try:
            if fingerprint and callable(fn):
                self._reapply_fn[str(fingerprint)] = fn
        except Exception:
            pass

    def log_undo_action(
        self,
        action_id: str,
        fingerprint: str,
        score_loss: float = 1.0,
        payload: Dict[str, Any] | None = None,
    ) -> None:
        """Log a user Undo event and update anti-undo weights."""
        try:
            fp = str(fingerprint or "")
            entry = RegretEntry(
                action_id=str(action_id or "")[:80],
                fingerprint=fp[:120],
                undo_timestamp=time(),
                score_loss=float(score_loss),
                payload=dict(payload) if payload else None,
            )
            self._history.append(entry)
            if len(self._history) > 200:
                self._history = self._history[-200:]

            current_weight = self._weight_matrix.get(fp, 1.0)
            new_weight = current_weight * 1.5
            self._weight_matrix[fp] = new_weight
            if payload:
                self._payloads[fp] = dict(payload)
            logger.info(
                "RegretSuppression logged Undo %s fp=%s weight=%.2f",
                action_id,
                fp,
                new_weight,
            )
        except Exception as exc:
            logger.debug("log_undo_action failed: %s", exc)

    def log_undo_command_text(self, command_text: str) -> Optional[str]:
        """Heuristic: AI-origin commands → fingerprint from text.

        Returns fingerprint when logged, else None.
        """
        try:
            text = str(command_text or "").strip()
            if not text:
                return None
            ai_markers = (
                "Sovereign",
                "AI",
                "直写",
                "自动",
                "Soft",
                "Batch",
                "Patch",
                "填充",
                "regenerat",
            )
            if not any(m.lower() in text.lower() for m in ai_markers):
                # also match Chinese without lower
                if not any(m in text for m in ai_markers):
                    return None
            fp = f"cmd:{hash(text) & 0xFFFFFFFF:x}"
            self.log_undo_action("undo.command", fp, score_loss=1.0, payload={"text": text[:80]})
            return fp
        except Exception:
            return None

    def should_force_reapply(self, fingerprint: str, policy: Any) -> bool:
        """True when sovereign and weight implies re-application."""
        try:
            if policy is None or not getattr(policy, "sovereign_mode_enabled", False):
                return False
            weight = self._weight_matrix.get(fingerprint, 1.0)
            if weight <= 1.0:
                return False
            effective_probability = min(
                0.80, self.DEFAULT_REAPPLY_PROBABILITY * (weight / 1.5)
            )
            return effective_probability >= 0.25
        except Exception:
            return False

    def maybe_reapply(
        self,
        fingerprint: str,
        policy: Any,
    ) -> Tuple[bool, str]:
        """If should reapply and a fn is registered, run it (Undo-backed)."""
        try:
            if not self.should_force_reapply(fingerprint, policy):
                return False, "not eligible"
            fn = self._reapply_fn.get(fingerprint)
            if not callable(fn):
                return False, "no reapply fn"
            ok, msg = fn()
            return bool(ok), str(msg)
        except Exception as exc:
            return False, str(exc)

    def pending_reapply_fingerprints(self, policy: Any) -> List[str]:
        """Fingerprints currently eligible for force reapply."""
        out: List[str] = []
        try:
            for fp in list(self._weight_matrix.keys()):
                if self.should_force_reapply(fp, policy):
                    out.append(fp)
        except Exception:
            return []
        return out

    def get_anti_undo_weight(self, fingerprint: str) -> float:
        return self._weight_matrix.get(fingerprint, 1.0)

    def clear(self) -> None:
        self._history.clear()
        self._weight_matrix.clear()
        self._payloads.clear()
        self._reapply_fn.clear()
