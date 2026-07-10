#!/usr/bin/env python3
"""Unit tests for tool/generate_audio.py.

Run with:
    python -m unittest discover -s test -p '*_audio_test.py'
"""

from __future__ import annotations

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
    target_path_for,
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

    def test_target_path_for_word(self) -> None:
        path = target_path_for("w-habari", "word")
        self.assertEqual(path, SOUNDS_DIR / "words" / "w-habari.mp3")

    def test_target_path_for_expression(self) -> None:
        path = target_path_for("e-habari", "expression")
        self.assertEqual(path, SOUNDS_DIR / "expressions" / "e-habari.mp3")

    def test_target_path_for_listening(self) -> None:
        path = target_path_for("section:foundations", "lesson")
        self.assertEqual(
            path, SOUNDS_DIR / "listening" / "section:foundations.mp3"
        )

    def test_collect_entries_includes_all_vocab(self) -> None:
        entries = collect_entries(COURSE_DIR, only_referenced=False)
        word_entries = [e for e in entries if e.category == "word"]
        self.assertGreaterEqual(len(word_entries), 35)
        ids = {e.audio_asset for e in word_entries}
        self.assertIn("w-naanu", ids)
        self.assertIn("w-howdu", ids)

    def test_collect_entries_only_referenced(self) -> None:
        entries = collect_entries(COURSE_DIR, only_referenced=True)
        ids = {e.audio_asset for e in entries}
        # w-baa is not referenced by any lesson in the current content inventory.
        self.assertNotIn("w-baa", ids)
        # w-howdu is referenced by a listenAndPick interaction.
        self.assertIn("w-howdu", ids)

    def test_generate_entry_skips_existing_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_sounds = Path(tmp)
            entry = AudioEntry(
                audio_asset="w-test", text="test", category="word"
            )
            target = tmp_sounds / "words" / "w-test.mp3"
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
            entry = AudioEntry(
                audio_asset="w-test", text="test", category="word"
            )
            target = tmp_sounds / "words" / "w-test.mp3"

            backend = _FakeTtsBackend()
            result = generate_entry(
                entry, backend, force=False, base_dir=tmp_sounds
            )
            self.assertEqual(result, target)
            self.assertEqual(len(backend.calls), 1)
            self.assertTrue(target.exists())


if __name__ == "__main__":
    unittest.main()
