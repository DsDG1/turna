"""The single shared template/genre selector (guiplan2 B8 fix).

Previously ``_build_template_selector`` was called twice — once for the normal
topic panel and once for the wish panel — and each call overwrote
``template_combo`` / ``_template_cards`` / ``genre_switch``, orphaning the
first set. The dialog now constructs **one** ``PromptTemplateBar`` and reparents
it into whichever panel is visible, so template/genre state is global and
unique (B8).
"""
from __future__ import annotations

from typing import Callable

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai_genre import GENRE_TEMPLATES
from src.application.ai_prompt_library import AiPromptLibrary, AiPromptHistory, AiPromptTemplate
from src.theme_tokens import BRAND_REED, BRAND_TEAL


def _card_stylesheet(selected: bool, palette: dict[str, str] | None = None) -> str:
    pal = palette or {}
    accent = pal.get("ai_accent", BRAND_REED)
    accent_border = pal.get("ai_accent_border", BRAND_TEAL)
    card_bg = pal.get("ai_card_bg", "#1F232C")
    border = pal.get("ai_bubble_bg", "#2C313C")
    text = pal.get("text", "#E8EAF0")
    if selected:
        return (
            "QPushButton {"
            f"  background-color: rgba(31, 114, 126, 0.25);"
            f"  color: {accent};"
            f"  border: 2px solid {accent_border};"
            "  border-radius: 8px;"
            "  padding: 8px 10px;"
            "  font-size: 13px;"
            "  text-align: left;"
            "}"
            "QPushButton:hover { background-color: rgba(31, 114, 126, 0.35); }"
        )
    return (
        "QPushButton {"
        f"  background-color: {card_bg};"
        f"  color: {text};"
        f"  border: 1px solid {border};"
        "  border-radius: 8px;"
        "  padding: 8px 10px;"
        "  font-size: 13px;"
        "  text-align: left;"
        "}"
        f"QPushButton:hover {{ border: 1px solid {accent_border}; color: {accent}; }}"
    )


