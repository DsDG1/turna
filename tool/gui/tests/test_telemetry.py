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

from src.infrastructure.telemetry import Telemetry


class TelemetryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_telemetry_"))
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
        # Real producer shape (generator_worker_hub.on_worker_usage): tokens
        # flat on the ai.usage payload — no nested "usage" dict.
        self.telemetry.record_event(
            "ai.usage",
            payload={
                "model": "deepseek-chat",
                "prompt_tokens": 1000,
                "completion_tokens": 500,
                "total_tokens": 1500,
            },
        )
        # Legacy nested shape still counts (old records on disk).
        self.telemetry.record_event(
            "ai.generate.done",
            payload={
                "success": True,
                "model": "deepseek-chat",
                "usage": {
                    "prompt_tokens": 100,
                    "completion_tokens": 50,
                    "total_tokens": 150,
                },
            },
        )
        self.telemetry.record_event(
            "ai.generate.error",
            payload={"success": False, "model": "deepseek-chat"},
        )
        summary = self.telemetry.usage_summary()
        total = summary["total"]
        self.assertEqual(total["requests"], 3)
        self.assertEqual(total["success"], 1)
        self.assertEqual(total["failure"], 1)
        self.assertEqual(total["prompt_tokens"], 1100)
        self.assertEqual(total["total_tokens"], 1650)
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


