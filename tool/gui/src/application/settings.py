"""Application-wide user settings model and QSettings persistence.

This module centralises all user-configurable preferences for the Varnamala
course editor. It intentionally stays close to Qt's QSettings so the rest of
the GUI can keep using the same storage backend without a migration.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from PySide6.QtCore import QSettings


@dataclass
class Settings:
    """User preferences for the course editor.

    Most attributes match keys persisted under the ``Varnamala/CourseEditor``
    QSettings namespace. ``ai_api_key`` is intentionally memory-only and is
    never written to disk; it is cleared when the application exits.
    """

    # Appearance
    theme: str = "dark"  # "dark" or "light"
    ui_scale_percent: int = 100  # 80 .. 150, step 10

    # AI provider configuration. ai_base_url and ai_model are persisted;
    # ai_api_key is memory-only for security.
    ai_base_url: str = ""
    ai_api_key: str = ""
    ai_model: str = ""
    # Currently selected provider preset ("deepseek", "openai", "moonshot",
    # "ollama", or "custom"). Used by SettingsDialog to fill defaults.
    ai_provider: str = "custom"
    # Max auto-retry rounds when a generated section fails validation (0 = no
    # retry, 1 = one correction round). Clamped to [0, 5].
    ai_retry_max: int = 1
    # Network timeout for ordinary AI requests (seconds). Clamped to [5, 600].
    ai_timeout: float = 120.0
    # Sampling temperature. Clamped to [0.0, 2.0].
    ai_temperature: float = 0.7
    # Whether to send reasoning/thinking payload fields. DeepSeek preset sets
    # this to True by default; custom preset leaves it to the user.
    ai_supports_reasoning: bool = False

    # --- Advanced AI options (aiEnhance.md 第三枪 批次①) ---
    # Optional chat-side model (alignment / explanation / chat). Empty = use
    # ``ai_model``. Lets users route cheap conversational calls to a smaller
    # model while JSON generation goes through ``ai_model_json`` (or ``ai_model``).
    ai_model_chat: str = ""
    # Optional JSON-side model (course / lesson / item transform / correction /
    # outline / extract). Empty = use ``ai_model``.
    ai_model_json: str = ""
    # ``auto`` (default) tries ``json_schema`` response format and falls back to
    # ``json_object`` if the provider returns 400 / "unsupported". ``on`` forces
    # ``json_schema``; ``off`` forces ``json_object``.
    ai_strict_schema: str = "auto"
    # In-memory LRU cache of AI JSON responses (sha256 of model+messages). Off
    # by default to preserve deterministic telemetry in tests.
    ai_cache_enabled: bool = False
    # Auto second-pass to fill ``[待补]`` / needs-review stubs after generation.
    # Off by default; opt-in per aiEnhance.md P1-7/P1-10.
    ai_fill_needs_review: bool = False
    # Max parallel lesson-generation workers in phased / pipeline mode. 1 =
    # sequential (safe default). Clamped to [1, 8].
    ai_max_parallel_lessons: int = 1
    # Default workshop generation mode when a new project is opened:
    # ``fast`` (single-shot full section) or ``refine`` (outline -> per-lesson).
    ai_pipeline_default_mode: str = "fast"

    # Editor behaviour
    auto_save_on_close: bool = False
    undo_limit: int = 100

    # Recent repositories (legacy JSON blob; kept as list[dict])
    recent_repos: list[dict[str, Any]] = field(default_factory=list)

    # --- Git library configuration ---
    # Default clone root directory for new git remotes.
    git_clone_root: str = ""
    # Path to the git binary (empty = use system "git").
    git_bin: str = ""
    # Default language code for copy-to-assets (e.g. "tr", "en").
    default_lang_code: str = ""
    # LAN collaboration server defaults.
    lan_default_port: int = 5000
    lan_bind_address: str = "0.0.0.0"
    # LAN server auth token (empty = no auth). Stored in QSettings (not
    # secret-grade; for LAN-only access control).
    lan_token: str = ""
    # Per-call git subprocess timeout (seconds).
    git_timeout: float = 60.0
    # Override for the assets repo root (empty = auto-detect via parents[4]).
    assets_repo_root: str = ""

    # --- MiniMax TTS (listening audio generation) ---
    # Non-secret tuning is persisted; tts_api_key is memory-only and never
    # written to disk (mirrors ai_api_key). The API key is forwarded to the
    # generate_audio subprocess via the environment, not argv.
    tts_voice_id: str = "female-tianmei"
    tts_model: str = "speech-2.8-hd"
    tts_speed: float = 0.9  # clamped to 0.5..2.0
    tts_force: bool = False
    tts_api_key: str = ""  # memory-only

    @classmethod
    def load_from_qsettings(cls, qsettings: QSettings) -> "Settings":
        """Load a Settings instance from the supplied QSettings object."""
        recent_raw = qsettings.value("recent_repos", "[]")
        recent_repos: list[dict[str, Any]] = []
        if isinstance(recent_raw, str):
            try:
                parsed = json.loads(recent_raw)
                if isinstance(parsed, list):
                    recent_repos = [
                        item for item in parsed
                        if isinstance(item, dict) and item.get("path")
                    ]
            except Exception:
                recent_repos = []

        # Read persisted AI config. The API key is intentionally memory-only;
        # we do not load it from QSettings and actively remove any stale value
        # left behind by earlier versions.
        ai_base_url = _str_or_empty(qsettings.value("ai/base_url", ""))
        ai_model = _str_or_empty(qsettings.value("ai/model", ""))
        ai_provider = _str_or_default(qsettings.value("ai/provider", "custom"), "custom")
        if ai_provider not in {"deepseek", "openai", "moonshot", "ollama", "custom"}:
            ai_provider = "custom"
        if qsettings.contains("ai/api_key"):
            qsettings.remove("ai/api_key")

        theme = _str_or_default(qsettings.value("appearance/theme", "dark"), "dark")
        if theme not in {"dark", "light", "high-contrast-dark", "high-contrast-light"}:
            theme = "dark"

        scale = _int_or_default(qsettings.value("appearance/ui_scale_percent", 100), 100)
        scale = max(80, min(150, scale))

        auto_save = _bool_or_default(
            qsettings.value("editor/auto_save_on_close", False), False
        )
        undo_limit = _int_or_default(qsettings.value("editor/undo_limit", 100), 100)
        undo_limit = max(10, min(500, undo_limit))

        ai_retry_max = _int_or_default(qsettings.value("ai/retry_max", 1), 1)
        ai_retry_max = max(0, min(5, ai_retry_max))

        ai_timeout = _float_or_default(qsettings.value("ai/timeout", 120.0), 120.0)
        ai_timeout = max(5.0, min(600.0, ai_timeout))

        ai_temperature = _float_or_default(qsettings.value("ai/temperature", 0.7), 0.7)
        ai_temperature = max(0.0, min(2.0, ai_temperature))

        ai_supports_reasoning = _bool_or_default(
            qsettings.value("ai/supports_reasoning", False), False
        )

        # Advanced AI options (第三枪 批次①). All keys are tolerant of missing
        # values so older installs upgrade cleanly.
        ai_model_chat = _str_or_empty(qsettings.value("ai/model_chat", ""))
        ai_model_json = _str_or_empty(qsettings.value("ai/model_json", ""))
        ai_strict_schema = _str_or_default(
            qsettings.value("ai/strict_schema", "auto"), "auto"
        )
        if ai_strict_schema not in {"auto", "on", "off"}:
            ai_strict_schema = "auto"
        ai_cache_enabled = _bool_or_default(
            qsettings.value("ai/cache_enabled", False), False
        )
        ai_fill_needs_review = _bool_or_default(
            qsettings.value("ai/fill_needs_review", False), False
        )
        ai_max_parallel_lessons = _int_or_default(
            qsettings.value("ai/max_parallel_lessons", 1), 1
        )
        ai_max_parallel_lessons = max(1, min(8, ai_max_parallel_lessons))
        ai_pipeline_default_mode = _str_or_default(
            qsettings.value("ai/pipeline_default_mode", "fast"), "fast"
        )
        if ai_pipeline_default_mode not in {"fast", "refine"}:
            ai_pipeline_default_mode = "fast"

        # Git library configuration
        git_clone_root = _str_or_empty(qsettings.value("git/clone_root", ""))
        git_bin = _str_or_empty(qsettings.value("git/bin", ""))
        default_lang_code = _str_or_empty(qsettings.value("git/default_lang", ""))
        lan_default_port = _int_or_default(
            qsettings.value("git/lan_port", 5000), 5000
        )
        lan_default_port = max(1, min(65535, lan_default_port))
        lan_bind_address = _str_or_default(
            qsettings.value("git/lan_bind", "0.0.0.0"), "0.0.0.0"
        )
        lan_token = _str_or_empty(qsettings.value("git/lan_token", ""))
        git_timeout = _float_or_default(qsettings.value("git/timeout", 60.0), 60.0)
        git_timeout = max(5.0, min(600.0, git_timeout))
        assets_repo_root = _str_or_empty(qsettings.value("git/assets_root", ""))

        # MiniMax TTS config. API key is memory-only (never loaded from disk);
        # we actively remove any stale value like ai_api_key.
        tts_voice_id = _str_or_default(qsettings.value("tts/voice_id", ""), "female-tianmei")
        tts_voice_id = tts_voice_id or "female-tianmei"
        tts_model = _str_or_default(qsettings.value("tts/model", ""), "speech-2.8-hd")
        tts_model = tts_model or "speech-2.8-hd"
        tts_speed = _float_or_default(qsettings.value("tts/speed", 0.9), 0.9)
        tts_speed = max(0.5, min(2.0, tts_speed))
        tts_force = _bool_or_default(qsettings.value("tts/force", False), False)
        if qsettings.contains("tts/api_key"):
            qsettings.remove("tts/api_key")

        return cls(
            theme=theme,
            ui_scale_percent=scale,
            ai_base_url=ai_base_url,
            ai_api_key="",  # Memory-only: never restore from storage.
            ai_model=ai_model,
            ai_provider=ai_provider,
            ai_retry_max=ai_retry_max,
            ai_timeout=ai_timeout,
            ai_temperature=ai_temperature,
            ai_supports_reasoning=ai_supports_reasoning,
            ai_model_chat=ai_model_chat,
            ai_model_json=ai_model_json,
            ai_strict_schema=ai_strict_schema,
            ai_cache_enabled=ai_cache_enabled,
            ai_fill_needs_review=ai_fill_needs_review,
            ai_max_parallel_lessons=ai_max_parallel_lessons,
            ai_pipeline_default_mode=ai_pipeline_default_mode,
            auto_save_on_close=auto_save,
            undo_limit=undo_limit,
            recent_repos=recent_repos,
            git_clone_root=git_clone_root,
            git_bin=git_bin,
            default_lang_code=default_lang_code,
            lan_default_port=lan_default_port,
            lan_bind_address=lan_bind_address,
            lan_token=lan_token,
            git_timeout=git_timeout,
            assets_repo_root=assets_repo_root,
            tts_voice_id=tts_voice_id,
            tts_model=tts_model,
            tts_speed=tts_speed,
            tts_force=tts_force,
            tts_api_key="",  # Memory-only: never restore from storage.
        )

    def save_to_qsettings(self, qsettings: QSettings) -> None:
        """Persist this Settings instance to the supplied QSettings object."""
        qsettings.setValue("appearance/theme", self.theme)
        qsettings.setValue("appearance/ui_scale_percent", self.ui_scale_percent)

        qsettings.setValue("ai/base_url", self.ai_base_url)
        # ai/api_key is never persisted. Ensure any legacy value is gone.
        if qsettings.contains("ai/api_key"):
            qsettings.remove("ai/api_key")
        qsettings.setValue("ai/model", self.ai_model)
        qsettings.setValue("ai/provider", self.ai_provider)
        qsettings.setValue("ai/retry_max", self.ai_retry_max)
        qsettings.setValue("ai/timeout", self.ai_timeout)
        qsettings.setValue("ai/temperature", self.ai_temperature)
        qsettings.setValue("ai/supports_reasoning", self.ai_supports_reasoning)

        # Advanced AI options (第三枪 批次①)
        qsettings.setValue("ai/model_chat", self.ai_model_chat)
        qsettings.setValue("ai/model_json", self.ai_model_json)
        qsettings.setValue("ai/strict_schema", self.ai_strict_schema)
        qsettings.setValue("ai/cache_enabled", self.ai_cache_enabled)
        qsettings.setValue("ai/fill_needs_review", self.ai_fill_needs_review)
        qsettings.setValue("ai/max_parallel_lessons", self.ai_max_parallel_lessons)
        qsettings.setValue("ai/pipeline_default_mode", self.ai_pipeline_default_mode)

        qsettings.setValue("editor/auto_save_on_close", self.auto_save_on_close)
        qsettings.setValue("editor/undo_limit", self.undo_limit)

        qsettings.setValue(
            "recent_repos",
            json.dumps(self.recent_repos[:10], ensure_ascii=False),
        )

        # Git library configuration
        qsettings.setValue("git/clone_root", self.git_clone_root)
        qsettings.setValue("git/bin", self.git_bin)
        qsettings.setValue("git/default_lang", self.default_lang_code)
        qsettings.setValue("git/lan_port", self.lan_default_port)
        qsettings.setValue("git/lan_bind", self.lan_bind_address)
        qsettings.setValue("git/lan_token", self.lan_token)
        qsettings.setValue("git/timeout", self.git_timeout)
        qsettings.setValue("git/assets_root", self.assets_repo_root)

        # MiniMax TTS config. tts/api_key is never persisted; ensure any legacy
        # value is gone.
        qsettings.setValue("tts/voice_id", self.tts_voice_id)
        qsettings.setValue("tts/model", self.tts_model)
        qsettings.setValue("tts/speed", self.tts_speed)
        qsettings.setValue("tts/force", self.tts_force)
        if qsettings.contains("tts/api_key"):
            qsettings.remove("tts/api_key")

    def add_recent_repo(self, path: Path | str) -> None:
        """Add a repository path to the top of the recent list."""
        from datetime import datetime, timezone

        path_str = str(Path(path).resolve())
        repos = [r for r in self.recent_repos if r.get("path") != path_str]
        repos.insert(
            0,
            {"path": path_str, "opened_at": datetime.now(timezone.utc).isoformat()},
        )
        self.recent_repos = repos[:10]

    def remove_recent_repo(self, path: str) -> None:
        """Remove a single repository entry by path."""
        self.recent_repos = [r for r in self.recent_repos if r.get("path") != path]

    def clear_recent_repos(self) -> None:
        """Clear the entire recent repository history."""
        self.recent_repos = []

    def clone(self) -> "Settings":
        """Return a deep-ish copy suitable for editing in a dialog."""
        return Settings(
            theme=self.theme,
            ui_scale_percent=self.ui_scale_percent,
            ai_base_url=self.ai_base_url,
            ai_api_key=self.ai_api_key,
            ai_model=self.ai_model,
            ai_provider=self.ai_provider,
            ai_retry_max=self.ai_retry_max,
            ai_timeout=self.ai_timeout,
            ai_temperature=self.ai_temperature,
            ai_supports_reasoning=self.ai_supports_reasoning,
            ai_model_chat=self.ai_model_chat,
            ai_model_json=self.ai_model_json,
            ai_strict_schema=self.ai_strict_schema,
            ai_cache_enabled=self.ai_cache_enabled,
            ai_fill_needs_review=self.ai_fill_needs_review,
            ai_max_parallel_lessons=self.ai_max_parallel_lessons,
            ai_pipeline_default_mode=self.ai_pipeline_default_mode,
            auto_save_on_close=self.auto_save_on_close,
            undo_limit=self.undo_limit,
            recent_repos=[dict(r) for r in self.recent_repos],
            git_clone_root=self.git_clone_root,
            git_bin=self.git_bin,
            default_lang_code=self.default_lang_code,
            lan_default_port=self.lan_default_port,
            lan_bind_address=self.lan_bind_address,
            lan_token=self.lan_token,
            git_timeout=self.git_timeout,
            assets_repo_root=self.assets_repo_root,
            tts_voice_id=self.tts_voice_id,
            tts_model=self.tts_model,
            tts_speed=self.tts_speed,
            tts_force=self.tts_force,
            tts_api_key=self.tts_api_key,
        )


def _str_or_empty(value: Any) -> str:
    if isinstance(value, str):
        return value
    return ""


def _str_or_default(value: Any, default: str) -> str:
    if isinstance(value, str):
        return value
    return default


def _int_or_default(value: Any, default: int) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return default
    if isinstance(value, bool):
        return int(value)
    return default


def _float_or_default(value: Any, default: float) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return default
    return default


def _bool_or_default(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.lower()
        if lowered in {"true", "1", "yes"}:
            return True
        if lowered in {"false", "0", "no"}:
            return False
        return default
    return default
