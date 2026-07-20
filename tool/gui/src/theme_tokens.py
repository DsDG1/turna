"""Semantic color tokens for the Varnamala GUI course editor.

This module is the single source of truth for all theme palettes. It is
deliberately free of Qt imports so the token tables and helpers can be
unit-tested headlessly and reused by ``theme.py`` (which owns the QSS
stylesheet generation and ``QApplication`` wiring).

Design language: **Peacock** - aligned with the Flutter app's
``VarnamalaTheme`` (``lib/views/theme.dart``). The primary accent family is
teal / cyan / turquoise rather than the generic blue that previously drove
the desktop editor. Four palettes are provided:

* ``dark``  - default, peacock-tinted dark surfaces
* ``light`` - bright, airy surfaces with peacock teal accents
* ``high-contrast-dark``  - near-black surfaces, pure-white text, thick borders
* ``high-contrast-light`` - pure-white surfaces, near-black text, thick borders

Every palette exposes the same key set so widgets can look up any token
without caring which theme is active. The ``ai_*`` namespace is preserved
for backward compatibility with the chat / orbit / workshop widgets.
"""
from __future__ import annotations

# ---------------------------------------------------------------------------
# Canonical peacock brand colors (mirrors lib/views/theme.dart)
# ---------------------------------------------------------------------------
PEACOCK_DEEP = "#1A0285"
PEACOCK_TEAL = "#1F727E"       # primary
PEACOCK_CYAN = "#359CBB"       # primaryLight
PEACOCK_TURQUOISE = "#46D1BF"  # secondary
PEACOCK_MINT = "#00FFC6"       # secondaryLight (glow accent)
PRIMARY_DARK = "#145A64"

# ---------------------------------------------------------------------------
# Template badge palette (theme-independent - colored chips w/ white text)
# ---------------------------------------------------------------------------
# Curated to harmonize with the peacock brand while staying distinguishable
# via hue separation. Only ``listening`` carries the brand teal; the rest
# retain their established hues to preserve visual memory.
TEMPLATE_BADGES: dict[str, str] = {
    "listening": PEACOCK_TEAL,      # brand teal (was #3B82F6 blue)
    "reading": "#10B981",           # emerald - kept
    "mastery": "#F59E0B",           # amber - kept
    "intro": "#6366F1",             # indigo - kept
    "practice": "#8B5CF6",          # violet - kept
    "review": "#EC4899",            # rose - kept
    "legacy": "#6B7280",            # slate - kept
}
TEMPLATE_BADGE_DEFAULT = "#6B7280"

# Resource-type pill colors (knowledge bubbles, review table)
RESOURCE_TYPE_COLORS: dict[str, str] = {
    "word": PEACOCK_TEAL,           # brand teal (was #3B82F6 blue)
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
    "bg": "#0F1C1A",
    "bg_secondary": "#1A2E2B",
    "bg_input": "#142624",
    "bg_elevated": "#1F3A36",
    "bg_disabled": "#1C2A28",
    # Text
    "text": "#E8EAF0",
    "text_secondary": "#B0CBC7",
    "text_disabled": "#6B8A85",
    # Borders
    "border": "#2A4540",
    "border_hover": PEACOCK_TURQUOISE,
    # Accent (peacock teal family - was Tailwind blue)
    "accent": PEACOCK_TEAL,
    "accent_hover": PEACOCK_CYAN,
    "accent_pressed": PRIMARY_DARK,
    "accent_subtle": "#331F727E",   # alpha 0x33 (~20%) over bg
    "accent_text": PEACOCK_TURQUOISE,
    # Semantic
    "danger": "#EF4444",
    "danger_hover": "#DC2626",
    "success": "#27AE60",
    "success_text": "#2ECC71",
    "warning": "#FF9F43",
    "warning_text": "#FFB877",
    "error": "#E74C3C",
    "error_text": "#FF6B6B",
    "info": PEACOCK_CYAN,
    # Scrollbars (peacock-tinted)
    "scrollbar": "#3A5A55",
    "scrollbar_hover": "#5A7A75",
    # Depth / brand
    "surface_elevated": "#1F3A36",
    "shadow": "#000000",
    "glow": PEACOCK_TURQUOISE,
    "accent_gradient_start": PEACOCK_TEAL,
    "accent_gradient_end": PEACOCK_CYAN,
    "toolbar_gradient_start": "#1A2E2B",
    "toolbar_gradient_end": "#0F1C1A",
    "ai_orbit_glow": PEACOCK_TURQUOISE,
    # AI dialog semantic colors (peacock-aligned)
    "ai_chat_bg": "#142624",
    "ai_bubble_bg": "#1F3A36",
    "ai_user_bubble": PEACOCK_TEAL,
    "ai_card_bg": "#1A2E2B",
    "ai_chip_bg": "#142624",
    "ai_accent": PEACOCK_TURQUOISE,
    "ai_accent_border": PEACOCK_TEAL,
    "ai_beta_bg": "#664400",
    "ai_beta_text": "#FFD93D",
}

