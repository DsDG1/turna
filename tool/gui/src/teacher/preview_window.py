"""Live lesson preview / "try it yourself" window (guiplan §15.7, T.6).

A high-fidelity desktop renderer that mirrors the Flutter app's lesson flow:
- Supports all 9 lesson templates (guide pages, reading passage + SVG/raster
  illustrations, dialogue scene turns, listening phase audio/transcripts,
  review-policy random sampling, sub-lessons, mastery).
- Supports all 17 interaction runtimeTypes with interactive widgets (clickable
  reorder chips, choice-mode fillBlank, imageRecall, dictation, ankiCard flip,
  non-graded listenOnly) and App-parity Turkish-aware grading + acceptedAnswers
  + read-aloud word-level scoring.
"""
from __future__ import annotations

import html
import logging
import re
from pathlib import Path
from typing import Any

from PySide6.QtCore import Qt, Signal
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
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from src.application.lesson_edit_service import (
    matches_course_answer,
    sample_review_pool,
    score_read_aloud,
)
from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_content import listening_phase_has_items
from src.teacher.guide_preview import GuidePreviewWidget
from src.teacher.preview_media import PreviewAudioBar, PreviewImageWidget
from src.theme import current_palette

logger = logging.getLogger(__name__)

PREVIEW_FIX_INSTRUCTION = "教师试做答错：题干/选项可能有歧义或难度不当，请优化，保持 id 与正确答案不变"
_HTML_TAG_RE = re.compile(r"<[^>]+>")


def _strip_html_simple(raw: str) -> str:
    return html.unescape(_HTML_TAG_RE.sub(" ", raw or "")).strip()


def _preview_fix_suggest_enabled(settings: Any | None = None) -> bool:
    try:
        from src.application.runtime_context import current_settings

        st = settings or current_settings()
        return bool(getattr(st, "experience_preview_fix_suggest", False))
    except Exception:
        logger.debug("preview_window: failed reading settings", exc_info=True)
        return False


def _course_dir_of(adapter: Any) -> Path | None:
    raw = getattr(adapter, "course_dir", None)
    return Path(raw) if raw is not None else None


