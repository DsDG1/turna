"""S-07 JobRegistry pure model tests (+ O-03 duration estimates)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.job_registry import (  # noqa: E402
    JOB_KIND_AI,
    JOB_KIND_VALIDATE,
    LEGACY_JOB_ID,
    JobRegistry,
)


class JobRegistryTest(unittest.TestCase):
    def test_start_finish_count(self) -> None:
        reg = JobRegistry()
        self.assertTrue(reg.start("a", "A", kind=JOB_KIND_AI))
        self.assertTrue(reg.start("b", "B", kind=JOB_KIND_VALIDATE))
        self.assertEqual(reg.count(), 2)
        self.assertTrue(reg.finish("a"))
        self.assertEqual(reg.count(), 1)
        self.assertFalse(reg.finish("a"))

    def test_empty_id_rejected(self) -> None:
        reg = JobRegistry()
        self.assertFalse(reg.start("", "x"))
        self.assertEqual(reg.count(), 0)

    def test_idempotent_refresh_keeps_order(self) -> None:
        reg = JobRegistry()
        reg.start("a", "A1")
        reg.start("b", "B")
        reg.start("a", "A2")  # refresh label
        self.assertEqual([j.job_id for j in reg.active()], ["a", "b"])
        self.assertEqual(reg.get("a").label, "A2")

    def test_is_busy_ai_filters(self) -> None:
        reg = JobRegistry()
        reg.start("v", "诊断", kind=JOB_KIND_VALIDATE)
        self.assertTrue(reg.is_busy())
        self.assertFalse(reg.is_busy_ai())
        reg.start("ai1", "改题", kind=JOB_KIND_AI)
        self.assertTrue(reg.is_busy_ai())

    def test_summary_line_multi(self) -> None:
        reg = JobRegistry()
        self.assertEqual(reg.summary_line(), "任务：空闲")
        reg.start("a", "清待补")
        reg.start("b", "听力")
        line = reg.summary_line()
        self.assertIn("（2）", line)
        self.assertIn("清待补", line)
        self.assertIn("听力", line)

    def test_snapshots_shape(self) -> None:
        reg = JobRegistry()
        reg.start("chip-1", "AI 改题", kind=JOB_KIND_AI, node_key="item:q1")
        snaps = reg.snapshots()
        self.assertEqual(len(snaps), 1)
        self.assertEqual(snaps[0]["job_id"], "chip-1")
        self.assertEqual(snaps[0]["node_key"], "item:q1")
        self.assertEqual(snaps[0]["kind"], JOB_KIND_AI)

    def test_clear(self) -> None:
        reg = JobRegistry()
        reg.start(LEGACY_JOB_ID, "legacy")
        reg.clear()
        self.assertEqual(reg.count(), 0)
        self.assertEqual(reg.summary_line(), "任务：空闲")

    def test_avg_duration_ms_and_estimate_suffix(self) -> None:
        reg = JobRegistry()
        with patch("src.backend.experience.job_registry.time") as t:
            t.time.side_effect = [100.0, 160.0, 200.0, 320.0]
            reg.start("j1", "清待补：正在补全词条 …", kind="ai")
            reg.finish("j1")
            reg.start("j2", "清待补：正在补全词条 …", kind="ai")
            reg.finish("j2")
        self.assertEqual(reg.avg_duration_ms("清待补：正在补全词条 …"), 90000)
        self.assertIsNone(reg.avg_duration_ms("别的"))

    def test_history_survives_clear_and_ring_capped(self) -> None:
        reg = JobRegistry()
        with patch("src.backend.experience.job_registry.time") as t:
            t.time.side_effect = [float(i) for i in range(200)]
            for i in range(25):
                reg.start(f"j{i}", "x", kind="local")
                reg.finish(f"j{i}")
        self.assertEqual(len(reg._durations["x"]), 20)
        reg.clear()
        self.assertIsNotNone(reg.avg_duration_ms("x"))


if __name__ == "__main__":
    unittest.main()
