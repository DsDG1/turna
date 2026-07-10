#!/usr/bin/env python3
"""Bulk audio generation for Swahili listening lessons.

Uses the same Piper VITS model that the Flutter runtime bundles, so
pre-generated listening assets and fallback TTS sound identical.

Word and expression pronunciation is handled at runtime by Piper (or
flutter_tts); this script only generates MP3 for `audioAsset` references
inside listening lessons.

Backends (tried in order):
  1. sherpa-onnx Python API  (matches the Flutter runtime)
  2. Piper command-line executable

If neither backend is available, the script prints a manifest of missing
audio and exits with a non-zero code. It does not modify course JSON.

Examples:
  python tool/generate_audio.py all
  python tool/generate_audio.py list section:foundations
  python tool/generate_audio.py speak "Habari za asubuhi" assets/sounds/swahili/listening/l-greetings.mp3
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from course_cli import is_listening_lesson  # type: ignore

COURSE_DIR = Path("assets/courses/swahili")
SOUNDS_DIR = Path("assets/sounds/swahili")
VOICE_DIR = (
    Path("assets/voices/swahili/vits-piper-sw_CD-lanfrica-medium-int8")
)
MODEL_FILE = VOICE_DIR / "sw_CD-lanfrica-medium.onnx"
TOKENS_FILE = VOICE_DIR / "tokens.txt"
DATA_DIR = VOICE_DIR / "espeak-ng-data"


# --------------------------------------------------------------------------- #
# Data structures
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class AudioEntry:
    """A single listening-lesson audio asset that needs to become an MP3."""

    audio_asset: str
    text: str  # the transcript to synthesize


# --------------------------------------------------------------------------- #
# TTS backends
# --------------------------------------------------------------------------- #


class TtsBackend(ABC):
    """Abstract TTS backend that can synthesize text to a wave file."""

    @abstractmethod
    def name(self) -> str:
        ...

    @abstractmethod
    def synthesize(self, text: str, output_wav: Path) -> None:
        """Synthesize [text] to a mono wave file at [output_wav]."""
        ...


class SherpaOnnxBackend(TtsBackend):
    """sherpa-onnx Python API backend."""

    def __init__(self) -> None:
        import sherpa_onnx

        self._sherpa_onnx = sherpa_onnx
        sherpa_onnx.initBindings()

        vits = sherpa_onnx.OfflineTtsVitsModelConfig(
            model=str(MODEL_FILE),
            tokens=str(TOKENS_FILE),
            data_dir=str(DATA_DIR),
        )
        model_config = sherpa_onnx.OfflineTtsModelConfig(
            vits=vits,
            num_threads=2,
            provider="cpu",
        )
        config = sherpa_onnx.OfflineTtsConfig(
            model=model_config,
            maxNumSenetences=1,
        )
        self._tts = sherpa_onnx.OfflineTts(config)

    def name(self) -> str:
        return "sherpa-onnx"

    def synthesize(self, text: str, output_wav: Path) -> None:
        audio = self._tts.generate(text=text, sid=0, speed=1.0)
        ok = self._sherpa_onnx.writeWave(
            filename=str(output_wav),
            samples=audio.samples,
            sampleRate=audio.sampleRate,
        )
        if not ok:
            raise RuntimeError(f"sherpa-onnx failed to write {output_wav}")


class PiperCliBackend(TtsBackend):
    """Piper command-line backend."""

    def __init__(self, executable: str = "piper") -> None:
        self._executable = executable

    def name(self) -> str:
        return f"piper-cli ({self._executable})"

    def synthesize(self, text: str, output_wav: Path) -> None:
        cmd = [
            self._executable,
            "--model",
            str(MODEL_FILE),
            "--output_file",
            str(output_wav),
        ]
        result = subprocess.run(
            cmd,
            input=text,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"piper failed: {result.stderr.strip() or result.stdout.strip()}"
            )


def detect_backend(prefer: str | None = None) -> TtsBackend | None:
    """Return the best available TTS backend, or None if none is available."""
    if prefer == "sherpa-onnx" or prefer is None:
        try:
            if MODEL_FILE.exists() and TOKENS_FILE.exists() and DATA_DIR.exists():
                return SherpaOnnxBackend()
        except Exception:
            pass

    if prefer == "piper" or prefer is None:
        executable = shutil.which("piper") or shutil.which("piper-tts")
        if executable:
            return PiperCliBackend(executable)

    return None


# --------------------------------------------------------------------------- #
# Audio output helpers
# --------------------------------------------------------------------------- #


def _wav_to_mp3(wav_path: Path, mp3_path: Path) -> None:
    """Convert a wave file to MP3 using ffmpeg or pydub if available."""
    if shutil.which("ffmpeg"):
        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(wav_path),
                "-ar",
                "44100",
                "-ac",
                "1",
                "-q:a",
                "4",
                str(mp3_path),
            ],
            check=True,
            capture_output=True,
        )
        wav_path.unlink()
        return

    try:
        from pydub import AudioSegment

        segment = AudioSegment.from_wav(str(wav_path))
        segment.export(str(mp3_path), format="mp3", parameters=["-q:a", "4"])
        wav_path.unlink()
        return
    except Exception:
        pass

    # No converter available: keep the wave file but name it back to mp3
    # so the manifest is still correct. The build will need a real mp3 later.
    wav_path.rename(mp3_path)
    print(
        f"Warning: no mp3 encoder found; kept raw wave data at {mp3_path}",
        file=sys.stderr,
    )


def listening_asset_path(asset: str, base_dir: Path = SOUNDS_DIR) -> Path:
    """Return the canonical filesystem path for a listening audio asset id."""
    return base_dir / "listening" / f"{asset}.mp3"


def target_path_for(asset: str, category: str | None = None) -> Path:
    """Return the canonical output path for an audio asset id.

    ``category`` is retained for call-site compatibility; all bundled assets
    are listening assets now, so it is ignored.
    """
    return listening_asset_path(asset, SOUNDS_DIR)


def generate_entry(
    entry: AudioEntry,
    backend: TtsBackend,
    force: bool = False,
    base_dir: Path = SOUNDS_DIR,
) -> Path:
    """Generate the audio file for a single entry. Returns the output path."""
    output = listening_asset_path(entry.audio_asset, base_dir)
    if output.exists() and not force:
        return output

    output.parent.mkdir(parents=True, exist_ok=True)
    wav_path = output.with_suffix(".wav")
    backend.synthesize(entry.text, wav_path)
    _wav_to_mp3(wav_path, output)
    return output


# --------------------------------------------------------------------------- #
# Course scanning
# --------------------------------------------------------------------------- #


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def collect_entries(course_dir: Path) -> list[AudioEntry]:
    """Return listening-lesson AudioEntries that should have MP3 files.

    Only `ListeningPhase.audioAsset` references with a non-empty `transcript`
    are bundled: the transcript is the text Piper synthesizes, mirroring the
    runtime listen-only fallback (speak the transcript). Word/expression
    pronunciation is synthesized at runtime, so those ids are excluded. Assets
    that lack a transcript (e.g. legacy `content.audioAsset`) are intentionally
    skipped — they need a human recording or a transcript, not synthesized
    id-string speech.
    """
    vocab = _load_json(course_dir / "vocab.json")
    expressions = _load_json(course_dir / "expressions.json")
    index = _load_json(course_dir / "index.json")

    word_ids = {w["id"] for w in vocab.get("words", [])}
    expr_ids = {e["id"] for e in (expressions.get("expressions", []) or [])}
    word_and_expr_ids = word_ids | expr_ids

    # asset_id -> transcript (first non-empty wins; dedup across phases)
    listening_assets: dict[str, str] = {}

    for section_meta in index.get("sections", []):
        section = _load_json(course_dir / section_meta["file"])
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                content = lesson.get("content", {})
                if not is_listening_lesson(lesson, content):
                    continue
                for phase in content.get("listeningPhases", []) or []:
                    asset = phase.get("audioAsset")
                    transcript = (phase.get("transcript") or "").strip()
                    if not (isinstance(asset, str) and asset and transcript):
                        continue
                    if asset in word_and_expr_ids:
                        continue
                    listening_assets.setdefault(asset, transcript)

    return [
        AudioEntry(audio_asset=asset, text=listening_assets[asset])
        for asset in sorted(listening_assets)
    ]


# --------------------------------------------------------------------------- #
# CLI commands
# --------------------------------------------------------------------------- #


def cmd_all(args: argparse.Namespace) -> int:
    backend = detect_backend(prefer=args.backend)
    if backend is None:
        print(
            "Error: no TTS backend available. Install sherpa-onnx "
            "(`pip install sherpa-onnx`) or put `piper` on PATH.",
            file=sys.stderr,
        )
        entries = collect_entries(args.course_dir)
        print(f"\nWould generate {len(entries)} audio file(s):", file=sys.stderr)
        for e in entries:
            print(f"  {e.audio_asset:30} -> {e.text}", file=sys.stderr)
        return 1

    print(f"Using backend: {backend.name()}")
    entries = collect_entries(args.course_dir)
    generated = 0
    skipped = 0
    for entry in entries:
        target = listening_asset_path(entry.audio_asset)
        if target.exists() and not args.force:
            skipped += 1
            continue
        generate_entry(entry, backend, force=args.force)
        generated += 1
        print(f"Generated {target}")

    print(f"\nDone: {generated} generated, {skipped} skipped, {len(entries)} total.")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    backend = detect_backend(prefer=args.backend)
    if backend is None:
        print(
            "Error: no TTS backend available. Install sherpa-onnx "
            "(`pip install sherpa-onnx`) or put `piper` on PATH.",
            file=sys.stderr,
        )
        return 1

    # `list` is a manual-override entry point: the caller supplies the asset
    # ids to synthesize. There is no transcript lookup here — if the caller
    # wants specific spoken text they use `speak`. We synthesize the asset id
    # itself only when explicitly asked.
    entries = [
        AudioEntry(audio_asset=asset, text=asset)
        for asset in args.ids
    ]

    for entry in entries:
        target = generate_entry(entry, backend, force=args.force)
        print(f"Generated {target}")
    return 0


def cmd_speak(args: argparse.Namespace) -> int:
    backend = detect_backend(prefer=args.backend)
    if backend is None:
        print(
            "Error: no TTS backend available. Install sherpa-onnx "
            "(`pip install sherpa-onnx`) or put `piper` on PATH.",
            file=sys.stderr,
        )
        return 1

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    wav_path = output.with_suffix(".wav")
    backend.synthesize(args.text, wav_path)
    _wav_to_mp3(wav_path, output)
    print(f"Generated {output}")
    return 0


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bulk audio generation for Swahili listening lessons"
    )
    parser.add_argument(
        "--course-dir",
        type=Path,
        default=COURSE_DIR,
        help="Course directory (default: assets/courses/swahili)",
    )
    parser.add_argument(
        "--backend",
        choices=["sherpa-onnx", "piper"],
        default=None,
        help="TTS backend to use (default: auto-detect)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate files even if they already exist",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    p_all = subparsers.add_parser(
        "all", help="Generate audio for all listening-lesson assets"
    )
    p_all.set_defaults(func=cmd_all)

    p_list = subparsers.add_parser(
        "list", help="Generate audio for a list of listening asset ids"
    )
    p_list.add_argument("ids", nargs="+", help="Listening asset ids")
    p_list.set_defaults(func=cmd_list)

    p_speak = subparsers.add_parser(
        "speak", help="Generate audio for arbitrary text"
    )
    p_speak.add_argument("text", help="Text to synthesize")
    p_speak.add_argument("output", help="Output mp3 path")
    p_speak.set_defaults(func=cmd_speak)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