class _PreviewCard(QFrame):
    """A single try-it-yourself question card bound to one item."""

    answered_wrong = Signal(dict)

    def __init__(
        self,
        adapter: CourseAdapter,
        item: dict[str, Any],
        vocab_override: dict[str, dict[str, Any]] | None = None,
        stage: dict[str, Any] | None = None,
    ) -> None:
        super().__init__()
        self.adapter = adapter
        self.item = item
        self.stage = stage or {}
        self._vocab_override = vocab_override or {}
        self._course_dir = _course_dir_of(adapter)
        self.setFrameShape(QFrame.Shape.StyledPanel)
        pal = current_palette()
        self.setStyleSheet(
            "_PreviewCard {"
            f" background-color: {pal['bg_elevated']};"
            f" border: 1px solid {pal['border']};"
            " border-radius: 8px; }"
        )
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(8)
        self._build(layout)

    def _emit_wrong(self) -> None:
        self.answered_wrong.emit({"item": self.item, "stage": self.stage})

    def _term_for(self, ref_id: str) -> str:
        w = self._vocab_override.get(ref_id)
        if w is None:
            for cand in self.adapter.vocab:
                if cand.get("id") == ref_id:
                    w = cand
                    break
        term = self.item.get("term") or (w.get("term") if w else None) or ref_id
        translation = self.item.get("translation") or (w.get("translation") if w else "")
        return f"{term} — {translation}" if translation else str(term)

    def _add_media_strips(self, layout: QVBoxLayout) -> None:
        img = str(self.item.get("imageAsset") or "").strip()
        if img:
            layout.addWidget(PreviewImageWidget(self._course_dir, img))
        for extra_img in self.item.get("imageAssets") or []:
            if extra_img:
                layout.addWidget(PreviewImageWidget(self._course_dir, str(extra_img)))
        audio = str(self.item.get("audioAsset") or "").strip()
        if audio:
            layout.addWidget(PreviewAudioBar(self._course_dir, audio))
        for extra_audio in self.item.get("audioAssets") or []:
            if extra_audio:
                layout.addWidget(PreviewAudioBar(self._course_dir, str(extra_audio)))

    def _build(self, layout: QVBoxLayout) -> None:
        rt = str(self.item.get("runtimeType") or "")
        prompt = (
            self.item.get("prompt")
            or self.item.get("sentence")
            or self.item.get("source")
            or self.item.get("statement")
            or ""
        )
        title = QLabel(f"题目（{rt}）")
        title.setStyleSheet(f"font-weight: 700; color: {current_palette()['text']};")
        layout.addWidget(title)

        if rt == "showWord":
            self._build_show_word(layout)
            return
        if rt == "listenOnly":
            self._build_listen_only(layout, str(prompt))
            return
        if rt in ("multipleChoice", "readingMcq", "listenAndPick"):
            self._add_media_strips(layout)
            self._build_single_choice(layout, str(prompt))
        elif rt == "multiSelect":
            self._add_media_strips(layout)
            self._build_multi_select(layout, str(prompt))
        elif rt == "fillBlank":
            self._add_media_strips(layout)
            self._build_fill_blank(layout, str(prompt))
        elif rt in ("translateSentence", "readingShortAnswer", "typeTheWord"):
            self._add_media_strips(layout)
            self._build_text_answer(layout, str(prompt))
        elif rt == "readingTrueFalse":
            self._build_true_false(layout, str(prompt))
        elif rt == "reorderSentence":
            self._build_reorder_sentence(layout)
        elif rt == "readAloud":
            self._build_read_aloud(layout, str(prompt))
        elif rt == "imageRecall":
            self._build_image_recall(layout)
        elif rt == "dictation":
            self._build_dictation(layout)
        elif rt == "ankiCard":
            self._build_anki_card(layout)
        elif rt == "ankiHtmlCard":
            self._build_anki_html_card(layout)
        else:
            self._build_display(layout, str(prompt or self.item))

    def _build_show_word(self, layout: QVBoxLayout) -> None:
        self._add_media_strips(layout)
        layout.addWidget(QLabel(self._term_for(str(self.item.get("wordId") or ""))))
        if self.item.get("pronunciation"):
            pron = QLabel(f"读音：{self.item['pronunciation']}")
            pron.setStyleSheet(f"color: {current_palette()['text_secondary']};")
            layout.addWidget(pron)
        if self.item.get("context"):
            layout.addWidget(QLabel(str(self.item["context"])))
        if self.item.get("example"):
            layout.addWidget(QLabel(f"例句：{self.item['example']}"))
        layout.addWidget(QLabel("（展示题，无需作答）"))

    def _build_listen_only(self, layout: QVBoxLayout, prompt: str) -> None:
        if prompt:
            layout.addWidget(QLabel(prompt))
        audio = str(self.item.get("audioAsset") or "").strip()
        if audio:
            layout.addWidget(PreviewAudioBar(self._course_dir, audio))
        transcript = str(self.item.get("transcript") or "").strip()
        if transcript:
            tr_lbl = QLabel(transcript)
            tr_lbl.setWordWrap(True)
            tr_lbl.setVisible(False)
            toggle = QPushButton("展开 / 收起原文")
            toggle.setCheckable(True)
            toggle.toggled.connect(tr_lbl.setVisible)
            layout.addWidget(toggle)
            layout.addWidget(tr_lbl)
        done = QLabel("（只听不答卡片，无需判分）")
        done.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 11px;")
        layout.addWidget(done)

    def _build_single_choice(self, layout: QVBoxLayout, prompt: str) -> None:
        lbl = QLabel(prompt or "选择正确答案：")
        lbl.setWordWrap(True)
        layout.addWidget(lbl)
        options = self.item.get("options", []) or []
        correct = int(self.item.get("correctIndex", 0) or 0)
        group = QButtonGroup(self)
        group.setExclusive(True)
        status = QLabel("")
        status.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        status.setWordWrap(True)

        def _check() -> None:
            for i in range(len(options)):
                btn = group.button(i)
                if btn is not None and btn.isChecked():
                    ok = i == correct
                    if not ok:
                        self._emit_wrong()
                    QMessageBox.information(
                        self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案是第 {correct + 1} 项"
                    )
                    return
            status.setText("请先选择答案")

        for opt in options:
            rb = QRadioButton(str(opt))
            group.addButton(rb)
            layout.addWidget(rb)
        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)
        layout.addWidget(status)

    def _build_multi_select(self, layout: QVBoxLayout, prompt: str) -> None:
        lbl = QLabel(prompt or "选择所有正确答案：")
        lbl.setWordWrap(True)
        layout.addWidget(lbl)
        options = self.item.get("options", []) or []
        correct = set(self.item.get("correctIndices", []) or [])
        min_sel = int(self.item.get("minSelections") or 1)
        max_sel = int(self.item.get("maxSelections") or len(options) or 1)
        boxes: list[QCheckBox] = []
        status = QLabel("")
        status.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )

        def _check() -> None:
            chosen = {i for i, cb in enumerate(boxes) if cb.isChecked()}
            if len(chosen) < min_sel:
                status.setText(f"请至少选择 {min_sel} 项")
                return
            if len(chosen) > max_sel:
                status.setText(f"最多选择 {max_sel} 项")
                return
            ok = chosen == correct
            if not ok:
                self._emit_wrong()
            QMessageBox.information(
                self,
                "结果",
                "✅ 答对了！" if ok else f"❌ 正确答案是第 {[c + 1 for c in sorted(correct)]} 项",
            )

        for opt in options:
            cb = QCheckBox(str(opt))
            boxes.append(cb)
            layout.addWidget(cb)
        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)
        layout.addWidget(status)

    def _build_fill_blank(self, layout: QVBoxLayout, prompt: str) -> None:
        lbl = QLabel(prompt)
        lbl.setWordWrap(True)
        layout.addWidget(lbl)
        hint = str(self.item.get("hint") or "").strip()
        if hint:
            h_lbl = QLabel(f"💡 提示：{hint}")
            h_lbl.setWordWrap(True)
            h_lbl.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 11px;")
            layout.addWidget(h_lbl)

        choices = [str(c) for c in (self.item.get("choices") or []) if str(c).strip()]
        answer = str(self.item.get("answer", ""))
        status = QLabel("")
        status.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        status.setWordWrap(True)

        if choices:
            group = QButtonGroup(self)
            group.setExclusive(True)
            for ch in choices:
                rb = QRadioButton(ch)
                group.addButton(rb)
                layout.addWidget(rb)

            def _check_choice() -> None:
                if not answer.strip():
                    status.setText("该题未提供参考答案，无法判定")
                    return
                picked = group.checkedButton()
                if picked is None:
                    status.setText("请先点选一个词块")
                    return
                ok = matches_course_answer(picked.text(), answer)
                if not ok:
                    self._emit_wrong()
                QMessageBox.information(
                    self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案：{answer}"
                )

            check_btn = QPushButton("提交")
            check_btn.clicked.connect(_check_choice)
            layout.addWidget(check_btn)
            layout.addWidget(status)
            return

        edit = QLineEdit()
        edit.setPlaceholderText("填入答案…")
        layout.addWidget(edit)

        def _check() -> None:
            if not answer.strip():
                status.setText("该题未提供参考答案，无法判定")
                return
            ok = matches_course_answer(edit.text(), answer)
            if not ok:
                self._emit_wrong()
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案：{answer}"
            )

        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)
        layout.addWidget(status)

    def _build_text_answer(self, layout: QVBoxLayout, prompt: str) -> None:
        lbl = QLabel(prompt)
        lbl.setWordWrap(True)
        layout.addWidget(lbl)
        hints = [str(h) for h in (self.item.get("hints") or []) if str(h).strip()]
        edit = QLineEdit()
        edit.setPlaceholderText("输入答案…")
        if hints:
            hint_row = QHBoxLayout()
            for h in hints:
                chip = QPushButton(h)
                chip.clicked.connect(
                    lambda _c=False, text=h: edit.setText(
                        (edit.text() + (" " if edit.text() and not edit.text().endswith(" ") else "") + text)
                    )
                )
                hint_row.addWidget(chip)
            hint_row.addStretch()
            wrap = QWidget()
            wrap.setLayout(hint_row)
            layout.addWidget(wrap)
        layout.addWidget(edit)

        answer = str(self.item.get("expected") or self.item.get("expectedAnswer") or "")
        accepted = [str(a) for a in (self.item.get("acceptedAnswers") or []) if str(a).strip()]
        status = QLabel("")
        status.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        status.setWordWrap(True)

        def _check() -> None:
            if not answer.strip():
                status.setText("该题未提供参考答案，无法判定")
                return
            ok = matches_course_answer(edit.text(), answer, accepted)
            if not ok:
                self._emit_wrong()
            alt_note = f"\n也可接受：{' / '.join(accepted)}" if accepted else ""
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 参考答案：{answer}{alt_note}"
            )

        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)
        layout.addWidget(status)

    def _build_reorder_sentence(self, layout: QVBoxLayout) -> None:
        prompt = str(self.item.get("prompt") or "").strip()
        if prompt:
            p_lbl = QLabel(prompt)
            p_lbl.setWordWrap(True)
            layout.addWidget(p_lbl)
        scrambled = [str(t) for t in (self.item.get("scrambled") or [])]
        correct = [str(t) for t in (self.item.get("correct") or [])]
        accepted = [str(a) for a in (self.item.get("acceptedAnswers") or []) if str(a).strip()]
        pal = current_palette()

        selected_indices: list[int] = []
        answer_lbl = QLabel("（点击下方词块依次拼接句子）")
        answer_lbl.setWordWrap(True)
        answer_lbl.setStyleSheet(
            f"padding: 8px; background-color: {pal['bg_input']};"
            f" border: 1px solid {pal['border']}; border-radius: 6px;"
        )
        layout.addWidget(answer_lbl)

        bank_row = QHBoxLayout()
        bank_buttons: list[QPushButton] = []

        def _sync() -> None:
            if selected_indices:
                answer_lbl.setText(" ".join(scrambled[i] for i in selected_indices))
            else:
                answer_lbl.setText("（点击下方词块依次拼接句子）")
            for idx, btn in enumerate(bank_buttons):
                btn.setEnabled(idx not in selected_indices)

        def _pick(idx: int) -> None:
            if idx not in selected_indices:
                selected_indices.append(idx)
                _sync()

        for i, token in enumerate(scrambled):
            btn = QPushButton(token)
            btn.clicked.connect(lambda _c=False, idx=i: _pick(idx))
            bank_buttons.append(btn)
            bank_row.addWidget(btn)
        bank_row.addStretch()
        bank_wrap = QWidget()
        bank_wrap.setLayout(bank_row)
        layout.addWidget(bank_wrap)

        status = QLabel("")
        status.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")

        def _undo() -> None:
            if selected_indices:
                selected_indices.pop()
                _sync()

        def _clear() -> None:
            selected_indices.clear()
            _sync()

        def _check() -> None:
            if not correct:
                status.setText("该题未提供正确词序，无法判定")
                return
            if not selected_indices:
                status.setText("请先点击词块拼接句子")
                return
            built = " ".join(scrambled[i] for i in selected_indices)
            canonical = " ".join(correct)
            ok = matches_course_answer(built, canonical, accepted)
            if not ok:
                self._emit_wrong()
            alt_note = f"\n也可接受：{' / '.join(accepted)}" if accepted else ""
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 正确顺序：{canonical}{alt_note}"
            )

        actions = QHBoxLayout()
        submit_btn = QPushButton("提交")
        submit_btn.clicked.connect(_check)
        undo_btn = QPushButton("撤回一词")
        undo_btn.clicked.connect(_undo)
        clear_btn = QPushButton("清空")
        clear_btn.clicked.connect(_clear)
        actions.addWidget(submit_btn)
        actions.addWidget(undo_btn)
        actions.addWidget(clear_btn)
        actions.addStretch()
        layout.addLayout(actions)
        layout.addWidget(status)

    def _build_read_aloud(self, layout: QVBoxLayout, prompt: str) -> None:
        layout.addWidget(QLabel(prompt or "大声跟读以下句子："))
        target_text = str(self.item.get("targetText") or "").strip()

        pal = current_palette()
        target_card = QLabel(target_text or "（未填写朗读目标句）")
        target_card.setStyleSheet(
            f"font-size: 15px; font-weight: bold; padding: 10px;"
            f" background-color: {pal['bg_input']};"
            f" border: 1px solid {pal['border']}; border-radius: 6px;"
        )
        target_card.setWordWrap(True)
        layout.addWidget(target_card)

        hint = QLabel("💡 与 App 端一致的词面评分（土耳其语折叠 + 前缀/单错字容错，≥ 60% 通过）。")
        hint.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        edit = QLineEdit()
        edit.setPlaceholderText("试做测试：输入模拟朗读识别文本…")
        layout.addWidget(edit)

        status = QLabel("")
        status.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")
        status.setWordWrap(True)

        def _check() -> None:
            if not target_text:
                status.setText("该题未设置朗读目标句 targetText，无法判定")
                return
            input_text = edit.text().strip()
            if not input_text:
                status.setText("请先输入试做识别文本")
                return
            result = score_read_aloud(target_text, input_text)
            word_summary = "  ".join(
                f"{'✓' if w.matched else '✗'}{w.word}" for w in result.words
            )
            status.setText(f"匹配率：{int(round(result.ratio * 100))}% — {word_summary}")
            if not result.passed:
                self._emit_wrong()
            QMessageBox.information(
                self,
                "结果",
                f"✅ 跟读匹配通过（{int(round(result.ratio * 100))}%）！\n{word_summary}"
                if result.passed
                else f"❌ 匹配未达标（{int(round(result.ratio * 100))}% < 60%）\n{word_summary}",
            )

        btn_row = QHBoxLayout()
        check_btn = QPushButton("提交试做比对")
        check_btn.clicked.connect(_check)
        btn_row.addWidget(check_btn)

        quick_btn = QPushButton("填入目标句")
        quick_btn.clicked.connect(lambda: edit.setText(target_text))
        btn_row.addWidget(quick_btn)

        layout.addLayout(btn_row)
        layout.addWidget(status)

    def _build_image_recall(self, layout: QVBoxLayout) -> None:
        for img in self.item.get("imageAssets") or []:
            if img:
                layout.addWidget(PreviewImageWidget(self._course_dir, str(img)))
        hint = str(self.item.get("hint") or "").strip()
        if hint:
            h = QLabel(f"💡 提示：{hint}")
            h.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 11px;")
            layout.addWidget(h)
        ans = QLabel(f"参考答案：{self.item.get('answerText') or '（空）'}")
        ans.setWordWrap(True)
        ans.setVisible(False)
        reveal = QPushButton("显示答案")
        reveal.setCheckable(True)
        reveal.toggled.connect(ans.setVisible)
        layout.addWidget(reveal)
        layout.addWidget(ans)

    def _build_dictation(self, layout: QVBoxLayout) -> None:
        for audio in self.item.get("audioAssets") or []:
            if audio:
                layout.addWidget(PreviewAudioBar(self._course_dir, str(audio)))
        hint = str(self.item.get("hint") or "").strip()
        if hint:
            h = QLabel(f"💡 提示：{hint}")
            h.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 11px;")
            layout.addWidget(h)
        self._build_text_answer(layout, "请听音频并输入听写内容：")

    def _build_anki_card(self, layout: QVBoxLayout) -> None:
        front = QLabel(f"正面：{self.item.get('front') or '（空）'}")
        front.setWordWrap(True)
        layout.addWidget(front)
        for img in self.item.get("frontImageAssets") or []:
            layout.addWidget(PreviewImageWidget(self._course_dir, str(img)))
        for audio in self.item.get("frontAudioAssets") or []:
            layout.addWidget(PreviewAudioBar(self._course_dir, str(audio), label="正面音频"))

        back_box = QWidget()
        bv = QVBoxLayout(back_box)
        bv.setContentsMargins(0, 4, 0, 0)
        back = QLabel(f"背面：{self.item.get('back') or '（空）'}")
        back.setWordWrap(True)
        bv.addWidget(back)
        for img in [*(self.item.get("backImageAssets") or []), *(self.item.get("imageAssets") or [])]:
            bv.addWidget(PreviewImageWidget(self._course_dir, str(img)))
        for audio in [*(self.item.get("backAudioAssets") or []), *(self.item.get("audioAssets") or [])]:
            bv.addWidget(PreviewAudioBar(self._course_dir, str(audio), label="背面音频"))
        back_box.setVisible(False)

        flip = QPushButton("翻面（查看背面）")
        flip.setCheckable(True)
        flip.toggled.connect(back_box.setVisible)
        layout.addWidget(flip)
        layout.addWidget(back_box)

    def _build_anki_html_card(self, layout: QVBoxLayout) -> None:
        note = QLabel("HTML 记忆卡片（桌面端展示去标签纯文本，完整样式以 App 为准）")
        note.setWordWrap(True)
        note.setStyleSheet(f"color: {current_palette()['text_secondary']}; font-size: 11px;")
        layout.addWidget(note)
        front = QLabel(f"正面：{_strip_html_simple(str(self.item.get('frontHtml') or '')) or '（空）'}")
        front.setWordWrap(True)
        layout.addWidget(front)
        back = QLabel(f"背面：{_strip_html_simple(str(self.item.get('backHtml') or '')) or '（空）'}")
        back.setWordWrap(True)
        back.setVisible(False)
        flip = QPushButton("翻面（查看背面）")
        flip.setCheckable(True)
        flip.toggled.connect(back.setVisible)
        layout.addWidget(flip)
        layout.addWidget(back)

    def _build_true_false(self, layout: QVBoxLayout, prompt: str) -> None:
        lbl = QLabel(prompt)
        lbl.setWordWrap(True)
        layout.addWidget(lbl)
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
        answer = bool(self.item.get("answer", False))
        status = QLabel("")
        status.setStyleSheet(
            f"color: {current_palette()['text_secondary']}; font-size: 11px;"
        )
        status.setWordWrap(True)

        def _check() -> None:
            if not (true_btn.isChecked() or false_btn.isChecked()):
                status.setText("请先选择答案")
                return
            chosen = true_btn.isChecked()
            ok = chosen == answer
            if not ok:
                self._emit_wrong()
            QMessageBox.information(
                self, "结果", "✅ 答对了！" if ok else f"❌ 正确答案：{'正确' if answer else '错误'}"
            )

        check_btn = QPushButton("提交")
        check_btn.clicked.connect(_check)
        layout.addWidget(check_btn)
        layout.addWidget(status)

    def _build_display(self, layout: QVBoxLayout, text: str) -> None:
        layout.addWidget(QLabel("（此题型在预览中仅展示，不可作答）"))
        if text:
            lbl = QLabel(text)
            lbl.setWordWrap(True)
            layout.addWidget(lbl)


