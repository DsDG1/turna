"""E4: local intent interception-rate sampling across persisted metrics events.

The per-event ``interception_rate`` math is covered by ``test_experience_metrics``
and the per-event persisted ratio by ``test_telemetry``. This module locks the
**aggregate** sampling gate (E4 「local 意图拦截率 ≥40%」): read back multiple
``experience.metrics`` events via ``Telemetry.recent_experience_metrics`` and
compute the cross-event rate with ``aggregate_interception_rate``.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience import ExperienceMetrics  # noqa: E402
from src.backend.experience.metrics import aggregate_interception_rate  # noqa: E402
from src.infrastructure.telemetry import Telemetry  # noqa: E402


def _metrics_with(resolved: int, fell: int) -> dict:
    m = ExperienceMetrics()
    for _ in range(resolved):
        m.inc_intent_resolved()
    for _ in range(fell):
        m.inc_intent_fell_through()
    return m.snapshot()


class AggregateHelperTest(unittest.TestCase):
    """Pure aggregate math (no telemetry / no Qt)."""

    def test_empty_and_missing_buckets(self) -> None:
        self.assertIsNone(aggregate_interception_rate([]))
        self.assertIsNone(aggregate_interception_rate(None))
        self.assertIsNone(aggregate_interception_rate([{}, {"payload": {}}]))
        self.assertIsNone(
            aggregate_interception_rate(
                [{"payload": {"metrics": {"intent": {}}}}]
            )
        )

    def test_sums_across_events(self) -> None:
        events = [
            {"payload": {"metrics": {"intent": {"resolved": 3, "fell_through": 1}}}},
            {"payload": {"metrics": {"intent": {"resolved": 1, "fell_through": 1}}}},
        ]
        # (3+1) resolved / (3+1+1+1) total = 4/6
        self.assertAlmostEqual(aggregate_interception_rate(events), 4 / 6)

    def test_never_raises_on_garbage(self) -> None:
        events = [
            "not-a-dict",
            {"payload": "x"},
            {"payload": {"metrics": {"intent": {"resolved": "bad"}}}},
            {"payload": {"metrics": {"intent": {"resolved": 2, "fell_through": 0}}}},
        ]
        self.assertAlmostEqual(aggregate_interception_rate(events), 1.0)

    def test_threshold_discrimination(self) -> None:
        above = [
            {"payload": {"metrics": {"intent": {"resolved": 2, "fell_through": 1}}}}
        ]
        below = [
            {"payload": {"metrics": {"intent": {"resolved": 1, "fell_through": 3}}}}
        ]
        self.assertGreaterEqual(aggregate_interception_rate(above), 0.40)
        self.assertLess(aggregate_interception_rate(below), 0.40)


class TelemetrySamplingTest(unittest.TestCase):
    """Read back multiple persisted events and aggregate (E4 sampling gate)."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_intercept_"))
        self.log_file = self.tmp / "telemetry.log"
        self.telemetry = Telemetry(self.log_file)
        self.telemetry.start_session()

    def tearDown(self) -> None:
        import shutil

        self.telemetry.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_aggregate_over_recent_events(self) -> None:
        # Session 1: 3 resolved / 1 fell; Session 2: 1 resolved / 1 fell.
        self.telemetry.record_experience_metrics(
            _metrics_with(3, 1), reason="close_course"
        )
        self.telemetry.record_experience_metrics(
            _metrics_with(1, 1), reason="app_close"
        )
        events = self.telemetry.recent_experience_metrics(20)
        self.assertEqual(len(events), 2)
        rate = aggregate_interception_rate(events)
        self.assertIsNotNone(rate)
        assert rate is not None
        self.assertAlmostEqual(rate, 4 / 6)
        # E4 target: this sample clears the 40% gate.
        self.assertGreaterEqual(rate, 0.40)

    def test_aggregate_below_gate_detectable(self) -> None:
        self.telemetry.record_experience_metrics(
            _metrics_with(1, 4), reason="close_course"
        )
        events = self.telemetry.recent_experience_metrics(20)
        rate = aggregate_interception_rate(events)
        self.assertIsNotNone(rate)
        assert rate is not None
        self.assertLess(rate, 0.40)

    def test_no_intent_events_returns_none(self) -> None:
        # record a metrics event with no intent counters (ambient only)
        m = ExperienceMetrics()
        m.inc_ambient("shown")
        self.telemetry.record_experience_metrics(m.snapshot(), reason="manual")
        events = self.telemetry.recent_experience_metrics(20)
        self.assertIsNone(aggregate_interception_rate(events))


if __name__ == "__main__":
    unittest.main()
