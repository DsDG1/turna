"""Interactive AI Orbit widget as the course creator's drag-and-drop drop zone.

Horizontal param band + wrapping chip row (the drop zone itself). The old
vertical "orbit" squeezed the chip row into a fixed 36-48 px strip, which is
why the design chat had to fight the layout for every pixel.
"""
from __future__ import annotations

import json
from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QComboBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QProgressBar,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.widgets.knowledge_bubble import KnowledgeBubble
from src.widgets.ui.flow_layout import FlowLayout
from src.theme import current_palette, apply_shadow
from src.theme_tokens import BRAND_REED, BRAND_TEAL

#: Core generate button is a round accent button; half of it is the radius.
_CORE_BTN_SIZE = 72
_CORE_BTN_RADIUS = _CORE_BTN_SIZE // 2
#: Shown under the chip row while the orbit is empty / after a removal.
_ORBIT_HINT = "拖入知识点气泡聚焦 · 留空则用整池 · Ctrl+Enter 生成"


class AiOrbitWidget(QWidget):
    """Non-traditional AI creative orbit.

    Drop zone that accepts ``application/x-knowledge-point`` mime data.
    Displays bubbles inside the orbit and provides controls to configure generation.
    This is the **single source of truth** for generation params in the workshop.
    """

    generate_requested = Signal()
    #: User wants the full design chat / template panel (right tab).
    chat_requested = Signal()
    #: Orbit focus set changed (drop / remove / clear) — host refreshes summary.
    focus_changed = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.dropped_items: list[dict[str, Any]] = []
        self._drag_active = False

        self.setAcceptDrops(True)
        self._build_ui()
        self._apply_style()

    def _build_ui(self) -> None:
        main_lay = QVBoxLayout(self)
        main_lay.setContentsMargins(8, 8, 8, 8)
        main_lay.setSpacing(6)

        # --- Param band: one horizontal row (single source for generation) ---
        params_row = QHBoxLayout()
        params_row.setSpacing(6)
        params_row.addWidget(QLabel("主题:"))
        self.topic_edit = QLineEdit()
        self.topic_edit.setPlaceholderText("如：日常问候与自我介绍")
        self.topic_edit.setMinimumWidth(120)
        params_row.addWidget(self.topic_edit, 1)

        params_row.addWidget(QLabel("等级:"))
        self.level_combo = QComboBox()
        self.level_combo.addItems(["A1", "A2", "B1", "B2", "C1"])
        params_row.addWidget(self.level_combo)

        params_row.addWidget(QLabel("单元:"))
        self.unit_spin = QSpinBox()
        self.unit_spin.setRange(1, 5)
        params_row.addWidget(self.unit_spin)

        params_row.addWidget(QLabel("课时:"))
        self.lessons_spin = QSpinBox()
        self.lessons_spin.setRange(1, 5)
        self.lessons_spin.setValue(3)
        params_row.addWidget(self.lessons_spin)

        params_row.addWidget(QLabel("模板:"))
        self.template_combo = QComboBox()
        self.template_combo.addItem("混合", "mixed")
        self.template_combo.addItem("认识新词", "intro")
        self.template_combo.addItem("巩固练习", "practice")
        self.template_combo.addItem("复习", "review")
        self.template_combo.addItem("听力", "listening")
        self.template_combo.addItem("阅读", "reading")
        self.template_combo.addItem("综合", "mastery")
        params_row.addWidget(self.template_combo)

        params_row.addWidget(QLabel("生成:"))
        self.gen_mode_combo = QComboBox()
        self.gen_mode_combo.addItem("快速", "fast")
        self.gen_mode_combo.addItem("精修", "phased")
        self.gen_mode_combo.setToolTip(
            "快速：一次生成完整 section。\n"
            "精修：大纲→分课→校验→质量→修复流水线。"
        )
        params_row.addWidget(self.gen_mode_combo)

        params_row.addWidget(QLabel("悄悄话:"))
        self.whisper_edit = QLineEdit()
        self.whisper_edit.setPlaceholderText("可选微调（如：第三节改听力）…")
        self.whisper_edit.setMinimumWidth(100)
        params_row.addWidget(self.whisper_edit, 1)
        main_lay.addLayout(params_row)
        # Kept for the single-row contract (and host-side assertions).
        self._params_row = params_row

        self.focus_summary = QLabel("")
        self.focus_summary.setWordWrap(False)
        self.focus_summary.setStyleSheet(
            "font-size: 11px; opacity: 0.9;"
        )
        self.focus_summary.setToolTip(
            "显示本次生成将使用的知识点规模（轨道内聚焦或整个资源池）"
        )
        main_lay.addWidget(self.focus_summary)

        # --- Orbit zone: the chip row IS the drop zone (wraps, no clamp) ---
        self.orbit_zone = QWidget()
        self.orbit_zone.setObjectName("orbitZone")
        self.orbit_zone.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)

        orbit_lay = QVBoxLayout(self.orbit_zone)
        orbit_lay.setContentsMargins(8, 6, 8, 6)
        orbit_lay.setSpacing(4)

        self.prompt_label = QLabel(_ORBIT_HINT)
        self.prompt_label.setAlignment(Qt.AlignmentFlag.AlignRight)
        self.prompt_label.setStyleSheet(
            "font-size: 11px; font-weight: bold; opacity: 0.85;"
        )
        # One thin hint line, not two: the drop hint rides to the right of
        # the pool summary instead of spending its own row above the chips.
        summary_row = QHBoxLayout()
        summary_row.addWidget(self.prompt_label)
        summary_row.addStretch(1)
        orbit_lay.addLayout(summary_row)

        # No min/max height clamp: the row wraps and grows with the zone, which
        # itself takes the vertical stretch. Scrolls only when chips overflow.
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setFrameShape(QScrollArea.Shape.NoFrame)
        self.scroll_area.setHorizontalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self.scroll_area.setVerticalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAsNeeded
        )

        self.bubbles_container = QWidget()
        self.bubbles_layout = FlowLayout(
            self.bubbles_container, hspacing=6, vspacing=6
        )
        self.scroll_area.setWidget(self.bubbles_container)
        # Band, not a pane: the chip row keeps a drop-target-sized floor and
        # may grow with wrapped chips up to a ceiling, then scrolls. Without
        # the ceiling the zone's default hint (~190 px) out-bids the design
        # chat for vertical space.
        self.scroll_area.setMinimumHeight(36)
        self.scroll_area.setMaximumHeight(72)
        orbit_lay.addWidget(self.scroll_area, 1)

        # --- Action row: round core button + chat, side by side ---
        action_row = QHBoxLayout()
        action_row.setSpacing(8)
        action_row.addStretch(1)

        self.core_btn = QPushButton("AI 核心\n开始生成")
        self.core_btn.setObjectName("coreBtn")
        self.core_btn.setFixedSize(_CORE_BTN_SIZE, _CORE_BTN_SIZE)
        self.core_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.core_btn.setToolTip(
            "根据参数带与轨道内知识点生成课程草稿（Ctrl+Enter）"
        )
        self.core_btn.clicked.connect(self._emit_generate)
        action_row.addWidget(self.core_btn)

        self.chat_btn = QPushButton("对话与高级…")
        self.chat_btn.setToolTip(
            "打开「对话与高级」：许愿聊天、附件、Prompt 模板、genre、JSON"
        )
        self.chat_btn.clicked.connect(self.chat_requested.emit)
        action_row.addWidget(self.chat_btn)
        action_row.addStretch(1)
        self._action_row = action_row
        orbit_lay.addLayout(action_row)

        self._gen_shortcut = QShortcut(QKeySequence("Ctrl+Return"), self)
        self._gen_shortcut.activated.connect(self._emit_generate)
        self._gen_shortcut2 = QShortcut(QKeySequence("Ctrl+Enter"), self)
        self._gen_shortcut2.activated.connect(self._emit_generate)

        main_lay.addWidget(self.orbit_zone, 1)

        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)
        self.progress_bar.setFixedHeight(6)
        self.progress_bar.setVisible(False)
        main_lay.addWidget(self.progress_bar)

        self.status_label = QLabel("")
        self.status_label.setStyleSheet("font-size: 11px; opacity: 0.8;")
        self.status_label.setVisible(False)
        main_lay.addWidget(self.status_label)

    def add_action_widget(self, widget: QWidget) -> None:
        """Host hook: place a widget on the action row, before the trailing
        stretch (the workshop canvas parks the bubble-pool popover there)."""
        self._action_row.insertWidget(self._action_row.count() - 1, widget)

    def params_dict(self) -> dict[str, Any]:
        """Current generation params from the orbit band."""
        mode = self.gen_mode_combo.currentData()
        if mode is None:
            mode = "fast"
        return {
            "topic": self.topic_edit.text().strip(),
            "level": self.level_combo.currentText(),
            "unit_count": self.unit_spin.value(),
            "lessons_per_unit": self.lessons_spin.value(),
            "template": self.template_combo.currentData() or "mixed",
            "extra_instructions": self.whisper_edit.text().strip(),
            "generation_mode": str(mode),
        }

    def apply_params(self, params: dict[str, Any]) -> None:
        """Load controller/project params into the orbit bar."""
        self.level_combo.setCurrentText(params.get("level", "A1") or "A1")
        self.unit_spin.setValue(int(params.get("unit_count", 1) or 1))
        self.lessons_spin.setValue(int(params.get("lessons_per_unit", 3) or 3))
        idx = self.template_combo.findData(params.get("template", "mixed") or "mixed")
        if idx >= 0:
            self.template_combo.setCurrentIndex(idx)
        self.topic_edit.setText(params.get("topic", "") or "")
        self.whisper_edit.setText(params.get("extra_instructions", "") or "")
        mode = str(params.get("generation_mode") or "fast")
        midx = self.gen_mode_combo.findData(mode)
        if midx < 0 and mode == "refine":
            midx = self.gen_mode_combo.findData("phased")
        self.gen_mode_combo.setCurrentIndex(midx if midx >= 0 else 0)

    def _apply_style(self) -> None:
        p = current_palette()
        border_color = p.get("border", "#2C313C")
        accent = p.get("ai_accent", BRAND_REED)
        accent_border = p.get("ai_accent_border", BRAND_TEAL)

        self.orbit_zone.setStyleSheet(
            f"QWidget#orbitZone {{"
            f"  background-color: {p.get('ai_chat_bg', '#1A1D23')};"
            f"  border: 2px dashed {border_color};"
            f"  border-radius: 12px;"
            f"}}"
        )

        on_accent = p.get("text_on_accent", "#FFFFFF")
        self.core_btn.setStyleSheet(
            "QPushButton#coreBtn {"
            f"  background-color: {accent_border};"
            f"  color: {on_accent};"
            f"  border: 3px solid {accent};"
            f"  border-radius: {_CORE_BTN_RADIUS}px;"
            "  font-weight: bold;"
            "  font-size: 12px;"
            "  text-align: center;"
            "}"
            "QPushButton#coreBtn:hover {"
            f"  background-color: {accent};"
            f"  border-color: {on_accent};"
            "}"
        )

        apply_shadow(
            self.core_btn, color_key="glow", blur_radius=14, dy=0, alpha=0.3
        )

    def _set_drag_active(self, active: bool) -> None:
        self._drag_active = active
        p = current_palette()
        border_color = (
            p.get("ai_accent", BRAND_REED) if active else p.get("border", "#2C313C")
        )
        self.orbit_zone.setStyleSheet(
            f"QWidget#orbitZone {{"
            f"  background-color: {p.get('ai_chat_bg', '#1A1D23')};"
            f"  border: 2px {'solid' if active else 'dashed'} {border_color};"
            f"  border-radius: 12px;"
            f"}}"
        )

    def dragEnterEvent(self, event) -> None:
        if event.mimeData().hasFormat("application/x-knowledge-point"):
            event.acceptProposedAction()
            self._set_drag_active(True)

    def dragLeaveEvent(self, event) -> None:
        self._set_drag_active(False)
        super().dragLeaveEvent(event)

    def dropEvent(self, event) -> None:
        self._set_drag_active(False)
        raw = bytes(event.mimeData().data("application/x-knowledge-point")).decode(
            "utf-8"
        )
        try:
            payload = json.loads(raw)
        except Exception:
            return
        entry = payload.get("entry") or payload
        rtype = payload.get("resource_type") or "word"
        if isinstance(entry, dict):
            self.add_knowledge_point(entry, rtype)
            event.acceptProposedAction()

    def add_knowledge_point(self, entry: dict[str, Any], res_type: str) -> None:
        """Add a knowledge point bubble to the orbit."""
        term = entry.get("term") or entry.get("title") or ""
        for item in self.dropped_items:
            t = (
                item.get("entry", {}).get("term")
                or item.get("entry", {}).get("title")
                or ""
            )
            if t == term and item.get("resource_type") == res_type:
                return

        payload = {"entry": entry, "resource_type": res_type}
        self.dropped_items.append(payload)

        bubble = KnowledgeBubble(
            entry, res_type, parent=self.bubbles_container, show_close=True
        )
        bubble.closed.connect(self._on_bubble_closed)
        self.bubbles_layout.addWidget(bubble)
        self.prompt_label.setText(
            f"已投入 {len(self.dropped_items)} 个知识点 · Ctrl+Enter 生成"
        )
        self.focus_changed.emit()

    def _on_bubble_closed(self) -> None:
        sender = self.sender()
        if isinstance(sender, KnowledgeBubble):
            payload = {"entry": sender.data, "resource_type": sender.resource_type}
            self.remove_knowledge_point(payload, sender)

    def remove_knowledge_point(
        self, payload: dict[str, Any], bubble: KnowledgeBubble
    ) -> None:
        if payload in self.dropped_items:
            self.dropped_items.remove(payload)
        bubble.deleteLater()
        self.prompt_label.setText(
            _ORBIT_HINT
            if not self.dropped_items
            else f"已投入 {len(self.dropped_items)} 个知识点 · Ctrl+Enter 生成"
        )
        self.focus_changed.emit()

    def clear_orbit(self) -> None:
        self.dropped_items.clear()
        for i in reversed(range(self.bubbles_layout.count())):
            w = self.bubbles_layout.itemAt(i).widget()
            if w is not None:
                w.deleteLater()
        self.prompt_label.setText(_ORBIT_HINT)
        self.focus_changed.emit()

    def set_focus_summary(self, text: str) -> None:
        self.focus_summary.setText(text)
        self.focus_summary.setVisible(bool(text))

    def set_empty_hint(self, text: str) -> None:
        self.prompt_label.setText(text)

    def set_busy(self, busy: bool, stage_text: str = "") -> None:
        self.progress_bar.setVisible(busy)
        self.status_label.setVisible(busy)
        self.status_label.setText(stage_text)
        self.core_btn.setEnabled(not busy)
        if busy:
            p = current_palette()
            self.core_btn.setText("AI 生成中\n请稍候…")
            self.core_btn.setStyleSheet(
                "QPushButton#coreBtn {"
                f"  background-color: {p.get('ai_chat_bg', '#1A1D23')};"
                f"  color: {p.get('text_secondary', '#9CA3AF')};"
                f"  border: 3px solid {p.get('border', '#2C313C')};"
                f"  border-radius: {_CORE_BTN_RADIUS}px;"
                "}"
            )
        else:
            self._apply_style()
            self.core_btn.setText("AI 核心\n开始生成")

    def _emit_generate(self) -> None:
        if self.core_btn.isEnabled():
            self.generate_requested.emit()