def iter_preview_items(lesson: dict[str, Any]):
    """Yield ``(sub_lesson_name, stage_name, item, stage)`` for every interactive item."""
    content = lesson.get("content", {}) or {}
    for sl in content.get("subLessons", []) or []:
        for stage in sl.get("stages", []) or []:
            for item in stage.get("items", []) or []:
                yield sl.get("name", ""), stage.get("name", ""), item, stage
    for stage in content.get("stages", []) or []:
        for item in stage.get("items", []) or []:
            yield "", stage.get("name", ""), item, stage
    for phase in content.get("listeningPhases", []) or []:
        if listening_phase_has_items(phase.get("type", "")):
            for item in phase.get("items", []) or []:
                yield "", phase.get("name", ""), item, phase


def _build_reading_header(adapter: Any, content: dict[str, Any]) -> QWidget | None:
    passage = content.get("readingPassage")
    if not isinstance(passage, dict) or not (passage.get("title") or passage.get("paragraphs")):
        return None
    pal = current_palette()
    box = QFrame()
    box.setFrameShape(QFrame.Shape.StyledPanel)
    box.setStyleSheet(
        f"background-color: {pal['bg_secondary']};"
        f" border: 1px solid {pal['border']}; border-radius: 8px;"
    )
    v = QVBoxLayout(box)
    v.setContentsMargins(12, 12, 12, 12)
    v.setSpacing(6)
    title = QLabel(str(passage.get("title") or "阅读材料"))
    title.setStyleSheet(f"font-size: 16px; font-weight: 700; color: {pal['text']};")
    v.addWidget(title)
    if passage.get("imageAsset"):
        v.addWidget(
            PreviewImageWidget(
                _course_dir_of(adapter),
                str(passage["imageAsset"]),
                alt_text=str(passage.get("imageAlt") or ""),
            )
        )
    for para in passage.get("paragraphs") or []:
        lbl = QLabel(str(para))
        lbl.setWordWrap(True)
        v.addWidget(lbl)
    return box


