"""Lesson content editor: dispatches by template to the right content form.

Covers §6.2 template↔content shapes:
- intro / practice / review / legacy  -> SubLessonTreeEditor
- listening                            -> ListeningPhasesEditor
- reading                              -> ReadingEditor
- mastery                              -> MasteryEditor (single stage only)
"""
from __future__ import annotations

from typing import Any

from PySide6.QtWidgets import (
    QComboBox,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QSplitter,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    INTERACTION_LABELS,
    LISTENING_PHASE_TYPES,
    TEMPLATE_LABELS,
    add_item,
    add_listening_phase,
    add_stage,
    add_sub_lesson,
    allowed_content_keys,
    switch_template,
)
from src.backend.schema_constants import ContentKey, ItemKey
from src.theme import current_palette
from src.widgets.interaction_forms import InteractionForm


class ItemListPanel(QWidget):
    """Right pane: list items in a stage and edit the selected one."""

    def __init__(self, adapter: CourseAdapter) -> None:
        super().__init__()
        self.adapter = adapter
        self.stage: dict[str, Any] | None = None
        layout = QVBoxLayout(self)
        self.list_widget = QListWidget()
        self.list_widget.currentRowChanged.connect(self._on_select)
        layout.addWidget(self.list_widget)

        row = QHBoxLayout()
        self.add_combo = QComboBox()
        for rt, label in INTERACTION_LABELS.items():
            self.add_combo.addItem(label, rt)
        self.add_btn = QPushButton("+ 添加题目")
        self.del_btn = QPushButton("- 删除")
        row.addWidget(self.add_combo)
        row.addWidget(self.add_btn)
        row.addWidget(self.del_btn)
        layout.addLayout(row)

        self.form_host = QWidget()
        self.form_layout = QVBoxLayout(self.form_host)
        self.form_layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.form_host, 1)

        self.add_btn.clicked.connect(self._on_add)
        self.del_btn.clicked.connect(self._on_del)

    def show_stage(self, stage: dict[str, Any]) -> None:
        self.stage = stage
        self._refresh()
        if stage.get(ContentKey.ITEMS):
            self.list_widget.setCurrentRow(0)
        else:
            self._clear_form()

    def _refresh(self) -> None:
        self.list_widget.clear()
        if not self.stage:
            return
        for item in self.stage.get(ContentKey.ITEMS, []):
            rt = item.get(ItemKey.RUNTIME_TYPE, "?")
            label = INTERACTION_LABELS.get(rt, rt)
            prompt = (
                item.get("prompt")
                or item.get("sentence")
                or item.get("source")
                or item.get("statement")
                or item.get("front")
                or item.get("frontHtml")
                or ""
            )
            self.list_widget.addItem(f"[{label}] {prompt}")

    def _on_select(self, row: int) -> None:
        if not self.stage or row < 0:
            self._clear_form()
            return
        items = self.stage.get("items", [])
        if row >= len(items):
            self._clear_form()
            return
        self._clear_form()
        form = InteractionForm(self.adapter, items[row])
        self.form_layout.addWidget(form)

    def _clear_form(self) -> None:
        while self.form_layout.count():
            child = self.form_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()

    def _on_add(self) -> None:
        if not self.stage:
            return
        rt = self.add_combo.currentData()
        item = add_item(self.stage, rt)
        self._refresh()
        self.list_widget.setCurrentRow(len(self.stage["items"]) - 1)

    def _on_del(self) -> None:
        if not self.stage:
            return
        row = self.list_widget.currentRow()
        items = self.stage.get("items", [])
        if 0 <= row < len(items):
            del items[row]
            self._refresh()
            self._clear_form()


