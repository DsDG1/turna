"""Unified header chrome for the teacher lesson editors.

The four teacher editors (SubLessonFlow + Listening/Reading/Mastery) share
the same header: a breadcrumb + template-badge row, then a wrapping row of
action buttons (预览 / AI 改写 / 高级编辑, plus any template-specific
extras). The action row uses a FlowLayout so on a narrow detail panel the
buttons wrap to extra rows instead of being squeezed below their text width
(which would clip the labels).

Colors are resolved from the active palette (``current_palette()``) so the
chrome follows the light / dark / high-contrast themes like the rest of the
app. The header and body stylesheets move together — the breadcrumb uses
``text_secondary``, the 课型 badge pairs ``accent_text`` on ``accent`` with
``text_on_accent`` so it stays legible in both directions.
"""
from __future__ import annotations

from typing import Any
from collections.abc import Callable

from PySide6.QtWidgets import QLabel, QPushButton, QWidget

from src.backend.lesson_content import TEMPLATE_LABELS
from src.theme import current_palette
from src.widgets.ui.flow_layout import FlowLayout

# Fallbacks only — the last-resort values if a palette lacks a key.
_TEXT_SECONDARY = "#B9CCC0"
_ACCENT_BG = "#1F727E"


def _pal() -> dict[str, str]:
    """Active palette, resolved per call so a theme switch is picked up."""
    return current_palette()


def breadcrumb_label(
    section: dict[str, Any], unit: dict[str, Any], lesson: dict[str, Any]
) -> QLabel:
    """Return the section › unit › lesson breadcrumb for a teacher editor."""
    label = QLabel(
        f"{section.get('name', '')} › {unit.get('name', '')} › "
        f"{lesson.get('name', '')}"
    )
    label.setStyleSheet(
        f"color: {_pal().get('text_secondary', _TEXT_SECONDARY)};"
    )
    return label


def template_badge(lesson: dict[str, Any]) -> QLabel:
    """Return the styled 课型 badge for a lesson."""
    template = lesson.get("template", "legacy")
    badge = QLabel(f"课型：{TEMPLATE_LABELS.get(template, template)}")
    pal = _pal()
    badge.setStyleSheet(
        f"color: {pal.get('text_on_accent', '#FFFFFF')};"
        f" background-color: {pal.get('accent', _ACCENT_BG)};"
        " padding: 4px 10px; border-radius: 12px; font-weight: 600;"
    )
    return badge


def build_common_actions(
    *,
    on_preview: Callable[[], None],
    on_ai_rewrite: Callable[[], None],
    on_advanced_toggled: Callable[[bool], None],
) -> tuple[QPushButton, QPushButton, QPushButton]:
    """Return the (preview, ai, advanced) action buttons with unified styling.

    ``advanced`` is checkable; its ``toggled`` signal drives the swap between
    the teacher view and the raw expert LessonEditor.
    """
    preview = QPushButton("预览本课")
    preview.setToolTip("实际做题验证题目设置")
    preview.clicked.connect(on_preview)

    ai = QPushButton("AI 改写")
    ai.setToolTip("用 AI 根据你的指令改写当前课程")
    ai.clicked.connect(on_ai_rewrite)

    advanced = QPushButton("高级编辑")
    advanced.setCheckable(True)
    advanced.toggled.connect(on_advanced_toggled)
    return preview, ai, advanced


def build_teacher_header(
    section: dict[str, Any],
    unit: dict[str, Any],
    lesson: dict[str, Any],
    *,
    on_preview: Callable[[], None],
    on_ai_rewrite: Callable[[], None],
    on_advanced_toggled: Callable[[bool], None],
    extra_widgets: list[QWidget] | None = None,
) -> tuple[QWidget, QPushButton]:
    """Build the unified teacher editor header.

    Layout: a top row (breadcrumb + template badge, left-aligned), then a
    FlowLayout row of action buttons - ``extra_widgets`` first (template
    specifics like 从词库生成 / 实时预览), then the common 预览 / AI 改写 /
    高级编辑. The flow row wraps on narrow panels so button labels never clip.

    Returns ``(header_widget, advanced_btn)``.
    """
    from PySide6.QtWidgets import QHBoxLayout, QVBoxLayout

    header = QWidget()
    v = QVBoxLayout(header)
    v.setContentsMargins(0, 0, 0, 0)
    v.setSpacing(6)

    top = QHBoxLayout()
    top.setContentsMargins(0, 0, 0, 0)
    top.setSpacing(8)
    top.addWidget(breadcrumb_label(section, unit, lesson))
    top.addWidget(template_badge(lesson))
    top.addStretch()
    v.addLayout(top)

    flow = FlowLayout()
    for extra in extra_widgets or []:
        flow.addWidget(extra)
    preview_btn, ai_btn, advanced_btn = build_common_actions(
        on_preview=on_preview,
        on_ai_rewrite=on_ai_rewrite,
        on_advanced_toggled=on_advanced_toggled,
    )
    flow.addWidget(preview_btn)
    flow.addWidget(ai_btn)
    flow.addWidget(advanced_btn)
    v.addLayout(flow)

    return header, advanced_btn
