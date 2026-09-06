"""Unit tests for CircuitBreaker (E2.0)."""
from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.circuit_breaker import (
    CircuitBreaker,
    CircuitState,
    get_circuit_breaker,
    reset_circuit_breaker,
)


class TestCircuitBreaker(unittest.TestCase):
    def setUp(self):
        self.cb = CircuitBreaker(
            failure_threshold=3,
            reset_timeout=0.2,  # 200ms for fast test
            burst_window_seconds=1.0,
            burst_max_count=5,
        )

    def test_initial_state_closed(self):
        self.assertEqual(self.cb.state, CircuitState.CLOSED)
        allowed, reason = self.cb.can_auto_dispatch("lesson.regenerate")
        self.assertTrue(allowed)
        self.assertEqual(reason, "")

    def test_trip_to_open_after_consecutive_failures(self):
        self.assertFalse(self.cb.record_failure("test.action", "err 1"))
        self.assertEqual(self.cb.state, CircuitState.CLOSED)
        self.assertFalse(self.cb.record_failure("test.action", "err 2"))
        self.assertEqual(self.cb.state, CircuitState.CLOSED)

        # 3rd failure trips the breaker
        tripped = self.cb.record_failure("test.action", "err 3")
        self.assertTrue(tripped)
        self.assertEqual(self.cb.state, CircuitState.OPEN)

        allowed, reason = self.cb.can_auto_dispatch("test.action")
        self.assertFalse(allowed)
        self.assertIn("熔断保护生效中", reason)

    def test_half_open_transition_and_recovery(self):
        for _ in range(3):
            self.cb.record_failure("test.action", "err")
        self.assertEqual(self.cb.state, CircuitState.OPEN)

        # Fast-forward time past reset timeout
        self.cb._last_failure_time -= (self.cb._reset_timeout + 0.1)

        # In half-open, trial is allowed
        self.assertEqual(self.cb.state, CircuitState.HALF_OPEN)
        allowed, _ = self.cb.can_auto_dispatch("test.action")
        self.assertTrue(allowed)

        # Success closes the breaker
        self.cb.record_success("test.action")
        self.assertEqual(self.cb.state, CircuitState.CLOSED)

    def test_half_open_failure_retrips_immediately(self):
        for _ in range(3):
            self.cb.record_failure("test.action", "err")
        self.cb._last_failure_time -= (self.cb._reset_timeout + 0.1)
        self.assertEqual(self.cb.state, CircuitState.HALF_OPEN)

        # Failure during trial immediately re-opens
        tripped = self.cb.record_failure("test.action", "trial failed")
        self.assertTrue(tripped)
        self.assertEqual(self.cb.state, CircuitState.OPEN)

    def test_burst_rate_limit(self):
        for _ in range(5):
            self.cb.record_dispatch("test.action")

        # 6th dispatch exceeds burst limit of 5
        allowed, reason = self.cb.can_auto_dispatch("test.action")
        self.assertFalse(allowed)
        self.assertIn("频控限制", reason)

        # After window passes, allowed again (fast-forward timestamps)
        from collections import deque
        self.cb._burst_history = deque(
            t - (self.cb._burst_window_seconds + 0.1) for t in self.cb._burst_history
        )
        allowed, reason = self.cb.can_auto_dispatch("test.action")
        self.assertTrue(allowed)

    def test_manual_reset(self):
        for _ in range(3):
            self.cb.record_failure("test.action", "err")
        self.assertEqual(self.cb.state, CircuitState.OPEN)

        self.cb.reset()
        self.assertEqual(self.cb.state, CircuitState.CLOSED)
        allowed, _ = self.cb.can_auto_dispatch("test.action")
        self.assertTrue(allowed)

    def test_global_singleton(self):
        reset_circuit_breaker()
        gcb = get_circuit_breaker()
        self.assertIsInstance(gcb, CircuitBreaker)
        st = gcb.status()
        self.assertEqual(st["state"], "closed")


if __name__ == "__main__":
    unittest.main()