class SubLessonTreeEditor(QWidget):
    """intro / practice / review / legacy: subLesson -> stage -> item tree."""

    def __init__(self, adapter: CourseAdapter, lesson: dict[str, Any]) -> None:
        super().__init__()
        self.adapter = adapter
        self.lesson = lesson
        content = lesson.setdefault("content", {})
        allowed = allowed_content_keys(lesson.get("template", "legacy"))
        if ContentKey.SUB_LESSONS in allowed:
            content.setdefault(ContentKey.SUB_LESSONS, [])
        if ContentKey.STAGES in allowed:
            content.setdefault(ContentKey.STAGES, [])

        layout = QVBoxLayout(self)
        splitter = QSplitter()

        self.sub_list = QListWidget()
        self.stage_list = QListWidget()
        self.item_panel = ItemListPanel(adapter)
        splitter.addWidget(self._labeled("教学环节", self.sub_list, self._add_sub))
        splitter.addWidget(self._labeled("教学步骤", self.stage_list, self._add_stage))
        splitter.addWidget(self.item_panel)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 1)
        splitter.setStretchFactor(2, 2)
        layout.addWidget(splitter)

        self.sub_list.currentRowChanged.connect(self._on_sub_select)
        self.stage_list.currentRowChanged.connect(self._on_stage_select)
        self._refresh_subs()
        if content[ContentKey.SUB_LESSONS]:
            self.sub_list.setCurrentRow(0)
        elif content[ContentKey.STAGES]:
            self._show_flat_stages()

    def _labeled(self, title: str, inner: QWidget, on_add: Any) -> QWidget:
        wrap = QWidget()
        v = QVBoxLayout(wrap)
        v.setContentsMargins(0, 0, 0, 0)
        v.addWidget(QLabel(title))
        v.addWidget(inner)
        btn = QPushButton(f"+ {title}")
        btn.clicked.connect(on_add)
        v.addWidget(btn)
        return wrap

    def _refresh_subs(self) -> None:
        self.sub_list.clear()
        for sub in self.lesson["content"].get(ContentKey.SUB_LESSONS, []):
            self.sub_list.addItem(sub.get("name", sub.get("id", "")))

    def _on_sub_select(self, row: int) -> None:
        subs = self.lesson["content"].get(ContentKey.SUB_LESSONS, [])
        if row < 0 or row >= len(subs):
            return
        self._current_sub = subs[row]
        self._refresh_stages(self._current_sub)

    def _refresh_stages(self, sub: dict[str, Any]) -> None:
        self.stage_list.clear()
        for st in sub.get(ContentKey.STAGES, []):
            self.stage_list.addItem(st.get("name", st.get("id", "")))
        if sub.get(ContentKey.STAGES):
            self.stage_list.setCurrentRow(0)

    def _on_stage_select(self, row: int) -> None:
        subs = self.lesson["content"].get(ContentKey.SUB_LESSONS, [])
        stages = self._current_sub.get(ContentKey.STAGES, []) if hasattr(self, "_current_sub") else []
        if row < 0 or row >= len(stages):
            return
        self.item_panel.show_stage(stages[row])

    def _show_flat_stages(self) -> None:
        stages = self.lesson["content"].get(ContentKey.STAGES, [])
        self._current_sub = {ContentKey.STAGES: stages}
        self._refresh_stages(self._current_sub)

    def _add_sub(self) -> None:
        sub = add_sub_lesson(self.lesson["content"])
        self._refresh_subs()
        self.sub_list.setCurrentRow(len(self.lesson["content"][ContentKey.SUB_LESSONS]) - 1)

    def _add_stage(self) -> None:
        if not hasattr(self, "_current_sub") or not self._current_sub:
            return
        stage = add_stage(self._current_sub)
        self._refresh_stages(self._current_sub)
        self.stage_list.setCurrentRow(len(self._current_sub[ContentKey.STAGES]) - 1)


class MasteryEditor(QWidget):
    """mastery: single stage editor; blocks adding a second stage."""

    def __init__(self, adapter: CourseAdapter, lesson: dict[str, Any]) -> None:
        super().__init__()
        self.adapter = adapter
        self.lesson = lesson
        content = lesson.setdefault("content", {})
        stages = content.setdefault(ContentKey.STAGES, [])
        if not stages:
            add_stage(content, "Check")

        layout = QVBoxLayout(self)
        info = QLabel("综合测验只能有一个教学步骤")
        info.setStyleSheet(f"color: {current_palette()['accent_pressed']};")
        layout.addWidget(info)
        self.item_panel = ItemListPanel(adapter)
        layout.addWidget(self.item_panel, 1)
        self.item_panel.show_stage(stages[0])


