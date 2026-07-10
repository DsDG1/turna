#!/usr/bin/env python3
"""Unit tests for tool/course_cli.py.

Run with:
    python -m unittest discover -s test -p '*_cli_test.py'
"""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import sys

# Add project root to path so we can import the CLI module.
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from course_cli import (  # type: ignore
    cmd_audio_manifest,
    cmd_export_csv,
    cmd_import_csv,
    cmd_lint,
    cmd_validate,
    load_json,
    load_vocab,
)


class Args:
    """Lightweight namespace for CLI subcommand arguments."""

    def __init__(self, **kwargs: object) -> None:
        for key, value in kwargs.items():
            setattr(self, key, value)


class TestCourseCli(unittest.TestCase):
    def setUp(self) -> None:
        self.course_dir = PROJECT_ROOT / "assets" / "courses" / "swahili"

    def test_validate_passes_for_bundled_course(self) -> None:
        args = Args(course_dir=self.course_dir)
        self.assertEqual(cmd_validate(args), 0)

    def test_validate_fails_on_dangling_word_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "swahili"
            shutil.copytree(self.course_dir, tmp_course)

            section_path = tmp_course / "sections" / "s-test.json"
            section = load_json(section_path)
            # Replace the first ShowWord with a dangling word id.
            first_item = section["units"][0]["lessons"][0]["content"]["stages"][0][
                "items"
            ][0]
            self.assertEqual(first_item.get("runtimeType"), "showWord")
            first_item["wordId"] = "w-does-not-exist"
            section_path.write_text(json.dumps(section, indent=2), encoding="utf-8")

            args = Args(course_dir=tmp_course)
            self.assertEqual(cmd_validate(args), 1)

    def test_validate_fails_on_duplicate_lesson_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "swahili"
            shutil.copytree(self.course_dir, tmp_course)

            section_path = tmp_course / "sections" / "s-test.json"
            section = load_json(section_path)
            lessons = section["units"][0]["lessons"]
            lessons[1]["id"] = lessons[0]["id"]
            section_path.write_text(json.dumps(section, indent=2), encoding="utf-8")

            args = Args(course_dir=tmp_course)
            self.assertEqual(cmd_validate(args), 1)

    def test_export_csv_vocab(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "vocab.csv"
            args = Args(course_dir=self.course_dir, type="vocab", output=str(out_path))
            self.assertEqual(cmd_export_csv(args), 0)
            self.assertTrue(out_path.exists())
            text = out_path.read_text(encoding="utf-8")
            self.assertIn("id,term,translation,pronunciation,audioAsset,tags", text)
            self.assertIn("w-naanu,Naanu,I,,,pronoun", text)

    def test_import_csv_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "swahili"
            shutil.copytree(self.course_dir, tmp_course)

            # Export existing vocab.
            export_path = Path(tmp) / "vocab.csv"
            args = Args(
                course_dir=tmp_course, type="vocab", output=str(export_path)
            )
            self.assertEqual(cmd_export_csv(args), 0)

            # Modify a row and add a new row.
            text = export_path.read_text(encoding="utf-8")
            lines = text.splitlines()
            new_lines = []
            for line in lines:
                if line.startswith("w-naanu,"):
                    new_lines.append("w-naanu,Mimi,I,,,pronoun")
                else:
                    new_lines.append(line)
            new_lines.append("w-new-word,New,New translation,,,noun")
            export_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")

            # Import back.
            args = Args(
                course_dir=tmp_course,
                type="vocab",
                input=str(export_path),
                dry_run=False,
            )
            self.assertEqual(cmd_import_csv(args), 0)

            vocab = load_vocab(tmp_course)
            by_id = {w["id"]: w for w in vocab}
            self.assertEqual(by_id["w-naanu"]["term"], "Mimi")
            self.assertEqual(by_id["w-new-word"]["term"], "New")

    def test_lint_detects_missing_audio(self) -> None:
        args = Args(course_dir=self.course_dir, strict=False)
        # Lint should succeed (warnings only) because every vocab entry lacks
        # an audioAsset, but no structural errors exist.
        self.assertEqual(cmd_lint(args), 0)

    def test_audio_manifest_lists_referenced_assets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_path = Path(tmp) / "audio.csv"
            args = Args(course_dir=self.course_dir, output=str(out_path))
            self.assertEqual(cmd_audio_manifest(args), 0)
            text = out_path.read_text(encoding="utf-8")
            self.assertIn("asset_id,type,referenced_by,status", text)
            # At least one audio asset is referenced from a lesson.
            self.assertIn("w-howdu,lesson,", text)


if __name__ == "__main__":
    unittest.main()