def _populate_lesson_preview(
    layout: QVBoxLayout,
    adapter: CourseAdapter,
    lesson: dict[str, Any],
    vocab_override: dict[str, dict[str, Any]],
    *,
    on_wrong: Any | None = None,
    sampled_mode: bool = False,
) -> int:
    """Populate *layout* with template-aware preview widgets. Returns card count."""
    template = str(lesson.get("template") or "legacy")
    content = lesson.get("content") or {}
    pal = current_palette()

    if template == "guide":
        layout.addWidget(GuidePreviewWidget(lesson))
        return len(content.get("pages") or [])

    if template == "reading":
        header = _build_reading_header(adapter, content)
        if header is not None:
            layout.addWidget(header)

    if template == "dialogue" and isinstance(content.get("dialogueScene"), dict):
        scene = content["dialogueScene"]
        course_dir = _course_dir_of(adapter)
        chars = {
            str(c.get("id") or ""): c
            for c in (scene.get("characters") or [])
            if isinstance(c, dict)
        }
        item_map: dict[str, tuple[dict[str, Any], dict[str, Any]]] = {}
        for st in content.get("stages") or []:
            for it in st.get("items") or []:
                if it.get("id"):
                    item_map[str(it["id"])] = (it, st)
        if scene.get("title"):
            t = QLabel(f"情景对话：{scene['title']}")
            t.setStyleSheet(f"font-size: 15px; font-weight: 700; color: {pal['text']};")
            layout.addWidget(t)
        count = 0
        for turn in scene.get("turns") or []:
            if not isinstance(turn, dict):
                continue
            char = chars.get(str(turn.get("speakerId") or ""), {})
            speaker = str(char.get("name") or turn.get("speakerId") or "")
            if turn.get("text"):
                bubble = QFrame()
                bubble.setStyleSheet(
                    f"background-color: {pal['bg_secondary']};"
                    f" border: 1px solid {pal['border']}; border-radius: 8px;"
                )
                bv = QVBoxLayout(bubble)
                bv.setContentsMargins(10, 8, 10, 8)
                if char.get("imageAsset"):
                    bv.addWidget(
                        PreviewImageWidget(
                            course_dir, str(char["imageAsset"]), max_width=56, max_height=56
                        )
                    )
                line = QLabel(f"<b>{speaker}：</b>{turn['text']}")
                line.setWordWrap(True)
                bv.addWidget(line)
                layout.addWidget(bubble)
                count += 1
            elif turn.get("interactionId") and str(turn["interactionId"]) in item_map:
                item, st = item_map[str(turn["interactionId"])]
                card = _PreviewCard(adapter, item, vocab_override, stage=st)
                if on_wrong is not None:
                    card.answered_wrong.connect(on_wrong)
                layout.addWidget(card)
                count += 1
        return count

    if template == "listening" and content.get("listeningPhases"):
        course_dir = _course_dir_of(adapter)
        count = 0
        for phase in content.get("listeningPhases") or []:
            ph_title = QLabel(f"🎧 {phase.get('name') or phase.get('type', '')}")
            ph_title.setStyleSheet(f"font-weight: 700; color: {pal['text']};")
            layout.addWidget(ph_title)
            if phase.get("audioAsset"):
                layout.addWidget(PreviewAudioBar(course_dir, str(phase["audioAsset"]), label="阶段音频"))
            if phase.get("transcript"):
                tr = QLabel(str(phase["transcript"]))
                tr.setWordWrap(True)
                tr.setVisible(False)
                btn = QPushButton("展开 / 收起阶段原文")
                btn.setCheckable(True)
                btn.toggled.connect(tr.setVisible)
                layout.addWidget(btn)
                layout.addWidget(tr)
            if listening_phase_has_items(str(phase.get("type") or "")):
                for item in phase.get("items") or []:
                    card = _PreviewCard(adapter, item, vocab_override, stage=phase)
                    if on_wrong is not None:
                        card.answered_wrong.connect(on_wrong)
                    layout.addWidget(card)
                    count += 1
            else:
                count += 1
        return count

    if sampled_mode and isinstance(content.get("reviewPolicy"), dict):
        all_pairs = [
            (item, st)
            for st in (content.get("stages") or [])
            for item in (st.get("items") or [])
        ]
        sampled_items = sample_review_pool(
            [it for it, _ in all_pairs], content["reviewPolicy"]
        )
        stage_by_id = {id(it): st for it, st in all_pairs}
        for item in sampled_items:
            card = _PreviewCard(adapter, item, vocab_override, stage=stage_by_id.get(id(item), {}))
            if on_wrong is not None:
                card.answered_wrong.connect(on_wrong)
            layout.addWidget(card)
        return len(sampled_items)

    count = 0
    for sl_name, st_name, item, stage in iter_preview_items(lesson):
        label_parts = [p for p in (sl_name, st_name) if p]
        if label_parts:
            layout.addWidget(QLabel("  ›  ".join(label_parts)))
        card = _PreviewCard(adapter, item, vocab_override, stage=stage)
        if on_wrong is not None:
            card.answered_wrong.connect(on_wrong)
        layout.addWidget(card)
        count += 1
    return count


