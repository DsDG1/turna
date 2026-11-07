#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import _audio_asset_path  # type: ignore
from export_author_workspace import export_author_workspace  # type: ignore


class AuthorWorkspaceTest(unittest.TestCase):
    def test_export_contains_course_media_and_honest_missing_audio(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "workspace"
            manifest = export_author_workspace(
                PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish",
                output,
            )
            self.assertTrue((output / "course" / "index.json").is_file())
            self.assertTrue(
                (output / "assets" / "images" / "course" / "nt" / "cay.svg").is_file()
            )
            self.assertEqual(
                json.loads((output / "workspace.json").read_text(encoding="utf-8"))["format"],
                "turna-author-workspace/1",
            )
            self.assertIn("missing", {row["status"] for row in manifest["media"]})

    def test_assets_resolve_from_an_exported_workspace_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "workspace"
            export_author_workspace(
                PROJECT_ROOT / "assets" / "courses" / "nouveau-turkish",
                output,
            )
            path = _audio_asset_path(
                "assets/sounds/listening/example.mp3",
                "listening",
                output / "course",
            )
            self.assertEqual(path, output / "assets" / "sounds" / "listening" / "example.mp3")


if __name__ == "__main__":
    unittest.main()
