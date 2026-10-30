#!/usr/bin/env python3
"""Bulk audio generation for Turkish listening lessons via MiniMax TTS.

Synthesizes listening-lesson audio assets by calling the MiniMax REST API
(https://api.minimax.io/v1/t2a_v2). The generated MP3s are stored under
assets/sounds/turkish/listening/ and can then be mixed with BGM using
`tool/mix_listening_a1.py`.

Authentication:
  export MINIMAX_API_KEY="sk-..."
  # Optional, required by some MiniMax accounts:
  export MINIMAX_GROUP_ID="..."

Examples:
  python tool/generate_audio.py all
  python tool/generate_audio.py all --voice-id male-qn-jingying --speed 0.9
  python tool/generate_audio.py all --model speech-2.8-turbo --emotion calm
  python tool/generate_audio.py list section:foundations
  python tool/generate_audio.py speak "Habari za asubuhi" assets/sounds/turkish/listening/l-greetings.mp3

``language_boost`` defaults to the course's own language (``index.json``
``language``: ``tr`` → ``Turkish``); an explicit ``--language-boost`` wins, and
an unknown code falls back to ``auto``. Without it MiniMax phonemizes Turkish
text with the voice's native (often Mandarin) phonetics.

The GUI passes ``--course-dir`` and ``--sounds-dir`` explicitly so any language
course (not just Turkish) can be synthesized into ``assets/sounds/<lang>/listening/``.
The ``all`` subcommand accepts ``--format json`` to emit a final machine-readable
summary line (used by the GUI's background worker).
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from course_cli import is_listening_lesson  # type: ignore

COURSE_DIR = Path(__file__).resolve().parent.parent / "assets" / "courses" / "turkish"
SOUNDS_DIR = Path(__file__).resolve().parent.parent / "assets" / "sounds" / "turkish"

MINIMAX_API_URL = os.environ.get("MINIMAX_API_URL", "https://api.minimax.io/v1/t2a_v2")


def _api_url() -> str:
    """Return MINIMAX_API_URL, rejecting non-http(s) schemes (e.g. file://)."""
    url = MINIMAX_API_URL.strip()
    if urllib.parse.urlsplit(url).scheme.lower() not in ("http", "https"):
        raise RuntimeError(f"MINIMAX_API_URL 仅支持 http/https URL: {url!r}")
    return url
DEFAULT_VOICE_ID = "female-tianmei"
DEFAULT_MODEL = "speech-2.8-hd"
DEFAULT_SPEED = 0.9

# --- Model / parameter surface (mirrors platform.minimax.io t2a_v2) ---------
#
# ``speech-2.8-*`` is the current generation (interjection tags, quality text
# normalization); the older series stay accepted so a user with a pinned
# contract can still regenerate assets without editing code.
SUPPORTED_MODELS: tuple[str, ...] = (
    "speech-2.8-hd",
    "speech-2.8-turbo",
    "speech-2.6-hd",
    "speech-2.6-turbo",
    "speech-02-hd",
    "speech-02-turbo",
    "speech-01-hd",
    "speech-01-turbo",
)
#: Models that accept ``text_normalization_mode=quality`` (official note:
#: ``quality`` silently degrades to ``basic`` on other models / streaming).
QUALITY_NORMALIZATION_MODELS: tuple[str, ...] = (
    "speech-2.8-hd",
    "speech-2.8-turbo",
    "speech-2.6-hd",
    "speech-2.6-turbo",
)

#: ``language_boost`` enum, verbatim from the API reference. Turkish is the
#: project default course language; callers pass the course's own language.
LANGUAGE_BOOSTS: tuple[str, ...] = (
    "Chinese",
    "Chinese,Yue",
    "English",
    "Arabic",
    "Russian",
    "Spanish",
    "French",
    "Portuguese",
    "German",
    "Turkish",
    "Dutch",
    "Ukrainian",
    "Vietnamese",
    "Indonesian",
    "Japanese",
    "Italian",
    "Korean",
    "Thai",
    "Polish",
    "Romanian",
    "Greek",
    "Czech",
    "Finnish",
    "Hindi",
    "Bulgarian",
    "Danish",
    "Hebrew",
    "Malay",
    "Persian",
    "Slovak",
    "Swedish",
    "Croatian",
    "Filipino",
    "Hungarian",
    "Norwegian",
    "Slovenian",
    "Catalan",
    "Nynorsk",
    "Tamil",
    "Afrikaans",
    "auto",
)

#: ``voice_setting.emotion`` enum. ``fluent`` / ``whisper`` only exist on the
#: 2.6 series; 2.8 rejects ``whisper``. Empty string = let the model choose.
EMOTIONS: tuple[str, ...] = (
    "happy",
    "sad",
    "angry",
    "fearful",
    "disgusted",
    "surprised",
    "calm",
    "fluent",
    "whisper",
)

#: ``audio_setting.sample_rate`` / ``bitrate`` allowed values.
SAMPLE_RATES: tuple[int, ...] = (8000, 16000, 22050, 24000, 32000, 44100)
BITRATES: tuple[int, ...] = (32000, 64000, 128000, 256000)

DEFAULT_LANGUAGE_BOOST = "Turkish"
#: ``quality`` runs an LLM-assisted normalizer, which matters for Turkish
#: numbers / dates / abbreviations in reading passages.
DEFAULT_TEXT_NORMALIZATION = "quality"
DEFAULT_EMOTION = ""
DEFAULT_SAMPLE_RATE = 32000
DEFAULT_BITRATE = 128000

#: Course ``index.json`` language code -> ``language_boost`` value.
_LANGUAGE_CODE_TO_BOOST: dict[str, str] = {
    "tr": "Turkish",
    "en": "English",
    "zh": "Chinese",
    "de": "German",
    "fr": "French",
    "es": "Spanish",
    "it": "Italian",
    "ja": "Japanese",
    "ko": "Korean",
    "ru": "Russian",
    "pt": "Portuguese",
    "ar": "Arabic",
    "nl": "Dutch",
    "pl": "Polish",
    "sv": "Swedish",
    "id": "Indonesian",
    "vi": "Vietnamese",
    "th": "Thai",
    "hi": "Hindi",
    "uk": "Ukrainian",
}


def language_boost_for_code(code: str) -> str:
    """Map a course language code (``tr`` / ``tr-TR``) to ``language_boost``.

    Unknown codes fall back to ``auto`` so the model detects the language
    itself instead of being forced into Turkish pronunciation.
    """
    base = (code or "").strip().lower().replace("_", "-").split("-")[0]
    return _LANGUAGE_CODE_TO_BOOST.get(base, "auto")


def normalize_language_boost(value: str) -> str:
    """Return the canonically-cased ``language_boost`` value or raise."""
    text = (value or "").strip()
    for candidate in LANGUAGE_BOOSTS:
        if candidate.lower() == text.lower():
            return candidate
    raise RuntimeError(
        f"不支持的 language_boost: {value!r}。可选值：{', '.join(LANGUAGE_BOOSTS)}"
    )


def normalize_model(value: str) -> str:
    """Return ``value`` after warning when it is not a documented model id.

    Unknown ids are forwarded rather than rejected: proxies and pinned
    snapshots use their own aliases, and the API is the authority on whether a
    model exists. The warning keeps plain typos visible in the run log.
    """
    text = (value or "").strip()
    if not text:
        return DEFAULT_MODEL
    if text not in SUPPORTED_MODELS:
        print(
            f"[warn] 未知的 MiniMax 语音模型 {text!r}，仍按原样提交。"
            f"文档中列出的模型：{', '.join(SUPPORTED_MODELS)}",
            file=sys.stderr,
        )
    return text


# --------------------------------------------------------------------------- #
# Data structures
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class AudioEntry:
    """A single listening-lesson audio asset that needs to become an MP3."""

    audio_asset: str
    text: str  # the transcript to synthesize


# --------------------------------------------------------------------------- #
# MiniMax backend
# --------------------------------------------------------------------------- #


class MiniMaxBackend:
    """Call the MiniMax Text-to-Audio v2 HTTP API."""

    def __init__(
        self,
        voice_id: str = DEFAULT_VOICE_ID,
        speed: float = DEFAULT_SPEED,
        model: str = DEFAULT_MODEL,
        language_boost: str = DEFAULT_LANGUAGE_BOOST,
        text_normalization: str = DEFAULT_TEXT_NORMALIZATION,
        emotion: str = DEFAULT_EMOTION,
        sample_rate: int = DEFAULT_SAMPLE_RATE,
        bitrate: int = DEFAULT_BITRATE,
    ) -> None:
        self.api_key = os.environ.get("MINIMAX_API_KEY")
        if not self.api_key:
            raise RuntimeError(
                "MINIMAX_API_KEY environment variable is required. "
                "Set it with: export MINIMAX_API_KEY=sk-..."
            )

        self.group_id = os.environ.get("MINIMAX_GROUP_ID")
        self.voice_id = voice_id
        self.speed = min(2.0, max(0.5, float(speed)))
        self.model = normalize_model(model)
        self.language_boost = normalize_language_boost(language_boost)
        if text_normalization not in ("basic", "quality"):
            raise RuntimeError(
                f"text_normalization 只能是 basic / quality，当前为: {text_normalization!r}"
            )
        self.text_normalization = text_normalization
        self.emotion = (emotion or "").strip().lower()
        if self.emotion and self.emotion not in EMOTIONS:
            raise RuntimeError(
                f"不支持的情绪 {emotion!r}。可选值：{', '.join(EMOTIONS)}"
            )
        if int(sample_rate) not in SAMPLE_RATES:
            raise RuntimeError(
                f"不支持的采样率 {sample_rate}。可选值：{SAMPLE_RATES}"
            )
        if int(bitrate) not in BITRATES:
            raise RuntimeError(f"不支持的码率 {bitrate}。可选值：{BITRATES}")
        self.sample_rate = int(sample_rate)
        self.bitrate = int(bitrate)

    def name(self) -> str:
        parts = [
            f"minimax ({self.model}",
            f"voice={self.voice_id}",
            f"speed={self.speed}",
            f"lang={self.language_boost}",
            f"normalize={self.text_normalization}",
        ]
        if self.emotion:
            parts.append(f"emotion={self.emotion}")
        return ", ".join(parts) + ")"

    def synthesize(self, text: str, output_mp3: Path) -> None:
        """Synthesize [text] to an MP3 file at [output_mp3]."""
        if len(text) > 10000:
            raise RuntimeError(
                f"单条文本 {len(text)} 字符超过 MiniMax 的 10000 字符上限，"
                "请拆分为多个听力阶段后重试。"
            )
        voice_setting: dict[str, Any] = {
            "voice_id": self.voice_id,
            "speed": self.speed,
            "vol": 1.0,
            "pitch": 0,
        }
        if self.emotion:
            voice_setting["emotion"] = self.emotion
        payload: dict[str, Any] = {
            "model": self.model,
            "text": text,
            "stream": False,
            "voice_setting": voice_setting,
            "audio_setting": {
                "sample_rate": self.sample_rate,
                "bitrate": self.bitrate,
                "format": "mp3",
                "channel": 1,
            },
            # Language-aware phonemization: without it a Mandarin voice reads
            # Turkish with Mandarin phonetics (ı/ş/ğ/ü all wrong).
            "language_boost": self.language_boost,
            # LLM-assisted normalization of numbers / dates / abbreviations.
            "text_normalization_mode": self.text_normalization,
            # Ask MiniMax to return the audio bytes as a hex string inside JSON.
            # If the API instead returns base64, _decode_audio will fall back.
            "output_format": "hex",
        }

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        if self.group_id:
            headers["MiniMax-Group-Id"] = self.group_id

        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            _api_url(),
            data=data,
            headers=headers,
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                response_body = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"MiniMax API error {exc.code}: {body}") from exc

        audio_bytes = _extract_audio_bytes(response_body)

        output_mp3.parent.mkdir(parents=True, exist_ok=True)
        with output_mp3.open("wb") as f:
            f.write(audio_bytes)


