"""Turna UI kit (GUI 焕新 W1).

Shared, token-driven widgets for the refreshed shell. Styling lives in the
global QSS (``src/theme_styles/shell.py``) keyed by ``objectName`` and
dynamic properties, so components restyle automatically on theme switch —
per-widget inline hex is not allowed here.
"""
from src.widgets.ui.activity_bar import ActivityBar, ActivityBarItem
from src.widgets.ui.badges import Badge, Pill
from src.widgets.ui.buttons import TurnaButton
from src.widgets.ui.containers import Card, EmptyState, TurnaDialog, ViewHeader
from src.widgets.ui.inputs import SearchField
from src.widgets.ui.toast import ToastHost

__all__ = [
    "ActivityBar",
    "ActivityBarItem",
    "Badge",
    "Card",
    "EmptyState",
    "Pill",
    "SearchField",
    "ToastHost",
    "TurnaButton",
    "TurnaDialog",
    "ViewHeader",
]
