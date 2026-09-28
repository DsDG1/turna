"""Tests for git credential redaction in diagnostics."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.backend.git_library import _redact_secrets


class RedactSecretsTest(unittest.TestCase):
    def test_pasted_remote_with_token_is_masked(self) -> None:
        out = _redact_secrets("git clone -- https://alice:ghp_abc123@github.com/o/r.git failed")
        self.assertNotIn("ghp_abc123", out)
        self.assertNotIn("alice", out)
        self.assertIn("github.com/o/r.git", out)

    def test_git_stderr_echo_is_masked(self) -> None:
        err = "fatal: unable to access 'https://bot:glpat-XYZ@gitlab.com/g/p.git/': 403"
        out = _redact_secrets(err)
        self.assertNotIn("glpat-XYZ", out)
        self.assertIn("403", out)

    def test_token_without_username_is_masked(self) -> None:
        out = _redact_secrets("https://ghp_onlytoken@github.com/o/r.git")
        self.assertNotIn("ghp_onlytoken", out)

    def test_ssh_form_is_untouched(self) -> None:
        s = "git@github.com:owner/repo.git"
        self.assertEqual(_redact_secrets(s), s)

    def test_plain_text_is_untouched(self) -> None:
        s = "fatal: could not read from remote repository"
        self.assertEqual(_redact_secrets(s), s)

    def test_empty_is_safe(self) -> None:
        self.assertEqual(_redact_secrets(""), "")

    def test_multiple_urls_all_masked(self) -> None:
        out = _redact_secrets(
            "a https://u1:p1@h1/x b https://u2:p2@h2/y c"
        )
        for secret in ("p1", "p2", "u1", "u2"):
            self.assertNotIn(secret, out)
        self.assertIn("h1/x", out)
        self.assertIn("h2/y", out)


if __name__ == "__main__":
    unittest.main()
