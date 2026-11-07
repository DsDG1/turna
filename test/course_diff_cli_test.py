#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import cmd_diff  # type: ignore


class Args:
    def __init__(self, before: Path, after: Path) -> None:
        self.before = before
        self.after = after


class CourseContentDiffTest(unittest.TestCase):
    def test_same_id_with_edited_content_is_changed_not_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            before = Path(tmp) / "before"
            after = Path(tmp) / "after"
            source = PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish"
            shutil.copytree(source, before)
            shutil.copytree(source, after)
            vocab_path = after / "vocab.json"
            vocab = json.loads(vocab_path.read_text(encoding="utf-8"))
            vocab["words"][0]["translation"] = "土耳其语（已修订）"
            vocab_path.write_text(json.dumps(vocab, ensure_ascii=False), encoding="utf-8")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(cmd_diff(Args(before, after)), 0)
            self.assertIn("changed content (vocab): nt-w-turkce", output.getvalue())
            self.assertNotIn("unchanged (vocab)", output.getvalue())


if __name__ == "__main__":
    unittest.main()