class ListeningPhasesEditor(QWidget):
    """listening: three-phase editor (wordPairing / dialogue / summary)."""

    def __init__(self, adapter: CourseAdapter, lesson: dict[str, Any]) -> None:
        super().__init__()
        self.adapter = adapter
        self.lesson = lesson
        content = lesson.setdefault("content", {})
        content.setdefault(ContentKey.LISTENING_PHASES, [])

        layout = QVBoxLayout(self)
        splitter = QSplitter()

        left = QWidget()
        lv = QVBoxLayout(left)
        lv.setContentsMargins(0, 0, 0, 0)
        lv.addWidget(QLabel("听力阶段"))
        self.phase_list = QListWidget()
        lv.addWidget(self.phase_list)
        row = QHBoxLayout()
        self.phase_type_combo = QComboBox()
        for pt in LISTENING_PHASE_TYPES:
            self.phase_type_combo.addItem(pt, pt)
        row.addWidget(self.phase_type_combo)
        self.add_phase_btn = QPushButton("+ 添加阶段")
        self.del_phase_btn = QPushButton("- 删除")
        row.addWidget(self.add_phase_btn)
        row.addWidget(self.del_phase_btn)
        lv.addLayout(row)
        splitter.addWidget(left)

        self.item_panel = ItemListPanel(adapter)
        self.meta_host = QWidget()
        self.meta_layout = QFormLayout(self.meta_host)
        self.meta_layout.setContentsMargins(0, 0, 0, 0)
        right = QWidget()
        rv = QVBoxLayout(right)
        rv.setContentsMargins(0, 0, 0, 0)
        rv.addWidget(self.meta_host)
        rv.addWidget(self.item_panel, 1)
        splitter.addWidget(right)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 2)
        layout.addWidget(splitter)

        self.phase_list.currentRowChanged.connect(self._on_phase_select)
        self.add_phase_btn.clicked.connect(self._on_add_phase)
        self.del_phase_btn.clicked.connect(self._on_del_phase)
        self._refresh()
        if content[ContentKey.LISTENING_PHASES]:
            self.phase_list.setCurrentRow(0)

    def _refresh(self) -> None:
        self.phase_list.clear()
        for ph in self.lesson["content"][ContentKey.LISTENING_PHASES]:
            self.phase_list.addItem(f"{ph.get('type', '?')} — {ph.get('name', '')}")

    def _on_phase_select(self, row: int) -> None:
        phases = self.lesson["content"][ContentKey.LISTENING_PHASES]
        if row < 0 or row >= len(phases):
            return
        self._current_phase_index = row
        phase = phases[row]
        self._clear_meta()
        if "audioAsset" in phase:
            self.audio_edit = QLineEdit(phase.get("audioAsset", ""))
            self.audio_edit.textChanged.connect(self._on_audio_changed)
            self.meta_layout.addRow("audioAsset:", self.audio_edit)
        if "transcript" in phase:
            self.transcript_edit = QTextEdit(phase.get("transcript", ""))
            self.transcript_edit.setMaximumHeight(80)
            self.transcript_edit.textChanged.connect(self._on_transcript_changed)
            self.meta_layout.addRow("transcript:", self.transcript_edit)

    def _current_phase(self) -> dict[str, Any] | None:
        phases = self.lesson.get("content", {}).get(ContentKey.LISTENING_PHASES, [])
        idx = getattr(self, "_current_phase_index", -1)
        if 0 <= idx < len(phases):
            return phases[idx]
        return None

    def _on_audio_changed(self, text: str) -> None:
        phase = self._current_phase()
        if phase is not None:
            phase["audioAsset"] = text

    def _on_transcript_changed(self) -> None:
        phase = self._current_phase()
        if phase is not None and hasattr(self, "transcript_edit"):
            phase["transcript"] = self.transcript_edit.toPlainText()
        if ContentKey.ITEMS in phase:
            self.item_panel.show_stage(phase)
        else:
            self.item_panel.show_stage({"items": []})
            if phase.get("type") == "summary":
                self.meta_layout.addRow(
                    QLabel("摘要阶段无需题目，仅需 audioAsset / transcript。")
                )

    def _clear_meta(self) -> None:
        while self.meta_layout.rowCount():
            self.meta_layout.removeRow(0)

    def _on_add_phase(self) -> None:
        pt = self.phase_type_combo.currentData()
        phase = add_listening_phase(self.lesson, pt, f"New {pt}")
        self._refresh()
        self.phase_list.setCurrentRow(len(self.lesson["content"]["listeningPhases"]) - 1)

    def _on_del_phase(self) -> None:
        row = self.phase_list.currentRow()
        phases = self.lesson["content"]["listeningPhases"]
        if 0 <= row < len(phases):
            del phases[row]
            self._refresh()
            self._clear_meta()
            self.item_panel.show_stage({"items": []})


