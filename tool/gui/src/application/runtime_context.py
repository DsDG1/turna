"""Live settings / AI-config access for non-dialog code.

``MainWindow`` registers getter callables here at startup, so lower layers
(backend/, application/) can read the current settings without importing
``src.app`` — that reverse dependency was the root of the app ↔ backend
import cycles. Providers must be callables (not snapshots): the Settings
dialog and ``_save_ai_config`` rebind attributes on the window, and callers
expect the latest value on every read.
"""
from __future__ import annotations

from typing import Any, Callable

from src.application.settings import Settings
from src.backend.ai import AiApiConfig
import logging
logger = logging.getLogger(__name__)

SettingsFn = Callable[[], Settings]
ConfigFn = Callable[[], AiApiConfig]

_settings_fn: SettingsFn | None = None
_config_fn: ConfigFn | None = None
_owner: Any = None


def set_providers(
    owner: Any,
    *,
    settings_fn: SettingsFn,
    config_fn: ConfigFn,
) -> None:
    """Register live getters (last registration wins; one window in practice)."""
    global _settings_fn, _config_fn, _owner
    _settings_fn = settings_fn
    _config_fn = config_fn
    _owner = owner


def clear_providers(owner: Any) -> None:
    """Drop the registration when ``owner`` is still the active one."""
    global _settings_fn, _config_fn, _owner
    if _owner is owner:
        _settings_fn = None
        _config_fn = None
        _owner = None


def current_settings() -> Settings:
    """Current settings from the registered provider, or a default."""
    try:
        if _settings_fn is not None:
            value = _settings_fn()
            if isinstance(value, Settings):
                return value
    except Exception:
        logger.debug("application/runtime_context.py:current_settings best-effort step failed", exc_info=True)
    return Settings()


def current_ai_config() -> AiApiConfig:
    """Current AI config from the registered provider, or a default."""
    try:
        if _config_fn is not None:
            value = _config_fn()
            if isinstance(value, AiApiConfig):
                return value
    except Exception:
        logger.debug("application/runtime_context.py:current_ai_config best-effort step failed", exc_info=True)
    return AiApiConfig()
