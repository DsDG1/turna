from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_preview.client import PreviewSyncError, SshPreviewClient


class SshPreviewClientTest(unittest.TestCase):
    def test_publish_uses_ssh_runuser_and_stdin(self) -> None:
        client = SshPreviewClient()
        payload = {"preview_id": "a" * 22, "current_revision": 3}
        result = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=json.dumps(payload).encode("utf-8"), stderr=b""
        )
        with patch("subprocess.run", return_value=result) as run:
            self.assertEqual(client.publish({"id": "s", "units": []}), payload)

        command = run.call_args.args[0]
        self.assertIn("ssh", command)
        self.assertIn("turna", command)
        self.assertIn("runuser", command)
        self.assertIn("turna-preview", command)
        self.assertNotIn("shell=True", run.call_args.kwargs)
        self.assertEqual(json.loads(run.call_args.kwargs["input"]), {"id": "s", "units": []})

    def test_publish_course_uses_one_ssh_stdin_request(self) -> None:
        payload = {"course_id": "demo", "url": "https://example.test/c/demo/"}
        result = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=json.dumps(payload).encode("utf-8"), stderr=b""
        )
        bundle = {"course_id": "demo", "title": "Demo", "entries": []}
        with patch("subprocess.run", return_value=result) as run:
            self.assertEqual(SshPreviewClient().publish_course(bundle), payload)

        command = run.call_args.args[0]
        self.assertEqual(command[-1], "publish-course")
        self.assertEqual(json.loads(run.call_args.kwargs["input"]), bundle)

    def test_feedback_returns_only_dict_entries(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=json.dumps({"feedback": [{"id": "one"}, "bad"]}).encode("utf-8"),
            stderr=b"",
        )
        with patch("subprocess.run", return_value=result):
            self.assertEqual(SshPreviewClient().feedback("a" * 22), [{"id": "one"}])

    def test_nonzero_response_is_actionable(self) -> None:
        result = subprocess.CompletedProcess(args=[], returncode=2, stdout=b"", stderr=b"boom")
        with patch("subprocess.run", return_value=result), self.assertRaisesRegex(PreviewSyncError, "boom"):
            SshPreviewClient().feedback("a" * 22)

    def test_timeout_and_malformed_response_are_wrapped(self) -> None:
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("ssh", 1)), self.assertRaises(PreviewSyncError):
            SshPreviewClient().feedback("a" * 22)
        result = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"not-json", stderr=b"")
        with patch("subprocess.run", return_value=result), self.assertRaises(PreviewSyncError):
            SshPreviewClient().feedback("a" * 22)


if __name__ == "__main__":
    unittest.main()
