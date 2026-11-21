"""Interactive try-it-yourself preview for ``guide`` lessons (ADR 0074).

Mirrors ``lib/views/lesson/components/guide_session_body.dart`` and
``guide_block_view.dart`` so authors can click through pages, test
classification cards + hints, step through suffix builders, and toggle optional
word-order tokens directly in the desktop editor.
"""
from __future__ import annotations

import functools
from typing import Any

from PySide6.QtWidgets import (
    QCheckBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from src.theme import current_palette


class _GuideClassificationPreview(QFrame):
    """Click-to-place classification preview matching ADR 0074 (ungraded + author hint)."""

    def __init__(self, block: dict[str, Any], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.block = block
        self._cards = list(block.get("cards") or [])
        self._categories = list(block.get("categories") or [])
        self._placed: dict[str, str] = {}
        self._selected_card_id: str | None = (
            str(self._cards[0].get("id") or "") if self._cards else None
        )
        self._feedback_text = ""
        self._build_frame()

    def _build_frame(self) -> None:
        pal = current_palette()
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "_GuideClassificationPreview {"
            f" background-color: {pal['bg_secondary']};"
            f" border: 1px solid {pal['border']};"
            " border-radius: 8px; }"
        )
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(10, 10, 10, 10)
        self._layout.setSpacing(8)
        self._rebuild()

    def _rebuild(self) -> None:
        while self._layout.count():
            child = self._layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        pal = current_palette()

        title = QLabel(str(self.block.get("title") or "互动分类"))
        title.setStyleSheet(f"font-weight: 600; color: {pal['text']};")
        self._layout.addWidget(title)
        if self.block.get("instruction"):
            inst = QLabel(str(self.block["instruction"]))
            inst.setWordWrap(True)
            inst.setStyleSheet(f"color: {pal['text_secondary']};")
            self._layout.addWidget(inst)

        # Unplaced cards row
        unplaced = [c for c in self._cards if str(c.get("id") or "") not in self._placed]
        if unplaced:
            if self._selected_card_id not in {str(c.get("id") or "") for c in unplaced}:
                self._selected_card_id = str(unplaced[0].get("id") or "")
            cards_row = QHBoxLayout()
            for card in unplaced:
                cid = str(card.get("id") or "")
                btn = QPushButton(str(card.get("text") or cid))
                btn.setCheckable(True)
                btn.setChecked(cid == self._selected_card_id)
                btn.clicked.connect(functools.partial(self._select_card, cid))
                cards_row.addWidget(btn)
            cards_row.addStretch()
            wrap = QWidget()
            wrap.setLayout(cards_row)
            self._layout.addWidget(wrap)

        # Category buttons
        cat_row = QHBoxLayout()
        for cat in self._categories:
            cat_id = str(cat.get("id") or "")
            placed_here = [
                str(c.get("text") or "")
                for c in self._cards
                if self._placed.get(str(c.get("id") or "")) == cat_id
            ]
            label = str(cat.get("label") or cat_id)
            if placed_here:
                label += f"（{', '.join(placed_here)}）"
            btn = QPushButton(label)
            btn.clicked.connect(functools.partial(self._place_into, cat_id))
            cat_row.addWidget(btn)
        cat_wrap = QWidget()
        cat_wrap.setLayout(cat_row)
        self._layout.addWidget(cat_wrap)

        if self._feedback_text:
            fb = QLabel(self._feedback_text)
            fb.setWordWrap(True)
            fb.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 12px;")
            self._layout.addWidget(fb)

        if not unplaced and self._cards:
            done = QLabel(str(self.block.get("completionNote") or "✓ 全部卡片已归类完成"))
            done.setWordWrap(True)
            done.setStyleSheet(f"font-weight: 600; color: {pal['accent']};")
            self._layout.addWidget(done)

        reset_btn = QPushButton("重置分类")
        reset_btn.clicked.connect(self._reset)
        self._layout.addWidget(reset_btn)

    def _select_card(self, card_id: str, _checked: bool = False) -> None:
        self._selected_card_id = card_id
        self._rebuild()

    def _place_into(self, category_id: str, _checked: bool = False) -> None:
        if not self._selected_card_id:
            return
        card = next(
            (c for c in self._cards if str(c.get("id") or "") == self._selected_card_id),
            None,
        )
        if card is None:
            return
        if str(card.get("categoryId") or "") == category_id:
            self._placed[self._selected_card_id] = category_id
            self._feedback_text = f"✓ 「{card.get('text', '')}」归类正确"
        else:
            hint = str(card.get("hint") or "再观察一下这个词的特征，试试另一类。")
            self._feedback_text = f"💡 提示：{hint}"
        self._rebuild()

    def _reset(self) -> None:
        self._placed.clear()
        self._feedback_text = ""
        self._selected_card_id = (
            str(self._cards[0].get("id") or "") if self._cards else None
        )
        self._rebuild()


class _GuideSuffixPreview(QFrame):
    """Step-by-step suffix builder preview."""

    def __init__(self, block: dict[str, Any], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.block = block
        self._step_by_example: dict[int, int] = {}
        pal = current_palette()
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "_GuideSuffixPreview {"
            f" background-color: {pal['bg_secondary']};"
            f" border: 1px solid {pal['border']};"
            " border-radius: 8px; }"
        )
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(10, 10, 10, 10)
        self._layout.setSpacing(8)
        self._rebuild()

    def _rebuild(self) -> None:
        while self._layout.count():
            child = self._layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        pal = current_palette()
        title = QLabel(str(self.block.get("title") or "词缀拼接"))
        title.setStyleSheet(f"font-weight: 600; color: {pal['text']};")
        self._layout.addWidget(title)
        if self.block.get("instruction"):
            inst = QLabel(str(self.block["instruction"]))
            inst.setWordWrap(True)
            inst.setStyleSheet(f"color: {pal['text_secondary']};")
            self._layout.addWidget(inst)

        for idx, ex in enumerate(self.block.get("examples") or []):
            steps = list(ex.get("steps") or [])
            cur = self._step_by_example.get(idx, 0)
            if cur == 0:
                word = str(ex.get("root") or "")
                meaning = str(ex.get("rootMeaning") or "")
            else:
                st = steps[min(cur - 1, len(steps) - 1)]
                word = str(st.get("result") or "")
                meaning = str(st.get("meaning") or "")
            chain = " + ".join(
                [str(ex.get("root") or ""), *[str(s.get("suffix") or "") for s in steps[:cur]]]
            )
            row = QHBoxLayout()
            lbl = QLabel(f"<b>{word}</b>（{meaning}）  <span style='color:{pal['text_secondary']}'>{chain}</span>")
            lbl.setWordWrap(True)
            row.addWidget(lbl, 1)
            next_btn = QPushButton("+ 下一词缀")
            next_btn.setEnabled(cur < len(steps))
            next_btn.clicked.connect(functools.partial(self._advance, idx))
            reset_btn = QPushButton("重置")
            reset_btn.setEnabled(cur > 0)
            reset_btn.clicked.connect(functools.partial(self._reset, idx))
            row.addWidget(next_btn)
            row.addWidget(reset_btn)
            wrap = QWidget()
            wrap.setLayout(row)
            self._layout.addWidget(wrap)

    def _advance(self, idx: int, _checked: bool = False) -> None:
        self._step_by_example[idx] = self._step_by_example.get(idx, 0) + 1
        self._rebuild()

    def _reset(self, idx: int, _checked: bool = False) -> None:
        self._step_by_example[idx] = 0
        self._rebuild()


class _GuideWordOrderPreview(QFrame):
    """Sentence token display with optional-token toggle."""

    def __init__(self, block: dict[str, Any], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.block = block
        self._hide_optional = False
        pal = current_palette()
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "_GuideWordOrderPreview {"
            f" background-color: {pal['bg_secondary']};"
            f" border: 1px solid {pal['border']};"
            " border-radius: 8px; }"
        )
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(10, 10, 10, 10)
        self._layout.setSpacing(6)
        self._rebuild()

    def _rebuild(self) -> None:
        while self._layout.count():
            child = self._layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        pal = current_palette()
        title = QLabel(str(self.block.get("title") or "语序探索"))
        title.setStyleSheet(f"font-weight: 600; color: {pal['text']};")
        self._layout.addWidget(title)

        tokens = list(self.block.get("tokens") or [])
        visible = [t for t in tokens if not (self._hide_optional and t.get("optional"))]
        tok_row = QHBoxLayout()
        for tok in visible:
            chip = QLabel(f"{tok.get('text', '')}\n[{tok.get('role', '')} · {tok.get('meaning', '')}]")
            chip.setStyleSheet(
                f"background-color: {pal['bg_elevated']};"
                f" border: 1px solid {pal['border']};"
                " border-radius: 6px; padding: 6px 8px;"
            )
            tok_row.addWidget(chip)
        tok_row.addStretch()
        wrap = QWidget()
        wrap.setLayout(tok_row)
        self._layout.addWidget(wrap)

        if self.block.get("translation"):
            tr = QLabel(f"译文：{self.block['translation']}")
            tr.setStyleSheet(f"color: {pal['text_secondary']};")
            self._layout.addWidget(tr)

        if any(t.get("optional") for t in tokens):
            toggle = QCheckBox(str(self.block.get("optionalToggleLabel") or "隐藏可省略成分"))
            toggle.setChecked(self._hide_optional)
            toggle.toggled.connect(self._on_toggle)
            self._layout.addWidget(toggle)

        if self.block.get("note"):
            note = QLabel(str(self.block["note"]))
            note.setWordWrap(True)
            note.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 12px;")
            self._layout.addWidget(note)

    def _on_toggle(self, checked: bool) -> None:
        self._hide_optional = checked
        self._rebuild()


class GuidePreviewWidget(QWidget):
    """Multi-page ungraded exploration preview for a ``guide`` lesson."""

    def __init__(self, lesson: dict[str, Any], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.pages: list[dict[str, Any]] = list(
            (lesson.get("content") or {}).get("pages") or []
        )
        self._page_idx = 0
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(0, 0, 0, 0)
        self._layout.setSpacing(10)
        self._render_current()

    def _render_current(self) -> None:
        while self._layout.count():
            child = self._layout.takeAt(0)
            w = child.widget()
            if w is not None:
                w.setParent(None)
                w.deleteLater()
        pal = current_palette()

        if not self.pages:
            empty = QLabel("这节导览课还没有页面，请先在编辑器里添加页面。")
            empty.setStyleSheet(f"color: {pal['text_secondary']};")
            self._layout.addWidget(empty)
            return

        page = self.pages[self._page_idx]
        nav = QHBoxLayout()
        indicator = QLabel(f"第 {self._page_idx + 1} / {len(self.pages)} 页")
        indicator.setStyleSheet(f"font-weight: 600; color: {pal['accent']};")
        prev_btn = QPushButton("← 上一页")
        prev_btn.setEnabled(self._page_idx > 0)
        prev_btn.clicked.connect(self._prev_page)
        next_btn = QPushButton(
            str(page.get("nextLabel") or ("下一页 →" if self._page_idx < len(self.pages) - 1 else "导览完成"))
        )
        next_btn.setEnabled(self._page_idx < len(self.pages) - 1)
        next_btn.clicked.connect(self._next_page)
        nav.addWidget(indicator)
        nav.addStretch()
        nav.addWidget(prev_btn)
        nav.addWidget(next_btn)
        nav_wrap = QWidget()
        nav_wrap.setLayout(nav)
        self._layout.addWidget(nav_wrap)

        if page.get("kicker"):
            kicker = QLabel(str(page["kicker"]))
            kicker.setStyleSheet(f"color: {pal['text_secondary']}; font-size: 11px;")
            self._layout.addWidget(kicker)

        title = QLabel(str(page.get("title") or ""))
        title.setStyleSheet(f"font-size: 17px; font-weight: 700; color: {pal['text']};")
        self._layout.addWidget(title)

        if page.get("intro"):
            intro = QLabel(str(page["intro"]))
            intro.setWordWrap(True)
            intro.setStyleSheet(f"color: {pal['text_secondary']};")
            self._layout.addWidget(intro)

        for block in page.get("blocks") or []:
            self._layout.addWidget(self._build_block(block))

        self._layout.addStretch()

    def _build_block(self, block: dict[str, Any]) -> QWidget:
        pal = current_palette()
        rt = str(block.get("runtimeType") or "")
        if rt == "classification":
            return _GuideClassificationPreview(block)
        if rt == "suffixBuilder":
            return _GuideSuffixPreview(block)
        if rt == "wordOrder":
            return _GuideWordOrderPreview(block)

        card = QFrame()
        card.setFrameShape(QFrame.Shape.StyledPanel)
        card.setStyleSheet(
            f"background-color: {pal['bg_secondary']};"
            f" border: 1px solid {pal['border']};"
            " border-radius: 8px;"
        )
        v = QVBoxLayout(card)
        v.setContentsMargins(10, 10, 10, 10)
        v.setSpacing(6)
        if block.get("title"):
            t = QLabel(str(block["title"]))
            t.setStyleSheet(f"font-weight: 600; color: {pal['text']};")
            v.addWidget(t)
        if rt == "text":
            body = QLabel(str(block.get("body") or ""))
            body.setWordWrap(True)
            v.addWidget(body)
        elif rt == "terms":
            for item in block.get("items") or []:
                line = f"• <b>{item.get('text', '')}</b>"
                if item.get("translation"):
                    line += f" — {item['translation']}"
                if item.get("note"):
                    line += f"（{item['note']}）"
                lbl = QLabel(line)
                lbl.setWordWrap(True)
                v.addWidget(lbl)
        else:
            v.addWidget(QLabel(f"[{rt}] {block}"))
        return card

    def _prev_page(self) -> None:
        if self._page_idx > 0:
            self._page_idx -= 1
            self._render_current()

    def _next_page(self) -> None:
        if self._page_idx < len(self.pages) - 1:
            self._page_idx += 1
            self._render_current()
