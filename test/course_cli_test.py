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
        self.course_dir = PROJECT_ROOT / "assets" / "courses" / "turkish"

    def test_validate_passes_for_bundled_course(self) -> None:
        args = Args(course_dir=self.course_dir)
        self.assertEqual(cmd_validate(args), 0)

    def test_lint_passes_for_bundled_course(self) -> None:
        args = Args(course_dir=self.course_dir, strict=False)
        self.assertEqual(cmd_lint(args), 0)

    def test_bundled_course_has_no_placeholder_lessons(self) -> None:
        for path in sorted((self.course_dir / "sections").glob("section*.json")):
            section = load_json(path)
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    desc = (lesson.get("description") or "").lower()
                    self.assertNotIn(
                        "placeholder",
                        desc,
                        msg=f"placeholder lesson {lesson.get('id')} in {path.name}",
                    )

    def test_bundled_course_has_listening_and_reading_per_section(self) -> None:
        for path in sorted((self.course_dir / "sections").glob("section*.json")):
            section = load_json(path)
            templates: set[str] = set()
            lesson_count = 0
            for unit in section.get("units", []):
                for lesson in unit.get("lessons", []):
                    lesson_count += 1
                    templates.add(lesson.get("template") or "legacy")
            self.assertGreaterEqual(
                lesson_count,
                4,
                msg=f"{path.name} must have multi-lesson structure",
            )
            self.assertIn("listening", templates, msg=f"{path.name} missing listening")
            self.assertIn("reading", templates, msg=f"{path.name} missing reading")

    def test_bundled_pool_is_materially_enriched(self) -> None:
        vocab = load_vocab(self.course_dir)
        expressions = load_json(self.course_dir / "expressions.json").get(
            "expressions", []
        )
        grammar = load_json(self.course_dir / "grammar_points.json").get(
            "grammarPoints", []
        )
        # Pre-goal baseline: ~30 words / 6 expressions / 0 grammar.
        self.assertGreaterEqual(len(vocab), 100)
        self.assertGreaterEqual(len(expressions), 12)
        self.assertGreaterEqual(len(grammar), 4)

    def test_validate_fails_on_dangling_word_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "turkish"
            shutil.copytree(self.course_dir, tmp_course)

            section_path = tmp_course / "sections" / "section1.json"
            section = load_json(section_path)
            # Insert a ShowWord with a dangling word id at the front of the
            # first stage. The scaffold ships an empty vocab, so any word id
            # is dangling.
            first_stage = section["units"][0]["lessons"][0]["content"]["stages"][0]
            first_stage["items"].insert(
                0,
                {"runtimeType": "showWord", "id": "sw-bad", "wordId": "w-does-not-exist"},
            )
            section_path.write_text(json.dumps(section, indent=2), encoding="utf-8")

            args = Args(course_dir=tmp_course)
            self.assertEqual(cmd_validate(args), 1)

    def test_validate_fails_on_duplicate_lesson_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "turkish"
            shutil.copytree(self.course_dir, tmp_course)

            section_path = tmp_course / "sections" / "section1.json"
            section = load_json(section_path)
            lessons = section["units"][0]["lessons"]
            # Append a second lesson that duplicates the first lesson's id.
            dup = json.loads(json.dumps(lessons[0]))
            dup["id"] = lessons[0]["id"]
            lessons.append(dup)
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
            # The Turkish course ships real greeting vocab, so the CSV has a
            # header row plus at least one data row (e.g. w-merhaba).
            lines = text.splitlines()
            self.assertGreaterEqual(len(lines), 2)
            self.assertTrue(any(line.startswith("w-merhaba,") for line in lines))

    def test_import_csv_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "turkish"
            shutil.copytree(self.course_dir, tmp_course)

            # Export existing vocab (real greeting words + header).
            export_path = Path(tmp) / "vocab.csv"
            args = Args(
                course_dir=tmp_course, type="vocab", output=str(export_path)
            )
            self.assertEqual(cmd_export_csv(args), 0)

            # Add a new row.
            text = export_path.read_text(encoding="utf-8")
            lines = text.splitlines()
            lines.append("w-new-word,New,New translation,,,noun")
            export_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

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
            self.assertEqual(by_id["w-new-word"]["term"], "New")

    def test_lint_detects_missing_audio(self) -> None:
        args = Args(course_dir=self.course_dir, strict=False)
        # Lint should succeed (warnings only) because every vocab entry lacks
        # an audioAsset, but no structural errors exist.
        self.assertEqual(cmd_lint(args), 0)

    def test_audio_manifest_lists_referenced_assets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "turkish"
            shutil.copytree(self.course_dir, tmp_course)

            # Add a listening lesson referencing a listening asset that is not
            # a word/expression id (word/expression audio is runtime TTS and
            # excluded from the manifest).
            section = {
                "id": "s-manifest",
                "name": "Manifest",
                "units": [
                    {
                        "id": "u-m",
                        "name": "M",
                        "lessons": [
                            {
                                "id": "l-listen",
                                "name": "Listen",
                                "type": "listening",
                                "prerequisiteLessonIds": [],
                                "content": {
                                    "listeningPhases": [
                                        {
                                            "id": "p-1",
                                            "name": "P1",
                                            "audioAsset": "l-pilot-dialogue",
                                            "transcript": "Merhaba",
                                        }
                                    ]
                                },
                            }
                        ],
                    }
                ],
            }
            (tmp_course / "sections" / "s-manifest.json").write_text(
                json.dumps(section, indent=2), encoding="utf-8"
            )
            (tmp_course / "index.json").write_text(
                json.dumps(
                    {"sections": [{"id": "s-manifest", "file": "sections/s-manifest.json"}]}
                ),
                encoding="utf-8",
            )

            out_path = Path(tmp) / "audio.csv"
            args = Args(course_dir=tmp_course, output=str(out_path))
            self.assertEqual(cmd_audio_manifest(args), 0)
            text = out_path.read_text(encoding="utf-8")
            self.assertIn("asset_id,type,referenced_by,status", text)
            # The listening asset is listed with type 'listening' and is
            # missing on disk (no MP3 generated yet).
            self.assertIn("l-pilot-dialogue,listening,", text)
            self.assertIn(",missing", text)
            # Word/expression ids are NOT listed (runtime TTS handles them).
            self.assertNotIn(",word,", text)
            self.assertNotIn(",expression,", text)
            self.assertNotIn(",lesson,", text)
            self.assertNotIn(",phase,", text)


if __name__ == "__main__":
    unittest.main()