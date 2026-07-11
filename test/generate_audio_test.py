#!/usr/bin/env python3
"""Unit tests for tool/generate_audio.py.

Run with:
    python -m unittest discover -s test -p '*_audio_test.py'
"""

from __future__ import annotations

import json
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
    collect_entries,
    detect_backend,
    generate_entry,
    listening_asset_path,
    target_path_for,
)


def _write_listening_course(tmp_course: Path, phases: list[dict]) -> None:
    """Write a minimal course with one listening lesson containing `phases`."""
    src_course = PROJECT_ROOT / "assets" / "courses" / "swahili"
    shutil.copytree(src_course, tmp_course)
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
    """Backend that writes a minimal valid WAV file for testing."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, Path]] = []

    def name(self) -> str:
        return "fake"

    def synthesize(self, text: str, output_wav: Path) -> None:
        self.calls.append((text, output_wav))
        # Write a minimal RIFF/WAVE header with no samples.
        output_wav.write_bytes(
            b"RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00"
            b"\x44\xac\x00\x00\x88X\x01\x00\x02\x00\x10\x00data\x02\x00\x00\x00\x00\x00"
        )


class TestGenerateAudio(unittest.TestCase):
    def test_detect_backend_returns_none_when_nothing_available(self) -> None:
        # In this test environment neither sherpa-onnx nor piper is installed.
        backend = detect_backend()
        self.assertIsNone(backend)

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
            tmp_course = Path(tmp) / "swahili"
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
                        "type": "summary",
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
            tmp_course = Path(tmp) / "swahili"
            src_course = PROJECT_ROOT / "assets" / "courses" / "swahili"
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


if __name__ == "__main__":
    unittest.main()
