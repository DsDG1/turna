"""Tests for the generate_audio_client bridge (no network, no subprocess TTS)."""
from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings  # noqa: E402
from src.backend import generate_audio_client  # noqa: E402
from src.backend.generate_audio_client import TtsOptions  # noqa: E402
from tests._course_fixture import COURSE_SRC, copy_turkish_course  # noqa: E402


class SoundsDirTest(unittest.TestCase):
    def test_derives_from_index_language(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="sounds_dir_"))
        self.addCleanup(_rmtree, tmp)
        course_dir = tmp / "turkish"
        copy_turkish_course(course_dir)
        # Turkish course index.language == "tr".
        settings = Settings(assets_repo_root="")
        sounds = generate_audio_client.sounds_dir_for(course_dir, settings)
        self.assertTrue(sounds.name == "tr" and sounds.parts[-3:] == ("assets", "sounds", "tr"), str(sounds))

    def test_honors_assets_repo_root(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="sounds_root_"))
        self.addCleanup(_rmtree, tmp)
        course_dir = tmp / "course"
        course_dir.mkdir()
        (course_dir / "index.json").write_text(
            json.dumps({"language": "sw", "sections": []}), encoding="utf-8"
        )
        settings = Settings(assets_repo_root=str(tmp / "repo"))
        sounds = generate_audio_client.sounds_dir_for(course_dir, settings)
        self.assertEqual(
            sounds, Path(tmp) / "repo" / "assets" / "sounds" / "sw"
        )


class BuildCommandTest(unittest.TestCase):
    def test_argv_without_force(self) -> None:
        cmd = generate_audio_client.build_command(
            Path("/c/course"), Path("/c/sounds"), TtsOptions(voice_id="v", model="m", speed=0.9)
        )
        self.assertIn(str(Path("/c/course")), cmd)
        self.assertIn(str(Path("/c/sounds")), cmd)
        self.assertIn("--voice-id", cmd)
        self.assertIn("v", cmd)
        self.assertIn("--model", cmd)
        self.assertIn("m", cmd)
        self.assertIn("--speed", cmd)
        self.assertIn("0.9", cmd)
        self.assertIn("all", cmd)
        self.assertIn("--format", cmd)
        self.assertIn("json", cmd)
        self.assertNotIn("--force", cmd)

    def test_argv_with_force(self) -> None:
        cmd = generate_audio_client.build_command(
            Path("/c/course"), Path("/c/sounds"), TtsOptions(force=True)
        )
        self.assertIn("--force", cmd)


class RunGenerateTest(unittest.TestCase):
    def test_parses_generated_lines_and_json_summary(self) -> None:
        stdout_lines = (
            "Using backend: minimax\n"
            "Generated C:\\sounds\\listening\\a.mp3\n"
            "Generated C:\\sounds\\listening\\b.mp3\n"
            "\n"
            "Done: 2 generated, 1 skipped, 3 total.\n"
            '{"generated": 2, "skipped": 1, "total": 3}\n'
        )
        fake_proc = SimpleNamespace(
            stdout=io.StringIO(stdout_lines),
            stderr=io.StringIO(""),
            wait=lambda: None,
            returncode=0,
        )

        with patch.object(generate_audio_client.subprocess, "Popen", return_value=fake_proc):
            result = generate_audio_client.run_generate(
                Path("/c/course"), Path("/c/sounds"), TtsOptions(), "sk-x"
            )

        self.assertEqual(result.generated, 2)
        self.assertEqual(result.skipped, 1)
        self.assertEqual(result.total, 3)

    def test_passes_api_key_via_env_not_argv(self) -> None:
        captured = {}

        def _popen(cmd, **kw):
            captured["cmd"] = cmd
            captured["env"] = kw["env"]
            return SimpleNamespace(
                stdout=io.StringIO('{"generated": 0, "skipped": 0, "total": 0}\n'),
                stderr=io.StringIO(""),
                wait=lambda: None,
                returncode=0,
            )

        with patch.object(generate_audio_client.subprocess, "Popen", side_effect=_popen):
            generate_audio_client.run_generate(
                Path("/c/course"), Path("/c/sounds"), TtsOptions(), "sk-secret"
            )

        cmd = " ".join(str(a) for a in captured["cmd"])
        self.assertNotIn("sk-secret", cmd)  # never on argv
        self.assertEqual(captured["env"].get("MINIMAX_API_KEY"), "sk-secret")

    def test_cancel_stops_before_complete(self) -> None:
        checks = {"n": 0}

        def _popen(cmd, **kw):
            return SimpleNamespace(
                stdout=io.StringIO("Generated a.mp3\nGenerated b.mp3\n"),
                stderr=io.StringIO(""),
                returncode=None,
                wait=lambda: None,
                terminate=lambda: None,
            )

        def _cancel_check() -> bool:
            # Cancel after the first line has been counted (generated=1).
            checks["n"] += 1
            return checks["n"] >= 2

        with patch.object(generate_audio_client.subprocess, "Popen", side_effect=_popen):
            result = generate_audio_client.run_generate(
                Path("/c/course"), Path("/c/sounds"), TtsOptions(), "k",
                cancel_check=_cancel_check,
            )
        self.assertEqual(result.generated, 1)  # stopped after first line


class PreviewGenerationTest(unittest.TestCase):
    def test_counts_single_phase_course(self) -> None:
        tmp = Path(tempfile.mkdtemp(prefix="preview_"))
        self.addCleanup(_rmtree, tmp)
        course_dir = tmp / "turkish"
        copy_turkish_course(course_dir)
        settings = Settings(assets_repo_root="")

        # No listening phases in the stock turkish course -> zero total.
        preview = generate_audio_client.preview_generation(course_dir, settings)
        self.assertEqual(preview["total"], 0)

    def test_subprocess_fallback_returns_counts(self) -> None:
        """The subprocess fallback parses the JSON summary from its stdout."""
        tmp = Path(tempfile.mkdtemp(prefix="preview_fb_"))
        self.addCleanup(_rmtree, tmp)
        course_dir = tmp / "turkish"
        copy_turkish_course(course_dir)
        sounds = generate_audio_client.sounds_dir_for(course_dir, Settings(assets_repo_root=""))

        proc = SimpleNamespace(
            stdout='{"generated": 0, "skipped": 4, "total": 4}\n',
            returncode=0,
        )
        with patch.object(
            generate_audio_client.subprocess, "run", return_value=proc
        ) as run:
            preview = generate_audio_client._preview_via_subprocess(course_dir, sounds)
        self.assertEqual(preview, {"total": 4, "existing": 4})
        run.assert_called_once()


def _rmtree(path: Path) -> None:
    import shutil

    shutil.rmtree(path, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
