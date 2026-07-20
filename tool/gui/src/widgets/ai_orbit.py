"""Interactive AI Orbit widget as the course creator's drag-and-drop drop zone."""
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
from src.theme import current_palette, apply_shadow


class FlowLayout(QWidget):
    """Simple flow widget that lays out child bubbles horizontally and wraps them."""
    
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.layout = QHBoxLayout(self)
        self.layout.setContentsMargins(4, 4, 4, 4)
        self.layout.setSpacing(6)
        self.layout.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop)
        # We can dynamically wrap children, but a simpler scrollable row is robust and clean.
        # Let's support a horizontal flow that allows scrolling if there are many.
        self.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)


class AiOrbitWidget(QWidget):
    """Non-traditional AI creative orbit.

    Drop zone that accepts ``application/x-knowledge-point`` mime data.
    Displays bubbles inside the orbit and provides controls to configure generation.
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
        main_lay.setContentsMargins(12, 12, 12, 12)
        main_lay.setSpacing(10)

        # 1. Circular Orbit Zone
        self.orbit_zone = QWidget()
        self.orbit_zone.setObjectName("orbitZone")
        self.orbit_zone.setMinimumHeight(240)
        self.orbit_zone.setAttribute(Qt.WidgetAttribute.WA_StyledBackground, True)

        orbit_lay = QVBoxLayout(self.orbit_zone)
        orbit_lay.setContentsMargins(16, 16, 16, 16)
        orbit_lay.setSpacing(12)
        orbit_lay.setAlignment(Qt.AlignmentFlag.AlignCenter)

        self.prompt_label = QLabel(
            "✨ 拖拽左侧的知识点气泡到此轨道中 ✨\n"
            "(留空则默认使用资源池中的全部知识点)"
        )
        self.prompt_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.prompt_label.setStyleSheet(
            "font-size: 12px; font-weight: bold; line-height: 1.4; opacity: 0.85;"
        )
        orbit_lay.addWidget(self.prompt_label)

        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setFrameShape(QScrollArea.Shape.NoFrame)
        self.scroll_area.setVerticalScrollBarPolicy(
            Qt.ScrollBarPolicy.ScrollBarAlwaysOff
        )
        self.scroll_area.setMinimumHeight(48)
        self.scroll_area.setMaximumHeight(64)

        self.bubbles_container = QWidget()
        self.bubbles_layout = QHBoxLayout(self.bubbles_container)
        self.bubbles_layout.setContentsMargins(4, 4, 4, 4)
        self.bubbles_layout.setSpacing(8)
        self.bubbles_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.scroll_area.setWidget(self.bubbles_container)

        orbit_lay.addWidget(self.scroll_area)

        self.core_btn = QPushButton("AI 核心\n开始设计课程")
        self.core_btn.setObjectName("coreBtn")
        self.core_btn.setFixedSize(130, 130)
        self.core_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.core_btn.setToolTip(
            "根据当前参数与轨道内知识点生成课程草稿（Ctrl+Enter）"
        )
        self.core_btn.clicked.connect(self._emit_generate)
        orbit_lay.addWidget(self.core_btn, 0, Qt.AlignmentFlag.AlignCenter)

        # Canvas-level shortcut also exists; this covers focus inside the orbit.
        self._gen_shortcut = QShortcut(QKeySequence("Ctrl+Return"), self)
        self._gen_shortcut.activated.connect(self._emit_generate)
        self._gen_shortcut2 = QShortcut(QKeySequence("Ctrl+Enter"), self)
        self._gen_shortcut2.activated.connect(self._emit_generate)

        self.chat_btn = QPushButton("打开对话 / 附件 / 模板…")
        self.chat_btn.setToolTip("切换到右侧「设计与草稿」：许愿聊天、附件、Prompt 模板")
        self.chat_btn.clicked.connect(self.chat_requested.emit)
        orbit_lay.addWidget(self.chat_btn, 0, Qt.AlignmentFlag.AlignCenter)

        main_lay.addWidget(self.orbit_zone, 1)

        # 2. Config options panel
        config_widget = QWidget()
        config_lay = QVBoxLayout(config_widget)
        config_lay.setContentsMargins(0, 0, 0, 0)
        config_lay.setSpacing(8)

        topic_row = QHBoxLayout()
        topic_row.addWidget(QLabel("主题:"))
        self.topic_edit = QLineEdit()
        self.topic_edit.setPlaceholderText("如：日常问候与自我介绍")
        topic_row.addWidget(self.topic_edit, 1)
        config_lay.addLayout(topic_row)

        row1 = QHBoxLayout()
        row1.addWidget(QLabel("等级:"))
        self.level_combo = QComboBox()
        self.level_combo.addItems(["A1", "A2", "B1", "B2", "C1"])
        row1.addWidget(self.level_combo)

        row1.addWidget(QLabel("单元数:"))
        self.unit_spin = QSpinBox()
        self.unit_spin.setRange(1, 5)
        row1.addWidget(self.unit_spin)

        row1.addWidget(QLabel("课时/单元:"))
        self.lessons_spin = QSpinBox()
        self.lessons_spin.setRange(1, 5)
        self.lessons_spin.setValue(3)
        row1.addWidget(self.lessons_spin)

        row1.addWidget(QLabel("生成模板:"))
        self.template_combo = QComboBox()
        self.template_combo.addItem("混合排课", "mixed")
        self.template_combo.addItem("认识新词", "intro")
        self.template_combo.addItem("巩固练习", "practice")
        self.template_combo.addItem("复习训练", "review")
        self.template_combo.addItem("听力训练", "listening")
        self.template_combo.addItem("阅读理解", "reading")
        self.template_combo.addItem("综合测验", "mastery")
        row1.addWidget(self.template_combo)
        row1.addStretch()
        config_lay.addLayout(row1)

        row2 = QHBoxLayout()
        row2.addWidget(QLabel("AI 悄悄话:"))
        self.whisper_edit = QLineEdit()
        self.whisper_edit.setPlaceholderText(
            "微调指令（如：前两节课重点练习口语，第三节课听力）..."
        )
        row2.addWidget(self.whisper_edit)
        config_lay.addLayout(row2)

        self.focus_summary = QLabel("")
        self.focus_summary.setWordWrap(True)
        self.focus_summary.setStyleSheet(
            "font-size: 11px; opacity: 0.9; margin-top: 2px;"
        )
        self.focus_summary.setToolTip(
            "显示本次生成将使用的知识点规模（轨道内聚焦或整个资源池）"
        )
        config_lay.addWidget(self.focus_summary)

        main_lay.addWidget(config_widget)

        # 3. Generating Progress state (Slim overlay or below orbit)
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 0)
        self.progress_bar.setFixedHeight(6)
        self.progress_bar.setVisible(False)
        main_lay.addWidget(self.progress_bar)

        self.status_label = QLabel("")
        self.status_label.setStyleSheet("font-size: 11px; opacity: 0.8;")
        self.status_label.setVisible(False)
        main_lay.addWidget(self.status_label)

    def _apply_style(self) -> None:
        p = current_palette()
        border_color = p.get("border", "#2C313C")
        bg_card = p.get("ai_card_bg", "#1F232C")
        accent = p.get("ai_accent", "#46D1BF")
        accent_border = p.get("ai_accent_border", "#1F727E")

        # Central AI Core styling (circular, glowing)
        self.orbit_zone.setStyleSheet(
            f"QWidget#orbitZone {{"
            f"  background-color: {p.get('ai_chat_bg', '#1A1D23')};"
            f"  border: 2px dashed {border_color};"
            f"  border-radius: 12px;"
            f"}}"
        )

        self.core_btn.setStyleSheet(
            "QPushButton#coreBtn {"
            f"  background-color: {accent_border};"
            "  color: #FFFFFF;"
            f"  border: 3px solid {accent};"
            "  border-radius: 65px;"  # half of 130px makes it a perfect circle
            "  font-weight: bold;"
            "  font-size: 14px;"
            "  text-align: center;"
            "  line-height: 1.3;"
            "}"
            "QPushButton#coreBtn:hover {"
            f"  background-color: {accent};"
            "  border-color: #FFFFFF;"
            "}"
        )

        # Peacock glow shadow on the AI core button for depth (QSS can't do box-shadow).
        apply_shadow(self.core_btn, color_key="glow", blur_radius=24, dy=0, alpha=0.3)

    def _set_drag_active(self, active: bool) -> None:
        self._drag_active = active
        p = current_palette()
        border_color = p.get("ai_accent", "#46D1BF") if active else p.get("border", "#2C313C")
        bg_card = p.get("ai_chat_bg", "#1A1D23")
        
        self.orbit_zone.setStyleSheet(
            f"QWidget#orbitZone {{"
            f"  background-color: {bg_card};"
            f"  border: 2px {'solid' if active else 'dashed'} {border_color};"
            f"  border-radius: 12px;"
            f"}}"
        )

    def add_knowledge_point(self, entry: dict[str, Any], res_type: str) -> None:
        """Add a knowledge point bubble to the orbit."""
        # Prevent duplicates
        term = entry.get("term") or entry.get("title") or ""
        for item in self.dropped_items:
            t = item.get("entry", {}).get("term") or item.get("entry", {}).get("title") or ""
            if t == term and item.get("resource_type") == res_type:
                return

        payload = {"entry": entry, "resource_type": res_type}
        self.dropped_items.append(payload)

        # Visual Bubble
        bubble = KnowledgeBubble(entry, res_type, parent=self.bubbles_container, show_close=True)
        bubble.closed.connect(lambda: self.remove_knowledge_point(payload, bubble))
        self.bubbles_layout.addWidget(bubble)
        self.prompt_label.setText(f"已投入 {len(self.dropped_items)} 个知识点，AI 将定向生成课时")
        self._emit_focus_changed()

    def remove_knowledge_point(self, payload: dict[str, Any], bubble: KnowledgeBubble) -> None:
        """Remove a knowledge point from the orbit."""
        if payload in self.dropped_items:
            self.dropped_items.remove(payload)
        bubble.deleteLater()
        
        if not self.dropped_items:
            self.prompt_label.setText("✨ 拖拽左侧的知识点气泡到此轨道中 ✨\n(留空则默认使用资源池中的全部知识点)")
        else:
            self.prompt_label.setText(f"已投入 {len(self.dropped_items)} 个知识点，AI 将定向生成课时")
        self._emit_focus_changed()

    def clear_orbit(self) -> None:
        """Remove all bubbles from the orbit."""
        self.dropped_items.clear()
        # Clear child widgets
        for i in reversed(range(self.bubbles_layout.count())):
            w = self.bubbles_layout.itemAt(i).widget()
            if w is not None:
                w.deleteLater()
        self.prompt_label.setText("✨ 拖拽左侧的知识点气泡到此轨道中 ✨\n(留空则默认使用资源池中的全部知识点)")
        self._emit_focus_changed()

    def set_focus_summary(self, text: str) -> None:
        """Update the grounded-focus strip under generation params."""
        self.focus_summary.setText(text)
        self.focus_summary.setVisible(bool(text))

    def _emit_focus_changed(self) -> None:
        self.focus_changed.emit()

    def set_empty_hint(self, text: str) -> None:
        """Override the drop-zone prompt (blank-project / guided empty state)."""
        self.prompt_label.setText(text)

    def _emit_generate(self) -> None:
        if self.core_btn.isEnabled():
            self.generate_requested.emit()

    def set_busy(self, busy: bool, stage_text: str = "") -> None:
        """Update visual state when generator is active."""
        self.progress_bar.setVisible(busy)
        self.status_label.setVisible(busy)
        self.status_label.setText(stage_text)
        self.core_btn.setEnabled(not busy)
        if busy:
            p = current_palette()
            self.core_btn.setText("AI 生成中\n请稍候...")
            self.core_btn.setStyleSheet(
                "QPushButton#coreBtn {"
                f"  background-color: {p.get('ai_chat_bg', '#1A1D23')};"
                f"  color: {p.get('text_secondary', '#9CA3AF')};"
                f"  border: 3px solid {p.get('border', '#2C313C')};"
                "  border-radius: 65px;"
                "}"
            )
        else:
            self._apply_style()
            self.core_btn.setText("AI 核心\n开始设计课程")

    # --- Drag & Drop event overrides ------------------------------------------

    def dragEnterEvent(self, event) -> None:  # noqa: N802
        if event.mimeData().hasFormat("application/x-knowledge-point"):
            event.acceptProposedAction()
            self._set_drag_active(True)

    def dragLeaveEvent(self, event) -> None:  # noqa: N802
        self._set_drag_active(False)
        super().dragLeaveEvent(event)

    def dropEvent(self, event) -> None:  # noqa: N802
        data_bytes = event.mimeData().data("application/x-knowledge-point")
        try:
            payload = json.loads(bytes(data_bytes).decode("utf-8"))
            entry = payload["entry"]
            res_type = payload["resource_type"]
            self.add_knowledge_point(entry, res_type)
        except Exception:
            pass
        self._set_drag_active(False)
        event.acceptProposedAction()
