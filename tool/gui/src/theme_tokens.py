"""Semantic color tokens for the Turna GUI course editor.

This module is the single source of truth for all theme palettes. It is
deliberately free of Qt imports so the token tables and helpers can be
unit-tested headlessly and reused by ``theme.py`` (which owns the QSS
stylesheet generation and ``QApplication`` wiring).

Design language: **Turna** - aligned with the Flutter app's
``TurnaTheme`` (``lib/views/theme.dart``). The primary accent family is
navy / teal / reed with restrained clay and sand accents. Four palettes are provided:

* ``dark``  - default, Turna-tinted dark surfaces
* ``light`` - bright, airy surfaces with Turna teal accents
* ``high-contrast-dark``  - near-black surfaces, pure-white text, thick borders
* ``high-contrast-light`` - pure-white surfaces, near-black text, thick borders

Every palette exposes the same key set so widgets can look up any token
without caring which theme is active. The ``ai_*`` namespace is preserved
for backward compatibility with the chat / orbit / workshop widgets.
"""
from __future__ import annotations

# ---------------------------------------------------------------------------
# Canonical Turna brand colors (mirrors lib/views/theme.dart — ADR 0033)
# Scheme A locked: BRAND_TEAL stays #1F727E. Keep hex in sync with Flutter.
# ---------------------------------------------------------------------------
BRAND_NAVY = "#19324A"
BRAND_TEAL = "#1F727E"       # primary / main CTA
BRAND_TEAL_LIGHT = "#2F7F8E" # primaryLight / button gradient end
BRAND_SKY = "#4A95A8"        # information and chart accent
BRAND_REED = "#78C7B8"       # low-intensity highlight and glow
BRAND_TEAL_DARK = "#145A64"  # pressed (≡ Flutter brandTealDark / primaryDark)
BRAND_CLAY = "#B85C3F"       # anatolianClay / secondary brand warm
BRAND_SAND = "#EAD9B8"       # warmSand / secondaryContainer

# ---------------------------------------------------------------------------
# Template badge palette (theme-independent - colored chips w/ white text)
# ---------------------------------------------------------------------------
# Canonical data lives with the lesson-template schema in
# ``backend.lesson_content`` (backend must not import theme modules);
# re-exported here for the ``template_badge_color`` helper and back-compat.
from src.backend.lesson_content import TEMPLATE_COLOR_DEFAULT as _BADGE_DEFAULT
from src.backend.lesson_content import TEMPLATE_COLORS as _TEMPLATE_COLORS

TEMPLATE_BADGES: dict[str, str] = dict(_TEMPLATE_COLORS)
TEMPLATE_BADGE_DEFAULT = _BADGE_DEFAULT

# Resource-type pill colors (knowledge bubbles, review table)
RESOURCE_TYPE_COLORS: dict[str, str] = {
    "word": BRAND_TEAL,           # brand teal (was #3B82F6 blue)
    "expression": "#10B981",        # emerald - kept
    "grammarPoint": "#F59E0B",      # amber - kept
}
RESOURCE_TYPE_DEFAULT = "#6B7280"


def template_badge_color(template: str) -> str:
    """Return the badge hex for a functional lesson template."""
    return TEMPLATE_BADGES.get(template, TEMPLATE_BADGE_DEFAULT)


def resource_type_color(resource_type: str) -> str:
    """Return the pill hex for a resource type (word/expression/grammarPoint)."""
    return RESOURCE_TYPE_COLORS.get(resource_type, RESOURCE_TYPE_DEFAULT)


# ---------------------------------------------------------------------------
# Palette definitions
# ---------------------------------------------------------------------------

