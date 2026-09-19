"""Shell / UI-kit QSS: ActivityBar, ViewHeader, ui kit components, welcome.

Selectors key off ``objectName`` + dynamic properties so components carry no
inline styles and restyle automatically when the theme changes.
"""
from __future__ import annotations

from src.theme_tokens import RADIUS, TYPE


def build_shell_qss(p: dict[str, str], border_w: str, base_font_px: int) -> str:
    """Return QSS for the W1+ shell widgets (activity bar, view header, kit)."""
    display_px = int(TYPE["display"]["size"]) + (base_font_px - 14)
    title_px = int(TYPE["title"]["size"]) + (base_font_px - 14)
    caption_px = int(TYPE["caption"]["size"]) + (base_font_px - 14)
    r_pill = RADIUS["pill"]

    return f"""
/* ---- Activity bar (48px icon rail) ---- */
#ActivityBar {{
    background-color: {p['bg_chrome']};
    border-right: 1px solid {p['border']};
}}

#ActivityBarItem {{
    background-color: transparent;
    border: none;
    border-left: 2px solid transparent;
    border-radius: {RADIUS['md']}px;
}}

#ActivityBarItem:hover {{
    background-color: {p['accent_subtle']};
}}

#ActivityBarItem:checked {{
    background-color: {p['accent_subtle']};
    border-left: 2px solid {p['accent']};
}}

#ActivityBarSeparator {{
    background-color: {p['border']};
}}

/* ---- Count badge (activity-bar corner chip / inline) ---- */
#Badge {{
    border-radius: {r_pill}px;
    padding: 1px 5px;
    font-size: {caption_px - 1}px;
    font-weight: 700;
    min-width: 16px;
    min-height: 14px;
}}

#Badge[variant="accent"] {{
    background-color: {p['accent']};
    color: {p['text_on_accent']};
}}

#Badge[variant="danger"] {{
    background-color: {p['danger']};
    color: #FFFFFF;
}}

#Badge[variant="muted"] {{
    background-color: {p['bg_elevated']};
    color: {p['text_secondary']};
}}

/* ---- Type pill ---- */
#Pill {{
    border-radius: {r_pill}px;
    padding: 2px 10px;
    font-size: {caption_px}px;
    border: 1px solid transparent;
}}

#Pill[variant="accent"] {{
    color: {p['accent_text']};
    border-color: {p['accent']};
}}

#Pill[variant="success"] {{
    color: {p['success_text']};
    border-color: {p['success']};
}}

#Pill[variant="warning"] {{
    color: {p['warning_text']};
    border-color: {p['warning']};
}}

#Pill[variant="danger"] {{
    color: {p['error_text']};
    border-color: {p['danger']};
}}

#Pill[variant="muted"] {{
    color: {p['text_secondary']};
    border-color: {p['border']};
}}

/* ---- TurnaButton (primary / secondary / ghost / danger × sm / md) ---- */
#TurnaButton {{
    border-radius: {RADIUS['md']}px;
    padding: 6px 14px;
    font-weight: 500;
}}

#TurnaButton[btnSize="sm"] {{
    padding: 3px 10px;
    font-size: {caption_px}px;
}}

#TurnaButton[variant="primary"] {{
    background-color: {p['accent']};
    color: {p['text_on_accent']};
    border: {border_w} solid {p['accent']};
}}

#TurnaButton[variant="primary"]:hover {{
    background-color: {p['accent_hover']};
    border-color: {p['accent_hover']};
}}

#TurnaButton[variant="primary"]:pressed {{
    background-color: {p['accent_pressed']};
    border-color: {p['accent_pressed']};
}}

#TurnaButton[variant="secondary"] {{
    background-color: {p['bg_input']};
    color: {p['text']};
    border: {border_w} solid {p['border']};
}}

#TurnaButton[variant="secondary"]:hover {{
    background-color: {p['bg_elevated']};
    border-color: {p['border_hover']};
}}

#TurnaButton[variant="ghost"] {{
    background-color: transparent;
    color: {p['text_secondary']};
    border: {border_w} solid transparent;
}}

#TurnaButton[variant="ghost"]:hover {{
    background-color: {p['accent_subtle']};
    color: {p['accent_text']};
}}

#TurnaButton[variant="danger"] {{
    background-color: {p['danger']};
    color: #FFFFFF;
    border: {border_w} solid {p['danger']};
}}

#TurnaButton[variant="danger"]:hover {{
    background-color: {p['danger_hover']};
    border-color: {p['danger_hover']};
}}

#TurnaButton:disabled {{
    background-color: {p['bg_disabled']};
    color: {p['text_disabled']};
    border-color: {p['bg_disabled']};
}}

/* ---- Card ---- */
#TurnaCard {{
    background-color: {p['bg_elevated']};
    border: {border_w} solid {p['border']};
    border-radius: {RADIUS['lg']}px;
}}

/* ---- View header (per-view 44px strip) ---- */
#ViewHeader {{
    background-color: {p['bg_chrome']};
    border-bottom: 1px solid {p['border']};
}}

#ViewHeaderTitle {{
    font-size: {display_px}px;
    font-weight: 700;
    color: {p['text']};
}}

#ViewHeaderContext {{
    font-size: {caption_px}px;
    color: {p['text_secondary']};
}}

/* ---- TurnaDialog ---- */
#TurnaDialog {{
    background-color: {p['bg']};
}}

#TurnaDialogHeader {{
    background-color: {p['bg_chrome']};
    border-bottom: 1px solid {p['border']};
}}

#TurnaDialogTitle {{
    font-size: {title_px}px;
    font-weight: 600;
}}

#TurnaDialogDescription {{
    font-size: {caption_px}px;
    color: {p['text_secondary']};
}}

#TurnaDialogFooter {{
    background-color: {p['bg_chrome']};
    border-top: 1px solid {p['border']};
}}

/* ---- Empty state ---- */
#EmptyStateTitle {{
    font-size: {title_px}px;
    font-weight: 600;
}}

#EmptyStateDescription {{
    font-size: {caption_px}px;
    color: {p['text_secondary']};
}}

/* ---- Toast ---- */
#Toast {{
    background-color: {p['bg_elevated']};
    border: {border_w} solid {p['border']};
    border-left-width: 3px;
    border-radius: {RADIUS['lg']}px;
}}

#Toast[severity="info"] {{ border-left-color: {p['info']}; }}
#Toast[severity="success"] {{ border-left-color: {p['success']}; }}
#Toast[severity="warning"] {{ border-left-color: {p['warning']}; }}
#Toast[severity="danger"] {{ border-left-color: {p['danger']}; }}

#ToastMessage {{
    color: {p['text']};
}}

/* ---- Search field ---- */
#SearchField {{
    border-radius: {RADIUS['md']}px;
    padding-left: 6px;
}}

/* ---- Sidebar (edit-view course-tree dock) ---- */
#SideBar {{
    background-color: {p['bg_secondary']};
}}

#SideBarToolBar {{
    background-color: transparent;
    border-top: 1px solid {p['border']};
}}

/* ---- Welcome view ---- */
#WelcomeView {{
    background-color: {p['bg']};
}}

#WelcomeBrand {{
    font-size: {display_px + 6}px;
    font-weight: 700;
    color: {p['accent_text']};
}}

#WelcomeSubtitle {{
    font-size: {caption_px}px;
    color: {p['text_secondary']};
}}

#WelcomeRecentHeader {{
    font-size: {caption_px}px;
    font-weight: 600;
    color: {p['text_secondary']};
}}

#WelcomeRecentItem {{
    background-color: {p['bg_secondary']};
    border: {border_w} solid {p['border']};
    border-radius: {RADIUS['md']}px;
    padding: 8px 12px;
}}

#WelcomeRecentItem:hover {{
    border-color: {p['border_hover']};
    background-color: {p['bg_elevated']};
}}

/* ---- Dock widgets (copilot right rail / sidebar) ---- */
QDockWidget {{
    color: {p['text_secondary']};
    font-size: {caption_px}px;
    font-weight: 600;
    titlebar-close-icon: none;
    titlebar-normal-icon: none;
}}

QDockWidget::title {{
    background-color: {p['bg_chrome']};
    border-bottom: 1px solid {p['border']};
    padding: 6px 10px;
    text-align: left;
}}

/* ---- Right-rail tab container ---- */
#RightRail {{
    background-color: {p['bg_chrome']};
    border-left: 1px solid {p['border']};
}}

/* ---- PreviewHost strip ---- */
#PreviewStripHost {{
    background-color: {p['bg_chrome']};
    border-top: 1px solid {p['border']};
}}

/* ---- Status bar: save-state indicator ---- */
#SaveStateLabel {{
    color: {p['text_secondary']};
    font-size: {caption_px - 1}px;
}}

#SaveStateLabel[saveState="dirty"] {{
    color: {p['warning_text']};
}}

#SaveStateLabel[saveState="clean"] {{
    color: {p['success_text']};
}}

/* ---- W3: course-tree sidebar ---- */
#TreeSidebar {{
    background-color: {p['bg_chrome']};
}}

#TreeMiniToolButton {{
    background-color: transparent;
    border: 1px solid transparent;
    border-radius: {RADIUS['sm']}px;
    padding: 4px;
}}

#TreeMiniToolButton:hover {{
    background-color: {p['accent_subtle']};
}}

#TreeMiniToolButton:checked {{
    background-color: {p['accent_subtle']};
    border-color: {p['accent']};
}}

#TreeMiniToolButton:disabled {{
    color: {p['text_disabled']};
}}

/* ---- W3: detail-panel document tabs ---- */
#DetailTabs::pane {{
    border: none;
    border-top: 1px solid {p['border']};
    background-color: {p['bg']};
}}

#DetailTabs QTabBar::tab {{
    border: none;
    border-bottom: 2px solid transparent;
    padding: 6px 14px;
    margin-right: 4px;
}}

#DetailTabs QTabBar::tab:selected {{
    background-color: transparent;
    border-bottom: 2px solid {p['accent']};
}}
"""
