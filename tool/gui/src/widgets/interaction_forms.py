"""Dynamic forms for the 12 Interaction runtimeTypes.

Each form binds to an item dict (in the adapter's in-memory lesson tree) and
writes edits back in place. Reference fields (wordId / expressionId /
grammarPointId) use QComboBox populated from the adapter's loaded resources so
dangling ids cannot be typed by hand (guiplan §5 reference-integrity guard).
"""
from __future__ import annotations

from typing import Any, Callable

from PySide6.QtGui import QStandardItemModel
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import INTERACTION_SCHEMA, INTERACTION_LABELS
from src.widgets.option_models import build_options_model, select_by_id


class StringListEditor(QWidget):
    """Edit a list[str]: list on the left, add/remove buttons on the right."""

    def __init__(self, value: list[str], on_change: Callable[[list[str]], None]) -> None:
        super().__init__()
        self._value = list(value)
        self._on_change = on_change
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        self.list_widget = QListWidget()
        self.list_widget.setMaximumHeight(110)
        layout.addWidget(self.list_widget)
        btns = QVBoxLayout()
        self.add_btn = QPushButton("+")
        self.add_btn.setFixedWidth(28)
        self.del_btn = QPushButton("-")
        self.del_btn.setFixedWidth(28)
        self.up_btn = QPushButton("↑")
        self.up_btn.setFixedWidth(28)
        self.down_btn = QPushButton("↓")
        self.down_btn.setFixedWidth(28)
        btns.addWidget(self.add_btn)
        btns.addWidget(self.del_btn)
        btns.addWidget(self.up_btn)
        btns.addWidget(self.down_btn)
        btns.addStretch()
        layout.addLayout(btns)
        self._refresh()
        self.add_btn.clicked.connect(self._on_add)
        self.del_btn.clicked.connect(self._on_del)
        self.up_btn.clicked.connect(lambda: self._move(-1))
        self.down_btn.clicked.connect(lambda: self._move(1))

    def _refresh(self) -> None:
        self.list_widget.clear()
        for v in self._value:
            self.list_widget.addItem(v)

    def _emit(self) -> None:
        self._on_change(list(self._value))

    def _on_add(self) -> None:
        from PySide6.QtWidgets import QInputDialog
        text, ok = QInputDialog.getText(self, "添加", "输入内容:")
        if ok and text:
            self._value.append(text)
            self._refresh()
            self._emit()

    def _on_del(self) -> None:
        row = self.list_widget.currentRow()
        if 0 <= row < len(self._value):
            del self._value[row]
            self._refresh()
            self._emit()

    def _move(self, delta: int) -> None:
        row = self.list_widget.currentRow()
        new = row + delta
        if 0 <= row < len(self._value) and 0 <= new < len(self._value):
            self._value[row], self._value[new] = self._value[new], self._value[row]
            self._refresh()
            self.list_widget.setCurrentRow(new)
            self._emit()


def _ref_combo(
    adapter: CourseAdapter,
    kind: str,
    current: str,
    vocab_model: QStandardItemModel | None = None,
    expression_model: QStandardItemModel | None = None,
    grammar_model: QStandardItemModel | None = None,
) -> QComboBox:
    combo = QComboBox()
    if kind == "ref_word":
        model = vocab_model
        options = None if model is not None else adapter.vocab_options()
        placeholder = "(无)"
    elif kind == "ref_expression":
        model = expression_model
        options = None if model is not None else adapter.expression_options()
        placeholder = "(无)"
    else:
        model = grammar_model
        options = None if model is not None else adapter.grammar_options()
        placeholder = "(无)"
    if model is None:
        model = build_options_model(options, placeholder=placeholder)
    combo.setModel(model)
    select_by_id(combo, model, current)
    return combo


class InteractionForm(QWidget):
    """Form for a single interaction item, dispatched by runtimeType."""

    def __init__(
        self,
        adapter: CourseAdapter,
        item: dict[str, Any],
        on_changed: Callable[[], None] | None = None,
        vocab_model: QStandardItemModel | None = None,
        expression_model: QStandardItemModel | None = None,
        grammar_model: QStandardItemModel | None = None,
    ) -> None:
        super().__init__()
        self.adapter = adapter
        self.item = item
        self._on_changed = on_changed
        self._vocab_model = vocab_model
        self._expression_model = expression_model
        self._grammar_model = grammar_model
        rt = item.get("runtimeType", "")
        layout = QVBoxLayout(self)
        title = QLabel(f"题型：{INTERACTION_LABELS.get(rt, rt)}")
        title.setStyleSheet("font-weight: bold;")
        layout.addWidget(title)

        form = QFormLayout()
        schema = INTERACTION_SCHEMA.get(rt, [])
        self._widgets: dict[str, QWidget] = {}
        for spec in schema:
            if spec.name == "runtimeType":
                continue
            widget = self._build_field(spec, item.get(spec.name, spec.default))
            form.addRow(spec.name + (" *" if spec.required else ""), widget)
            self._widgets[spec.name] = widget
        layout.addLayout(form)
        layout.addStretch()

    def _build_field(self, spec: Any, value: Any) -> QWidget:
        if spec.kind == "string":
            edit = QLineEdit(str(value or ""))
            edit.textChanged.connect(lambda v, n=spec.name: self._set(n, v))
            return edit
        if spec.kind == "int":
            spin = QSpinBox()
            spin.setRange(0, 2147483647)
            spin.setValue(int(value or 0))
            spin.valueChanged.connect(lambda v, n=spec.name: self._set(n, v))
            return spin
        if spec.kind == "bool":
            chk = QCheckBox()
            chk.setChecked(bool(value))
            chk.toggled.connect(lambda v, n=spec.name: self._set(n, v))
            return chk
        if spec.kind == "string_list":
            return StringListEditor(
                list(value or []), lambda v, n=spec.name: self._set(n, v)
            )
        if spec.kind == "int_list":
            edit = QLineEdit(", ".join(str(i) for i in (value or [])))
            edit.textChanged.connect(
                lambda v, n=spec.name: self._set(n, _parse_int_list(v))
            )
            return edit
        if spec.kind in ("ref_word", "ref_expression", "ref_grammar"):
            combo = _ref_combo(
                self.adapter,
                spec.kind,
                str(value or ""),
                vocab_model=self._vocab_model,
                expression_model=self._expression_model,
                grammar_model=self._grammar_model,
            )
            combo.currentIndexChanged.connect(
                lambda _i, c=combo, n=spec.name: self._set(n, c.currentData())
            )
            return combo
        return QLabel(str(value))

    def _set(self, name: str, value: Any) -> None:
        self.item[name] = value
        if self._on_changed:
            self._on_changed()


def _parse_int_list(text: str) -> list[int]:
    out: list[int] = []
    for part in (text or "").split(","):
        part = part.strip()
        if part.isdigit():
            out.append(int(part))
    return out