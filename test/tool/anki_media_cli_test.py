#!/usr/bin/env python3
"""course_cli lint rules for the anki:// media protocol (schema-sync P0.4).

An anki://<importId>/<file> reference resolves inside the app's Anki import
directory, not the desktop repo: it must not fire the "referenced outside a
listening lesson" error nor the missing-bundled-file warning. The synthetic
ankiHtmlCard.wordId (anki-<importId>-c<cardId>) must not fire dangling-wordId
errors either.
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))

import course_cli  # noqa: E402


def _write_course(course_dir: Path, lesson: dict) -> None:
    sections = course_dir / "sections"
    sections.mkdir(parents=True)
    section = {"id": "s-1", "name": "S1", "units": [
        {"id": "u-1", "name": "U1", "lessons": [lesson]},
    ]}
    (sections / "s1.json").write_text(json.dumps(section), encoding="utf-8")
    (course_dir / "index.json").write_text(json.dumps({
        "version": 1, "language": "tr", "displayName": "T",
        "sections": [{"id": "s-1", "name": "S1", "description": "",
                      "prerequisiteSectionIds": [], "file": "sections/s1.json"}],
    }), encoding="utf-8")
    (course_dir / "vocab.json").write_text('{"words": []}', encoding="utf-8")
    (course_dir / "expressions.json").write_text('{"expressions": []}', encoding="utf-8")
    (course_dir / "grammar_points.json").write_text('{"grammarPoints": []}', encoding="utf-8")


def _run_lint(course_dir: Path) -> tuple[int, str]:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = course_cli.cmd_lint(Namespace(course_dir=course_dir, strict=False))
    return code, buf.getvalue()


class AnkiMediaLintTest(unittest.TestCase):
    def test_anki_protocol_refs_produce_no_audio_errors(self) -> None:
        lesson = {
            "id": "l-1", "name": "L1", "type": "normal", "template": "legacy",
            "content": {"stages": [{"id": "st-1", "name": "S", "items": [
                {
                    "runtimeType": "ankiCard", "id": "anki-imp1-n1-c0",
                    "front": "f", "back": "b",
                    "audioAssets": ["anki://imp1/a.mp3"],
                    "imageAssets": ["anki://imp1/i.png"],
                    "sourceNoteId": "1",
                },
                {
                    "runtimeType": "ankiHtmlCard", "id": "anki-imp1-n1-c1",
                    "frontHtml": "<b>f</b>", "backHtml": "<i>b</i>",
                    "audioAssets": ["anki://imp1/b.mp3"],
                    "wordId": "anki-imp1-c1700000001",
                },
                {
                    "runtimeType": "multipleChoice", "id": "mc-1",
                    "prompt": "p", "options": ["a", "b"], "correctIndex": 0,
                    "audioAssets": ["anki://imp1/c.mp3"],
                },
            ]}]},
        }
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            _write_course(course_dir, lesson)
            code, out = _run_lint(course_dir)
        self.assertEqual(code, 0, f"lint output:\n{out}")
        self.assertNotIn("anki://", out)
        self.assertIn("Lint passed.", out)

    def test_regular_audio_outside_listening_still_errors(self) -> None:
        lesson = {
            "id": "l-1", "name": "L1", "type": "normal", "template": "legacy",
            "content": {"stages": [{"id": "st-1", "name": "S", "items": [
                {
                    "runtimeType": "ankiCard", "id": "anki-imp1-n1-c0",
                    "front": "f", "back": "b",
                    "audioAssets": ["assets/sounds/listening/plain.mp3"],
                },
            ]}]},
        }
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            _write_course(course_dir, lesson)
            code, out = _run_lint(course_dir)
        self.assertEqual(code, 1)
        self.assertIn("referenced outside a listening lesson", out)

    def test_audio_assets_list_collected_by_manifest_builder(self) -> None:
        lesson = {
            "id": "l-1", "name": "L1", "type": "normal", "template": "listening",
            "content": {"listeningPhases": [{"id": "lp-1", "name": "P",
                                             "type": "summary", "items": [], }],
                        "stages": [{"id": "st-1", "name": "S", "items": [
                            {"runtimeType": "ankiCard", "id": "a-1", "front": "f",
                             "back": "b", "audioAssets": ["anki://imp1/x.mp3"]},
                        ]}]},
        }
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = Path(tmp)
            _write_course(course_dir, lesson)
            rows = course_cli.build_audio_manifest(course_dir)
        asset_ids = [r["asset_id"] for r in rows]
        self.assertNotIn("anki://imp1/x.mp3", asset_ids,
                         "anki:// refs must not appear as bundled-file rows")


if __name__ == "__main__":
    unittest.main()
