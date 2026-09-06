"""Question cards for the teacher view (guiplan §15.5, T.4).

Each runtimeType renders as a self-contained card. The `correctIndex` /
`correctIndices` concept is hidden behind radio buttons / checkboxes the
teacher clicks directly. Edits write back to the in-memory item dict so save()
persists them.

Anki cards (ankiCard / ankiHtmlCard) get degraded desktop previews: a plain
flip interaction for ankiCard and tag-stripped text plus an "App 渲染为准"
badge for ankiHtmlCard — the full HTML/CSS/JS WebView rendering lives in the
app, not the editor (non-goal of the schema-sync plan).
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtGui import QStandardItemModel
from PySide6.QtWidgets import (
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QRadioButton,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import ALLOWED_RUNTIME_TYPES
from src.backend.schema_constants import InteractionType, ItemKey
from src.i18n.labels import field_label, interaction_label
from src.theme import current_palette
from src.widgets.option_models import build_options_model, select_by_id

#: Media refs under this protocol resolve inside the app's Anki import dir,
#: not the desktop repo — teacher cards show them as path placeholders only.
ANKI_MEDIA_PREFIX = "anki://"


class _OptionRow(QWidget):
    """Single row representing one option: selector + editable text."""

    def __init__(
        self,
        text: str,
        checked: bool,
        exclusive: bool,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        if exclusive:
            self.selector = QRadioButton()
        else:
            self.selector = QCheckBox()
        self.selector.setChecked(checked)
        self.edit = QLineEdit(text)
        layout.addWidget(self.selector)
        layout.addWidget(self.edit, 1)


class QuestionCard(QFrame):
    """A single question card bound to one interaction item."""

    changed = Signal()
    delete_requested = Signal()
    type_changed = Signal(str)
    move_up_requested = Signal()
    move_down_requested = Signal()
    ai_rewrite_requested = Signal()

    _CONTENT_BUILDERS: dict[str, str] = {
        InteractionType.SHOW_WORD: "_build_show_word",
        InteractionType.MULTIPLE_CHOICE: "_build_single_choice",
        InteractionType.READING_MCQ: "_build_single_choice",
        InteractionType.LISTEN_AND_PICK: "_build_single_choice",
        InteractionType.MULTI_SELECT: "_build_multi_select",
        InteractionType.FILL_BLANK: "_build_fill_blank",
        InteractionType.TRANSLATE_SENTENCE: "_build_translate",
        InteractionType.READING_TRUE_FALSE: "_build_true_false",
        InteractionType.READING_SHORT_ANSWER: "_build_short_answer",
        InteractionType.TYPE_THE_WORD: "_build_type_the_word",
        InteractionType.LISTEN_ONLY: "_build_listen_only",
        InteractionType.REORDER_SENTENCE: "_build_reorder_sentence",
        InteractionType.ANKI_CARD: "_build_anki_card",
        InteractionType.ANKI_HTML_CARD: "_build_anki_html_card",
    }

    def __init__(
        self,
        adapter: CourseAdapter,
        item: dict[str, Any],
        vocab_model: QStandardItemModel | None = None,
        expression_model: QStandardItemModel | None = None,
        grammar_model: QStandardItemModel | None = None,
    ) -> None:
        super().__init__()
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "QuestionCard { background-color: #232833; border: 1px solid #2C313C; border-radius: 8px; }"
        )
        self.adapter = adapter
        self.item = item
        self._vocab_model = vocab_model
        self._expression_model = expression_model
        self._grammar_model = grammar_model
        self._content_widget: QWidget | None = None
        self._type_combo: QComboBox | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(10)
        layout.addWidget(self._build_header())
        self._build_content()

    def _build_header(self) -> QWidget:
        header = QWidget()
        hlayout = QHBoxLayout(header)
        hlayout.setContentsMargins(0, 0, 0, 0)
        hlayout.setSpacing(8)

        self._type_combo = QComboBox()
        for rt in ALLOWED_RUNTIME_TYPES:
            self._type_combo.addItem(interaction_label(rt), rt)
        rt = self.item.get(ItemKey.RUNTIME_TYPE, "")
        for i in range(self._type_combo.count()):
            if self._type_combo.itemData(i) == rt:
                self._type_combo.setCurrentIndex(i)
                break
        self._type_combo.currentIndexChanged.connect(self._on_type_changed)
        hlayout.addWidget(self._type_combo)

        hlayout.addStretch()

        up_btn = QPushButton("↑")
        up_btn.setFixedWidth(28)
        up_btn.setToolTip("上移")
        up_btn.clicked.connect(self.move_up_requested.emit)
        hlayout.addWidget(up_btn)

        down_btn = QPushButton("↓")
        down_btn.setFixedWidth(28)
        down_btn.setToolTip("下移")
        down_btn.clicked.connect(self.move_down_requested.emit)
        hlayout.addWidget(down_btn)

        del_btn = QPushButton("删除")
        del_btn.setMinimumWidth(48)
        del_btn.setToolTip("删除题目")
        del_btn.clicked.connect(self._on_delete)
        hlayout.addWidget(del_btn)

        ai_btn = QPushButton("AI")
        ai_btn.setMinimumWidth(48)
        ai_btn.setToolTip("AI 改写本题")
        ai_btn.clicked.connect(self.ai_rewrite_requested.emit)
        hlayout.addWidget(ai_btn)

        return header

    def _on_type_changed(self) -> None:
        if self._type_combo is None:
            return
        new_type = self._type_combo.currentData()
        if new_type == self.item.get(ItemKey.RUNTIME_TYPE):
            return
        self.type_changed.emit(new_type)

    def _on_delete(self) -> None:
        reply = QMessageBox.question(
            self,
            "删除题目",
            "确认删除这道题目？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply == QMessageBox.StandardButton.Yes:
            self.delete_requested.emit()

    def _build_content(self) -> None:
        if self._content_widget is not None:
            self._content_widget.setParent(None)
            self._content_widget.deleteLater()
        self._content_widget = QWidget()
        layout = QVBoxLayout(self._content_widget)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)

        rt = self.item.get(ItemKey.RUNTIME_TYPE, "")
        method_name = self._CONTENT_BUILDERS.get(rt, "_build_fallback")
        builder = getattr(self, method_name, self._build_fallback)
        builder(layout)

        self._build_grammar_combo(layout)

        self.layout().addWidget(self._content_widget)

    def _add_labeled_edit(
        self, layout: QVBoxLayout, field: str, multi_line: bool = False
    ) -> QLineEdit | QTextEdit:
        layout.addWidget(QLabel(field_label(field)))
        if multi_line:
            edit = QTextEdit()
            edit.setPlainText(str(self.item.get(field, "") or ""))
            edit.setProperty("bound_field", field)
            edit.textChanged.connect(self._on_text_edit_changed)
            layout.addWidget(edit)
            return edit
        edit = QLineEdit()
        edit.setText(str(self.item.get(field, "") or ""))
        edit.setProperty("bound_field", field)
        edit.textChanged.connect(self._on_line_edit_changed)
        layout.addWidget(edit)
        return edit

    def _on_text_edit_changed(self) -> None:
        sender = self.sender()
        if isinstance(sender, QTextEdit):
            field = sender.property("bound_field")
            if field:
                self._set_field(str(field), sender.toPlainText())

    def _on_line_edit_changed(self, text: str) -> None:
        sender = self.sender()
        if isinstance(sender, QLineEdit):
            field = sender.property("bound_field")
            if field:
                self._set_field(str(field), text)

    def _on_combo_field_changed(self, _index: int) -> None:
        sender = self.sender()
        if isinstance(sender, QComboBox):
            field = sender.property("bound_field")
            if field:
                self._set_field(str(field), sender.currentData() or "")

    def _set_field(self, field: str, value: Any) -> None:
        self.item[field] = value
        self.changed.emit()

    def _word_combo(self, current_id: str) -> QComboBox:
        combo = QComboBox()
        model = self._vocab_model
        if model is None:
            model = build_options_model(self.adapter.vocab_options(), placeholder="(未选择)")
        combo.setModel(model)
        select_by_id(combo, model, current_id)
        return combo

    def _build_grammar_combo(self, layout: QVBoxLayout) -> None:
        combo = QComboBox()
        model = self._grammar_model
        if model is None:
            model = build_options_model(self.adapter.grammar_options(), placeholder="(未关联)")
        combo.setModel(model)
        select_by_id(combo, model, self.item.get(ItemKey.GRAMMAR_POINT_ID) or "")
        combo.setProperty("bound_field", ItemKey.GRAMMAR_POINT_ID)
        combo.currentIndexChanged.connect(self._on_combo_field_changed)
        layout.addWidget(QLabel(field_label(ItemKey.GRAMMAR_POINT_ID)))
        layout.addWidget(combo)

    def _build_show_word(self, layout: QVBoxLayout) -> None:
        layout.addWidget(QLabel(field_label(ItemKey.WORD_ID)))
        combo = self._word_combo(self.item.get(ItemKey.WORD_ID, ""))
        combo.setProperty("bound_field", ItemKey.WORD_ID)
        combo.currentIndexChanged.connect(self._on_combo_field_changed)
        layout.addWidget(combo)
        self._add_labeled_edit(layout, "context")
        # Inline overrides: when non-empty the app prefers them over the vocab
        # entry (interaction.dart ShowWord). Show the effective value in the
        # editors so what the teacher sees matches what the learner gets.
        hint = QLabel("以下内联字段非空时覆盖词表默认显示（通常留空）")
        hint.setStyleSheet("color: gray;")
        layout.addWidget(hint)
        for field in ("term", "translation", "pronunciation", "audioAsset", "imageAsset", "example"):
            self._add_labeled_edit(layout, field)

    def _build_type_the_word(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, "prompt")
        self._add_labeled_edit(layout, "expected")
        self._add_labeled_edit(layout, "audioAsset")

    def _build_listen_only(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, "audioAsset")
        self._add_labeled_edit(layout, "transcript")
        self._add_labeled_edit(layout, "prompt")

    def _build_reorder_sentence(self, layout: QVBoxLayout) -> None:
        from src.widgets.interaction_forms import StringListEditor

        layout.addWidget(QLabel("打乱顺序的词"))
        scrambled = self.item.get("scrambled", []) or []
        layout.addWidget(
            StringListEditor(
                list(scrambled), lambda v: self._set_field("scrambled", v)
            )
        )
        layout.addWidget(QLabel("正确顺序"))
        correct = self.item.get("correct", []) or []
        layout.addWidget(
            StringListEditor(
                list(correct), lambda v: self._set_field("correct", v)
            )
        )

    def _build_options_editor(self, layout: QVBoxLayout, exclusive: bool) -> None:
        """Build radio/checkbox options list with add/delete buttons."""
        options = list(self.item.get(ItemKey.OPTIONS, []) or [])
        group = QButtonGroup(self) if exclusive else None
        if group is not None:
            group.setExclusive(True)

        rows: list[_OptionRow] = []
        if exclusive:
            correct_idx = int(self.item.get(ItemKey.CORRECT_INDEX, 0) or 0)
            correct_set = {correct_idx}
        else:
            correct_set = set(self.item.get(ItemKey.CORRECT_INDICES, []) or [])

        self._option_rows = rows
        self._options_exclusive = exclusive
        for i, opt in enumerate(options):
            row = _OptionRow(str(opt), i in correct_set, exclusive=exclusive)
            if group is not None:
                group.addButton(row.selector)
            row.selector.toggled.connect(self._on_option_row_toggled)
            row.edit.setProperty("option_index", i)
            row.edit.textChanged.connect(self._on_option_row_text_changed)
            rows.append(row)
            layout.addWidget(row)

        add_btn = QPushButton("+ 添加选项")
        del_btn = QPushButton("- 删除末项")
        add_btn.clicked.connect(self._on_add_option)
        del_btn.clicked.connect(self._on_del_option)
        btn_row = QHBoxLayout()
        btn_row.addWidget(add_btn)
        btn_row.addWidget(del_btn)
        layout.addLayout(btn_row)

    def _on_option_row_toggled(self, checked: bool) -> None:
        rows = getattr(self, "_option_rows", [])
        exclusive = getattr(self, "_options_exclusive", True)
        self._on_option_toggled(checked, exclusive, rows)

    def _on_option_row_text_changed(self, text: str) -> None:
        sender = self.sender()
        if isinstance(sender, QLineEdit):
            idx = sender.property("option_index")
            if idx is not None:
                self._on_option_text_changed(int(idx), text)

    def _on_option_toggled(
        self, checked: bool, exclusive: bool, rows: list[_OptionRow]
    ) -> None:
        if not checked:
            return
        if exclusive:
            for idx, r in enumerate(rows):
                if r.selector.isChecked():
                    self._set_field(ItemKey.CORRECT_INDEX, idx)
                    return
        else:
            indices = [i for i, r in enumerate(rows) if r.selector.isChecked()]
            self._set_field(ItemKey.CORRECT_INDICES, indices)

    def _on_option_text_changed(self, index: int, text: str) -> None:
        opts = list(self.item.get(ItemKey.OPTIONS, []) or [])
        if 0 <= index < len(opts):
            opts[index] = text
            self._set_field(ItemKey.OPTIONS, opts)

    def _on_add_option(self) -> None:
        self.item.setdefault(ItemKey.OPTIONS, []).append("新选项")
        self._build_content()
        self.changed.emit()

    def _on_del_option(self) -> None:
        opts = self.item.get(ItemKey.OPTIONS, [])
        if len(opts) > 2:
            opts.pop()
            self._build_content()
            self.changed.emit()

    def _build_single_choice(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, ItemKey.PROMPT)
        if self.item.get(ItemKey.RUNTIME_TYPE) == InteractionType.MULTIPLE_CHOICE:
            self._add_media_list(layout, ItemKey.AUDIO_ASSETS)
        self._build_options_editor(layout, exclusive=True)

    def _build_multi_select(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, ItemKey.PROMPT)
        self._build_options_editor(layout, exclusive=False)

    def _build_fill_blank(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, "sentence")
        self._add_labeled_edit(layout, "answer")
        self._add_labeled_edit(layout, "translation")
        layout.addWidget(QLabel(field_label("hints")))
        edit = QTextEdit()
        hints = self.item.get("hints")
        if isinstance(hints, list):
            edit.setPlainText("\n".join(str(h) for h in hints))
        else:
            edit.setPlainText(str(hints or ""))
        edit.textChanged.connect(self._on_hints_text_changed)
        layout.addWidget(edit)

    def _on_hints_text_changed(self) -> None:
        sender = self.sender()
        if isinstance(sender, QTextEdit):
            lines = [ln.strip() for ln in sender.toPlainText().splitlines() if ln.strip()]
            self._set_field("hints", lines)

    def _build_translate(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, "source")
        self._add_labeled_edit(layout, "expected")
        # hints is a string_list field: one hint per line in the editor.
        layout.addWidget(QLabel(field_label("hints")))
        edit = QTextEdit()
        hints = self.item.get("hints")
        if isinstance(hints, list):
            edit.setPlainText("\n".join(str(h) for h in hints))
        else:
            edit.setPlainText(str(hints or ""))
        edit.textChanged.connect(self._on_hints_text_changed)
        layout.addWidget(edit)

    def _build_true_false(self, layout: QVBoxLayout) -> None:
        layout.addWidget(QLabel("陈述:"))
        edit = QLineEdit(str(self.item.get("statement", "")))
        edit.textChanged.connect(self._on_statement_text_changed)
        layout.addWidget(edit)
        true_btn = QRadioButton("正确")
        false_btn = QRadioButton("错误")
        if self.item.get("answer") is True:
            true_btn.setChecked(True)
        else:
            false_btn.setChecked(True)
        true_btn.toggled.connect(self._on_true_btn_toggled)
        false_btn.toggled.connect(self._on_false_btn_toggled)
        row = QHBoxLayout()
        row.addWidget(true_btn)
        row.addWidget(false_btn)
        layout.addLayout(row)

    def _on_statement_text_changed(self, text: str) -> None:
        self._set_field("statement", text)

    def _on_true_btn_toggled(self, checked: bool) -> None:
        if checked:
            self._set_field("answer", True)

    def _on_false_btn_toggled(self, checked: bool) -> None:
        if checked:
            self._set_field("answer", False)

    def _build_short_answer(self, layout: QVBoxLayout) -> None:
        self._add_labeled_edit(layout, "prompt")
        self._add_labeled_edit(layout, "expectedAnswer")

    def _add_media_list(self, layout: QVBoxLayout, field: str) -> None:
        """Editable placeholder list for media refs (audioAssets / imageAssets).

        Refs may use the ``anki://<importId>/<file>`` protocol whose files live
        in the app's Anki import dir — the desktop only shows/edits the paths,
        it does not play them.
        """
        from src.widgets.interaction_forms import StringListEditor

        layout.addWidget(QLabel(field_label(field)))

        def _on_media_changed(vals: list[str]) -> None:
            self._set_field(field, vals)

        layout.addWidget(
            StringListEditor(
                list(self.item.get(field) or []),
                _on_media_changed,
            )
        )

    def _build_anki_card(self, layout: QVBoxLayout) -> None:
        """Plain flip card: click the face to reveal the other side."""
        layout.addWidget(QLabel(field_label("front")))
        front_edit = QLineEdit(str(self.item.get("front", "") or ""))
        front_edit.textChanged.connect(self._on_front_text_changed)
        layout.addWidget(front_edit)

    def _on_front_text_changed(self, text: str) -> None:
        self._set_field("front", text)

        self._flip_label = QLabel("(点击下方按钮翻面)")
        self._flip_label.setWordWrap(True)
        self._flip_label.setStyleSheet(f"padding: 6px; color: {current_palette()['text_disabled']};")
        layout.addWidget(self._flip_label)

        self._flip_btn = QPushButton("翻面（显示背面）")
        self._revealed = False
        self._flip_btn.clicked.connect(self._on_toggle_anki_flip)
        layout.addWidget(self._flip_btn)

        layout.addWidget(QLabel(field_label("back")))
        back_edit = QLineEdit(str(self.item.get("back", "") or ""))
        back_edit.textChanged.connect(self._on_anki_back_changed)
        layout.addWidget(back_edit)

        hint = str(self.item.get("hint", "") or "")
        if hint:
            hint_btn = QPushButton("提示")
            hint_btn.setToolTip(hint)
            hint_btn.setProperty("hint_text", hint)
            hint_btn.clicked.connect(self._on_hint_button_clicked)
            layout.addWidget(hint_btn)

        self._add_media_list(layout, "audioAssets")
        self._add_media_list(layout, "imageAssets")

    def _on_hint_button_clicked(self) -> None:
        sender = self.sender()
        hint = sender.property("hint_text") if sender else ""
        QMessageBox.information(self, "提示", str(hint) if hint else "(空)")

    def _on_toggle_anki_flip(self) -> None:
        self._revealed = not getattr(self, "_revealed", False)
        text = (
            (self.item.get("back", "") or "(空)")
            if self._revealed
            else (self.item.get("front", "") or "(空)")
        )
        if hasattr(self, "_flip_label"):
            self._flip_label.setText(text)
        if hasattr(self, "_flip_btn"):
            self._flip_btn.setText(
                "翻面（显示背面）" if self._revealed else "翻面（显示正面）"
            )

    def _on_anki_back_changed(self, text: str) -> None:
        self._set_field("back", text)
        if getattr(self, "_revealed", False) and hasattr(self, "_flip_label"):
            self._flip_label.setText(text or "(空)")


    def _build_anki_html_card(self, layout: QVBoxLayout) -> None:
        """Degraded preview: tag-stripped text; full rendering is app-side."""
        from src.backend.anki_import import _strip_html

        badge = QLabel("HTML 卡片，完整渲染请以 App 为准（此处为剥除标签的纯文本预览）")
        badge.setStyleSheet(
            "background-color: #4a3f2a; color: #e8c46a; border-radius: 4px;"
            "padding: 4px 8px;"
        )
        badge.setWordWrap(True)
        layout.addWidget(badge)

        front_text = _strip_html(str(self.item.get("frontHtml", "") or ""))
        layout.addWidget(QLabel(f"{field_label('frontHtml')}（纯文本）"))
        front_preview = QLabel(front_text or "(空)")
        front_preview.setWordWrap(True)
        layout.addWidget(front_preview)

        back_text = _strip_html(str(self.item.get("backHtml", "") or ""))
        layout.addWidget(QLabel(f"{field_label('backHtml')}（纯文本）"))
        back_preview = QLabel(back_text or "(空)")
        back_preview.setWordWrap(True)
        layout.addWidget(back_preview)

        self._add_media_list(layout, "audioAssets")

    def _build_fallback(self, layout: QVBoxLayout) -> None:
        from src.widgets.interaction_forms import InteractionForm

        layout.addWidget(QLabel("教师视图暂未优化此题型，已使用通用表单。"))
        form = InteractionForm(
            self.adapter,
            self.item,
            self.changed.emit,
            vocab_model=self._vocab_model,
            expression_model=self._expression_model,
            grammar_model=self._grammar_model,
        )
        layout.addWidget(form)

    def _rebuild(self) -> None:
        self._build_content()
