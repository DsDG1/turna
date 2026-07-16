"""Live lesson preview / "try it yourself" window (guiplan §15.7, T.6).

A lightweight read-only renderer that walks the current in-memory lesson and
lets the teacher actually answer each question, getting immediate correct /
wrong feedback. This closes the "did I author this correctly?" loop without
requiring the full Flutter app: zero-code teachers can self-verify by doing
the lesson themselves.

The preview reads the adapter + lesson at render time, so to refresh after an
edit the caller closes and reopens the dialog (or calls ``refresh()``).
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QButtonGroup,
    QCheckBox,
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QRadioButton,
    QVBoxLayout,
    QWidget,
)

from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import listening_phase_has_items


class _PreviewCard(QFrame):
    """A single try-it-yourself question card bound to one item."""

    def __init__(
        self,
        adapter: CourseAdapter,
        item: dict[str, Any],
        vocab_override: dict[str, dict[str, Any]] | None = None,
    ) -> None:
        super().__init__()
        self.adapter = adapter
        self.item = item
        self._vocab_override = vocab_override or {}
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "_PreviewCard { background-color: #232833; border: 1px solid #2C313C; border-radius: 8px; }"
        )
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)
        self._build(layout)

    def _term_for(self, ref_id: str) -> str:
        # Prefer a vocab override (used by the AI dialog's 试做 so generated
        # words resolve even before they're imported into the adapter).
        w = self._vocab_override.get(ref_id)
        if w is None:
            for cand in self.adapter.vocab:
                if cand.get("id") == ref_id:
                    w = cand
                    break
        if w is None:
            return ref_id
        return f"{w.get('term', ref_id)} — {w.get('translation', '')}"

    def _build(self, layout: QVBoxLayout) -> None:
        rt = self.item.get("runtimeType", "")
        prompt = (
            self.item.get("prompt")
            or self.item.get("sentence")
            or self.item.get("source")
            or self.item.get("statement")
            or ""
        )
        title = QLabel(f"题目（{rt}）")
        title.setStyleSheet("font-weight: 700; color: #E8EAF0;")
        layout.addWidget(title)

        if rt == "showWord":
            layout.addWidget(QLabel(self._term_for(self.item.get("wordId", ""))))
            if self.item.get("context"):
                layout.addWidget(QLabel(str(self.item["context"])))
            layout.addWidget(QLabel("（展示题，无需作答）"))
            return

        if rt in ("multipleChoice", "readingMcq", "listenAndPick"):
            self._build_single_choice(layout, prompt)
        elif rt == "multiSelect":
            self._build_multi_select(layout, prompt)
        elif rt in ("fillBlank",):
            self._build_fill_blank(layout, prompt)
        elif rt in ("translateSentence", "readingShortAnswer"):
            self._build_text_answer(layout, prompt)
        elif rt == "readingTrueFalse":
            self._build_true_false(layout, prompt)
        elif rt in ("typeTheWord", "listenOnly"):
            self._build_text_answer(layout, prompt)
        elif rt == "reorderSentence":
            self._build_display(layout, prompt)
        else:
            self._build_display(layout, prompt or str(self.item))

    def _build_single_choice(self, layout: QVBoxLayout, prompt: str) -> None:
        layout.addWidget(QLabel(prompt or "选择正确答案："))
        options = self.item.get("options", []) or []
        correct = int(self.item.get("correctIndex", 0) or 0)
        group = QButtonGroup(self)
        group.setExclusive(True)

        def _check() -> None:
            for i in range(len(options)):
                btn = group.button(i)
                if btn is not None and btn.isChecked():
                    ok = i == correct
                    QMessageBox.information(
                        self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案是第 {correct + 1} 项"
                    )
                    return

        for opt in options:
            rb = QRadioButton(str(opt))
            group.addButton(rb)
            layout.addWidget(rb)
        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)

    def _build_multi_select(self, layout: QVBoxLayout, prompt: str) -> None:
        layout.addWidget(QLabel(prompt or "选择所有正确答案："))
        options = self.item.get("options", []) or []
        correct = set(self.item.get("correctIndices", []) or [])
        boxes: list[QCheckBox] = []

        def _check() -> None:
            chosen = {i for i, cb in enumerate(boxes) if cb.isChecked()}
            ok = chosen == correct
            QMessageBox.information(
                self, "结果",
                "✅ 答对了！" if ok else f"❌ 正确答案是第 {[c+1 for c in sorted(correct)]} 项",
            )

        for opt in options:
            cb = QCheckBox(str(opt))
            boxes.append(cb)
            layout.addWidget(cb)
        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)

    def _build_fill_blank(self, layout: QVBoxLayout, prompt: str) -> None:
        layout.addWidget(QLabel(prompt))
        edit = QLineEdit()
        edit.setPlaceholderText("填入答案…")
        layout.addWidget(edit)
        answer = str(self.item.get("answer", ""))

        def _check() -> None:
            ok = edit.text().strip().lower() == answer.strip().lower()
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案：{answer}"
            )

        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)

    def _build_text_answer(self, layout: QVBoxLayout, prompt: str) -> None:
        layout.addWidget(QLabel(prompt))
        edit = QLineEdit()
        edit.setPlaceholderText("输入答案…")
        layout.addWidget(edit)
        answer = str(
            self.item.get("expected") or self.item.get("expectedAnswer") or ""
        )

        def _check() -> None:
            ok = edit.text().strip().lower() == answer.strip().lower()
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 参考答案：{answer}"
            )

        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)

    def _build_true_false(self, layout: QVBoxLayout, prompt: str) -> None:
        layout.addWidget(QLabel(prompt))
        true_btn = QRadioButton("正确")
        false_btn = QRadioButton("错误")
        group = QButtonGroup(self)
        group.addButton(true_btn)
        group.addButton(false_btn)
        row_widget = QWidget()
        rl = QHBoxLayout(row_widget)
        rl.addWidget(true_btn)
        rl.addWidget(false_btn)
        layout.addWidget(row_widget)
        answer = bool(self.item.get("answer", True))

        def _check() -> None:
            chosen = true_btn.isChecked()
            ok = chosen == answer
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案：{'正确' if answer else '错误'}"
            )

        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)

    def _build_display(self, layout: QVBoxLayout, text: str) -> None:
        layout.addWidget(QLabel("（此题型在预览中仅展示，不可作答）"))
        if text:
            layout.addWidget(QLabel(text))


class LessonPreviewDialog(QDialog):
    """Dialog showing all items of a lesson as try-it-yourself cards."""

    def __init__(
        self,
        adapter: CourseAdapter,
        lesson: dict[str, Any],
        parent: QWidget | None = None,
        vocab_override: dict[str, dict[str, Any]] | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.lesson = lesson
        self._vocab_override = vocab_override or {}
        self.setWindowTitle(f"预览：{lesson.get('name', lesson.get('id', ''))}")
        self.resize(560, 640)
        self._build()

    def _iter_items(self):
        content = self.lesson.get("content", {}) or {}
        for sl in content.get("subLessons", []) or []:
            for stage in sl.get("stages", []) or []:
                for item in stage.get("items", []) or []:
                    yield sl.get("name", ""), stage.get("name", ""), item
        for stage in content.get("stages", []) or []:
            for item in stage.get("items", []) or []:
                yield "", stage.get("name", ""), item
        for phase in content.get("listeningPhases", []) or []:
            if listening_phase_has_items(phase.get("type", "")):
                for item in phase.get("items", []) or []:
                    yield "", phase.get("name", ""), item

    def _build(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)

        title = QLabel(f"预览：{self.lesson.get('name', '')}")
        title.setStyleSheet("font-size: 18px; font-weight: 700; color: #FFFFFF;")
        layout.addWidget(title)
        hint = QLabel("实际做题验证你的题目设置。改题后重新打开此窗口即刷新。")
        hint.setStyleSheet("color: #9CA3AF; font-size: 11px;")
        layout.addWidget(hint)

        count = 0
        for sl_name, st_name, item in self._iter_items():
            label_parts = []
            if sl_name:
                label_parts.append(sl_name)
            if st_name:
                label_parts.append(st_name)
            if label_parts:
                layout.addWidget(QLabel("  ›  ".join(label_parts)))
            layout.addWidget(_PreviewCard(self.adapter, item, self._vocab_override))
            count += 1
        if count == 0:
            layout.addWidget(QLabel("这节课还没有题目，先在编辑器里添加。"))

        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.accept)
        layout.addWidget(close_btn)

    def refresh(self) -> None:
        """Rebuild from the current lesson state (re-read after edits)."""
        while self.layout().count() > 0:
            child = self.layout().takeAt(0)
            if child.widget():
                child.widget().deleteLater()
        self._build()