_DARK_PALETTE: dict[str, str] = {
    # Surfaces
    "bg": "#1B2E25",
    "bg_secondary": "#243D30",
    "bg_input": "#20362B",
    "bg_elevated": "#2A4638",
    "bg_disabled": "#1C2A28",
    # Text
    "text": "#E8EAF0",
    "text_secondary": "#B9CCC0",
    "text_disabled": "#84998C",
    # Borders
    "border": "#385246",
    "border_hover": BRAND_REED,
    # Accent (Turna teal family - was Tailwind blue)
    "accent": BRAND_TEAL,
    "accent_hover": BRAND_TEAL_LIGHT,
    "accent_pressed": BRAND_TEAL_DARK,
    "accent_subtle": "#331F727E",   # alpha 0x33 (~20%) over bg
    "accent_text": BRAND_REED,
    # Semantic
    "danger": "#EF4444",
    "danger_hover": "#DC2626",
    "success": "#27AE60",
    "success_text": "#2ECC71",
    "warning": "#FF9F43",
    "warning_text": "#FFB877",
    "error": "#E74C3C",
    "error_text": "#FF6B6B",
    "info": BRAND_SKY,
    # Scrollbars (Turna-tinted)
    "scrollbar": "#3A5A55",
    "scrollbar_hover": "#5A7A75",
    # Depth / brand
    "surface_elevated": "#2A4638",
    "shadow": "#000000",
    "glow": BRAND_REED,
    "accent_gradient_start": BRAND_TEAL,
    "accent_gradient_end": BRAND_TEAL_LIGHT,
    "toolbar_gradient_start": "#243D30",
    "toolbar_gradient_end": "#1B2E25",
    "ai_orbit_glow": BRAND_REED,
    # AI dialog semantic colors (Turna-aligned)
    "ai_chat_bg": "#20362B",
    "ai_bubble_bg": "#2A4638",
    "ai_user_bubble": BRAND_TEAL,
    "ai_card_bg": "#243D30",
    "ai_chip_bg": "#20362B",
    "ai_accent": BRAND_REED,
    "ai_accent_border": BRAND_TEAL,
    "ai_beta_bg": "#664400",
    "ai_beta_text": "#FFD93D",
}

_LIGHT_PALETTE: dict[str, str] = {
    # Surfaces
    "bg": "#F2F8F3",
    "bg_secondary": "#FFFFFF",
    "bg_input": "#EDF5EE",
    "bg_elevated": "#FFFFFF",
    "bg_disabled": "#F3F4F6",
    # Text
    "text": "#1A1A2E",
    "text_secondary": "#4A5568",
    "text_disabled": "#9CA3AF",
    # Borders
    "border": "#DFEBE0",
    "border_hover": BRAND_TEAL,
    # Accent (Turna teal family - was Tailwind blue)
    "accent": BRAND_TEAL,
    "accent_hover": BRAND_TEAL_DARK,      # darker on hover for light mode contrast
    "accent_pressed": "#0F3D44",
    "accent_subtle": "#261F727E",      # alpha 0x26 (~15%) over white
    "accent_text": BRAND_TEAL_DARK,       # readable on light surfaces
    # Semantic
    "danger": "#EF4444",
    "danger_hover": "#DC2626",
    "success": "#27AE60",
    "success_text": "#1E8449",
    "warning": "#FF9F43",
    "warning_text": "#B9770E",
    "error": "#E74C3C",
    "error_text": "#C0392B",
    "info": BRAND_TEAL,
    # Scrollbars (Turna-tinted light)
    "scrollbar": "#C1D5D1",
    "scrollbar_hover": "#9CB8B3",
    # Depth / brand
    "surface_elevated": "#FFFFFF",
    "shadow": BRAND_TEAL,
    "glow": BRAND_REED,
    "accent_gradient_start": BRAND_TEAL,
    "accent_gradient_end": BRAND_TEAL_LIGHT,
    "toolbar_gradient_start": "#F2F8F3",
    "toolbar_gradient_end": "#E3F1E5",
    "ai_orbit_glow": BRAND_REED,
    # AI dialog semantic colors (light variants)
    "ai_chat_bg": "#EDF5EE",
    "ai_bubble_bg": "#FFFFFF",
    "ai_user_bubble": BRAND_TEAL,
    "ai_card_bg": "#FFFFFF",
    "ai_chip_bg": "#EEF2F7",
    "ai_accent": BRAND_TEAL,
    "ai_accent_border": BRAND_TEAL_DARK,
    "ai_beta_bg": "#FFF3D6",
    "ai_beta_text": "#7A5A00",
}

_HIGH_CONTRAST_DARK_PALETTE: dict[str, str] = {
    # Pure surfaces for maximum contrast
    "bg": "#000000",
    "bg_secondary": "#000000",
    "bg_input": "#0A0A0A",
    "bg_elevated": "#111111",
    "bg_disabled": "#1A1A1A",
    # Text
    "text": "#FFFFFF",
    "text_secondary": "#E0E0E0",
    "text_disabled": "#AAAAAA",
    # Borders (thick, high-contrast)
    "border": "#FFFFFF",
    "border_hover": BRAND_REED,
    # Accent remains dark enough for white labels in high-contrast mode.
    "accent": BRAND_TEAL,
    "accent_hover": BRAND_TEAL_LIGHT,
    "accent_pressed": BRAND_TEAL_LIGHT,
    "accent_subtle": "#331F727E",
    "accent_text": "#FFFFFF",
    # Semantic (brighter variants)
    "danger": "#FF6B6B",
    "danger_hover": "#FF8585",
    "success": "#2ECC71",
    "success_text": "#2ECC71",
    "warning": "#FFB877",
    "warning_text": "#FFB877",
    "error": "#FF6B6B",
    "error_text": "#FF6B6B",
    "info": BRAND_SKY,
    # Scrollbars
    "scrollbar": "#666666",
    "scrollbar_hover": "#999999",
    # Depth / brand
    "surface_elevated": "#111111",
    "shadow": "#000000",
    "glow": BRAND_REED,
    "accent_gradient_start": BRAND_TEAL,
    "accent_gradient_end": BRAND_TEAL_LIGHT,
    "toolbar_gradient_start": "#000000",
    "toolbar_gradient_end": "#000000",
    "ai_orbit_glow": BRAND_REED,
    # AI dialog semantic colors (high-contrast dark)
    "ai_chat_bg": "#000000",
    "ai_bubble_bg": "#111111",
    "ai_user_bubble": BRAND_TEAL,
    "ai_card_bg": "#0A0A0A",
    "ai_chip_bg": "#111111",
    "ai_accent": BRAND_TEAL_LIGHT,
    "ai_accent_border": BRAND_TEAL_LIGHT,
    "ai_beta_bg": "#664400",
    "ai_beta_text": "#FFD93D",
}