def _extract_audio_bytes(response: dict[str, Any]) -> bytes:
    """Extract raw audio bytes from a MiniMax T2A v2 JSON response."""
    audio_value = response.get("audio") or response.get("data", {}).get("audio")
    if audio_value is None:
        raise RuntimeError(f"MiniMax response did not contain audio data: {response}")

    if isinstance(audio_value, bytes):
        return audio_value

    if not isinstance(audio_value, str):
        raise RuntimeError(f"Unexpected audio type in MiniMax response: {type(audio_value)}")

    cleaned = audio_value.strip()
    # MiniMax often returns hex-encoded audio when output_format=hex.
    try:
        return bytes.fromhex(cleaned)
    except ValueError:
        pass

    # Fall back to base64 decoding.
    try:
        return base64.b64decode(cleaned, validate=True)
    except Exception as exc:
        raise RuntimeError(
            f"Could not decode MiniMax audio as hex or base64: {cleaned[:80]}..."
        ) from exc


# --------------------------------------------------------------------------- #
# Audio output helpers
# --------------------------------------------------------------------------- #


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
    backend: MiniMaxBackend,
    force: bool = False,
    base_dir: Path = SOUNDS_DIR,
) -> Path:
    """Generate the audio file for a single entry. Returns the output path."""
    output = listening_asset_path(entry.audio_asset, base_dir)
    if output.exists() and not force:
        return output

    output.parent.mkdir(parents=True, exist_ok=True)
    backend.synthesize(entry.text, output)
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
    are bundled: the transcript is the text MiniMax synthesizes. Word/expression
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


