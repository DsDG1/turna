"""Functional-lesson creation wizard (workshop2 P2).

A 3-step guided flow for building a reading/listening/mastery lesson:
  1. 选择类型 - pick functional template + name + preset (or 空白骨架).
  2. 配置内容 - light high-level config (phase names/audio, passage fields,
     mastery question-type mix). Detailed question editing happens in the
     blueprint after creation.
  3. 预览 - read-only ``LessonBlueprint`` of the assembled lesson.

On accept, ``result_lesson()`` returns the built lesson dict; the caller
pushes an ``AppendLessonCommand`` to insert it and selects the new lesson.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QStackedWidget,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import (
    LISTENING_PHASE_TYPES,
    TEMPLATE_LABELS,
    add_listening_phase,
    default_interaction,
    short_id,
)
from src.backend.lesson_presets import (
    FUNCTIONAL_TEMPLATES,
    PRESET_BY_ID,
    build_preset_lesson,
    presets_for_template,
)
from src.widgets.lesson_blueprint import LessonBlueprint

_PHASE_LABELS = {
    "wordPairing": "听音选词",
    "dialogue": "对话理解",
    "summary": "摘要回顾",
}

_MASTERY_TYPES = [
    ("multipleChoice", "选择题"),
    ("fillBlank", "填空题"),
    ("translateSentence", "翻译题"),
]


def _empty_functional_lesson(template: str, name: str) -> dict[str, Any]:
    """A minimal functional lesson skeleton (空白骨架)."""
    lesson: dict[str, Any] = {
        "id": short_id("l"),
        "name": name or TEMPLATE_LABELS.get(template, template),
        "description": "",
        "type": {"listening": "listening", "reading": "reading", "mastery": "challenge"}.get(
            template, "normal"
        ),
        "template": template,
        "prerequisiteLessonIds": [],
        "content": {},
    }
    if template == "listening":
        lesson["content"] = {"listeningPhases": []}
    elif template == "reading":
        lesson["content"] = {
            "readingPassage": {
                "title": name or "",
                "paragraphs": [],
                "difficulty": 1,
                "linkedWordIds": [],
                "linkedExpressionIds": [],
            },
            "stages": [{"id": short_id("st"), "name": "Comprehension", "items": []}],
        }
    else:  # mastery
        lesson["content"] = {
            "stages": [{"id": short_id("st"), "name": "Check", "items": []}]
        }
    return lesson


class FunctionalLessonWizard(QDialog):
    """Multi-step wizard that assembles a functional lesson dict."""

    def __init__(
        self,
        adapter: CourseAdapter,
        unit_id: str,
        parent: QWidget | None = None,
        initial_template: str | None = None,
        initial_name: str = "",
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("功能课向导")
        self.resize(720, 560)
        self.adapter = adapter
        self.unit_id = unit_id
        self._lesson: dict[str, Any] | None = None
        self._step = 0

        layout = QVBoxLayout(self)
        layout.setSpacing(10)

        self._step_label = QLabel()
        self._step_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._step_label.setStyleSheet("font-weight: 600; padding: 4px;")
        layout.addWidget(self._step_label)

        self._stack = QStackedWidget()
        self._stack.addWidget(self._build_step_type(initial_template, initial_name))
        self._stack.addWidget(self._build_step_config())
        self._stack.addWidget(self._build_step_preview())
        layout.addWidget(self._stack, 1)

        self._nav = self._build_nav()
        layout.addWidget(self._nav)

        self._goto_step(0)

    # --- step 1: choose type + name + preset ----------------------------

    def _build_step_type(self, initial_template: str | None, initial_name: str) -> QWidget:
        page = QWidget()
        form = QFormLayout(page)
        form.setSpacing(10)

        self._name_edit = QLineEdit(initial_name)
        self._name_edit.setPlaceholderText("如：第一课 问候语 听力")
        form.addRow("课时名称：", self._name_edit)

        self._type_group = QButtonGroup(self)
        self._type_buttons: dict[str, QPushButton] = {}
        type_row = QHBoxLayout()
        for ft in FUNCTIONAL_TEMPLATES:
            btn = QPushButton(TEMPLATE_LABELS.get(ft, ft))
            btn.setCheckable(True)
            btn.setMinimumHeight(48)
            self._type_group.addButton(btn)
            self._type_buttons[ft] = btn
            type_row.addWidget(btn)
        type_row.addStretch()
        type_wrap = QWidget()
        type_wrap.setLayout(type_row)
        form.addRow("功能课类型：", type_wrap)

        self._preset_combo = QComboBox()
        self._preset_combo.addItem("空白骨架", "")
        form.addRow("模板预设：", self._preset_combo)
        self._preset_desc = QLabel("")
        self._preset_desc.setWordWrap(True)
        self._preset_desc.setStyleSheet("color: #6B7280;")
        form.addRow("", self._preset_desc)

        initial = initial_template if initial_template in FUNCTIONAL_TEMPLATES else "listening"
        self._type_buttons[initial].setChecked(True)
        self._type_group.buttonClicked.connect(self._refresh_presets)
        self._preset_combo.currentIndexChanged.connect(self._refresh_preset_desc)
        self._refresh_presets()
        return page

    def _current_template(self) -> str:
        for ft, btn in self._type_buttons.items():
            if btn.isChecked():
                return ft
        return "listening"

    def _refresh_presets(self, *_args) -> None:
        template = self._current_template()
        prev = self._preset_combo.currentData()
        self._preset_combo.clear()
        self._preset_combo.addItem("空白骨架", "")
        for preset in presets_for_template(template):
            self._preset_combo.addItem(f"{preset.label}（{preset.description}）", preset.id)
        # restore selection if still valid
        for i in range(self._preset_combo.count()):
            if self._preset_combo.itemData(i) == prev:
                self._preset_combo.setCurrentIndex(i)
                break
        self._refresh_preset_desc()

    def _refresh_preset_desc(self, *_args) -> None:
        pid = self._preset_combo.currentData()
        if pid:
            self._preset_desc.setText(f"将套用预设「{PRESET_BY_ID[pid].label}」并可在下一步调整。")
        else:
            self._preset_desc.setText("将从空白骨架开始，下一步填入基本结构。")

    # --- step 2: light config -------------------------------------------

    def _build_step_config(self) -> QWidget:
        self._config_host = QWidget()
        self._config_layout = QVBoxLayout(self._config_host)
        self._config_layout.setContentsMargins(0, 0, 0, 0)
        return self._config_host

    def _render_config(self) -> None:
        # Clear.
        while self._config_layout.count():
            child = self._config_layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        template = self._lesson.get("template", "listening")
        if template == "listening":
            self._config_layout.addWidget(self._build_listening_config())
        elif template == "reading":
            self._config_layout.addWidget(self._build_reading_config())
        else:
            self._config_layout.addWidget(self._build_mastery_config())
        self._config_layout.addStretch()

    def _build_listening_config(self) -> QWidget:
        wrap = QWidget()
        v = QVBoxLayout(wrap)
        v.setSpacing(8)
        hint = QLabel("为每个听力阶段命名并设置音频/转录文本；题目可在创建后的蓝图中编辑。")
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #6B7280;")
        v.addWidget(hint)

        phases = self._lesson["content"].get("listeningPhases", [])
        for i, phase in enumerate(phases):
            v.addWidget(self._build_phase_row(i, phase))

        add_row = QHBoxLayout()
        self._phase_type_combo = QComboBox()
        for pt in LISTENING_PHASE_TYPES:
            self._phase_type_combo.addItem(f"{_PHASE_LABELS.get(pt, pt)} ({pt})", pt)
        add_row.addWidget(self._phase_type_combo)
        add_btn = QPushButton("+ 添加阶段")
        add_btn.clicked.connect(self._on_wizard_add_phase)
        add_row.addWidget(add_btn)
        add_row.addStretch()
        v.addLayout(add_row)
        return wrap

    def _build_phase_row(self, idx: int, phase: dict[str, Any]) -> QGroupBox:
        ptype = phase.get("type", "wordPairing")
        box = QGroupBox(f"阶段 {idx + 1}：{_PHASE_LABELS.get(ptype, ptype)}")
        form = QFormLayout(box)
        name_edit = QLineEdit(phase.get("name", ""))
        name_edit.textChanged.connect(lambda v: phase.__setitem__("name", v))
        form.addRow("名称：", name_edit)
        audio_edit = QLineEdit(phase.get("audioAsset", ""))
        audio_edit.setPlaceholderText("音频资源路径（可留空）")
        audio_edit.textChanged.connect(
            lambda v: phase.__setitem__("audioAsset", v)
            if ("audioAsset" in phase or v)
            else None
        )
        form.addRow("音频：", audio_edit)
        # Ensure audioAsset/transcript keys exist for dialogue/summary editing.
        if "audioAsset" not in phase:
            phase["audioAsset"] = ""
        if "transcript" not in phase:
            phase["transcript"] = ""
        transcript_edit = QTextEdit(phase.get("transcript", ""))
        transcript_edit.setMaximumHeight(70)
        transcript_edit.setPlaceholderText("转录文本（可留空）")
        transcript_edit.textChanged.connect(
            lambda e=transcript_edit, p=phase: p.__setitem__("transcript", e.toPlainText())
        )
        form.addRow("转录：", transcript_edit)
        del_btn = QPushButton("删除该阶段")
        del_btn.clicked.connect(lambda _c=False, p=phase: self._on_wizard_delete_phase(p))
        form.addRow("", del_btn)
        return box

    def _on_wizard_add_phase(self) -> None:
        pt = self._phase_type_combo.currentData() if hasattr(self, "_phase_type_combo") else "dialogue"
        add_listening_phase(self._lesson, pt, f"新{_PHASE_LABELS.get(pt, pt)}")
        self._render_config()

    def _on_wizard_delete_phase(self, phase: dict[str, Any]) -> None:
        from src.backend.lesson_content import delete_listening_phase

        delete_listening_phase(self._lesson, phase.get("id", ""))
        self._render_config()

    def _build_reading_config(self) -> QWidget:
        wrap = QWidget()
        form = QFormLayout(wrap)
        passage = self._lesson["content"].setdefault(
            "readingPassage",
            {"title": "", "paragraphs": [], "difficulty": 1, "linkedWordIds": [], "linkedExpressionIds": []},
        )
        title_edit = QLineEdit(passage.get("title", ""))
        title_edit.textChanged.connect(lambda v: passage.__setitem__("title", v))
        form.addRow("篇章标题：", title_edit)
        diff = QSpinBox()
        diff.setRange(1, 5)
        diff.setValue(int(passage.get("difficulty", 1)))
        diff.valueChanged.connect(lambda v: passage.__setitem__("difficulty", v))
        form.addRow("难度（1-5）：", diff)
        paras = QTextEdit("\n\n".join(passage.get("paragraphs", [])))
        paras.setMaximumHeight(160)
        paras.setPlaceholderText("段落之间用空行分隔")
        paras.textChanged.connect(
            lambda e=paras, pa=passage: pa.__setitem__(
                "paragraphs",
                [s.strip() for s in e.toPlainText().split("\n\n") if s.strip()],
            )
        )
        form.addRow("正文段落：", paras)
        hint = QLabel("理解题（选择/判断/简答）可在创建后的蓝图中编辑。")
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #6B7280;")
        form.addRow("", hint)
        return wrap

    def _build_mastery_config(self) -> QWidget:
        wrap = QWidget()
        v = QVBoxLayout(wrap)
        v.addWidget(QLabel("选择综合测验包含的题型（将生成对应占位题，可在蓝图中编辑）："))
        stage = self._lesson["content"]["stages"][0]
        existing = {it.get("runtimeType") for it in stage.get("items", [])}
        self._mastery_checks: dict[str, QCheckBox] = {}
        for rt, label in _MASTERY_TYPES:
            cb = QCheckBox(label)
            cb.setChecked(rt in existing)
            cb.stateChanged.connect(lambda _s, r=rt: self._on_mastery_type_toggled(r))
            self._mastery_checks[rt] = cb
            v.addWidget(cb)
        v.addStretch()
        return wrap

    def _on_mastery_type_toggled(self, rt: str) -> None:
        stage = self._lesson["content"]["stages"][0]
        items = stage.setdefault("items", [])
        checked = self._mastery_checks[rt].isChecked()
        has = any(it.get("runtimeType") == rt for it in items)
        if checked and not has:
            item = default_interaction(rt)
            item["id"] = short_id(rt[:2])
            items.append(item)
        elif not checked and has:
            stage["items"] = [it for it in items if it.get("runtimeType") != rt]

    # --- step 3: read-only preview --------------------------------------

    def _build_step_preview(self) -> QWidget:
        self._preview_host = QWidget()
        self._preview_layout = QVBoxLayout(self._preview_host)
        self._preview_layout.setContentsMargins(0, 0, 0, 0)
        return self._preview_host

    def _render_preview(self) -> None:
        while self._preview_layout.count():
            child = self._preview_layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        bp = LessonBlueprint(self.adapter, self._lesson, read_only=True)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(bp)
        self._preview_layout.addWidget(scroll)

    # --- navigation -----------------------------------------------------

    def _build_nav(self) -> QWidget:
        self._back_btn = QPushButton("上一步")
        self._back_btn.clicked.connect(self._back)
        self._next_btn = QPushButton("下一步")
        self._next_btn.clicked.connect(self._next)
        self._finish_btn = QPushButton("完成")
        self._finish_btn.clicked.connect(self.accept)
        cancel_btn = QPushButton("取消")
        cancel_btn.clicked.connect(self.reject)
        row = QHBoxLayout()
        row.addWidget(self._back_btn)
        row.addStretch()
        row.addWidget(cancel_btn)
        row.addWidget(self._next_btn)
        row.addWidget(self._finish_btn)
        wrap = QWidget()
        wrap.setLayout(row)
        return wrap

    def _goto_step(self, step: int) -> None:
        # Leaving step 0: rebuild the working lesson if the type/preset/name
        # signature changed since the last build (so preset swaps are picked up,
        # but untouched config edits survive a back-and-forward).
        if self._step == 0 and step > 0:
            sig = (
                self._current_template(),
                self._preset_combo.currentData(),
                self._name_edit.text().strip(),
            )
            if self._lesson is None or getattr(self, "_built_sig", None) != sig:
                self._build_working_lesson()
                self._built_sig = sig
        self._step = step
        self._stack.setCurrentIndex(step)
        titles = ["1. 选择类型", "2. 配置内容", "3. 预览"]
        self._step_label.setText("  ›  ".join(titles[: step + 1]))
        self._back_btn.setEnabled(step > 0)
        self._next_btn.setVisible(step < 2)
        self._finish_btn.setVisible(step == 2)
        if step == 1:
            self._render_config()
        elif step == 2:
            self._render_preview()

    def _build_working_lesson(self) -> None:
        template = self._current_template()
        name = self._name_edit.text().strip()
        pid = self._preset_combo.currentData()
        if pid:
            self._lesson = build_preset_lesson(pid, name)
            # Ensure the template matches the chosen type (preset may differ).
            if self._lesson.get("template") != template:
                self._lesson["template"] = template
                self._lesson["type"] = {
                    "listening": "listening", "reading": "reading", "mastery": "challenge"
                }.get(template, "normal")
        else:
            self._lesson = _empty_functional_lesson(template, name)

    def _back(self) -> None:
        if self._step > 0:
            self._goto_step(self._step - 1)

    def _next(self) -> None:
        if self._step < 2:
            self._goto_step(self._step + 1)

    # --- result ---------------------------------------------------------

    def result_lesson(self) -> dict[str, Any] | None:
        return self._lesson