_HIGH_CONTRAST_LIGHT_PALETTE: dict[str, str] = {
    # Pure white surfaces
    "bg": "#FFFFFF",
    "bg_secondary": "#FFFFFF",
    "bg_input": "#FFFFFF",
    "bg_elevated": "#FFFFFF",
    "bg_disabled": "#F0F0F0",
    # Text (near-black)
    "text": "#000000",
    "text_secondary": "#1A1A1A",
    "text_disabled": "#333333",
    # Borders (thick, high-contrast)
    "border": "#000000",
    "border_hover": BRAND_TEAL_DARK,
    # Accent (darker teal for max visibility on white)
    "accent": BRAND_TEAL_DARK,
    "accent_hover": "#0F3D44",
    "accent_pressed": "#08222B",
    "accent_subtle": "#26145A64",
    "accent_text": BRAND_TEAL_DARK,
    # Semantic (darker variants)
    "danger": "#C0392B",
    "danger_hover": "#A93226",
    "success": "#1E8449",
    "success_text": "#1E8449",
    "warning": "#B9770E",
    "warning_text": "#B9770E",
    "error": "#C0392B",
    "error_text": "#C0392B",
    "info": BRAND_TEAL_DARK,
    # Scrollbars
    "scrollbar": "#999999",
    "scrollbar_hover": "#666666",
    # Depth / brand
    "surface_elevated": "#FFFFFF",
    "shadow": BRAND_TEAL_DARK,
    "glow": BRAND_REED,
    "accent_gradient_start": BRAND_TEAL_DARK,
    "accent_gradient_end": BRAND_TEAL,
    "toolbar_gradient_start": "#FFFFFF",
    "toolbar_gradient_end": "#FFFFFF",
    "ai_orbit_glow": BRAND_REED,
    # AI dialog semantic colors (high-contrast light)
    "ai_chat_bg": "#FFFFFF",
    "ai_bubble_bg": "#FFFFFF",
    "ai_user_bubble": BRAND_TEAL_DARK,
    "ai_card_bg": "#FFFFFF",
    "ai_chip_bg": "#EEEEEE",
    "ai_accent": BRAND_TEAL_DARK,
    "ai_accent_border": "#000000",
    "ai_beta_bg": "#FFF3D6",
    "ai_beta_text": "#000000",
}

#: All four palettes keyed by theme name.
PALETTES: dict[str, dict[str, str]] = {
    "dark": _DARK_PALETTE,
    "light": _LIGHT_PALETTE,
    "high-contrast-dark": _HIGH_CONTRAST_DARK_PALETTE,
    "high-contrast-light": _HIGH_CONTRAST_LIGHT_PALETTE,
}

#: The set of valid theme identifiers (also the ``Settings.theme`` domain).
VALID_THEMES: frozenset[str] = frozenset(PALETTES.keys())

#: Default theme used when settings are absent or invalid.
DEFAULT_THEME = "dark"


def valid_themes() -> frozenset[str]:
    """Return the set of accepted theme identifiers."""
    return VALID_THEMES


def palette_for(theme: str) -> dict[str, str]:
    """Return the palette dict for *theme*, falling back to the default."""
    return PALETTES.get(theme, PALETTES[DEFAULT_THEME])


def is_high_contrast(theme: str) -> bool:
    """True when *theme* is one of the high-contrast accessibility variants."""
    return theme in {"high-contrast-dark", "high-contrast-light"}


def is_dark(theme: str) -> bool:
    """True when *theme* is a dark-surface variant (dark or high-contrast-dark)."""
    return theme in {"dark", "high-contrast-dark"}