def _course_language(course_dir: Path | None) -> str:
    """Read ``index.json``'s language code; '' when unavailable."""
    if course_dir is None:
        return ""
    try:
        with (Path(course_dir) / "index.json").open("r", encoding="utf-8") as f:
            index = json.load(f)
        return str(index.get("language") or index.get("lang") or "")
    except (OSError, ValueError):
        return ""


def _build_backend(args: argparse.Namespace, course_dir: Path | None = None) -> MiniMaxBackend:
    # ``getattr`` defaults keep programmatic callers (tests, older scripts)
    # working after the parameter surface grew.
    boost = getattr(args, "language_boost", None)
    if not boost:
        target = course_dir if course_dir is not None else getattr(args, "course_dir", None)
        code = _course_language(target)
        boost = language_boost_for_code(code) if code else DEFAULT_LANGUAGE_BOOST
    return MiniMaxBackend(
        voice_id=args.voice_id,
        speed=args.speed,
        model=args.model,
        language_boost=boost,
        text_normalization=getattr(
            args, "text_normalization", DEFAULT_TEXT_NORMALIZATION
        ),
        emotion=getattr(args, "emotion", DEFAULT_EMOTION),
        sample_rate=getattr(args, "sample_rate", DEFAULT_SAMPLE_RATE),
        bitrate=getattr(args, "bitrate", DEFAULT_BITRATE),
    )


