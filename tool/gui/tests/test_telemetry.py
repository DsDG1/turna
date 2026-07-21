"""Tests for the structured telemetry logger."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.infrastructure.telemetry import Telemetry  # noqa: E402


class TelemetryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="varnamala_telemetry_"))
        self.log_file = self.tmp / "telemetry.log"
        self.telemetry = Telemetry(self.log_file)

    def tearDown(self) -> None:
        import shutil

        self.telemetry.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _last_line(self) -> dict:
        lines = self.log_file.read_text(encoding="utf-8").strip().splitlines()
        return json.loads(lines[-1])

    def test_record_event_writes_json(self) -> None:
        self.telemetry.record_event("app.start", payload={"x": 1})
        data = self._last_line()
        self.assertEqual(data["event"], "app.start")
        self.assertEqual(data["payload"], {"x": 1})
        self.assertIn("ts", data)

    def test_record_duration_includes_ms(self) -> None:
        self.telemetry.record_duration("repo.save", 123.456, payload={"ok": True})
        data = self._last_line()
        self.assertEqual(data["event"], "repo.save")
        self.assertEqual(data["duration_ms"], 123.456)
        self.assertEqual(data["payload"], {"ok": True})

    def test_record_error_includes_traceback(self) -> None:
        try:
            raise ValueError("boom")
        except Exception as exc:
            self.telemetry.record_error(exc, context={"action": "test"})
        data = self._last_line()
        self.assertEqual(data["event"], "app.error")
        self.assertIn("ValueError: boom", data["payload"]["exception"])
        self.assertIsInstance(data["payload"]["traceback"], list)
        self.assertEqual(data["context"], {"action": "test"})

    def test_recent_lines_returns_last_n(self) -> None:
        for i in range(5):
            self.telemetry.record_event("event", payload={"i": i})
        lines = self.telemetry.recent_lines(3)
        self.assertEqual(len(lines), 3)
        self.assertIn("\"i\": 4", lines[-1])

    def test_usage_summary_empty_when_no_log(self) -> None:
        summary = self.telemetry.usage_summary()
        self.assertEqual(summary["today"]["requests"], 0)
        self.assertEqual(summary["total"]["requests"], 0)

    def test_usage_summary_aggregates_ai_events(self) -> None:
        self.telemetry.record_event(
            "ai.generate.done",
            payload={
                "success": True,
                "model": "deepseek-chat",
                "usage": {
                    "prompt_tokens": 1000,
                    "completion_tokens": 500,
                    "total_tokens": 1500,
                },
            },
        )
        self.telemetry.record_event(
            "ai.generate.error",
            payload={"success": False, "model": "deepseek-chat"},
        )
        summary = self.telemetry.usage_summary()
        total = summary["total"]
        self.assertEqual(total["requests"], 2)
        self.assertEqual(total["success"], 1)
        self.assertEqual(total["failure"], 1)
        self.assertEqual(total["total_tokens"], 1500)
        self.assertIsNotNone(total["estimated_cost"])

    def test_clear_truncates_log(self) -> None:
        self.telemetry.record_event("app.start")
        self.telemetry.clear()
        self.assertEqual(self.log_file.read_text(encoding="utf-8"), "")

    def test_record_event_accepts_cache_stats_payload(self) -> None:
        """第三枪 批次① Step 9: ai.cache.stats events carry the AiCacheStats dict."""
        stats = {
            "hits": 3,
            "misses": 7,
            "entries": 2,
            "disk_writes": 0,
            "disk_errors": 0,
        }
        self.telemetry.record_event("ai.cache.stats", payload=stats)
        data = self._last_line()
        self.assertEqual(data["event"], "ai.cache.stats")
        self.assertEqual(data["payload"]["hits"], 3)
        self.assertEqual(data["payload"]["misses"], 7)
        # No api key or messages leak into cache stats
        self.assertNotIn("api_key", data["payload"])
        self.assertNotIn("messages", data["payload"])


if __name__ == "__main__":
    unittest.main()