class ReadingEditor(QWidget):
    """reading: readingPassage editor + single comprehension stage items."""

    def __init__(self, adapter: CourseAdapter, lesson: dict[str, Any]) -> None:
        super().__init__()
        self.adapter = adapter
        self.lesson = lesson
        content = lesson.setdefault("content", {})
        passage = content.setdefault(ContentKey.READING_PASSAGE, {
            "title": "",
            "paragraphs": [],
            "difficulty": 1,
            "linkedWordIds": [],
            "linkedExpressionIds": [],
        })
        self.passage = passage
        stages = content.setdefault(ContentKey.STAGES, [])
        if not stages:
            add_stage(content, "Comprehension")

        layout = QVBoxLayout(self)
        passage_box = QGroupBox("阅读篇章")
        pform = QFormLayout()
        self.title_edit = QLineEdit(passage.get("title", ""))
        self.title_edit.textChanged.connect(self._on_title_changed)
        pform.addRow("title:", self.title_edit)
        self.diff_spin = QSpinBox()
        self.diff_spin.setRange(1, 5)
        self.diff_spin.setValue(int(passage.get("difficulty", 1)))
        self.diff_spin.valueChanged.connect(self._on_diff_changed)
        pform.addRow("difficulty:", self.diff_spin)
        self.paras_edit = QTextEdit("\n\n".join(passage.get("paragraphs", [])))
        self.paras_edit.setMaximumHeight(120)
        self.paras_edit.textChanged.connect(self._on_paras_changed)
        pform.addRow("paragraphs (空行分隔):", self.paras_edit)
        passage_box.setLayout(pform)
        layout.addWidget(passage_box)

        self.item_panel = ItemListPanel(adapter)
        layout.addWidget(self.item_panel, 1)
        self.item_panel.show_stage(stages[0])

    def _on_title_changed(self, text: str) -> None:
        self.passage["title"] = text

    def _on_diff_changed(self, val: int) -> None:
        self.passage["difficulty"] = val

    def _on_paras_changed(self) -> None:
        self.passage["paragraphs"] = [
            s.strip() for s in self.paras_edit.toPlainText().split("\n\n") if s.strip()
        ]


class LessonEditor(QWidget):
    """Container that picks the right editor by lesson template."""

    TEMPLATES = ("intro", "practice", "review", "listening", "reading", "mastery", "legacy")

    def __init__(self, adapter: CourseAdapter, lesson: dict[str, Any]) -> None:
        super().__init__()
        self.adapter = adapter
        self.lesson = lesson
        layout = QVBoxLayout(self)

        top = QHBoxLayout()
        top.addWidget(QLabel("课型:"))
        self.template_combo = QComboBox()
        for t in self.TEMPLATES:
            self.template_combo.addItem(f"{TEMPLATE_LABELS.get(t, t)} ({t})", t)
        cur = lesson.get("template", "legacy")
        idx = max(0, self.TEMPLATES.index(cur) if cur in self.TEMPLATES else 0)
        self.template_combo.setCurrentIndex(idx)
        self.template_combo.currentIndexChanged.connect(self._on_template_change)
        top.addWidget(self.template_combo)
        top.addStretch()
        layout.addLayout(top)

        self.body_host = QWidget()
        self.body_layout = QVBoxLayout(self.body_host)
        self.body_layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.body_host, 1)
        self._render_body()

    def _render_body(self) -> None:
        while self.body_layout.count():
            child = self.body_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()
        template = self.lesson.get("template", "legacy")
        if template in ("intro", "practice", "review", "legacy"):
            editor: QWidget = SubLessonTreeEditor(self.adapter, self.lesson)
        elif template == "listening":
            editor = ListeningPhasesEditor(self.adapter, self.lesson)
        elif template == "reading":
            editor = ReadingEditor(self.adapter, self.lesson)
        elif template == "mastery":
            editor = MasteryEditor(self.adapter, self.lesson)
        else:
            editor = SubLessonTreeEditor(self.adapter, self.lesson)
        self.body_layout.addWidget(editor)

    def _on_template_change(self, _idx: int) -> None:
        new_template = self.template_combo.currentData()
        if new_template == self.lesson.get("template"):
            return
        if self.lesson.get("content"):
            reply = QMessageBox.question(
                self,
                "切换课型",
                f"切换到「{TEMPLATE_LABELS.get(new_template, new_template)}」会清空不适用的内容，确认？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            )
            if reply != QMessageBox.StandardButton.Yes:
                self.template_combo.blockSignals(True)
                cur = self.lesson.get("template", "legacy")
                self.template_combo.setCurrentIndex(
                    max(0, self.TEMPLATES.index(cur) if cur in self.TEMPLATES else 0)
                )
                self.template_combo.blockSignals(False)
                return
        switch_template(self.lesson, new_template)
        self._render_body()

    def refresh_references(self) -> None:
        """Re-render the body so reference dropdowns pick up resource changes."""
        self._render_body()