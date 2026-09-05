"""Circuit breaker & burst failsafe for immersive full-auto apply (E2.0).

Pure Python, no Qt, thread-safe, never raises.
Protects the editor against runaway auto-apply loops and cascades of failing AI jobs.
"""
from __future__ import annotations

from collections import deque
from enum import Enum
import logging
from threading import Lock
import time
from typing import Any, Deque

logger = logging.getLogger(__name__)


class CircuitState(str, Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class CircuitBreaker:
    """Three-state circuit breaker with burst rate limiting.

    - CLOSED: Normal operation. Auto-apply proceeds.
    - OPEN: Tripped after consecutive failures. Auto-apply is blocked; falls back to manual confirm.
    - HALF_OPEN: Cooling period elapsed. Allows 1 trial execution. Success closes, failure re-opens.
    """

    def __init__(
        self,
        *,
        failure_threshold: int = 3,
        reset_timeout: float = 60.0,
        burst_window_seconds: float = 5.0,
        burst_max_count: int = 10,
    ) -> None:
        self._failure_threshold = max(1, int(failure_threshold))
        self._reset_timeout = max(0.01, float(reset_timeout))
        self._burst_window_seconds = max(0.01, float(burst_window_seconds))
        self._burst_max_count = max(1, int(burst_max_count))

        self._state: CircuitState = CircuitState.CLOSED
        self._failure_count: int = 0
        self._last_failure_time: float = 0.0
        self._last_state_change: float = time.time()
        self._burst_history: Deque[float] = deque()
        self._lock = Lock()

    @property
    def state(self) -> CircuitState:
        with self._lock:
            self._check_half_open_transition(time.time())
            return self._state

    def _check_half_open_transition(self, now: float) -> None:
        """Helper inside lock: if OPEN and timeout elapsed, transition to HALF_OPEN."""
        if self._state == CircuitState.OPEN:
            if now - self._last_failure_time >= self._reset_timeout:
                self._state = CircuitState.HALF_OPEN
                self._last_state_change = now
                logger.info(
                    "CircuitBreaker transitioned to HALF_OPEN after %.1fs cooling period",
                    self._reset_timeout,
                )

    def can_auto_dispatch(self, action_id: str = "") -> tuple[bool, str]:
        """Check if an action may proceed with auto-apply.

        Returns (True, "") if allowed, or (False, reason) if blocked by breaker or burst limit.
        Never raises.
        """
        try:
            with self._lock:
                now = time.time()
                self._check_half_open_transition(now)

                if self._state == CircuitState.OPEN:
                    remaining = max(1, int(self._reset_timeout - (now - self._last_failure_time)))
                    return (
                        False,
                        f"熔断保护生效中（OPEN）：连续失败 {self._failure_count} 次，暂停全自动应用（冷却剩余 {remaining}s）",
                    )

                # Burst rate limiting (sliding window)
                cutoff = now - self._burst_window_seconds
                while self._burst_history and self._burst_history[0] < cutoff:
                    self._burst_history.popleft()

                if len(self._burst_history) >= self._burst_max_count:
                    return (
                        False,
                        f"熔断保护频控限制：{self._burst_window_seconds:.0f}秒内自动执行达到 {len(self._burst_history)} 次上限",
                    )

                return True, ""
        except Exception as exc:
            logger.debug("CircuitBreaker.can_auto_dispatch best-effort check failed: %s", exc)
            return True, ""

    def record_dispatch(self, action_id: str = "") -> None:
        """Record an auto-dispatch attempt for burst rate limiting. Never raises."""
        try:
            with self._lock:
                self._burst_history.append(time.time())
        except Exception as exc:
            logger.debug("CircuitBreaker.record_dispatch best-effort failed: %s", exc)

    def record_success(self, action_id: str = "") -> None:
        """Record successful execution. Closes the circuit and resets failure count. Never raises."""
        try:
            with self._lock:
                prev_state = self._state
                self._failure_count = 0
                if self._state != CircuitState.CLOSED:
                    self._state = CircuitState.CLOSED
                    self._last_state_change = time.time()
                    logger.info("CircuitBreaker closed after successful execution of %s (was %s)", action_id, prev_state.value)
        except Exception as exc:
            logger.debug("CircuitBreaker.record_success best-effort failed: %s", exc)

    def record_failure(self, action_id: str = "", error: str = "") -> bool:
        """Record execution failure.

        Returns True if this failure tripped the circuit to OPEN, False otherwise.
        Never raises.
        """
        try:
            with self._lock:
                now = time.time()
                self._failure_count += 1
                self._last_failure_time = now
                tripped = False

                if self._state == CircuitState.HALF_OPEN:
                    self._state = CircuitState.OPEN
                    self._last_state_change = now
                    tripped = True
                    logger.warning(
                        "CircuitBreaker re-tripped to OPEN from HALF_OPEN on %s error: %s",
                        action_id,
                        error,
                    )
                elif self._failure_count >= self._failure_threshold:
                    if self._state != CircuitState.OPEN:
                        self._state = CircuitState.OPEN
                        self._last_state_change = now
                        tripped = True
                        logger.warning(
                            "CircuitBreaker tripped to OPEN on %s (failure count %d >= %d): %s",
                            action_id,
                            self._failure_count,
                            self._failure_threshold,
                            error,
                        )
                return tripped
        except Exception as exc:
            logger.debug("CircuitBreaker.record_failure best-effort failed: %s", exc)
            return False

    def reset(self) -> None:
        """Manually reset the breaker to CLOSED state. Never raises."""
        try:
            with self._lock:
                self._state = CircuitState.CLOSED
                self._failure_count = 0
                self._burst_history.clear()
                self._last_failure_time = 0.0
                self._last_state_change = time.time()
        except Exception as exc:
            logger.debug("CircuitBreaker.reset best-effort failed: %s", exc)

    def status(self) -> dict[str, Any]:
        """Return a snapshot of current circuit breaker state. Never raises."""
        try:
            with self._lock:
                now = time.time()
                self._check_half_open_transition(now)
                return {
                    "state": self._state.value,
                    "failure_count": self._failure_count,
                    "failure_threshold": self._failure_threshold,
                    "reset_timeout": self._reset_timeout,
                    "burst_count": len(self._burst_history),
                    "last_failure_time": self._last_failure_time,
                }
        except Exception as exc:
            logger.debug("CircuitBreaker.status best-effort failed: %s", exc)
            return {
                "state": CircuitState.CLOSED.value,
                "failure_count": 0,
                "failure_threshold": 3,
                "reset_timeout": 60.0,
                "burst_count": 0,
                "last_failure_time": 0.0,
            }


_global_breaker: CircuitBreaker | None = None
_global_lock = Lock()


def get_circuit_breaker() -> CircuitBreaker:
    """Return the application-wide singleton CircuitBreaker instance."""
    global _global_breaker
    if _global_breaker is None:
        with _global_lock:
            if _global_breaker is None:
                _global_breaker = CircuitBreaker()
    return _global_breaker


def reset_circuit_breaker() -> None:
    """Reset the application-wide singleton CircuitBreaker instance."""
    global _global_breaker
    if _global_breaker is not None:
        _global_breaker.reset()