class TelemetryPathScrubbingTest(unittest.TestCase):
    """T21: an absolute path must not survive into the log."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_telemetry_"))
        self.log_file = self.tmp / "telemetry.log"
        self.telemetry = Telemetry(self.log_file)

    def tearDown(self) -> None:
        import shutil

        from src.infrastructure.telemetry import set_telemetry_enabled

        set_telemetry_enabled(True)
        self.telemetry.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _last_line(self) -> dict:
        lines = self.log_file.read_text(encoding="utf-8").strip().splitlines()
        return json.loads(lines[-1])

    def _event_lines(self) -> list[str]:
        if not self.log_file.exists():
            return []
        return [
            line
            for line in self.log_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    def test_path_key_is_reduced_to_its_tail(self) -> None:
        secret = "/home/alice/projects/turna/turkish"
        self.telemetry.record_event("repo.open.failed", payload={"path": secret})
        written = self._last_line()["payload"]["path"]
        self.assertNotIn("/home/alice", written)
        self.assertEqual(written, "turna/turkish")

    def test_home_prefix_becomes_tilde(self) -> None:
        home = str(Path.home())
        payload = {"path": f"{home}/courses/german"}
        self.telemetry.record_event("x", payload=payload)
        written = self._last_line()["payload"]["path"]
        self.assertFalse(written.startswith(home))
        self.assertTrue(written.startswith("~"))

    def test_path_valued_keys_are_scrubbed(self) -> None:
        for key in ("course_dir", "lesson_path", "file", "dir"):
            with self.subTest(key=key):
                self.telemetry.record_event("x", payload={key: "/opt/data/courses/tr"})
                written = self._last_line()["payload"][key]
                self.assertNotIn("/opt/data", written)

    def test_path_objects_are_scrubbed(self) -> None:
        self.telemetry.record_event("x", payload={"path": Path("/srv/repos/german")})
        self.assertNotIn("/srv/repos", self._last_line()["payload"]["path"])

    def test_nested_path_in_a_list_is_scrubbed(self) -> None:
        self.telemetry.record_event(
            "x", payload={"path": ["/srv/a/one", "/srv/b/two"]}
        )
        written = self._last_line()["payload"]["path"]
        self.assertEqual(written, ["a/one", "b/two"])

    def test_non_path_values_are_untouched(self) -> None:
        self.telemetry.record_event(
            "x", payload={"count": 3, "ok": True, "name": "课程 A"}
        )
        data = self._last_line()["payload"]
        self.assertEqual(data["count"], 3)
        self.assertIs(data["ok"], True)
        self.assertEqual(data["name"], "课程 A")

    def test_context_is_scrubbed_too(self) -> None:
        self.telemetry.record_event(
            "x", context={"course_dir": "/home/bob/repos/turna"}
        )
        self.assertNotIn("/home/bob", self._last_line()["context"]["course_dir"])

    def test_disabled_telemetry_writes_no_events(self) -> None:
        from src.infrastructure.telemetry import set_telemetry_enabled

        set_telemetry_enabled(False)
        self.telemetry.record_event("x", payload={"a": 1})
        self.telemetry.record_action("ui.click", "button")
        # The handler is attached in __init__, so the file may exist; what
        # must not exist is a single event line.
        self.assertEqual(self._event_lines(), [])

    def test_reenabling_resumes_writing(self) -> None:
        from src.infrastructure.telemetry import set_telemetry_enabled

        set_telemetry_enabled(False)
        self.telemetry.record_event("x", payload={"a": 1})
        set_telemetry_enabled(True)
        self.telemetry.record_event("y", payload={"a": 2})
        self.assertEqual(self._last_line()["event"], "y")


class TelemetryScrubEdgeCasesTest(unittest.TestCase):
    """Gaps found while auditing T21: paths with spaces, file:// URLs, paths
    embedded in prose, and the user-name component."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_telemetry_"))
        self.log_file = self.tmp / "telemetry.log"
        self.telemetry = Telemetry(self.log_file)

    def tearDown(self) -> None:
        import shutil

        self.telemetry.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, key: str, value) -> str:
        self.telemetry.record_event("x", payload={key: value})
        line = self.log_file.read_text(encoding="utf-8").strip().splitlines()[-1]
        return json.loads(line)["payload"][key]

    def test_windows_path_with_spaces_is_scrubbed(self) -> None:
        out = self._write("where", "C:/Users/Alice Smith/my course/turkish")
        self.assertNotIn("Alice", out)

    def test_posix_path_with_spaces_is_scrubbed(self) -> None:
        out = self._write("where", "/home/bob/My Documents/turkish")
        self.assertNotIn("bob", out)

    def test_file_url_is_scrubbed(self) -> None:
        out = self._write("where", "file:///home/bob/course.md")
        self.assertNotIn("bob", out)

    def test_path_embedded_in_prose_is_scrubbed(self) -> None:
        # An exception message is prose, but it can carry the path.
        out = self._write(
            "error", "[Errno 2] No such file: '/home/bob/course.json'"
        )
        self.assertNotIn("bob", out)
        self.assertIn("No such file", out)  # the useful part survives

    def test_user_component_under_a_home_root_is_dropped(self) -> None:
        # Keeping only the tail would keep "<user>" for a short path.
        out = self._write("path", "/home/someone/course.json")
        self.assertNotIn("someone", out)

    def test_user_component_under_users_root_is_dropped(self) -> None:
        out = self._write("path", "C:/Users/someone/notes.md")
        self.assertNotIn("someone", out)

    def test_machine_home_name_is_dropped(self) -> None:
        from pathlib import Path as _P

        home_name = _P.home().name
        if not home_name:
            self.skipTest("no home directory name")
        out = self._write("path", f"/any/root/{home_name}/turkish")
        self.assertNotIn(home_name, out)

    def test_project_and_file_still_identify_the_course(self) -> None:
        # Scrubbing must not destroy the diagnostic value.
        out = self._write("path", "/opt/data/courses/turkish")
        self.assertIn("turkish", out)

    def test_prose_without_a_path_is_untouched(self) -> None:
        out = self._write("error", "验证错误：缺少 answer 字段")
        self.assertIn("answer", out)

    def test_url_value_is_untouched(self) -> None:
        out = self._write("endpoint", "https://api.example.com/v1")
        self.assertEqual(out, "https://api.example.com/v1")

    def test_url_api_key_is_masked(self) -> None:
        out = self._write(
            "endpoint", "https://api.example.com/v1/generate?key=AIzaSySECRET123"
        )
        self.assertNotIn("AIzaSySECRET123", out)
        self.assertIn("key=***", out)
        # The URL still identifies the endpoint, which is the diagnostic part.
        self.assertIn("api.example.com", out)

    def test_url_non_secret_query_params_survive(self) -> None:
        out = self._write("endpoint", "https://x.dev/v1?model=gpt-4o&key=abc")
        self.assertIn("model=gpt-4o", out)
        self.assertIn("key=***", out)

    def test_nested_dict_is_scrubbed(self) -> None:
        # A nested structure must not be a way around the scrubber.
        self.telemetry.record_event(
            "x", payload={"outer": {"path": "/home/alice/secret/project"}}
        )
        line = self.log_file.read_text(encoding="utf-8").strip().splitlines()[-1]
        blob = line
        self.assertNotIn("/home/alice", blob)
        self.assertNotIn("alice", blob)

    def test_traceback_lines_are_scrubbed(self) -> None:
        self.telemetry.record_event(
            "x",
            payload={
                "traceback": [
                    'File "D:/program/Turna/Turna/src/app.py", line 42, in run'
                ]
            },
        )
        line = self.log_file.read_text(encoding="utf-8").strip().splitlines()[-1]
        self.assertNotIn("D:/program", line)

    def test_short_relative_path_is_untouched(self) -> None:
        out = self._write("level", "A1/A2")
        self.assertEqual(out, "A1/A2")


if __name__ == "__main__":
    unittest.main()
