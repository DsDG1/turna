"""Git credential storage abstraction.

Prefers the OS keyring (via the ``keyring`` library) for HTTPS tokens and
secrets. When the keyring backend is unavailable (headless Linux without
D-Bus, sandboxed environments, etc.) it transparently falls back to QSettings
with light obfuscation and records a one-time warning.

SSH key paths are not secret and are stored directly in QSettings.
"""
from __future__ import annotations

import base64
import urllib.parse
from typing import Optional

from PySide6.QtCore import QSettings

_KEYRING_SERVICE = "turna.git"
# Legacy keyring service from the pre-rebrand "Varnamala" days. We still
# read it for one-shot migration: when a token lives under the legacy
# service but not under the new one, treat it as the user's choice and
# copy it to the new service so future reads are stable.
_KEYRING_SERVICE_LEGACY = "varnamala.git"
_KEYRING_UNAVAILABLE_WARNED = False


def _read_keyring_token(account: str) -> Optional[str]:
    """Read token from the active keyring service; on miss, fall back to the
    legacy service and copy the value to the new one for stability."""
    import keyring  # noqa: WPS433
    value = keyring.get_password(_KEYRING_SERVICE, account)
    if value:
        return value
    legacy = keyring.get_password(_KEYRING_SERVICE_LEGACY, account)
    if not legacy:
        return None
    try:
        keyring.set_password(_KEYRING_SERVICE, account, legacy)
    except Exception:
        # If the new service refuses to write, return the legacy value
        # without persisting so callers at least see the token once.
        pass
    return legacy


def _keyring_available() -> bool:
    """Return True if the keyring backend can be imported and has a usable backend."""
    global _KEYRING_UNAVAILABLE_WARNED
    try:
        import keyring  # noqa: WPS433
        backend = keyring.get_keyring()
        # The fail backend always returns None and is the default when no real
        # backend is wired; treat it as unavailable so we fall back.
        if backend is None:
            return False
        return type(backend).__name__ != "fail.Keyring"
    except Exception:
        return False


def _warn_keyring_unavailable_once() -> None:
    global _KEYRING_UNAVAILABLE_WARNED
    if not _KEYRING_UNAVAILABLE_WARNED:
        import warnings
        warnings.warn(
            "keyring 后端不可用，Git 凭据将回退到 QSettings 存储（安全性较低）。"
            "建议安装并配置一个 keyring 后端（如 SecretStorage / keyringctl）。",
            stacklevel=2,
        )
        _KEYRING_UNAVAILABLE_WARNED = True


def _account_for_url(url: str) -> str:
    """Derive a stable account string from a remote URL (by host)."""
    if not url:
        return "default"
    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname or url.split(":")[0].split("/")[-1] or "default"
    return host


# --- HTTPS token -------------------------------------------------------------

def get_git_token(url: str) -> Optional[str]:
    """Return the stored HTTPS token for ``url``, or None if not set."""
    account = _account_for_url(url)
    if _keyring_available():
        try:
            return _read_keyring_token(account)
        except Exception:
            _warn_keyring_unavailable_once()
    # Fallback: QSettings obfuscated.
    qsettings = QSettings("Turna", "CourseEditor")
    raw = qsettings.value(f"git/token/{account}", "")
    if not raw:
        return None
    try:
        return base64.b64decode(raw.encode("utf-8")).decode("utf-8")
    except Exception:
        return None


def set_git_token(url: str, token: str) -> None:
    """Store ``token`` for ``url``."""
    account = _account_for_url(url)
    if _keyring_available():
        try:
            import keyring  # noqa: WPS433
            keyring.set_password(_KEYRING_SERVICE, account, token)
            return
        except Exception:
            _warn_keyring_unavailable_once()
    # Fallback: QSettings obfuscated.
    qsettings = QSettings("Turna", "CourseEditor")
    encoded = base64.b64encode(token.encode("utf-8")).decode("utf-8")
    qsettings.setValue(f"git/token/{account}", encoded)


def delete_git_token(url: str) -> bool:
    """Delete the stored token for ``url``. Return True if something was removed."""
    account = _account_for_url(url)
    if _keyring_available():
        try:
            import keyring  # noqa: WPS433
            existing = keyring.get_password(_KEYRING_SERVICE, account)
            legacy_existing = keyring.get_password(_KEYRING_SERVICE_LEGACY, account)
            if existing is None and legacy_existing is None:
                return False
            if existing is not None:
                keyring.delete_password(_KEYRING_SERVICE, account)
            if legacy_existing is not None:
                try:
                    keyring.delete_password(_KEYRING_SERVICE_LEGACY, account)
                except Exception:
                    # Old service may be unwritable; leave it intact.
                    pass
            return True
        except Exception:
            _warn_keyring_unavailable_once()
    qsettings = QSettings("Turna", "CourseEditor")
    key = f"git/token/{account}"
    if not qsettings.contains(key):
        return False
    qsettings.remove(key)
    return True


# --- SSH key path ------------------------------------------------------------

def get_ssh_key_path() -> str:
    """Return the configured SSH key path (empty string if not set)."""
    qsettings = QSettings("Turna", "CourseEditor")
    return str(qsettings.value("git/ssh_key_path", ""))


def set_ssh_key_path(path: str) -> None:
    """Persist the SSH key path."""
    qsettings = QSettings("Turna", "CourseEditor")
    qsettings.setValue("git/ssh_key_path", path)


def keyring_status() -> dict[str, object]:
    """Return a diagnostic dict about the keyring backend."""
    available = _keyring_available()
    backend_name = "unavailable"
    if available:
        try:
            import keyring  # noqa: WPS433
            backend = keyring.get_keyring()
            backend_name = type(backend).__name__
        except Exception:
            backend_name = "error"
    return {
        "available": available,
        "backend": backend_name,
        "service": _KEYRING_SERVICE,
    }