class LessonPreviewWidget(QWidget):
    """Embedded lesson preview (W3 DetailPanel 预览 tab)."""

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
        self._sampled_mode = False
        self._root = QVBoxLayout(self)
        self._root.setContentsMargins(16, 12, 16, 16)
        self._root.setSpacing(10)
        self._rebuild()

    def _rebuild(self) -> None:
        while self._root.count():
            child = self._root.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()

        policy = (self.lesson.get("content") or {}).get("reviewPolicy")
        if isinstance(policy, dict):
            bar = QHBoxLayout()
            mode_btn = QPushButton("切换：当前为随机抽题" if self._sampled_mode else "模拟复习随机抽题")
            mode_btn.clicked.connect(self._toggle_sample)
            bar.addWidget(mode_btn)
            if self._sampled_mode:
                resample = QPushButton("重新抽一批")
                resample.clicked.connect(self._rebuild)
                bar.addWidget(resample)
            bar.addStretch()
            wrap = QWidget()
            wrap.setLayout(bar)
            self._root.addWidget(wrap)

        count = _populate_lesson_preview(
            self._root,
            self.adapter,
            self.lesson,
            self._vocab_override,
            sampled_mode=self._sampled_mode,
        )
        if count == 0:
            empty = QLabel("这节课还没有题目，先在编辑器里添加。")
            empty.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self._root.addWidget(empty)
        self._root.addStretch(1)

    def _toggle_sample(self) -> None:
        self._sampled_mode = not self._sampled_mode
        self._rebuild()


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
        self._last_wrong_payload: dict[str, Any] | None = None
        self._sampled_mode = False
        self.setWindowTitle(f"预览：{lesson.get('name', lesson.get('id', ''))}")
        self.resize(680, 740)
        self.setMinimumSize(480, 400)
        self._build()

    def _iter_items(self):
        yield from iter_preview_items(self.lesson)

    def _build(self) -> None:
        layout = self.layout()
        if layout is None:
            layout = QVBoxLayout(self)
            layout.setContentsMargins(16, 16, 16, 16)
            layout.setSpacing(10)

        title = QLabel(f"预览：{self.lesson.get('name', '')}")
        pal = current_palette()
        title.setStyleSheet(f"font-size: 18px; font-weight: 700; color: {pal['text']};")
        layout.addWidget(title)
        hint = QLabel("实际做题验证你的题目设置。改题后重新打开此窗口即刷新。")
        hint.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")
        layout.addWidget(hint)

        policy = (self.lesson.get("content") or {}).get("reviewPolicy")
        if isinstance(policy, dict):
            bar = QHBoxLayout()
            mode_btn = QPushButton("切换：全部题目" if self._sampled_mode else "模拟复习随机抽题")
            mode_btn.clicked.connect(self._toggle_sample)
            bar.addWidget(mode_btn)
            if self._sampled_mode:
                resample = QPushButton("重新抽一批")
                resample.clicked.connect(self.refresh)
                bar.addWidget(resample)
            bar.addStretch()
            wrap = QWidget()
            wrap.setLayout(bar)
            layout.addWidget(wrap)

        self._fix_bar = QWidget()
        self._fix_bar.setHidden(True)
        bar_layout = QHBoxLayout(self._fix_bar)
        bar_layout.setContentsMargins(0, 0, 0, 0)
        self._fix_label = QLabel("答错了？可以让 AI 针对该题提出修改建议：")
        self._fix_btn = QPushButton("获取 AI 改题建议")
        self._fix_btn.clicked.connect(self._on_fix_suggest_clicked)
        bar_layout.addWidget(self._fix_label)
        bar_layout.addWidget(self._fix_btn)
        bar_layout.addStretch()
        layout.addWidget(self._fix_bar)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        cards_host = QWidget()
        cards_layout = QVBoxLayout(cards_host)
        cards_layout.setContentsMargins(0, 0, 0, 0)
        cards_layout.setSpacing(10)

        count = _populate_lesson_preview(
            cards_layout,
            self.adapter,
            self.lesson,
            self._vocab_override,
            on_wrong=self._on_card_answered_wrong,
            sampled_mode=self._sampled_mode,
        )
        if count == 0:
            cards_layout.addWidget(QLabel("这节课还没有题目，先在编辑器里添加。"))
        cards_layout.addStretch(1)

        scroll.setWidget(cards_host)
        layout.addWidget(scroll, 1)

        close_btn = QPushButton("关闭")
        close_btn.clicked.connect(self.accept)
        layout.addWidget(close_btn)

    def _toggle_sample(self) -> None:
        self._sampled_mode = not self._sampled_mode
        self.refresh()

    def _on_card_answered_wrong(self, payload: dict) -> None:
        if not _preview_fix_suggest_enabled():
            return
        self._last_wrong_payload = payload
        self._fix_bar.setHidden(False)

    def _on_fix_suggest_clicked(self) -> None:
        if not self._last_wrong_payload:
            return
        from PySide6.QtGui import QUndoStack
        from src.teacher.item_ai_chip import find_main_attr, run_item_chip

        undo_stack = find_main_attr(self, "undo_stack")
        if undo_stack is None:
            undo_stack = QUndoStack(self)
        run_item_chip(
            self,
            adapter=self.adapter,
            item=self._last_wrong_payload.get("item"),
            stage=self._last_wrong_payload.get("stage"),
            instruction=PREVIEW_FIX_INSTRUCTION,
            undo_stack=undo_stack,
            lesson_id=str(self.lesson.get("id") or ""),
        )

    def refresh(self) -> None:
        """Rebuild from the current lesson state (re-read after edits)."""
        layout = self.layout()
        if layout is not None:
            while layout.count() > 0:
                child = layout.takeAt(0)
                if child.widget():
                    child.widget().deleteLater()
        self._build()
