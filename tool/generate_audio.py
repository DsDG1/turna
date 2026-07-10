#!/usr/bin/env python3
"""Bulk audio generation for the Swahili course.

Uses the same Piper VITS model that the Flutter runtime bundles, so
pre-generated assets and fallback TTS sound identical.

Backends (tried in order):
  1. sherpa-onnx Python API  (matches the Flutter runtime)
  2. Piper command-line executable

If neither backend is available, the script prints a manifest of missing
audio and exits with a non-zero code. It does not modify course JSON.

Examples:
  python tool/generate_audio.py all
  python tool/generate_audio.py all --only-referenced
  python tool/generate_audio.py list w-mimi w-wewe e-habari
  python tool/generate_audio.py speak "Habari" assets/sounds/swahili/words/w-habari.mp3
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
    """A single piece of text that needs to become an audio file."""

    audio_asset: str
    text: str
    category: str  # 'word', 'expression', 'listening'


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


def _audio_asset_path(
    asset: str,
    kind: str,
    base_dir: Path = SOUNDS_DIR,
) -> Path:
    """Return the canonical filesystem path for an audio asset id."""
    if kind == "word":
        return base_dir / "words" / f"{asset}.mp3"
    if kind == "expression":
        return base_dir / "expressions" / f"{asset}.mp3"
    return base_dir / "listening" / f"{asset}.mp3"


def target_path_for(asset: str, category: str) -> Path:
    """Return the canonical output path for an audio asset id."""
    return _audio_asset_path(asset, category, SOUNDS_DIR)


def generate_entry(
    entry: AudioEntry,
    backend: TtsBackend,
    force: bool = False,
    base_dir: Path = SOUNDS_DIR,
) -> Path:
    """Generate the audio file for a single entry. Returns the output path."""
    output = _audio_asset_path(entry.audio_asset, entry.category, base_dir)
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


def _collect_word_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if obj.get("runtimeType") == "showWord" and "wordId" in obj:
            ids.add(obj["wordId"])
        if "linkedWordIds" in obj:
            ids.update(obj["linkedWordIds"])
        for value in obj.values():
            ids.update(_collect_word_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(_collect_word_ids(item))
    return ids


def _collect_expression_ids(obj: Any) -> set[str]:
    ids: set[str] = set()
    if isinstance(obj, dict):
        if obj.get("runtimeType") == "showExpression" and "expressionId" in obj:
            ids.add(obj["expressionId"])
        if "exampleExpressionIds" in obj:
            ids.update(obj["exampleExpressionIds"])
        for value in obj.values():
            ids.update(_collect_expression_ids(value))
    elif isinstance(obj, list):
        for item in obj:
            ids.update(_collect_expression_ids(item))
    return ids


def _collect_audio_assets(obj: Any) -> set[str]:
    assets: set[str] = set()
    if isinstance(obj, dict):
        if "audioAsset" in obj and isinstance(obj["audioAsset"], str):
            assets.add(obj["audioAsset"])
        for value in obj.values():
            assets.update(_collect_audio_assets(value))
    elif isinstance(obj, list):
        for item in obj:
            assets.update(_collect_audio_assets(item))
    return assets


def collect_entries(
    course_dir: Path,
    only_referenced: bool = False,
) -> list[AudioEntry]:
    """Return all AudioEntries that should have audio files."""
    vocab = _load_json(course_dir / "vocab.json")
    expressions = _load_json(course_dir / "expressions.json")
    index = _load_json(course_dir / "index.json")

    vocab_by_id = {w["id"]: w for w in vocab.get("words", [])}
    expr_by_id = {e["id"]: e for e in (expressions.get("expressions", []) or [])}

    referenced_word_ids: set[str] = set()
    referenced_expression_ids: set[str] = set()
    referenced_assets: set[str] = set()

    for section_meta in index.get("sections", []):
        section = _load_json(course_dir / section_meta["file"])
        for unit in section.get("units", []):
            for lesson in unit.get("lessons", []):
                content = lesson.get("content", {})
                referenced_word_ids.update(_collect_word_ids(content))
                referenced_expression_ids.update(_collect_expression_ids(content))
                referenced_assets.update(_collect_audio_assets(content))

    entries: list[AudioEntry] = []

    # Words.
    word_ids = referenced_word_ids if only_referenced else set(vocab_by_id.keys())
    for wid in sorted(word_ids):
        word = vocab_by_id.get(wid)
        if not word:
            continue
        entries.append(
            AudioEntry(audio_asset=wid, text=word.get("term", ""), category="word")
        )

    # Expressions.
    expr_ids = (
        referenced_expression_ids if only_referenced else set(expr_by_id.keys())
    )
    for eid in sorted(expr_ids):
        expr = expr_by_id.get(eid)
        if not expr:
            continue
        entries.append(
            AudioEntry(
                audio_asset=eid,
                text=expr.get("term", ""),
                category="expression",
            )
        )

    # Listening / lesson-level assets that are not word/expression ids.
    word_and_expr_ids = set(vocab_by_id.keys()) | set(expr_by_id.keys())
    for asset in sorted(referenced_assets):
        if asset in word_and_expr_ids:
            continue
        # For lesson-level assets the text is the asset id itself; the caller
        # can supply a transcript in future iterations.
        entries.append(
            AudioEntry(audio_asset=asset, text=asset, category="listening")
        )

    return entries


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
        entries = collect_entries(args.course_dir, only_referenced=args.only_referenced)
        print(f"\nWould generate {len(entries)} audio file(s):", file=sys.stderr)
        for e in entries:
            print(f"  {e.category:12} {e.audio_asset:30} -> {e.text}", file=sys.stderr)
        return 1

    print(f"Using backend: {backend.name()}")
    entries = collect_entries(args.course_dir, only_referenced=args.only_referenced)
    generated = 0
    skipped = 0
    for entry in entries:
        target = target_path_for(entry.audio_asset, entry.category)
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

    vocab = _load_json(args.course_dir / "vocab.json")
    expressions = _load_json(args.course_dir / "expressions.json")
    vocab_by_id = {w["id"]: w for w in vocab.get("words", [])}
    expr_by_id = {e["id"]: e for e in (expressions.get("expressions", []) or [])}

    entries: list[AudioEntry] = []
    for asset in args.ids:
        if asset in vocab_by_id:
            entries.append(
                AudioEntry(
                    audio_asset=asset,
                    text=vocab_by_id[asset].get("term", ""),
                    category="word",
                )
            )
        elif asset in expr_by_id:
            entries.append(
                AudioEntry(
                    audio_asset=asset,
                    text=expr_by_id[asset].get("term", ""),
                    category="expression",
                )
            )
        else:
            print(f"Warning: unknown id {asset}, treating as listening asset")
            entries.append(AudioEntry(audio_asset=asset, text=asset, category="listening"))

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
        description="Bulk audio generation for the Swahili course"
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

    p_all = subparsers.add_parser("all", help="Generate audio for all entries")
    p_all.add_argument(
        "--only-referenced",
        action="store_true",
        help="Only generate audio for ids referenced by lessons",
    )
    p_all.set_defaults(func=cmd_all)

    p_list = subparsers.add_parser(
        "list", help="Generate audio for a list of ids"
    )
    p_list.add_argument("ids", nargs="+", help="Word/expression/asset ids")
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
