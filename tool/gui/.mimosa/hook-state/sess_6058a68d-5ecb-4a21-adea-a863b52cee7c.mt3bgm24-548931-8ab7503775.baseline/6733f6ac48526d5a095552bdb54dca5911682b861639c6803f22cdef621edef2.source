"""Tests for the operations log and the extended Telemetry API."""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.infrastructure.telemetry import Telemetry  # noqa: E402


class OperationsLogTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_ops_"))
        self.ops_file = self.tmp / "operations.log"
        self.tel_file = self.tmp / "telemetry.log"
        self.ops = Telemetry(self.ops_file)
        self.tel = Telemetry(self.tel_file)

    def tearDown(self) -> None:
        self.ops.close()
        self.tel.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _ops_lines(self) -> list[dict]:
        return [json.loads(l) for l in self.ops_file.read_text(encoding="utf-8").splitlines() if l.strip()]

    def test_record_action_writes_ui_event_with_target(self) -> None:
        self.ops.record_action("click", "保存", context={"window": "MainWindow"})
        data = self._ops_lines()[-1]
        self.assertEqual(data["event"], "ui.click")
        self.assertEqual(data["payload"]["target"], "保存")
        self.assertEqual(data["context"]["window"], "MainWindow")

    def test_record_action_merges_extra_payload(self) -> None:
        self.ops.record_action("input.commit", "名称", payload={"text": "hello"})
        data = self._ops_lines()[-1]
        self.assertEqual(data["event"], "ui.input.commit")
        self.assertEqual(data["payload"]["target"], "名称")
        self.assertEqual(data["payload"]["text"], "hello")

    def test_record_action_redacts_explicitly(self) -> None:
        self.ops.record_action("input.commit", "API Key", payload={"text": "<redacted>"})
        data = self._ops_lines()[-1]
        self.assertEqual(data["payload"]["text"], "<redacted>")

    def test_recent_events_filters_by_prefix(self) -> None:
        self.ops.record_action("click", "A")
        self.ops.record_duration("window.duration", 12.3, payload={"window": "W"})
        clicks = self.ops.recent_events(500, event_prefix="ui.click")
        durations = self.ops.recent_events(500, event_prefix="window.")
        self.assertEqual(len(clicks), 1)
        self.assertEqual(clicks[0]["event"], "ui.click")
        self.assertEqual(len(durations), 1)
        self.assertEqual(durations[0]["event"], "window.duration")

    def test_clear_isolates_operations_from_telemetry(self) -> None:
        self.ops.record_action("click", "A")
        self.tel.record_event("app.start")
        self.ops.clear()
        self.assertEqual(self.ops.recent_events(), [])
        self.assertEqual(len(self.tel.recent_events()), 1)

    def test_recent_events_preserves_order_newest_last(self) -> None:
        self.ops.record_action("click", "first")
        self.ops.record_action("click", "second")
        events = self.ops.recent_events()
        self.assertEqual([e["payload"]["target"] for e in events], ["first", "second"])


if __name__ == "__main__":
    unittest.main()