"""Bridge between the GUI and the ``generate_audio`` TTS script.

Mirrors ``api.py``'s role for ``course_cli``: this is the sanctioned place the
GUI shells out to ``tool/generate_audio.py``. Pure stdlib, no PySide6, so it is
unit-testable without a display.

The script is language-agnostic: the GUI passes both ``--course-dir`` and
``--sounds-dir`` (derived from the loaded course's ``index.language``), so any
language course can be synthesized into ``assets/sounds/<lang>/listening/``.
The MiniMax API key travels to the subprocess via the environment (never argv,
never persisted).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

_TOOL_DIR = Path(__file__).resolve().parents[3]
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

from src.backend.course_adapter import _REPO_ROOT  # noqa: E402
import logging
logger = logging.getLogger(__name__)

#: Path to the standalone TTS script this bridge drives.
GENERATE_AUDIO_SCRIPT = _TOOL_DIR / "generate_audio.py"

#: Timeout for the subprocess TTS run (TTS can be slow; generous but bounded so
#: a hung child cannot freeze the GUI forever).
_TTS_TIMEOUT_SECONDS = 3600


@dataclass(frozen=True)
class TtsOptions:
    """TTS generation options collected from the dialog."""

    voice_id: str = "female-tianmei"
    model: str = "speech-2.8-hd"
    speed: float = 0.9
    force: bool = False


@dataclass(frozen=True)
class GenerateResult:
    generated: int
    skipped: int
    total: int


def repo_root_for(settings) -> Path:
    """Return the assets repo root, honoring ``settings.assets_repo_root``."""
    root = getattr(settings, "assets_repo_root", "") or ""
    if root:
        return Path(root)
    return _REPO_ROOT


def _course_language(course_dir: Path) -> str:
    """Read ``index.language`` from a course dir; '' if unreadable."""
    try:
        with (course_dir / "index.json").open("r", encoding="utf-8") as f:
            index = json.load(f)
        return str(index.get("language") or index.get("lang") or "")
    except Exception:
        return ""


def sounds_dir_for(course_dir: Path, settings) -> Path:
    """Return ``<repo>/assets/sounds/<language>`` for the course."""
    lang = _course_language(course_dir) or "en"
    return repo_root_for(settings) / "assets" / "sounds" / lang


def _preview_via_subprocess(course_dir: Path, sounds_dir: Path) -> dict[str, int]:
    """Count total/existing assets via a no-TTS subprocess fallback."""
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(GENERATE_AUDIO_SCRIPT),
                "--course-dir",
                str(course_dir),
                "--sounds-dir",
                str(sounds_dir),
                "all",
                "--format",
                "json",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=60,
        )
        for line in (proc.stdout or "").splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                counts = json.loads(line)
            except ValueError:
                continue
            total = int(counts.get("total", 0))
            existing = int(counts.get("skipped", 0))
            return {"total": total, "existing": existing}
    except Exception:
        logger.debug("backend/generate_audio_client.py:_preview_via_subprocess best-effort step failed", exc_info=True)
    return {"total": 0, "existing": 0}


def preview_generation(course_dir: Path, settings) -> dict[str, int]:
    """Compute how many listening assets will be generated / skipped.

    Fast path imports ``generate_audio`` and calls ``collect_entries`` (pure
    JSON reads, no network) to count total and how many already exist. Falls
    back to a subprocess count if the in-process import fails.
    """
    sounds_dir = sounds_dir_for(course_dir, settings)
    total = 0
    existing = 0
    try:
        import generate_audio  # noqa: PLC0415

        entries = generate_audio.collect_entries(Path(course_dir))
        total = len(entries)
        existing = sum(
            1
            for e in entries
            if generate_audio.listening_asset_path(e.audio_asset, sounds_dir).exists()
        )
    except Exception:
        return _preview_via_subprocess(course_dir, sounds_dir)
    return {"total": total, "existing": existing}


def build_command(
    course_dir: Path, sounds_dir: Path, opts: TtsOptions
) -> list[str]:
    """Build the argv for the generate_audio subprocess."""
    cmd = [
        sys.executable,
        str(GENERATE_AUDIO_SCRIPT),
        "--course-dir",
        str(course_dir),
        "--sounds-dir",
        str(sounds_dir),
        "--voice-id",
        opts.voice_id,
        "--model",
        opts.model,
        "--speed",
        f"{opts.speed:g}",
    ]
    if opts.force:
        cmd.append("--force")
    cmd.extend(["all", "--format", "json"])
    return cmd


def run_generate(
    course_dir: Path,
    sounds_dir: Path,
    opts: TtsOptions,
    api_key: str,
    on_line: Callable[[str], None] | None = None,
    cancel_check: Callable[[], bool] | None = None,
) -> GenerateResult:
    """Run the TTS subprocess, forwarding stdout lines and parsing the summary.

    ``on_line`` receives each human-readable stdout line (including the
    ``Generated <path>`` lines, used for progress). ``cancel_check`` is polled
    between lines so a cooperative cancel can terminate the run.

    The API key is injected via ``MINIMAX_API_KEY`` in the child env; it never
    appears in argv.
    """
    cmd = build_command(course_dir, sounds_dir, opts)
    env = dict(os.environ)
    if api_key:
        env["MINIMAX_API_KEY"] = api_key

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        env=env,
    )
    assert proc.stdout is not None
    assert proc.stderr is not None

    generated = 0
    skipped = 0
    total = 0
    try:
        for raw in proc.stdout:
            line = raw.rstrip("\n")
            if cancel_check and cancel_check():
                proc.terminate()
                break
            if on_line:
                on_line(line)
            stripped = line.strip()
            if stripped.startswith("Generated "):
                generated += 1
            elif stripped.startswith("{"):
                try:
                    counts = json.loads(stripped)
                    generated = int(counts.get("generated", generated))
                    skipped = int(counts.get("skipped", skipped))
                    total = int(counts.get("total", total))
                except ValueError:
                    logger.debug("backend/generate_audio_client.py:run_generate best-effort step failed", exc_info=True)
    finally:
        proc.wait()
        stderr = proc.stderr.read()

    if proc.returncode not in (0, None) and not (cancel_check and cancel_check()):
        raise RuntimeError(
            f"generate_audio 退出码 {proc.returncode}：\n{stderr.strip() or '(无错误输出)'}"
        )
    return GenerateResult(generated=generated, skipped=skipped, total=total)


def run_tts_generation(
    course_dir: Path,
    sounds_dir: Path,
    opts: TtsOptions,
    api_key: str,
    *,
    on_progress: Callable[[int, int], None],
    is_cancelled: Callable[[], bool],
) -> GenerateResult:
    """Run the blocking TTS subprocess with parsed-line progress callbacks.

    Pure-stdlib orchestration (no Qt): ``on_progress(files_done, total)``
    fires per "Generated" line and on the total-count JSON line; ``total``
    is ``-1`` until the subprocess reports it. Raises whatever
    ``run_generate`` raises — the Qt shell in ``application/audio_worker``
    decides how failures surface.
    """
    state = {"done": 0, "total": 0}

    def _on_line(line: str) -> None:
        stripped = line.strip()
        if stripped.startswith("Generated "):
            state["done"] += 1
            on_progress(state["done"], state["total"] or -1)
        elif stripped.startswith("{"):
            try:
                counts = json.loads(stripped)
                state["total"] = int(counts.get("total", state["total"]))
                on_progress(state["done"], state["total"])
            except ValueError:
                logger.debug("backend/generate_audio_client.py:run_tts_generation best-effort step failed", exc_info=True)

    return run_generate(
        course_dir,
        sounds_dir,
        opts,
        api_key,
        on_line=_on_line,
        cancel_check=is_cancelled,
    )