_LIGHT_PALETTE: dict[str, str] = {
    # Surfaces
    "bg": "#F8FFFE",
    "bg_secondary": "#FFFFFF",
    "bg_input": "#F5F8F7",
    "bg_elevated": "#FFFFFF",
    "bg_disabled": "#F3F4F6",
    # Text
    "text": "#1A1A2E",
    "text_secondary": "#4A5568",
    "text_disabled": "#9CA3AF",
    # Borders
    "border": "#EEF2F1",
    "border_hover": PEACOCK_TEAL,
    # Accent (peacock teal family - was Tailwind blue)
    "accent": PEACOCK_TEAL,
    "accent_hover": PRIMARY_DARK,      # darker on hover for light mode contrast
    "accent_pressed": "#0F3D44",
    "accent_subtle": "#261F727E",      # alpha 0x26 (~15%) over white
    "accent_text": PRIMARY_DARK,       # readable on light surfaces
    # Semantic
    "danger": "#EF4444",
    "danger_hover": "#DC2626",
    "success": "#27AE60",
    "success_text": "#1E8449",
    "warning": "#FF9F43",
    "warning_text": "#B9770E",
    "error": "#E74C3C",
    "error_text": "#C0392B",
    "info": PEACOCK_TEAL,
    # Scrollbars (peacock-tinted light)
    "scrollbar": "#C1D5D1",
    "scrollbar_hover": "#9CB8B3",
    # Depth / brand
    "surface_elevated": "#FFFFFF",
    "shadow": PEACOCK_TEAL,
    "glow": PEACOCK_TURQUOISE,
    "accent_gradient_start": PEACOCK_TEAL,
    "accent_gradient_end": PEACOCK_CYAN,
    "toolbar_gradient_start": "#F0FFFC",
    "toolbar_gradient_end": "#E0F5F1",
    "ai_orbit_glow": PEACOCK_TURQUOISE,
    # AI dialog semantic colors (light variants)
    "ai_chat_bg": "#F5F8F7",
    "ai_bubble_bg": "#FFFFFF",
    "ai_user_bubble": PEACOCK_TEAL,
    "ai_card_bg": "#FFFFFF",
    "ai_chip_bg": "#EEF2F7",
    "ai_accent": PEACOCK_TEAL,
    "ai_accent_border": PRIMARY_DARK,
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
    "border_hover": PEACOCK_TURQUOISE,
    # Accent (brighter turquoise for max visibility on black)
    "accent": PEACOCK_TURQUOISE,
    "accent_hover": PEACOCK_MINT,
    "accent_pressed": PEACOCK_CYAN,
    "accent_subtle": "#3346D1BF",
    "accent_text": PEACOCK_TURQUOISE,
    # Semantic (brighter variants)
    "danger": "#FF6B6B",
    "danger_hover": "#FF8585",
    "success": "#2ECC71",
    "success_text": "#2ECC71",
    "warning": "#FFB877",
    "warning_text": "#FFB877",
    "error": "#FF6B6B",
    "error_text": "#FF6B6B",
    "info": PEACOCK_TURQUOISE,
    # Scrollbars
    "scrollbar": "#666666",
    "scrollbar_hover": "#999999",
    # Depth / brand
    "surface_elevated": "#111111",
    "shadow": "#000000",
    "glow": PEACOCK_MINT,
    "accent_gradient_start": PEACOCK_TURQUOISE,
    "accent_gradient_end": PEACOCK_CYAN,
    "toolbar_gradient_start": "#000000",
    "toolbar_gradient_end": "#000000",
    "ai_orbit_glow": PEACOCK_MINT,
    # AI dialog semantic colors (high-contrast dark)
    "ai_chat_bg": "#000000",
    "ai_bubble_bg": "#111111",
    "ai_user_bubble": PEACOCK_TEAL,
    "ai_card_bg": "#0A0A0A",
    "ai_chip_bg": "#111111",
    "ai_accent": PEACOCK_TURQUOISE,
    "ai_accent_border": PEACOCK_TURQUOISE,
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
    "border_hover": PRIMARY_DARK,
    # Accent (darker teal for max visibility on white)
    "accent": PRIMARY_DARK,
    "accent_hover": "#0F3D44",
    "accent_pressed": "#08222B",
    "accent_subtle": "#26145A64",
    "accent_text": PRIMARY_DARK,
    # Semantic (darker variants)
    "danger": "#C0392B",
    "danger_hover": "#A93226",
    "success": "#1E8449",
    "success_text": "#1E8449",
    "warning": "#B9770E",
    "warning_text": "#B9770E",
    "error": "#C0392B",
    "error_text": "#C0392B",
    "info": PRIMARY_DARK,
    # Scrollbars
    "scrollbar": "#999999",
    "scrollbar_hover": "#666666",
    # Depth / brand
    "surface_elevated": "#FFFFFF",
    "shadow": PRIMARY_DARK,
    "glow": PEACOCK_TURQUOISE,
    "accent_gradient_start": PRIMARY_DARK,
    "accent_gradient_end": PEACOCK_TEAL,
    "toolbar_gradient_start": "#FFFFFF",
    "toolbar_gradient_end": "#FFFFFF",
    "ai_orbit_glow": PEACOCK_TURQUOISE,
    # AI dialog semantic colors (high-contrast light)
    "ai_chat_bg": "#FFFFFF",
    "ai_bubble_bg": "#FFFFFF",
    "ai_user_bubble": PRIMARY_DARK,
    "ai_card_bg": "#FFFFFF",
    "ai_chip_bg": "#EEEEEE",
    "ai_accent": PRIMARY_DARK,
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
