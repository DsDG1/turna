"""M-04 voice→palette skill (pure Python, no Qt).

Input channel for ⌘K: optional local microphone transcription fills the
command palette text box. This is **not** a course-write skill — no
ConflictGuard, no sandbox, no undo, no ``dangerous`` flag, and no auto-
dispatch after transcription (user reviews then presses Enter; aligns
with C-06 "LLM candidates do not auto-Enter").

红线（§14.5.3 M-04）：
* 纯函数探测 / 转录 / 闭集 metrics；无 Qt、不写树、不写盘。
* 转录原文 / 音频波形 / 麦克风设备名一律不进 Timeline/telemetry —— 只记
  ``status`` / ``ok`` / 可选 ``engine``。
* 永不抛：坏输入 / 缺依赖 / 无麦 / 超时归一为状态串，对齐 §14.5.2。
* 默认关 ``experience/voice_palette``（§6.4；麦克风隐私 + 可选依赖非必装）。
* 默认本地 Sphinx（离线）；云端 Whisper 等另切片。
"""
from __future__ import annotations

from typing import Any, Literal

# Closed status set for voice results + telemetry (no free-form text).
VoiceStatus = Literal[
    "ok",
    "missing_dep",
    "no_mic",
    "timeout",
    "disabled",
    "too_long",
    "failed",
]

# Cap transcript length so a runaway recognizer cannot flood the palette.
TRANSCRIPT_MAX_CHARS = 500

# Default offline engine name recorded in closed-set metrics only.
DEFAULT_ENGINE = "sphinx"


def is_voice_palette_enabled(settings: Any) -> bool:
    """True only when the ``experience/voice_palette`` switch is on.

    Reads ``experience_voice_palette`` from a settings object/dataclass (or
    Mapping); never raises — missing/false → False (default off).
    """
    try:
        if settings is None:
            return False
        if isinstance(settings, dict) or hasattr(settings, "__getitem__"):
            try:
                return bool(settings.get("experience_voice_palette", False))
            except Exception:
                pass
        return bool(getattr(settings, "experience_voice_palette", False))
    except Exception:
        return False


def voice_available() -> tuple[bool, str]:
    """Lazy-probe whether local voice transcription can run.

    Returns ``(True, "ok")`` when both the ``speech_recognition`` package and
    a microphone backend (``pyaudio``) are importable; otherwise
    ``(False, reason)`` where reason ∈ {"missing_dep","no_mic"}. Never raises.
    """
    try:
        import speech_recognition  # noqa: F401
    except Exception:
        return False, "missing_dep"
    try:
        import pyaudio  # noqa: F401
    except Exception:
        # SpeechRecognition can use other backends, but design pins pyaudio.
        return False, "missing_dep"
    try:
        import speech_recognition as sr

        names = sr.Microphone.list_microphone_names()
        if not names:
            return False, "no_mic"
    except Exception:
        # list_microphone_names may fail without a live device; still treat
        # as available if packages import (actual capture maps no_mic later).
        pass
    return True, "ok"


def build_voice_metrics(status: str, *, ok: bool, engine: str = DEFAULT_ENGINE) -> dict:
    """Closed-set metrics payload — never includes transcript text.

    Keys: ``status``, ``ok``, ``engine``. Callers must not add free text.
    """
    st = str(status or "failed")
    eng = str(engine or DEFAULT_ENGINE)[:32]
    return {"status": st, "ok": bool(ok), "engine": eng}


def _cap_transcript(text: str) -> tuple[str, VoiceStatus]:
    """Trim whitespace; if over cap return truncated text with too_long."""
    try:
        cleaned = str(text or "").strip()
    except Exception:
        return "", "failed"
    if not cleaned:
        return "", "failed"
    if len(cleaned) > TRANSCRIPT_MAX_CHARS:
        return cleaned[:TRANSCRIPT_MAX_CHARS], "too_long"
    return cleaned, "ok"


def transcribe_once(
    *,
    lang: str = "en-US",
    timeout: float = 5.0,
    phrase_time_limit: float = 12.0,
    recognizer: Any | None = None,
    source: Any | None = None,
) -> tuple[str, VoiceStatus]:
    """Capture one utterance and transcribe with local Sphinx.

    Success → ``(text, "ok")`` (or ``"too_long"`` if truncated).
    Failures map to closed status strings. Never raises.

    Optional ``recognizer`` / ``source`` inject mocks for unit tests so CI
    never opens a real microphone.
    """
    try:
        avail, reason = voice_available()
        if not avail and recognizer is None:
            return "", reason  # type: ignore[return-value]

        if recognizer is None:
            import speech_recognition as sr

            recognizer = sr.Recognizer()
            try:
                mic_ctx = sr.Microphone()
            except Exception:
                return "", "no_mic"
            try:
                with mic_ctx as mic:
                    audio = recognizer.listen(
                        mic,
                        timeout=float(timeout),
                        phrase_time_limit=float(phrase_time_limit),
                    )
            except Exception as exc:
                name = type(exc).__name__
                if "WaitTimeout" in name or "Timeout" in name:
                    return "", "timeout"
                return "", "no_mic"
        else:
            # Injected path: source may be a pre-built AudioData or a context.
            try:
                if source is not None and hasattr(recognizer, "listen"):
                    audio = recognizer.listen(
                        source,
                        timeout=float(timeout),
                        phrase_time_limit=float(phrase_time_limit),
                    )
                elif source is not None:
                    audio = source
                else:
                    return "", "no_mic"
            except Exception as exc:
                name = type(exc).__name__
                if "WaitTimeout" in name or "Timeout" in name:
                    return "", "timeout"
                return "", "failed"

        # Local offline engine (default). Cloud engines are out of scope.
        try:
            text = recognizer.recognize_sphinx(audio, language=str(lang or "en-US"))
        except Exception as exc:
            name = type(exc).__name__
            msg = str(exc).lower()
            if "unknown" in name.lower() or "unknownvalue" in msg:
                return "", "failed"
            if "request" in name.lower():
                return "", "failed"
            # pocketsphinx missing often surfaces as RequestError/OSError
            if "sphinx" in msg or "pocketsphinx" in msg:
                return "", "missing_dep"
            return "", "failed"

        return _cap_transcript(text)
    except Exception:
        return "", "failed"


def status_message(status: str) -> str:
    """Short Chinese statusBar copy for a closed VoiceStatus. Never raises."""
    mapping = {
        "ok": "已填入语音文本，请确认后 Enter",
        "too_long": "语音过长已截断，请确认后 Enter",
        "missing_dep": "语音输入不可用：请安装 SpeechRecognition + pyaudio（可选依赖）",
        "no_mic": "未检测到麦克风",
        "timeout": "未听到语音（超时）",
        "disabled": "语音输入未开启（设置 ▸ 体验 OS）",
        "failed": "语音识别失败",
    }
    try:
        return mapping.get(str(status or "failed"), mapping["failed"])
    except Exception:
        return "语音识别失败"