class PromptTemplateBar(QWidget):
    """Visual template cards + hidden combo + genre-batch switch.

    The hidden ``template_combo`` is the single source of truth for the
    selected template value (read via ``selected_template()``). Emits
    ``template_changed`` and ``genre_toggled`` so the host dialog can update
    placeholders / run genre-tag sync without reaching into internals.
    """

    template_changed = Signal(str)
    genre_toggled = Signal(bool)
    template_applied = Signal(object)  # AiPromptTemplate
    history_applied = Signal(object)  # AiPromptHistory

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._library: AiPromptLibrary | None = None
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        # Hidden combo — single source of truth for the template value.
        self.template_combo = QComboBox()
        self.template_combo.addItem("混合", "mixed")
        self.template_combo.addItem("认识新词", "intro")
        self.template_combo.addItem("巩固练习", "practice")
        self.template_combo.addItem("复习", "review")
        self.template_combo.addItem("听力训练", "listening")
        self.template_combo.addItem("阅读理解", "reading")
        self.template_combo.addItem("综合测验", "mastery")
        self.template_combo.currentIndexChanged.connect(self._on_combo_changed)
        self.template_combo.setVisible(False)

        cards_row = QHBoxLayout()
        cards_row.setContentsMargins(0, 0, 0, 0)
        cards_row.setSpacing(8)
        cards_row.addWidget(QLabel("课程类型:"))
        self._template_cards: dict[str, QPushButton] = {}
        for tag, meta in GENRE_TEMPLATES.items():
            template = meta["template"]
            card = QPushButton(meta["label"])
            card.setCheckable(True)
            card.setToolTip(meta.get("description", ""))
            card.setCursor(Qt.CursorShape.PointingHandCursor)
            card.setMinimumWidth(86)
            card.setStyleSheet(_card_stylesheet(selected=False))
            card.setProperty("template_name", template)
            card.clicked.connect(self._on_template_card_clicked)
            self._template_cards[template] = card
            cards_row.addWidget(card)
        cards_row.addWidget(self.template_combo)
        cards_row.addStretch()
        layout.addLayout(cards_row)

        genre_row = QHBoxLayout()
        genre_row.setContentsMargins(0, 0, 0, 0)
        genre_row.setSpacing(8)
        self.genre_switch = QCheckBox("启用 [genre] 多模板批量生成（高 token 消耗）")
        self.genre_switch.setChecked(False)
        self.genre_switch.setToolTip(
            "开启后，可在主题或额外指令中插入 [intro]、[listening] 等标签，"
            "让 AI 批量生成多种模板的课程。会显著增加 token 消耗。"
        )
        self.genre_switch.stateChanged.connect(self._on_genre_state_changed)
        genre_row.addWidget(self.genre_switch)
        genre_row.addStretch()
        layout.addLayout(genre_row)

        library_row = QHBoxLayout()
        library_row.setContentsMargins(0, 0, 0, 0)
        library_row.setSpacing(8)

        self.save_template_btn = QPushButton("保存为模板")
        self.save_template_btn.setToolTip("把当前主题与规格保存为可复用的 prompt 模板")
        self.save_template_btn.clicked.connect(self._on_save_template)
        library_row.addWidget(self.save_template_btn)

        library_row.addWidget(QLabel("模板:"))
        self.template_library_combo = QComboBox()
        self.template_library_combo.setMinimumWidth(120)
        self.template_library_combo.setToolTip("选择已保存的 prompt 模板")
        self.template_library_combo.currentIndexChanged.connect(self._on_template_selected)
        library_row.addWidget(self.template_library_combo)

        library_row.addWidget(QLabel("历史:"))
        self.history_combo = QComboBox()
        self.history_combo.setMinimumWidth(120)
        self.history_combo.setToolTip("最近使用过的生成 prompt")
        self.history_combo.currentIndexChanged.connect(self._on_history_selected)
        library_row.addWidget(self.history_combo)

        library_row.addStretch()
        layout.addLayout(library_row)

        # Default selection = mixed.
        self.select_template("mixed", emit=False)

    def _on_template_card_clicked(self) -> None:
        sender = self.sender()
        if not sender:
            return
        template = sender.property("template_name")
        if isinstance(template, str):
            self.select_template(template)

    # --- public API ------------------------------------------------------

    def selected_template(self) -> str:
        return self.template_combo.currentData() or "mixed"

    def is_genre_enabled(self) -> bool:
        return self.genre_switch.isChecked()

    def select_template(self, template: str, emit: bool = True) -> None:
        """Visually select a card and sync the hidden combo."""
        for tpl, card in self._template_cards.items():
            is_sel = tpl == template
            card.setChecked(is_sel)
            card.setStyleSheet(_card_stylesheet(selected=is_sel, palette=self._palette))
        target_index = 0
        for i in range(self.template_combo.count()):
            if self.template_combo.itemData(i) == template:
                target_index = i
                break
        if emit:
            self.template_combo.setCurrentIndex(target_index)
        else:
            self.template_combo.blockSignals(True)
            self.template_combo.setCurrentIndex(target_index)
            self.template_combo.blockSignals(False)

    def set_genre_enabled(self, enabled: bool) -> None:
        self.genre_switch.setChecked(enabled)

    def set_library(self, library: AiPromptLibrary | None) -> None:
        """Attach a prompt library for template/history dropdowns."""
        self._library = library
        self._refresh_library_ui()

    def _refresh_library_ui(self) -> None:
        self.template_library_combo.blockSignals(True)
        self.template_library_combo.clear()
        self.template_library_combo.addItem("— 选择模板 —", None)
        if self._library is not None:
            for tpl in self._library.list_templates():
                self.template_library_combo.addItem(tpl.name, tpl.to_dict())
        self.template_library_combo.blockSignals(False)

        self.history_combo.blockSignals(True)
        self.history_combo.clear()
        self.history_combo.addItem("— 最近历史 —", None)
        if self._library is not None:
            for entry in self._library.recent_history():
                label = entry.topic or "(无主题)"
                if entry.extra_instructions:
                    label += " · " + entry.extra_instructions[:20]
                self.history_combo.addItem(label, entry.to_dict())
        self.history_combo.blockSignals(False)

    def set_fallback_label(self, enabled: bool) -> None:
        """Relabel combo item 0 to reflect the genre-batch fallback semantics."""
        self.template_combo.setItemText(0, "默认回退" if enabled else "混合")

    def set_template_by_tags(
        self, tags: list[str], genre_to_template: Callable[[str], str]
    ) -> None:
        """Pick the template from the first genre tag (genre-tag sync helper)."""
        if tags:
            self.select_template(genre_to_template(tags[0]))
        self.set_fallback_label(enabled=True)

    def update_placeholders(
        self,
        topic_edit: "QWidget | None" = None,
        input_edit: "QWidget | None" = None,
    ) -> None:
        if self.genre_switch.isChecked():
            if topic_edit is not None:
                topic_edit.setPlaceholderText("例如：旅行词汇 [intro] [practice]")
            if input_edit is not None:
                input_edit.setPlaceholderText(
                    "输入你想说的，可插入 [intro]、[listening] 等 genre 标签；Ctrl+Enter 发送..."
                )
        else:
            if topic_edit is not None:
                topic_edit.setPlaceholderText("例如：旅行词汇")
            if input_edit is not None:
                input_edit.setPlaceholderText("输入你想说的，Ctrl+Enter 发送...")

    def restyle(self, palette: dict[str, str]) -> None:
        self._palette = palette
        sel = self.selected_template()
        for tpl, card in self._template_cards.items():
            card.setStyleSheet(_card_stylesheet(selected=tpl == sel, palette=palette))

    # --- internal --------------------------------------------------------

    _palette: dict[str, str] = {}

    def _on_combo_changed(self, index: int) -> None:
        template = self.template_combo.itemData(index) or "mixed"
        for tpl, card in self._template_cards.items():
            is_sel = tpl == template
            card.setChecked(is_sel)
            card.setStyleSheet(_card_stylesheet(selected=is_sel, palette=self._palette))
        self.template_changed.emit(template)

    def _on_genre_state_changed(self, state: int) -> None:
        enabled = state == Qt.CheckState.Checked.value
        self.set_fallback_label(enabled)
        self.genre_toggled.emit(enabled)

    def _on_save_template(self) -> None:
        from PySide6.QtWidgets import QInputDialog

        if self._library is None:
            return
        name, ok = QInputDialog.getText(
            self,
            "保存 prompt 模板",
            "模板名称（相同名称会覆盖）：",
        )
        if not ok or not name.strip():
            return
        # The host dialog is responsible for providing the current spec.
        self._pending_template_name = name.strip()
        self.template_applied.emit({"action": "save_request", "name": name.strip()})

    def save_current_template(self, spec) -> None:
        """Call after the host dialog has supplied a spec for _pending_template_name."""
        if self._library is None:
            return
        name = getattr(self, "_pending_template_name", "")
        if not name:
            return
        template = AiPromptTemplate.from_spec(name, spec)
        self._library.save_template(template)
        self._refresh_library_ui()
        self._pending_template_name = ""

    def _on_template_selected(self, index: int) -> None:
        data = self.template_library_combo.itemData(index)
        if not data:
            return
        template = AiPromptTemplate.from_dict(data)
        self.template_applied.emit(template)

    def _on_history_selected(self, index: int) -> None:
        data = self.history_combo.itemData(index)
        if not data:
            return
        entry = AiPromptHistory.from_dict(data)
        self.history_applied.emit(entry)

    def record_history(self, spec) -> None:
        """Convenience wrapper: record the current spec into history."""
        if self._library is not None:
            self._library.record_history(spec)
            self._refresh_library_ui()