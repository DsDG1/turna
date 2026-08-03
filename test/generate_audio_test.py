#!/usr/bin/env python3
"""Unit tests for tool/generate_audio.py.

Run with:
    python -m unittest discover -s test -p '*_audio_test.py'
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from generate_audio import (  # type: ignore
    AudioEntry,
    COURSE_DIR,
    SOUNDS_DIR,
    MiniMaxBackend,
    cmd_all,
    collect_entries,
    generate_entry,
    listening_asset_path,
    target_path_for,
)


def _write_listening_course(tmp_course: Path, phases: list[dict]) -> None:
    """Write a minimal course with one listening lesson containing `phases."""
    src_course = PROJECT_ROOT / "assets" / "courses" / "turkish"
    shutil.copytree(src_course, tmp_course)
    # Seed a vocab entry so word-id exclusion (audioAsset == a vocab id) is
    # exercised — the scaffold ships an empty vocab by design.
    (tmp_course / "vocab.json").write_text(
        json.dumps(
            {"version": 1, "language": "tr", "words": [{"id": "w-mimi", "term": "Mimi"}]},
        ),
        encoding="utf-8",
    )
    section = {
        "id": "s-test",
        "name": "Test",
        "units": [
            {
                "id": "u-test",
                "name": "Test",
                "lessons": [
                    {
                        "id": "l-test",
                        "name": "Test",
                        "type": "listening",
                        "prerequisiteLessonIds": [],
                        "content": {"listeningPhases": phases},
                    }
                ],
            }
        ],
    }
    (tmp_course / "sections" / "s-test.json").write_text(
        json.dumps(section, indent=2), encoding="utf-8"
    )
    (tmp_course / "index.json").write_text(
        json.dumps({"sections": [{"id": "s-test", "file": "sections/s-test.json"}]}),
        encoding="utf-8",
    )


class _FakeTtsBackend:
    """Backend that writes minimal MP3-like bytes for testing."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, Path]] = []

    def name(self) -> str:
        return "fake"

    def synthesize(self, text: str, output_mp3: Path) -> None:
        self.calls.append((text, output_mp3))
        # Write a tiny byte sequence; tests only check existence/contents length.
        output_mp3.write_bytes(b"FAKE_MP3_" + text.encode("utf-8"))


class TestMiniMaxBackend(unittest.TestCase):
    def test_backend_requires_api_key(self) -> None:
        env_key = os.environ.pop("MINIMAX_API_KEY", None)
        try:
            with self.assertRaises(RuntimeError) as ctx:
                MiniMaxBackend()
            self.assertIn("MINIMAX_API_KEY", str(ctx.exception))
        finally:
            if env_key is not None:
                os.environ["MINIMAX_API_KEY"] = env_key

    def test_backend_name_includes_model_and_voice(self) -> None:
        os.environ["MINIMAX_API_KEY"] = "sk-test"
        backend = MiniMaxBackend(
            voice_id="male-qn-jingying", speed=0.85, model="speech-2.8-hd"
        )
        self.assertIn("minimax", backend.name())
        self.assertIn("male-qn-jingying", backend.name())
        self.assertIn("0.85", backend.name())


class TestGenerateAudio(unittest.TestCase):
    def test_target_path_for_listening(self) -> None:
        # category is now ignored; all bundled assets live under listening/.
        self.assertEqual(
            target_path_for("l-habari", "word"),
            SOUNDS_DIR / "listening" / "l-habari.mp3",
        )
        self.assertEqual(
            target_path_for("l-habari"),
            SOUNDS_DIR / "listening" / "l-habari.mp3",
        )
        self.assertEqual(
            listening_asset_path("section:foundations"),
            SOUNDS_DIR / "listening" / "section:foundations.mp3",
        )

    def test_collect_entries_uses_phase_transcripts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "turkish"
            _write_listening_course(
                tmp_course,
                phases=[
                    {
                        "id": "p-dialogue",
                        "name": "Dialogue",
                        "type": "dialogue",
                        "audioAsset": "l-habari",
                        "transcript": "Habari za asubuhi",
                    },
                    {
                        "id": "p-summary",
                        "name": "Summary",
                        # No transcript -> skipped (needs recording).
                        "audioAsset": "l-needs-recording",
                    },
                    {
                        "id": "p-word",
                        "name": "Word",
                        # audioAsset collides with a vocab word id -> excluded
                        # (word pronunciation is runtime TTS, not bundled MP3).
                        "audioAsset": "w-mimi",
                        "transcript": "Mimi",
                    },
                ],
            )
            entries = collect_entries(tmp_course)
            self.assertEqual(len(entries), 1)
            entry = entries[0]
            self.assertEqual(entry.audio_asset, "l-habari")
            self.assertEqual(entry.text, "Habari za asubuhi")

    def test_collect_entries_skips_non_listening_lessons(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_course = Path(tmp) / "turkish"
            src_course = PROJECT_ROOT / "assets" / "courses" / "turkish"
            shutil.copytree(src_course, tmp_course)
            # A non-listening lesson carrying an audioAsset must not yield a
            # bundled-asset entry.
            section = {
                "id": "s-test",
                "name": "Test",
                "units": [
                    {
                        "id": "u-test",
                        "name": "Test",
                        "lessons": [
                            {
                                "id": "l-normal",
                                "name": "Normal",
                                "type": "normal",
                                "prerequisiteLessonIds": [],
                                "content": {
                                    "stages": [
                                        {
                                            "id": "stage",
                                            "name": "S",
                                            "prerequisiteStageIds": [],
                                            "items": [
                                                {
                                                    "runtimeType": "listenOnly",
                                                    "id": "lo",
                                                    "audioAsset": "l-normal-asset",
                                                    "transcript": "Habari",
                                                }
                                            ],
                                        }
                                    ]
                                },
                            }
                        ],
                    }
                ],
            }
            (tmp_course / "sections" / "s-test.json").write_text(
                json.dumps(section, indent=2), encoding="utf-8"
            )
            (tmp_course / "index.json").write_text(
                json.dumps(
                    {"sections": [{"id": "s-test", "file": "sections/s-test.json"}]}
                ),
                encoding="utf-8",
            )
            entries = collect_entries(tmp_course)
            self.assertEqual(entries, [])

    def test_generate_entry_skips_existing_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_sounds = Path(tmp)
            entry = AudioEntry(audio_asset="l-test", text="Habari")
            target = tmp_sounds / "listening" / "l-test.mp3"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("already exists")

            backend = _FakeTtsBackend()
            result = generate_entry(
                entry, backend, force=False, base_dir=tmp_sounds
            )
            self.assertEqual(result, target)
            self.assertEqual(len(backend.calls), 0)
            self.assertEqual(target.read_text(), "already exists")

    def test_generate_entry_creates_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_sounds = Path(tmp)
            entry = AudioEntry(audio_asset="l-test", text="Habari")
            target = tmp_sounds / "listening" / "l-test.mp3"

            backend = _FakeTtsBackend()
            result = generate_entry(
                entry, backend, force=False, base_dir=tmp_sounds
            )
            self.assertEqual(result, target)
            self.assertEqual(len(backend.calls), 1)
            self.assertEqual(backend.calls[0][0], "Habari")
            self.assertTrue(target.exists())

    def test_cmd_all_writes_into_sounds_dir(self) -> None:
        """cmd_all honors --sounds-dir and --format json (language-agnostic CLI)."""
        import argparse
        import io
        from types import SimpleNamespace
        from unittest.mock import patch

        import generate_audio

        os.environ["MINIMAX_API_KEY"] = "sk-test"
        try:
            with tempfile.TemporaryDirectory() as tmp:
                tmp_course = Path(tmp) / "turkish"
                _write_listening_course(
                    tmp_course,
                    phases=[
                        {
                            "id": "p-dialogue",
                            "name": "Dialogue",
                            "type": "dialogue",
                            "audioAsset": "l-habari",
                            "transcript": "Habari za asubuhi",
                        }
                    ],
                )
                tmp_sounds = Path(tmp) / "out_sounds"

                args = SimpleNamespace(
                    course_dir=tmp_course,
                    sounds_dir=tmp_sounds,
                    voice_id="female-tianmei",
                    model="speech-2.8-hd",
                    speed=0.9,
                    force=False,
                    format="json",
                )
                # Patch the real TTS backend with a fake factory (ignores the
                # voice/model kwargs _build_backend passes) so no network is hit.
                fake_backend = _FakeTtsBackend()
                with patch.object(
                    generate_audio, "MiniMaxBackend", lambda **kw: fake_backend
                ):
                    with patch.object(sys, "stdout", io.StringIO()) as captured:
                        rc = cmd_all(args)
                        out = captured.getvalue()

                self.assertEqual(rc, 0)
                # JSON summary line emitted.
                summary = [l for l in out.splitlines() if l.strip().startswith("{")]
                self.assertEqual(len(summary), 1)
                counts = json.loads(summary[0])
                self.assertEqual(counts["generated"], 1)
                self.assertEqual(counts["skipped"], 0)
                self.assertEqual(counts["total"], 1)
                # File written into the provided sounds dir (not SOUNDS_DIR).
                self.assertTrue(
                    (tmp_sounds / "listening" / "l-habari.mp3").exists()
                )
        finally:
            os.environ.pop("MINIMAX_API_KEY", None)


if __name__ == "__main__":
    unittest.main()
