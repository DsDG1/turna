"""Lucide SVG icon system (GUI 焕新 W1).

Vendored `Lucide <https://lucide.dev>`_ icons (ISC license) live in
``src/icons/svg/``. They are stroke-only 24x24 SVGs drawn with
``currentColor``; :func:`icon` / :func:`pixmap` recolor them to a semantic
palette role and rasterize at ``devicePixelRatio`` so they stay crisp on
high-DPI displays.

API::

    from src.icons import icon, pixmap, icon_names

    btn.setIcon(icon("save", size=18))
    label.setPixmap(pixmap("alert-circle", size=32, role="danger"))

Roles map to palette keys: ``default`` → text, ``muted`` → text_disabled,
``accent`` → accent_text, ``on_accent`` → text_on_accent, ``danger`` /
``success`` / ``warning`` / ``info`` → the same-named semantic colors.

Rendered pixmaps are cached by (name, size, color, dpr); a palette switch
produces different cache keys automatically (the resolved hex is part of
the key), so no explicit invalidation is needed. ``clear_icon_cache`` is
provided for tests.
"""
from __future__ import annotations

import logging
import sys
from pathlib import Path

from PySide6.QtCore import QByteArray, Qt
from PySide6.QtGui import QGuiApplication, QIcon, QPainter, QPixmap
from PySide6.QtSvg import QSvgRenderer

logger = logging.getLogger(__name__)


def _svg_dir() -> Path:
    """Locate the vendored SVG dir (handles the PyInstaller bundle layout)."""
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        return Path(meipass) / "src" / "icons" / "svg"
    return Path(__file__).resolve().parent / "svg"


_SVG_DIR = _svg_dir()

#: Semantic role -> palette key.
ROLE_TO_PALETTE_KEY: dict[str, str] = {
    "default": "text",
    "muted": "text_disabled",
    "secondary": "text_secondary",
    "accent": "accent_text",
    "accent_fill": "accent",
    "on_accent": "text_on_accent",
    "danger": "danger",
    "success": "success",
    "warning": "warning",
    "info": "info",
}

_ICON_CACHE: dict[tuple[str, int, str, float], QPixmap] = {}
_SVG_TEXT_CACHE: dict[str, str] = {}


def icon_names() -> list[str]:
    """Return the sorted list of available (vendored) icon names."""
    if not _SVG_DIR.is_dir():
        return []
    return sorted(p.stem for p in _SVG_DIR.glob("*.svg"))


def _load_svg_text(name: str) -> str | None:
    """Read and cache the raw SVG text for *name* (None when missing)."""
    cached = _SVG_TEXT_CACHE.get(name)
    if cached is not None:
        return cached
    path = _SVG_DIR / f"{name}.svg"
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        logger.debug("icons: missing svg %s", path)
        return None
    _SVG_TEXT_CACHE[name] = text
    return text


def _resolve_color(role: str, palette: dict[str, str] | None) -> str:
    """Resolve *role* to a hex color from *palette* (active when omitted)."""
    if palette is None:
        from src.theme import current_palette

        palette = current_palette()
    key = ROLE_TO_PALETTE_KEY.get(role, ROLE_TO_PALETTE_KEY["default"])
    return palette.get(key) or palette.get("text", "#E8EAF0")


def _dpr() -> float:
    """Best-effort primary-screen device pixel ratio (>= 1.0)."""
    try:
        screen = QGuiApplication.primaryScreen()
        if screen is not None:
            return max(1.0, float(screen.devicePixelRatio()))
    except Exception:
        pass
    return 1.0


def pixmap(
    name: str,
    *,
    size: int = 20,
    role: str = "default",
    palette: dict[str, str] | None = None,
) -> QPixmap:
    """Render *name* to a ``QPixmap`` of ``size`` logical px, colored by *role*.

    Rasterizes at ``size * devicePixelRatio`` and stamps the DPR back onto
    the pixmap, so Qt scales it crisply on high-DPI screens. Unknown names
    produce an empty (null) pixmap rather than raising — callers may treat
    ``pm.isNull()`` as "no icon".
    """
    color = _resolve_color(role, palette)
    dpr = _dpr()
    key = (name, int(size), color, dpr)
    cached = _ICON_CACHE.get(key)
    if cached is not None:
        return QPixmap(cached)

    pm = QPixmap()
    svg_text = _load_svg_text(name)
    if svg_text is None:
        return pm

    colored = svg_text.replace("currentColor", color)
    renderer = QSvgRenderer(QByteArray(colored.encode("utf-8")))
    if not renderer.isValid():
        logger.debug("icons: invalid svg for %s", name)
        return pm

    px = max(1, round(size * dpr))
    pm = QPixmap(px, px)
    pm.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pm)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
    renderer.render(painter)
    painter.end()
    pm.setDevicePixelRatio(dpr)

    _ICON_CACHE[key] = pm
    return QPixmap(pm)


def icon(
    name: str,
    *,
    size: int = 20,
    role: str = "default",
    palette: dict[str, str] | None = None,
) -> QIcon:
    """Return a ``QIcon`` for *name* colored by *role* at ``size`` px."""
    return QIcon(pixmap(name, size=size, role=role, palette=palette))


def tinted(name: str, color: str, *, size: int = 20) -> QIcon:
    """Return a ``QIcon`` tinted to an explicit *color* hex.

    Escape hatch for one-off colors that are not semantic roles (e.g. a
    template badge color). Prefer :func:`icon` with a role where possible.
    """
    pm = pixmap(name, size=size, role="default", palette={"text": color})
    return QIcon(pm)


def clear_icon_cache() -> None:
    """Drop all cached pixmaps and SVG texts (tests / hot restyling)."""
    _ICON_CACHE.clear()
    _SVG_TEXT_CACHE.clear()


__all__ = [
    "ROLE_TO_PALETTE_KEY",
    "clear_icon_cache",
    "icon",
    "icon_names",
    "pixmap",
    "tinted",
]