def cmd_all(args: argparse.Namespace) -> int:
    backend = _build_backend(args, args.course_dir)
    print(f"Using backend: {backend.name()}")
    print(f"language_boost: {getattr(backend, 'language_boost', 'unknown')}")

    entries = collect_entries(args.course_dir)
    generated = 0
    skipped = 0
    for entry in entries:
        target = listening_asset_path(entry.audio_asset, args.sounds_dir)
        if target.exists() and not args.force:
            skipped += 1
            continue
        generate_entry(entry, backend, force=args.force, base_dir=args.sounds_dir)
        generated += 1
        print(f"Generated {target}")

    print(f"\nDone: {generated} generated, {skipped} skipped, {len(entries)} total.")
    if args.format == "json":
        print(
            json.dumps(
                {"generated": generated, "skipped": skipped, "total": len(entries)}
            )
        )
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    backend = _build_backend(args, args.course_dir)

    # `list` is a manual-override entry point: the caller supplies the asset
    # ids to synthesize. There is no transcript lookup here — if the caller
    # wants specific spoken text they use `speak`. We synthesize the asset id
    # itself only when explicitly asked.
    entries = [
        AudioEntry(audio_asset=asset, text=asset)
        for asset in args.ids
    ]

    for entry in entries:
        target = generate_entry(entry, backend, force=args.force, base_dir=args.sounds_dir)
        print(f"Generated {target}")
    return 0


def cmd_speak(args: argparse.Namespace) -> int:
    backend = _build_backend(args)
    output = Path(args.output)
    backend.synthesize(args.text, output)
    print(f"Generated {output}")
    return 0


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Bulk audio generation for Turkish listening lessons via MiniMax TTS"
    )
    parser.add_argument(
        "--course-dir",
        type=Path,
        default=COURSE_DIR,
        help="Course directory (default: assets/courses/turkish)",
    )
    parser.add_argument(
        "--sounds-dir",
        type=Path,
        default=SOUNDS_DIR,
        help="Sounds output root (default: assets/sounds/turkish)",
    )
    parser.add_argument(
        "--voice-id",
        default=DEFAULT_VOICE_ID,
        help=f"MiniMax voice ID (default: {DEFAULT_VOICE_ID})",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=(
            f"MiniMax model (default: {DEFAULT_MODEL}; documented: "
            f"{', '.join(SUPPORTED_MODELS)})"
        ),
    )
    parser.add_argument(
        "--language-boost",
        default=None,
        help=(
            "MiniMax language_boost (default: derived from the course "
            "index.language, e.g. tr -> Turkish; 'auto' detects)"
        ),
    )
    parser.add_argument(
        "--text-normalization",
        choices=["basic", "quality"],
        default=DEFAULT_TEXT_NORMALIZATION,
        help=(
            "Text normalization mode (default: quality; quality only takes "
            "effect on speech-2.8 / 2.6, non-streaming)"
        ),
    )
    parser.add_argument(
        "--emotion",
        default=DEFAULT_EMOTION,
        help=f"Optional emotion ({', '.join(EMOTIONS)}); empty = model decides",
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        choices=list(SAMPLE_RATES),
        default=DEFAULT_SAMPLE_RATE,
        help=f"MP3 sample rate (default: {DEFAULT_SAMPLE_RATE})",
    )
    parser.add_argument(
        "--bitrate",
        type=int,
        choices=list(BITRATES),
        default=DEFAULT_BITRATE,
        help=f"MP3 bitrate (default: {DEFAULT_BITRATE})",
    )
    parser.add_argument(
        "--speed",
        type=float,
        default=DEFAULT_SPEED,
        help=f"Speech speed (default: {DEFAULT_SPEED})",
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
    p_all.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help='Output summary format (json emits a final machine-readable line)',
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
