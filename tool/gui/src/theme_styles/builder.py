"""Main stylesheet orchestrator composing modular QSS sub-styles."""
from __future__ import annotations

from src.theme_tokens import is_high_contrast
from src.theme_styles.buttons import build_button_qss
from src.theme_styles.containers import build_container_qss
from src.theme_styles.core import build_core_qss
from src.theme_styles.inputs import build_input_qss
from src.theme_styles.views import build_view_qss


def opaque(color_aarrggbb: str, over_hex: str) -> str:
    """Pre-blend an ``#AARRGGBB`` color over an opaque ``#RRGGBB`` background.

    Qt paints some regions (e.g. the tree branch/indent gutter of a selected
    row) without alpha blending; pre-blending keeps those regions visually
    identical to the alpha-blended ``::item`` backgrounds.
    """
    alpha = int(color_aarrggbb[1:3], 16) / 255.0
    r = int(color_aarrggbb[3:5], 16) * alpha + int(over_hex[1:3], 16) * (1 - alpha)
    g = int(color_aarrggbb[5:7], 16) * alpha + int(over_hex[3:5], 16) * (1 - alpha)
    b = int(color_aarrggbb[7:9], 16) * alpha + int(over_hex[5:7], 16) * (1 - alpha)
    return f"#{round(r):02X}{round(g):02X}{round(b):02X}"


def build_qss(palette: dict[str, str], base_font_px: int, theme: str) -> str:
    """Return a parameterized stylesheet string composed of modular component styles.

    The ``theme`` argument controls high-contrast adjustments (thicker
    borders, stronger focus rings) that cannot be derived from the palette
    alone.
    """
    p = palette
    hc = is_high_contrast(theme)
    # Opaque stand-in for accent_subtle: the tree branch/indent gutter of a
    # selected row is painted without alpha blending (verified by pixel
    # sampling), so it needs the pre-blended color to match ::item:selected.
    branch_selected = opaque(p["accent_subtle"], p["bg_secondary"])

    # High-contrast tokens: thicker borders, stronger focus rings.
    border_w = "2px" if hc else "1px"
    focus_w = "2.5px" if hc else "2px"
    card_border = (
        f"border: {border_w} solid {p['border']};"
        if hc
        else f"border: 1px solid {p['border']};"
    )

    core_qss = build_core_qss(p, base_font_px, border_w)
    button_qss = build_button_qss(p, border_w, theme)
    input_qss = build_input_qss(p, border_w, focus_w)
    view_qss = build_view_qss(p, border_w, branch_selected)
    container_qss = build_container_qss(p, border_w, card_border, base_font_px)

    return "\n".join(
        [
            core_qss.strip(),
            button_qss.strip(),
            input_qss.strip(),
            view_qss.strip(),
            container_qss.strip(),
        ]
    ) + "\n"
