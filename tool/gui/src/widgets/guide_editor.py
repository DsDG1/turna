"""Visual editor for ungraded page-based ``guide`` lessons (ADR 0074).

Covers ``GuidePage`` and all 5 ``GuideBlock`` variants defined in
``lib/domain/course/guide_page.dart``:
- ``text``
- ``terms``
- ``classification``
- ``suffixBuilder``
- ``wordOrder``

Routes all structural mutations through ``src.application.lesson_edit_service``
to preserve ``max_ui_backend_imports``.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QFrame,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QPushButton,
    QScrollArea,
    QSplitter,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from src.application.lesson_edit_service import (
    GUIDE_BLOCK_LABELS,
    GUIDE_BLOCK_TYPES,
    add_guide_block,
    add_guide_page,
    delete_guide_block,
    delete_guide_page,
    move_guide_block,
    move_guide_page,
    short_id,
)
from src.theme import current_palette


class _GuideBlockCard(QFrame):
    """Editable card for one GuideBlock."""

    changed = Signal()
    move_requested = Signal(int)
    delete_requested = Signal()

    def __init__(
        self,
        adapter: Any,
        block: dict[str, Any],
        *,
        can_up: bool,
        can_down: bool,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.block = block
        pal = current_palette()
        self.setFrameShape(QFrame.Shape.StyledPanel)
        self.setStyleSheet(
            "_GuideBlockCard {"
            f" background-color: {pal['bg_secondary']};"
            f" border: 1px solid {pal['border']};"
            " border-radius: 8px; }"
        )
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(10, 10, 10, 10)
        self._layout.setSpacing(8)
        self._build_header(can_up=can_up, can_down=can_down)
        self._build_body()

    def _build_header(self, *, can_up: bool, can_down: bool) -> None:
        rt = str(self.block.get("runtimeType") or "text")
        label = GUIDE_BLOCK_LABELS.get(rt, rt)
        row = QHBoxLayout()
        title = QLabel(f"[{label}] {self.block.get('id', '')}")
        title.setStyleSheet(f"font-weight: 600; color: {current_palette()['text']};")
        row.addWidget(title)
        row.addStretch()

        up_btn = QPushButton("↑")
        up_btn.setFixedWidth(28)
        up_btn.setEnabled(can_up)
        up_btn.clicked.connect(lambda: self.move_requested.emit(-1))
        row.addWidget(up_btn)

        down_btn = QPushButton("↓")
        down_btn.setFixedWidth(28)
        down_btn.setEnabled(can_down)
        down_btn.clicked.connect(lambda: self.move_requested.emit(1))
        row.addWidget(down_btn)

        del_btn = QPushButton("删除块")
        del_btn.clicked.connect(self.delete_requested.emit)
        row.addWidget(del_btn)
        self._layout.addLayout(row)

    def _line(self, field: str, placeholder: str = "") -> QLineEdit:
        edit = QLineEdit(str(self.block.get(field) or ""))
        edit.setPlaceholderText(placeholder)
        edit.textChanged.connect(lambda text, f=field: self._set(f, text))
        return edit

    def _set(self, field: str, value: Any) -> None:
        self.block[field] = value
        self.changed.emit()

    def _build_body(self) -> None:
        rt = str(self.block.get("runtimeType") or "text")
        if rt == "text":
            self._build_text()
        elif rt == "terms":
            self._build_terms()
        elif rt == "classification":
            self._build_classification()
        elif rt == "suffixBuilder":
            self._build_suffix_builder()
        elif rt == "wordOrder":
            self._build_word_order()
        else:
            self._layout.addWidget(QLabel(f"未知导览块类型：{rt}"))

    def _build_text(self) -> None:
        form = QFormLayout()
        form.addRow("标题（可选）：", self._line("title", "小节标题"))
        body = QTextEdit(str(self.block.get("body") or ""))
        body.setMaximumHeight(110)
        body.textChanged.connect(lambda: self._set("body", body.toPlainText()))
        form.addRow("正文：", body)
        self._layout.addLayout(form)

    def _build_terms(self) -> None:
        form = QFormLayout()
        form.addRow("标题（可选）：", self._line("title", "词卡组标题"))
        compact = QCheckBox("紧凑排版 (compact)")
        compact.setChecked(bool(self.block.get("compact", False)))
        compact.toggled.connect(lambda checked: self._set("compact", checked))
        form.addRow("", compact)
        self._layout.addLayout(form)

        items = self.block.setdefault("items", [])
        table = QTableWidget(0, 5)
        table.setHorizontalHeaderLabels(["text", "translation", "note", "speechText", "wordId"])
        table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        table.setMaximumHeight(160)
        self._layout.addWidget(table)

        def _refresh() -> None:
            table.blockSignals(True)
            table.setRowCount(len(items))
            for r, entry in enumerate(items):
                for c, key in enumerate(("text", "translation", "note", "speechText", "wordId")):
                    val = entry.get(key)
                    table.setItem(r, c, QTableWidgetItem("" if val is None else str(val)))
            table.blockSignals(False)

        def _on_cell(row: int, col: int) -> None:
            keys = ("text", "translation", "note", "speechText", "wordId")
            if 0 <= row < len(items):
                text = table.item(row, col).text().strip()
                key = keys[col]
                if key in ("speechText", "wordId"):
                    items[row][key] = text or None
                else:
                    items[row][key] = text
                self.changed.emit()

        def _add() -> None:
            items.append(
                {"text": "新词", "translation": "", "note": "", "speechText": None, "wordId": None}
            )
            _refresh()
            self.changed.emit()

        def _del() -> None:
            r = table.currentRow()
            if 0 <= r < len(items):
                del items[r]
                _refresh()
                self.changed.emit()

        table.cellChanged.connect(_on_cell)
        _refresh()
        self._layout.addLayout(self._table_bar(_add, _del, "词条"))

    def _build_classification(self) -> None:
        form = QFormLayout()
        form.addRow("标题：", self._line("title"))
        form.addRow("引导说明：", self._line("instruction"))
        form.addRow("完成寄语：", self._line("completionNote"))
        self._layout.addLayout(form)

        cats = self.block.setdefault("categories", [])
        cards = self.block.setdefault("cards", [])

        self._layout.addWidget(QLabel("分类槽 (categories)："))
        cat_table = QTableWidget(0, 3)
        cat_table.setHorizontalHeaderLabels(["id", "label", "description"])
        cat_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        cat_table.setMaximumHeight(120)
        self._layout.addWidget(cat_table)

        def _refresh_cats() -> None:
            cat_table.blockSignals(True)
            cat_table.setRowCount(len(cats))
            for r, cat in enumerate(cats):
                for c, key in enumerate(("id", "label", "description")):
                    cat_table.setItem(r, c, QTableWidgetItem(str(cat.get(key) or "")))
            cat_table.blockSignals(False)

        def _cat_changed(row: int, col: int) -> None:
            keys = ("id", "label", "description")
            if 0 <= row < len(cats):
                cats[row][keys[col]] = cat_table.item(row, col).text().strip()
                self.changed.emit()

        def _add_cat() -> None:
            cats.append({"id": short_id("gc"), "label": "新分类", "description": ""})
            _refresh_cats()
            self.changed.emit()

        def _del_cat() -> None:
            r = cat_table.currentRow()
            if 0 <= r < len(cats):
                del cats[r]
                _refresh_cats()
                self.changed.emit()

        cat_table.cellChanged.connect(_cat_changed)
        _refresh_cats()
        self._layout.addLayout(self._table_bar(_add_cat, _del_cat, "分类"))

        self._layout.addWidget(QLabel("待分类卡片 (cards)："))
        card_table = QTableWidget(0, 5)
        card_table.setHorizontalHeaderLabels(["id", "text", "categoryId", "hint", "highlight"])
        card_table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        card_table.setMaximumHeight(150)
        self._layout.addWidget(card_table)

        def _refresh_cards() -> None:
            card_table.blockSignals(True)
            card_table.setRowCount(len(cards))
            for r, card in enumerate(cards):
                for c, key in enumerate(("id", "text", "categoryId", "hint", "highlight")):
                    card_table.setItem(r, c, QTableWidgetItem(str(card.get(key) or "")))
            card_table.blockSignals(False)

        def _card_changed(row: int, col: int) -> None:
            keys = ("id", "text", "categoryId", "hint", "highlight")
            if 0 <= row < len(cards):
                cards[row][keys[col]] = card_table.item(row, col).text().strip()
                self.changed.emit()

        def _add_card() -> None:
            default_cat = str(cats[0].get("id") or "") if cats else ""
            cards.append(
                {
                    "id": short_id("gcard"),
                    "text": "新卡片",
                    "categoryId": default_cat,
                    "hint": "",
                    "highlight": "",
                }
            )
            _refresh_cards()
            self.changed.emit()

        def _del_card() -> None:
            r = card_table.currentRow()
            if 0 <= r < len(cards):
                del cards[r]
                _refresh_cards()
                self.changed.emit()

        card_table.cellChanged.connect(_card_changed)
        _refresh_cards()
        self._layout.addLayout(self._table_bar(_add_card, _del_card, "卡片"))

    def _build_suffix_builder(self) -> None:
        form = QFormLayout()
        form.addRow("标题：", self._line("title"))
        form.addRow("说明：", self._line("instruction"))
        self._layout.addLayout(form)

        examples = self.block.setdefault("examples", [])
        self._layout.addWidget(QLabel("词根与阶梯（每行代表一个示例；步骤按「词缀=结果=释义」用分号分隔）："))
        table = QTableWidget(0, 5)
        table.setHorizontalHeaderLabels(["id", "root", "rootMeaning", "label", "steps (词缀=结果=释义;...)"])
        table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        table.setMaximumHeight(160)
        self._layout.addWidget(table)

        def _format_steps(steps: list[dict[str, Any]]) -> str:
            return "; ".join(
                f"{s.get('suffix', '')}={s.get('result', '')}={s.get('meaning', '')}"
                for s in steps
                if isinstance(s, dict)
            )

        def _parse_steps(raw: str) -> list[dict[str, str]]:
            out: list[dict[str, str]] = []
            for part in raw.split(";"):
                chunk = part.strip()
                if not chunk:
                    continue
                pieces = [p.strip() for p in chunk.split("=", 2)]
                if len(pieces) == 3:
                    out.append({"suffix": pieces[0], "result": pieces[1], "meaning": pieces[2]})
            return out

        def _refresh() -> None:
            table.blockSignals(True)
            table.setRowCount(len(examples))
            for r, ex in enumerate(examples):
                table.setItem(r, 0, QTableWidgetItem(str(ex.get("id") or "")))
                table.setItem(r, 1, QTableWidgetItem(str(ex.get("root") or "")))
                table.setItem(r, 2, QTableWidgetItem(str(ex.get("rootMeaning") or "")))
                table.setItem(r, 3, QTableWidgetItem(str(ex.get("label") or "")))
                table.setItem(r, 4, QTableWidgetItem(_format_steps(ex.get("steps") or [])))
            table.blockSignals(False)

        def _changed(row: int, col: int) -> None:
            if not 0 <= row < len(examples):
                return
            val = table.item(row, col).text().strip()
            if col == 0:
                examples[row]["id"] = val
            elif col == 1:
                examples[row]["root"] = val
            elif col == 2:
                examples[row]["rootMeaning"] = val
            elif col == 3:
                examples[row]["label"] = val
            elif col == 4:
                examples[row]["steps"] = _parse_steps(val)
            self.changed.emit()

        def _add() -> None:
            examples.append(
                {
                    "id": short_id("gex"),
                    "root": "ev",
                    "rootMeaning": "家",
                    "label": "",
                    "steps": [{"suffix": "-de", "result": "evde", "meaning": "在家"}],
                }
            )
            _refresh()
            self.changed.emit()

        def _del() -> None:
            r = table.currentRow()
            if 0 <= r < len(examples):
                del examples[r]
                _refresh()
                self.changed.emit()

        table.cellChanged.connect(_changed)
        _refresh()
        self._layout.addLayout(self._table_bar(_add, _del, "词缀示例"))

    def _build_word_order(self) -> None:
        form = QFormLayout()
        form.addRow("标题：", self._line("title"))
        form.addRow("整句译文：", self._line("translation"))
        form.addRow("省略开关文案：", self._line("optionalToggleLabel", "有 optional 词块时必填"))
        form.addRow("补充说明：", self._line("note"))
        self._layout.addLayout(form)

        tokens = self.block.setdefault("tokens", [])
        table = QTableWidget(0, 5)
        table.setHorizontalHeaderLabels(["id", "text", "role", "meaning", "optional (true/false)"])
        table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        table.setMaximumHeight(150)
        self._layout.addWidget(table)

        def _refresh() -> None:
            table.blockSignals(True)
            table.setRowCount(len(tokens))
            for r, tok in enumerate(tokens):
                table.setItem(r, 0, QTableWidgetItem(str(tok.get("id") or "")))
                table.setItem(r, 1, QTableWidgetItem(str(tok.get("text") or "")))
                table.setItem(r, 2, QTableWidgetItem(str(tok.get("role") or "")))
                table.setItem(r, 3, QTableWidgetItem(str(tok.get("meaning") or "")))
                table.setItem(r, 4, QTableWidgetItem("true" if tok.get("optional") else "false"))
            table.blockSignals(False)

        def _changed(row: int, col: int) -> None:
            if not 0 <= row < len(tokens):
                return
            val = table.item(row, col).text().strip()
            if col == 4:
                tokens[row]["optional"] = val.lower() in ("true", "1", "yes", "是")
            else:
                key = ("id", "text", "role", "meaning")[col]
                tokens[row][key] = val
            self.changed.emit()

        def _add() -> None:
            tokens.append(
                {
                    "id": short_id("gtok"),
                    "text": "词",
                    "role": "成分",
                    "meaning": "释义",
                    "optional": False,
                }
            )
            _refresh()
            self.changed.emit()

        def _del() -> None:
            r = table.currentRow()
            if 0 <= r < len(tokens):
                del tokens[r]
                _refresh()
                self.changed.emit()

        table.cellChanged.connect(_changed)
        _refresh()
        self._layout.addLayout(self._table_bar(_add, _del, "词块"))

    @staticmethod
    def _table_bar(on_add: Any, on_del: Any, noun: str) -> QHBoxLayout:
        bar = QHBoxLayout()
        add_btn = QPushButton(f"+ 添加{noun}")
        del_btn = QPushButton("- 删除选中")
        add_btn.clicked.connect(on_add)
        del_btn.clicked.connect(on_del)
        bar.addWidget(add_btn)
        bar.addWidget(del_btn)
        bar.addStretch()
        return bar


class GuideEditor(QWidget):
    """Full visual editor (and optional read-only viewer) for ``guide`` lessons."""

    changed = Signal()

    def __init__(
        self,
        adapter: Any,
        lesson: dict[str, Any],
        *,
        read_only: bool = False,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.lesson = lesson
        self.read_only = read_only
        self.content = lesson.setdefault("content", {})
        self.pages: list[dict[str, Any]] = self.content.setdefault("pages", [])
        self._current_page_idx = -1
        self._build_ui()

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        pal = current_palette()

        hint = QLabel(
            "分页导览课：无判分探索页面，支持说明文本、点读词卡、互动分类、词缀拼接和语序探索。"
        )
        hint.setStyleSheet(f"color: {pal['text_secondary']};")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        splitter = QSplitter()
        left = QWidget()
        lv = QVBoxLayout(left)
        lv.setContentsMargins(0, 0, 0, 0)
        lv.addWidget(QLabel("导览页面"))
        self.page_list = QListWidget()
        self.page_list.currentRowChanged.connect(self._on_page_selected)
        lv.addWidget(self.page_list)

        if not self.read_only:
            prow = QHBoxLayout()
            add_p = QPushButton("+ 页面")
            del_p = QPushButton("- 删除")
            up_p = QPushButton("↑")
            up_p.setFixedWidth(28)
            dn_p = QPushButton("↓")
            dn_p.setFixedWidth(28)
            add_p.clicked.connect(self._on_add_page)
            del_p.clicked.connect(self._on_del_page)
            up_p.clicked.connect(lambda: self._on_move_page(-1))
            dn_p.clicked.connect(lambda: self._on_move_page(1))
            for b in (add_p, del_p, up_p, dn_p):
                prow.addWidget(b)
            lv.addLayout(prow)

        splitter.addWidget(left)

        self.right_scroll = QScrollArea()
        self.right_scroll.setWidgetResizable(True)
        self.right_host = QWidget()
        self.right_layout = QVBoxLayout(self.right_host)
        self.right_layout.setContentsMargins(8, 8, 8, 8)
        self.right_layout.setSpacing(10)
        self.right_scroll.setWidget(self.right_host)
        splitter.addWidget(self.right_scroll)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 3)
        layout.addWidget(splitter, 1)

        self._refresh_page_list()
        if self.pages:
            self.page_list.setCurrentRow(0)
        else:
            self._render_empty_right()

    def _refresh_page_list(self) -> None:
        self.page_list.blockSignals(True)
        self.page_list.clear()
        for idx, page in enumerate(self.pages):
            title = page.get("title") or page.get("id") or f"第 {idx + 1} 页"
            blocks = len(page.get("blocks") or [])
            self.page_list.addItem(f"{idx + 1}. {title} ({blocks} 块)")
        self.page_list.blockSignals(False)

    def _clear_right(self) -> None:
        while self.right_layout.count():
            child = self.right_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

    def _render_empty_right(self) -> None:
        self._clear_right()
        lbl = QLabel("（暂无导览页面，点击左侧「+ 页面」创建）")
        lbl.setStyleSheet(f"color: {current_palette()['text_secondary']};")
        self.right_layout.addWidget(lbl)
        self.right_layout.addStretch()

    def _on_page_selected(self, row: int) -> None:
        self._current_page_idx = row
        if not (0 <= row < len(self.pages)):
            self._render_empty_right()
            return
        self._render_page(self.pages[row])

    def _render_page(self, page: dict[str, Any]) -> None:
        self._clear_right()
        pal = current_palette()

        if self.read_only:
            header = QLabel(f"<b>{page.get('title') or page.get('id', '')}</b>")
            self.right_layout.addWidget(header)
            if page.get("intro"):
                intro = QLabel(str(page["intro"]))
                intro.setWordWrap(True)
                intro.setStyleSheet(f"color: {pal['text_secondary']};")
                self.right_layout.addWidget(intro)
            for block in page.get("blocks") or []:
                rt = str(block.get("runtimeType") or "?")
                lbl = QLabel(f"[{GUIDE_BLOCK_LABELS.get(rt, rt)}] {block.get('title') or block.get('id') or ''}")
                lbl.setWordWrap(True)
                self.right_layout.addWidget(lbl)
            self.right_layout.addStretch()
            return

        meta = QFormLayout()
        meta.setSpacing(6)
        title_edit = QLineEdit(str(page.get("title") or ""))
        title_edit.textChanged.connect(lambda t: self._set_page_field(page, "title", t, refresh_list=True))
        meta.addRow("页面标题：", title_edit)

        kicker_edit = QLineEdit(str(page.get("kicker") or ""))
        kicker_edit.setPlaceholderText("顶部角标（可选）")
        kicker_edit.textChanged.connect(lambda t: self._set_page_field(page, "kicker", t))
        meta.addRow("角标 (kicker)：", kicker_edit)

        intro_edit = QTextEdit(str(page.get("intro") or ""))
        intro_edit.setMaximumHeight(72)
        intro_edit.textChanged.connect(lambda: self._set_page_field(page, "intro", intro_edit.toPlainText()))
        meta.addRow("导语 (intro)：", intro_edit)

        next_label_edit = QLineEdit(str(page.get("nextLabel") or ""))
        next_label_edit.setPlaceholderText("末页按钮文案（可选）")
        next_label_edit.textChanged.connect(
            lambda t: self._set_page_field(page, "nextLabel", t.strip() or None)
        )
        meta.addRow("跳转按钮文案：", next_label_edit)

        next_lesson_edit = QLineEdit(str(page.get("nextLessonId") or ""))
        next_lesson_edit.setPlaceholderText("可选：完成后跳转的 lessonId")
        next_lesson_edit.textChanged.connect(
            lambda t: self._set_page_field(page, "nextLessonId", t.strip() or None)
        )
        meta.addRow("下一课 ID：", next_lesson_edit)

        next_sub_edit = QLineEdit(str(page.get("nextSubLessonId") or ""))
        next_sub_edit.setPlaceholderText("可选：指定 subLessonId（需同时设下一课 ID）")
        next_sub_edit.textChanged.connect(
            lambda t: self._set_page_field(page, "nextSubLessonId", t.strip() or None)
        )
        meta.addRow("下一子课 ID：", next_sub_edit)

        meta_wrap = QWidget()
        meta_wrap.setLayout(meta)
        self.right_layout.addWidget(meta_wrap)

        blocks = page.setdefault("blocks", [])
        for idx, block in enumerate(blocks):
            card = _GuideBlockCard(
                self.adapter,
                block,
                can_up=idx > 0,
                can_down=idx < len(blocks) - 1,
            )
            card.changed.connect(self.changed.emit)
            card.move_requested.connect(
                lambda delta, i=idx, p=page: self._on_move_block(p, i, delta)
            )
            card.delete_requested.connect(
                lambda b=block, p=page: self._on_del_block(p, b)
            )
            self.right_layout.addWidget(card)

        add_bar = QHBoxLayout()
        block_combo = QComboBox()
        for bt in GUIDE_BLOCK_TYPES:
            block_combo.addItem(f"{GUIDE_BLOCK_LABELS[bt]} ({bt})", bt)
        add_block_btn = QPushButton("+ 添加内容块")
        add_block_btn.clicked.connect(
            lambda: self._on_add_block(page, str(block_combo.currentData() or "text"))
        )
        add_bar.addWidget(block_combo)
        add_bar.addWidget(add_block_btn)
        add_bar.addStretch()
        bar_wrap = QWidget()
        bar_wrap.setLayout(add_bar)
        self.right_layout.addWidget(bar_wrap)
        self.right_layout.addStretch()

    def _set_page_field(
        self, page: dict[str, Any], field: str, value: Any, *, refresh_list: bool = False
    ) -> None:
        if value is None and field in ("nextLabel", "nextLessonId", "nextSubLessonId"):
            page.pop(field, None)
        else:
            page[field] = value
        if refresh_list:
            cur = self.page_list.currentRow()
            self._refresh_page_list()
            if 0 <= cur < self.page_list.count():
                self.page_list.blockSignals(True)
                self.page_list.setCurrentRow(cur)
                self.page_list.blockSignals(False)
        self.changed.emit()

    def _on_add_page(self) -> None:
        add_guide_page(self.content, f"第 {len(self.pages) + 1} 页")
        self._refresh_page_list()
        self.page_list.setCurrentRow(len(self.pages) - 1)
        self.changed.emit()

    def _on_del_page(self) -> None:
        row = self.page_list.currentRow()
        if not (0 <= row < len(self.pages)):
            return
        page_id = str(self.pages[row].get("id") or "")
        if page_id:
            delete_guide_page(self.content, page_id)
        else:
            del self.pages[row]
        self._refresh_page_list()
        if self.pages:
            self.page_list.setCurrentRow(min(row, len(self.pages) - 1))
        else:
            self._render_empty_right()
        self.changed.emit()

    def _on_move_page(self, delta: int) -> None:
        row = self.page_list.currentRow()
        target = row + delta
        if not (0 <= row < len(self.pages) and 0 <= target < len(self.pages)):
            return
        move_guide_page(self.content, row, target)
        self._refresh_page_list()
        self.page_list.setCurrentRow(target)
        self.changed.emit()

    def _on_add_block(self, page: dict[str, Any], block_type: str) -> None:
        add_guide_block(page, block_type)
        self._refresh_page_list()
        if 0 <= self._current_page_idx < self.page_list.count():
            self.page_list.blockSignals(True)
            self.page_list.setCurrentRow(self._current_page_idx)
            self.page_list.blockSignals(False)
        self._render_page(page)
        self.changed.emit()

    def _on_del_block(self, page: dict[str, Any], block: dict[str, Any]) -> None:
        bid = str(block.get("id") or "")
        if bid:
            delete_guide_block(page, bid)
        elif block in page.get("blocks", []):
            page["blocks"].remove(block)
        self._refresh_page_list()
        if 0 <= self._current_page_idx < self.page_list.count():
            self.page_list.blockSignals(True)
            self.page_list.setCurrentRow(self._current_page_idx)
            self.page_list.blockSignals(False)
        self._render_page(page)
        self.changed.emit()

    def _on_move_block(self, page: dict[str, Any], idx: int, delta: int) -> None:
        blocks = page.get("blocks") or []
        target = idx + delta
        if not (0 <= idx < len(blocks) and 0 <= target < len(blocks)):
            return
        move_guide_block(page, idx, target)
        self._render_page(page)
        self.changed.emit()
