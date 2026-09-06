"""Injectable AI runtime handles (M3).

Dialogs and panels must receive ``config_fn`` / ``settings_fn`` (or an
:class:`AiRuntime`) from the host instead of importing ``src.app``.

``src.app.current_ai_config`` / ``current_settings`` remain for MainWindow
tests and non-dialog code; dialogs are gated by
``tool/check_ai_boundaries.py --fail-dialogs-app``.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from src.application.settings import Settings
from src.backend.ai import AiApiConfig
from src.application.experience_host import ExperienceHost


@dataclass(frozen=True)
class AiRuntime:
    """Callable providers for live AI config + settings.

    Using callables (not snapshots) ensures Settings dialog changes are
    visible on the next request without re-injecting dialogs.
    """

    config_fn: Callable[[], AiApiConfig]
    settings_fn: Callable[[], Settings]

    def config(self) -> AiApiConfig:
        return self.config_fn()

    def settings(self) -> Settings:
        return self.settings_fn()


def empty_ai_runtime() -> AiRuntime:
    """Default empty config/settings (tests / no MainWindow)."""
    return AiRuntime(
        config_fn=lambda: AiApiConfig(),
        settings_fn=lambda: Settings(),
    )


def runtime_from_host(host: ExperienceHost) -> AiRuntime:
    """Build an :class:`AiRuntime` from a MainWindow-like host object."""

    def config_fn() -> AiApiConfig:
        curr = host
        while curr is not None:
            cfg = getattr(curr, "_ai_config", None)
            if isinstance(cfg, AiApiConfig):
                return cfg
            curr = getattr(curr, "_parent_window", None) or (curr.parentWidget() if hasattr(curr, "parentWidget") else None)
        try:
            from src.application.runtime_context import current_ai_config
            return current_ai_config()
        except Exception:
            return AiApiConfig()

    def settings_fn() -> Settings:
        curr = host
        while curr is not None:
            s = getattr(curr, "_settings_obj", None)
            if isinstance(s, Settings):
                return s
            curr = getattr(curr, "_parent_window", None) or (curr.parentWidget() if hasattr(curr, "parentWidget") else None)
        try:
            from src.application.runtime_context import current_settings
            return current_settings()
        except Exception:
            return Settings()

    return AiRuntime(config_fn=config_fn, settings_fn=settings_fn)
