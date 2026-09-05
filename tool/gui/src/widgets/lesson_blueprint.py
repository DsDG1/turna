"""Visual lesson-structure blueprint (workshop2 P3).

A card-flow overview of a lesson that renders the whole structure at a glance
and supports inline editing. Per template:

- listening: horizontal phase cards (wordPairing -> dialogue -> summary), each
  expandable to edit its items.
- reading: a passage card (title/difficulty/paragraphs) + comprehension
  question cards.
- mastery: a single stage's question cards.
- intro/practice/review/legacy: sub-lesson columns, each with stage -> item
  cards (kanban-style).

``read_only=True`` renders compact item summaries instead of editable
``QuestionCard``s and hides add/delete/move affordances - used by the
functional-lesson wizard preview (P2).

Editing mirrors ``LinearFlowWidget``: when an ``undo_stack`` is supplied,
mutations go through commands (undoable); otherwise the lesson dict is
mutated directly.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    INTERACTION_LABELS,
    add_item,
    add_listening_phase,
    add_sub_lesson,
    delete_item,
    delete_listening_phase,
    delete_sub_lesson,
    listening_phase_has_items,
    move_item,
    switch_runtime_type,
)
from src.backend.schema_constants import ContentKey, TemplateType
from src.theme import current_palette
from src.teacher.question_cards import QuestionCard


def _pal(key: str) -> str:
    return current_palette().get(key, "#1F232C")


def _item_summary(item: dict[str, Any]) -> str:
    rt = item.get("runtimeType", "?")
    label = INTERACTION_LABELS.get(rt, rt)
    prompt = (
        item.get("prompt")
        or item.get("sentence")
        or item.get("source")
        or item.get("statement")
        or item.get("expected")
        or item.get("expectedAnswer")
        or ""
    )
    return f"[{label}] {prompt}"


_PHASE_LABELS = {
    "wordPairing": "听音选词",
    "dialogue": "对话理解",
    "summary": "摘要回顾",
}


class _Card(QFrame):
    """A themed card with a header row and a body widget."""

    def __init__(self, title: str, subtitle: str = "") -> None:
        super().__init__()
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            f"_Card {{ background-color: {_pal('bg_secondary')}; "
            f"border: 1px solid {_pal('border')}; border-radius: 10px; }}"
        )
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(14, 12, 14, 12)
        self._layout.setSpacing(8)

        header = QHBoxLayout()
        header.setSpacing(8)
        self.title_label = QLabel(title)
        self.title_label.setStyleSheet(
            f"font-weight: 600; color: {_pal('text')};"
        )
        header.addWidget(self.title_label)
        if subtitle:
            sub = QLabel(subtitle)
            sub.setStyleSheet(f"color: {_pal('text_secondary')};")
            header.addWidget(sub)
        header.addStretch()
        self._header_layout = header
        self._layout.addLayout(header)

    def header_layout(self) -> QHBoxLayout:
        return self._header_layout

    def add_body(self, widget: QWidget) -> None:
        self._layout.addWidget(widget)


class ClickableLabel(QLabel):
    """A QLabel that emits a clicked signal on mouse release."""

    clicked = Signal()

    def mouseReleaseEvent(self, event) -> None:
        self.clicked.emit()
        super().mouseReleaseEvent(event)


class BlueprintItemCard(QFrame):
    """A wrapper card for a single item in edit mode that can be expanded or collapsed."""

    def __init__(
        self,
        blueprint: LessonBlueprint,
        stage: dict[str, Any],
        item: dict[str, Any],
        expanded: bool = False,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.blueprint = blueprint
        self.stage = stage
        self.item = item
        self.expanded = expanded

        self.setFrameShape(QFrame.Shape.StyledPanel)
        self._update_style()

        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(6, 6, 6, 6)
        self._layout.setSpacing(6)

        self._build_ui()

    def _update_style(self) -> None:
        border_color = _pal("accent") if self.expanded else _pal("border")
        self.setStyleSheet(
            f"BlueprintItemCard {{ background-color: {_pal('bg_secondary')}; "
            f"border: 1px solid {border_color}; border-radius: 8px; }}"
        )

    def _build_ui(self) -> None:
        while self._layout.count():
            child = self._layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

        header = QHBoxLayout()
        header.setContentsMargins(6, 4, 6, 4)
        header.setSpacing(8)

        self.toggle_btn = QPushButton("▼" if self.expanded else "▶")
        self.toggle_btn.setFlat(True)
        self.toggle_btn.setFixedWidth(24)
        self.toggle_btn.setStyleSheet(
            f"QPushButton {{ color: {_pal('text_secondary')}; font-weight: bold; border: none; background: transparent; }}"
            f"QPushButton:hover {{ color: {_pal('accent')}; }}"
        )
        self.toggle_btn.clicked.connect(self._toggle_expand)
        header.addWidget(self.toggle_btn)

        summary_text = _item_summary(self.item)
        self.summary_label = ClickableLabel(summary_text)
        self.summary_label.setWordWrap(True)
        self.summary_label.setStyleSheet(
            f"color: {_pal('text') if self.expanded else _pal('text_secondary')}; font-size: 13px;"
        )
        self.summary_label.clicked.connect(self._toggle_expand)
        header.addWidget(self.summary_label, 1)

        if not self.expanded:
            items = self.stage.get("items", [])
            idx = next((i for i, it in enumerate(items) if it is self.item), -1)
            if idx < 0:
                idx = next((i for i, it in enumerate(items) if it.get("id") == self.item.get("id")), -1)

            up_btn = QPushButton("↑")
            up_btn.setFixedWidth(28)
            up_btn.setEnabled(idx > 0)
            up_btn.clicked.connect(lambda: self.blueprint._on_move_item(self.stage, self.item, -1))
            header.addWidget(up_btn)

            down_btn = QPushButton("↓")
            down_btn.setFixedWidth(28)
            down_btn.setEnabled(idx >= 0 and idx < len(items) - 1)
            down_btn.clicked.connect(lambda: self.blueprint._on_move_item(self.stage, self.item, 1))
            header.addWidget(down_btn)

            del_btn = QPushButton("删除")
            del_btn.setMinimumWidth(48)
            del_btn.clicked.connect(lambda: self.blueprint._on_delete_item(self.stage, self.item))
            header.addWidget(del_btn)

        self._layout.addLayout(header)

        if self.expanded:
            qcard = QuestionCard(self.blueprint.adapter, self.item)
            qcard.changed.connect(self.blueprint.changed.emit)
            qcard.delete_requested.connect(
                lambda _c=False: self.blueprint._on_delete_item(self.stage, self.item)
            )
            qcard.type_changed.connect(
                lambda nt: self.blueprint._on_change_item_type(self.stage, self.item, nt)
            )
            qcard.move_up_requested.connect(
                lambda _c=False: self.blueprint._on_move_item(self.stage, self.item, -1)
            )
            qcard.move_down_requested.connect(
                lambda _c=False: self.blueprint._on_move_item(self.stage, self.item, 1)
            )
            self._layout.addWidget(qcard)

    def _toggle_expand(self) -> None:
        self.expanded = not self.expanded
        item_id = self.item.get("id")
        if item_id:
            if self.expanded:
                self.blueprint.expanded_item_ids.add(item_id)
            else:
                self.blueprint.expanded_item_ids.discard(item_id)
        self._update_style()
        self._build_ui()


class LessonBlueprint(QWidget):
    """Card-flow lesson overview with optional inline editing."""

    changed = Signal()

    def __init__(
        self,
        adapter: CourseAdapter,
        lesson: dict[str, Any],
        undo_stack: Any = None,
        read_only: bool = False,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.lesson = lesson
        self.undo_stack = undo_stack
        self.read_only = read_only
        self._last_item_type = "multipleChoice"
        self._scroll: QScrollArea | None = None
        self._host: QWidget | None = None
        self.expanded_item_ids: set[str] = set()
        self._known_item_ids: set[str] = set()
        self._first_build = True
        self._build_outer()

    # --- outer shell with rebuild ---------------------------------------

    def _build_outer(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        self._host = QWidget()
        self._host_layout = QVBoxLayout(self._host)
        self._host_layout.setContentsMargins(8, 8, 8, 8)
        self._host_layout.setSpacing(14)
        self._host_layout.addStretch()
        self._scroll.setWidget(self._host)
        outer.addWidget(self._scroll)
        self._rebuild()

    def _collect_all_item_ids(self) -> set[str]:
        ids = set()
        content = self.lesson.get("content", {})
        template = self.lesson.get("template", "legacy")
        if template == TemplateType.LISTENING:
            for phase in content.get(ContentKey.LISTENING_PHASES, []):
                for item in phase.get(ContentKey.ITEMS, []):
                    item_id = item.get("id")
                    if item_id:
                        ids.add(item_id)
        elif template in (TemplateType.READING, TemplateType.MASTERY):
            for stage in content.get(ContentKey.STAGES, []):
                for item in stage.get(ContentKey.ITEMS, []):
                    item_id = item.get("id")
                    if item_id:
                        ids.add(item_id)
        else:
            for sub in content.get(ContentKey.SUB_LESSONS, []):
                for stage in sub.get(ContentKey.STAGES, []):
                    for item in stage.get(ContentKey.ITEMS, []):
                        item_id = item.get("id")
                        if item_id:
                            ids.add(item_id)
        return ids

    def _rebuild(self) -> None:
        current_ids = self._collect_all_item_ids()
        if self._first_build:
            self._first_build = False
            content = self.lesson.setdefault("content", {})
            template = self.lesson.get("template", TemplateType.LEGACY)
            if template == TemplateType.LISTENING:
                for phase in content.setdefault(ContentKey.LISTENING_PHASES, []):
                    items = phase.setdefault(ContentKey.ITEMS, [])
                    if items:
                        item_id = items[0].get("id")
                        if item_id:
                            self.expanded_item_ids.add(item_id)
            elif template in (TemplateType.READING, TemplateType.MASTERY):
                for stage in content.setdefault(ContentKey.STAGES, []):
                    items = stage.setdefault(ContentKey.ITEMS, [])
                    if items:
                        item_id = items[0].get("id")
                        if item_id:
                            self.expanded_item_ids.add(item_id)
            else:
                for sub in content.setdefault(ContentKey.SUB_LESSONS, []):
                    for stage in sub.setdefault(ContentKey.STAGES, []):
                        items = stage.setdefault(ContentKey.ITEMS, [])
                        if items:
                            item_id = items[0].get("id")
                            if item_id:
                                self.expanded_item_ids.add(item_id)
            self._known_item_ids = current_ids
        else:
            new_ids = current_ids - self._known_item_ids
            if new_ids:
                self.expanded_item_ids.update(new_ids)
            self._known_item_ids = current_ids

        # Clear all but the trailing stretch.
        while self._host_layout.count() > 1:
            child = self._host_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()
        template = self.lesson.get("template", "legacy")
        if template == "listening":
            self._build_listening()
        elif template == "reading":
            self._build_reading()
        elif template == "mastery":
            self._build_mastery()
        else:
            self._build_sublessons()

    def refresh_references(self) -> None:
        """Re-render so reference dropdowns inside QuestionCards pick up
        resource changes (mirrors LessonEditor.refresh_references)."""
        self._rebuild()

    # --- listening ------------------------------------------------------

    def _build_listening(self) -> None:
        content = self.lesson.setdefault("content", {})
        phases = content.setdefault("listeningPhases", [])

        row = QHBoxLayout()
        row.setSpacing(6)
        for i, phase in enumerate(phases):
            if i > 0:
                arrow = QLabel("→")
                arrow.setStyleSheet(
                    f"color: {_pal('accent')}; font-size: 20px; font-weight: 700;"
                )
                row.addWidget(arrow)
            row.addWidget(self._build_phase_card(phase, i, len(phases)))
        if not self.read_only:
            add_btn = QPushButton("+ 添加听力阶段")
            add_btn.clicked.connect(self._on_add_phase)
            row.addWidget(add_btn)
        row.addStretch()

        wrap = QWidget()
        wrap.setLayout(row)
        self._host_layout.insertWidget(0, wrap)

        if not phases:
            hint = QLabel("（暂无听力阶段，点击「添加听力阶段」开始）")
            hint.setStyleSheet(f"color: {_pal('text_secondary')};")
            self._host_layout.insertWidget(1, hint)

    def _build_phase_card(self, phase: dict[str, Any], idx: int, total: int) -> _Card:
        ptype = phase.get("type", "wordPairing")
        title = f"阶段 {idx + 1}：{_PHASE_LABELS.get(ptype, ptype)}"
        n = len(phase.get("items", [])) if listening_phase_has_items(ptype) else 0
        card = _Card(title, f"{n} 道题")

        if not self.read_only:
            up = QPushButton("↑")
            up.setFixedWidth(30)
            up.setEnabled(idx > 0)
            up.clicked.connect(lambda _c=False, i=idx: self._on_move_phase(i, -1))
            card.header_layout().addWidget(up)
            down = QPushButton("↓")
            down.setFixedWidth(30)
            down.setEnabled(idx < total - 1)
            down.clicked.connect(lambda _c=False, i=idx: self._on_move_phase(i, 1))
            card.header_layout().addWidget(down)
            dele = QPushButton("删除")
            dele.clicked.connect(lambda _c=False, p=phase: self._on_delete_phase(p))
            card.header_layout().addWidget(dele)

        # audio + transcript summary line
        meta_bits = []
        if phase.get("audioAsset"):
            meta_bits.append("已设音频")
        if phase.get("transcript"):
            meta_bits.append("已设转录文本")
        if meta_bits:
            meta = QLabel(" · ".join(meta_bits))
            meta.setStyleSheet(f"color: {_pal('text_secondary')};")
            card.add_body(meta)

        if listening_phase_has_items(ptype):
            card.add_body(self._build_items_block(phase))
        elif not self.read_only:
            note = QLabel("摘要阶段：仅需音频与转录文本，无需题目。")
            note.setStyleSheet(f"color: {_pal('text_secondary')};")
            card.add_body(note)
        return card

    # --- reading --------------------------------------------------------

    def _build_reading(self) -> None:
        content = self.lesson.setdefault("content", {})
        passage = content.setdefault(
            ContentKey.READING_PASSAGE,
            {
                "title": "",
                "paragraphs": [],
                "difficulty": 1,
                "linkedWordIds": [],
                "linkedExpressionIds": [],
            },
        )
        stages = content.setdefault(ContentKey.STAGES, [])
        if not stages:
            from src.backend.lesson_content import add_stage

            add_stage(content, "Comprehension")
        stage = stages[0]

        passage_card = _Card("阅读篇章", f"难度 {passage.get('difficulty', 1)}")
        if self.read_only:
            title_lbl = QLabel(passage.get("title", "（无标题）"))
            title_lbl.setStyleSheet(f"font-weight: 600; color: {_pal('text')};")
            passage_card.add_body(title_lbl)
            for p in passage.get("paragraphs", []):
                para = QLabel(p)
                para.setWordWrap(True)
                para.setStyleSheet(f"color: {_pal('text_secondary')};")
                passage_card.add_body(para)
        else:
            form = QVBoxLayout()
            form.setSpacing(6)
            title_edit = QLineEdit(passage.get("title", ""))
            title_edit.setPlaceholderText("篇章标题")
            title_edit.textChanged.connect(lambda v: passage.__setitem__("title", v))
            form.addWidget(QLabel("标题"))
            form.addWidget(title_edit)
            diff = QSpinBox()
            diff.setRange(1, 5)
            diff.setValue(int(passage.get("difficulty", 1)))
            diff.valueChanged.connect(lambda v: passage.__setitem__("difficulty", v))
            form.addWidget(QLabel("难度 (1-5)"))
            form.addWidget(diff)
            from PySide6.QtWidgets import QTextEdit

            paras = QTextEdit("\n\n".join(passage.get("paragraphs", [])))
            paras.setMaximumHeight(140)
            paras.setPlaceholderText("段落之间用空行分隔")
            paras.textChanged.connect(
                lambda e=paras, pa=passage: pa.__setitem__(
                    "paragraphs",
                    [s.strip() for s in e.toPlainText().split("\n\n") if s.strip()],
                )
            )
            form.addWidget(QLabel("正文段落（空行分隔）"))
            form.addWidget(paras)
            passage_card.add_body(_wrap(form))
        self._host_layout.insertWidget(0, passage_card)

        qcard = _Card("理解题", f"{len(stage.get(ContentKey.ITEMS, []))} 道题")
        qcard.add_body(self._build_items_block(stage))
        self._host_layout.insertWidget(1, qcard)

    # --- mastery --------------------------------------------------------

    def _build_mastery(self) -> None:
        content = self.lesson.setdefault("content", {})
        stages = content.setdefault(ContentKey.STAGES, [])
        if not stages:
            from src.backend.lesson_content import add_stage

            add_stage(content, "Check")
        stage = stages[0]
        card = _Card("综合测验", f"{len(stage.get(ContentKey.ITEMS, []))} 道题")
        card.add_body(self._build_items_block(stage))
        self._host_layout.insertWidget(0, card)

    # --- intro / practice / review / legacy -----------------------------

    def _build_sublessons(self) -> None:
        content = self.lesson.setdefault("content", {})
        subs = content.get(ContentKey.SUB_LESSONS, [])
        if subs:
            row = QHBoxLayout()
            row.setSpacing(10)
            for sub in subs:
                row.addWidget(self._build_sublesson_card(sub))
            if not self.read_only:
                add_btn = QPushButton("+ 添加教学环节")
                add_btn.clicked.connect(self._on_add_sub_lesson)
                row.addWidget(add_btn)
            row.addStretch()
            wrap = QWidget()
            wrap.setLayout(row)
            self._host_layout.insertWidget(0, wrap)
        elif self.read_only:
            hint = QLabel("（暂无教学环节）")
            hint.setStyleSheet(f"color: {_pal('text_secondary')};")
            self._host_layout.insertWidget(0, hint)
        else:
            add_btn = QPushButton("+ 添加教学环节")
            add_btn.clicked.connect(self._on_add_sub_lesson)
            self._host_layout.insertWidget(0, add_btn)

    def _build_sublesson_card(self, sub: dict[str, Any]) -> _Card:
        stages = sub.get(ContentKey.STAGES, [])
        item_count = sum(len(st.get(ContentKey.ITEMS, [])) for st in stages)
        card = _Card(sub.get("name", "教学环节"), f"{len(stages)} 步 · {item_count} 题")
        if not self.read_only:
            dele = QPushButton("删除环节")
            dele.clicked.connect(lambda _c=False, s=sub: self._on_delete_sub_lesson(s))
            card.header_layout().addWidget(dele)
        for st in stages:
            stage_lbl = QLabel(f"步骤：{st.get('name', st.get('id', ''))}")
            stage_lbl.setStyleSheet(
                f"color: {_pal('text_secondary')}; font-weight: 600;"
            )
            card.add_body(stage_lbl)
            card.add_body(self._build_items_block(st))
        return card

    # --- items block (shared) -------------------------------------------

    def _build_items_block(self, stage: dict[str, Any]) -> QWidget:
        block = QWidget()
        layout = QVBoxLayout(block)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        items = stage.get("items", [])
        if not items:
            empty = QLabel("（无题目）")
            empty.setStyleSheet(f"color: {_pal('text_secondary')};")
            layout.addWidget(empty)
        for item in items:
            if self.read_only:
                layout.addWidget(self._build_item_summary(item))
            else:
                layout.addWidget(self._build_item_card(stage, item))
        if not self.read_only:
            layout.addLayout(self._build_add_item_row(stage))
        return block

    def _build_item_summary(self, item: dict[str, Any]) -> QWidget:
        lbl = QLabel(_item_summary(item))
        lbl.setWordWrap(True)
        lbl.setStyleSheet(
            f"background-color: {_pal('bg')}; border: 1px solid {_pal('border')}; "
            f"border-radius: 6px; padding: 6px 8px; color: {_pal('text')};"
        )
        return lbl

    def _build_item_card(self, stage: dict[str, Any], item: dict[str, Any]) -> BlueprintItemCard:
        is_expanded = item.get("id") in self.expanded_item_ids
        card = BlueprintItemCard(self, stage, item, expanded=is_expanded)
        return card

    def _build_add_item_row(self, stage: dict[str, Any]) -> QHBoxLayout:
        from PySide6.QtWidgets import QComboBox

        row = QHBoxLayout()
        combo = QComboBox()
        for rt, label in INTERACTION_LABELS.items():
            combo.addItem(label, rt)
        combo.setCurrentText(INTERACTION_LABELS.get(self._last_item_type, "选择题"))
        combo.currentIndexChanged.connect(self._on_item_type_combo_changed)
        row.addWidget(combo)
        add_btn = QPushButton("+ 添加题目")
        add_btn.clicked.connect(
            lambda _c=False, st=stage, c=combo: self._on_add_item(st, c)
        )
        row.addWidget(add_btn)
        row.addStretch()
        return row

    # --- command-push helpers -------------------------------------------

    def _push(self, make_cmd, direct_fn) -> None:
        if self.undo_stack is not None:
            cmd = make_cmd()
            cmd.signals.changed.connect(self._rebuild)
            self.undo_stack.push(cmd)
        else:
            direct_fn()
            self._rebuild()
        self.changed.emit()

    def _on_item_type_combo_changed(self, index: int) -> None:
        combo = self.sender()
        if combo is not None and hasattr(combo, "currentData"):
            rt = combo.currentData()
            if rt:
                self._last_item_type = rt

    # --- item handlers --------------------------------------------------

    def _on_add_item(self, stage: dict[str, Any], combo) -> None:
        rt = combo.currentData() or "multipleChoice"
        self._last_item_type = rt

        def make():
            from src.application.commands import AddItemCommand

            return AddItemCommand(stage, rt)

        self._push(make, lambda: add_item(stage, rt))

    def _on_delete_item(self, stage: dict[str, Any], item: dict[str, Any]) -> None:
        def make():
            from src.application.commands import DeleteItemCommand

            return DeleteItemCommand(stage, item)

        self._push(make, lambda: delete_item(stage, item.get("id", "")))

    def _on_move_item(self, stage: dict[str, Any], item: dict[str, Any], delta: int) -> None:
        items = stage.get("items", [])
        idx = next((i for i, it in enumerate(items) if it is item), -1)
        if idx < 0:
            idx = next(
                (i for i, it in enumerate(items) if it.get("id") == item.get("id")), -1
            )
        new_idx = idx + delta
        if not (0 <= new_idx < len(items)):
            return

        def make():
            from src.application.commands import MoveItemCommand

            return MoveItemCommand(stage, idx, new_idx)

        self._push(make, lambda: move_item(stage, idx, new_idx))

    def _on_change_item_type(
        self, stage: dict[str, Any], item: dict[str, Any], new_type: str
    ) -> None:
        new_item = switch_runtime_type(item, new_type)
        item_id = item.get("id", "")

        def make():
            from src.application.commands import ReplaceItemCommand

            return ReplaceItemCommand(stage, item_id, new_item)

        def direct():
            for i, it in enumerate(stage.get("items", [])):
                if it.get("id") == item_id:
                    stage["items"][i] = new_item
                    break

        self._push(make, direct)

    # --- structural handlers --------------------------------------------

    def _on_add_phase(self) -> None:
        def make():
            from src.application.commands import AddListeningPhaseCommand

            return AddListeningPhaseCommand(self.lesson, "dialogue", "新阶段")

        self._push(make, lambda: add_listening_phase(self.lesson, "dialogue", "新阶段"))

    def _on_delete_phase(self, phase: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self,
            "删除听力阶段",
            f"确认删除阶段「{phase.get('name', '')}」？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return

        def make():
            from src.application.commands import DeleteListeningPhaseCommand

            return DeleteListeningPhaseCommand(self.lesson, phase)

        self._push(make, lambda: delete_listening_phase(self.lesson, phase.get("id", "")))

    def _on_move_phase(self, idx: int, delta: int) -> None:
        phases = self.lesson.get("content", {}).get("listeningPhases", [])
        new_idx = idx + delta
        if not (0 <= new_idx < len(phases)):
            return

        def make():
            from src.application.commands import MoveListeningPhaseCommand

            return MoveListeningPhaseCommand(self.lesson, idx, new_idx)

        def direct():
            from src.backend.lesson_content import move_listening_phase

            move_listening_phase(self.lesson, idx, new_idx)

        self._push(make, direct)

    def _on_add_sub_lesson(self) -> None:
        content = self.lesson.setdefault("content", {})

        def make():
            from src.application.commands import AddSubLessonCommand

            return AddSubLessonCommand(content, "新教学环节")

        self._push(make, lambda: add_sub_lesson(content, "新教学环节"))

    def _on_delete_sub_lesson(self, sub: dict[str, Any]) -> None:
        reply = QMessageBox.question(
            self,
            "删除教学环节",
            f"确认删除「{sub.get('name', '')}」及其所有步骤与题目？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return
        content = self.lesson.setdefault("content", {})

        def make():
            from src.application.commands import DeleteSubLessonCommand

            return DeleteSubLessonCommand(content, sub)

        self._push(make, lambda: delete_sub_lesson(content, sub.get("id", "")))


def _wrap(layout) -> QWidget:
    widget = QWidget()
    widget.setLayout(layout)
    return widget
