"""Edit-view course-tree sidebar (W3).

``TreeSidebar`` wraps a :class:`CourseTreeWidget` with the design-plan
sidebar anatomy: a ``SearchField`` on top (filters tree nodes by name /
id / 课型）, the tree itself, and a bottom mini toolbar — 新建 ▾ /
上移 / 下移 / 全部折叠 / 全部展开 / 教师过滤 toggle.

The tree keeps its identity: ``host.tree`` still points at the
``CourseTreeWidget``, so every existing selection / refresh / command
API keeps working; the sidebar only owns the chrome around it.
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QHBoxLayout, QMenu, QToolButton, QVBoxLayout, QWidget

from src.icons import icon
from src.widgets.course_tree import CourseTreeWidget
from src.widgets.ui.inputs import SearchField

logger = logging.getLogger(__name__)


class TreeSidebar(QWidget):
    """Course-tree sidebar: SearchField + tree + mini toolbar."""

    def __init__(self, tree: CourseTreeWidget, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setObjectName("TreeSidebar")
        self.tree = tree

        col = QVBoxLayout(self)
        col.setContentsMargins(8, 8, 8, 8)
        col.setSpacing(6)

        # --- top: search filter -----------------------------------------
        self.search = SearchField("过滤课程节点…", parent=self)
        self.search.text_changed_debounced.connect(tree.set_filter)
        # Instant-feel filtering: also apply per keystroke via textChanged
        # (set_filter itself is cheap — a visibility walk, not a rebuild).
        self.search.textChanged.connect(tree.set_filter)
        col.addWidget(self.search)

        # --- middle: the course tree ------------------------------------
        tree.setParent(self)
        col.addWidget(tree, 1)

        # --- bottom: mini toolbar ---------------------------------------
        bar = QHBoxLayout()
        bar.setContentsMargins(0, 0, 0, 0)
        bar.setSpacing(2)

        self.new_btn = self._tool("plus", "新建…（Unit / Lesson）")
        self.new_btn.setPopupMode(QToolButton.ToolButtonPopupMode.InstantPopup)
        new_menu = QMenu(self.new_btn)
        new_menu.addAction("新建 Unit…", self._new_unit)
        new_menu.addAction("新建 Lesson…", self._new_lesson)
        self.new_btn.setMenu(new_menu)
        bar.addWidget(self.new_btn)

        bar.addSpacing(6)

        # Reuse the tree's existing move-button state machine by handing it
        # these buttons (it looks them up as _move_up_btn / _move_down_btn).
        self.move_up_btn = self._tool("chevron-up", "上移（可跨 Unit/Section）")
        self.move_up_btn.clicked.connect(tree._on_move_up_clicked)
        self.move_up_btn.setEnabled(False)
        tree._move_up_btn = self.move_up_btn
        bar.addWidget(self.move_up_btn)

        self.move_down_btn = self._tool("chevron-down", "下移（可跨 Unit/Section）")
        self.move_down_btn.clicked.connect(tree._on_move_down_clicked)
        self.move_down_btn.setEnabled(False)
        tree._move_down_btn = self.move_down_btn
        bar.addWidget(self.move_down_btn)
        tree.currentItemChanged.connect(tree._update_move_buttons)

        bar.addSpacing(6)

        self.collapse_btn = self._tool("chevrons-down-up", "全部折叠")
        self.collapse_btn.clicked.connect(self._collapse_all)
        bar.addWidget(self.collapse_btn)

        self.expand_btn = self._tool("chevrons-up-down", "全部展开")
        self.expand_btn.clicked.connect(self._expand_all)
        bar.addWidget(self.expand_btn)

        bar.addStretch(1)

        # 教师过滤: mirror the global teacher-mode toggle — the tree renders
        # friendly 课型 badges instead of raw type labels when active.
        self.teacher_filter_btn = self._tool(
            "graduation-cap", "教师过滤（课型徽标）"
        )
        self.teacher_filter_btn.setCheckable(True)
        bar.addWidget(self.teacher_filter_btn)

        col.addLayout(bar)

    # ------------------------------------------------------------------

    def _tool(self, icon_name: str, tooltip: str) -> QToolButton:
        btn = QToolButton(self)
        btn.setObjectName("TreeMiniToolButton")
        btn.setIcon(icon(icon_name, size=14, role="muted"))
        btn.setToolTip(tooltip)
        btn.setAutoRaise(True)
        btn.setCursor(Qt.CursorShape.PointingHandCursor)
        return btn

    def _collapse_all(self) -> None:
        self.tree.collapseAll()

    def _expand_all(self) -> None:
        self.tree.expandAll()

    def _new_unit(self) -> None:
        section_id = self._resolve_section_id()
        if section_id is None:
            self._hint("先在树中选中一个 Section（或其中的节点）")
            return
        self.tree._new_unit(section_id)

    def _new_lesson(self) -> None:
        unit_id = self._resolve_unit_id()
        if unit_id is None:
            self._hint("先在树中选中一个 Unit（或其中的 Lesson）")
            return
        self.tree._new_lesson(unit_id)

    def _resolve_section_id(self) -> str | None:
        ref = self._current_ref()
        if ref is None or self.tree.adapter is None:
            return None
        kind, node_id = ref
        try:
            if kind == "section":
                return node_id
            if kind == "unit":
                section, _u = self.tree.adapter.find_unit(node_id)
                return section.get("id")
            if kind == "lesson":
                section, _u, _l = self.tree.adapter.find_lesson(node_id)
                return section.get("id")
        except KeyError:
            return None
        return None

    def _resolve_unit_id(self) -> str | None:
        ref = self._current_ref()
        if ref is None or self.tree.adapter is None:
            return None
        kind, node_id = ref
        try:
            if kind == "unit":
                return node_id
            if kind == "lesson":
                _s, unit, _l = self.tree.adapter.find_lesson(node_id)
                return unit.get("id")
        except KeyError:
            return None
        return None

    def _current_ref(self) -> tuple[str, str] | None:
        item = self.tree.currentItem()
        if item is None:
            return None
        ref = item.data(0, 0x0100)
        return ref if isinstance(ref, tuple) else None

    def _hint(self, message: str) -> None:
        win = self.window()
        try:
            win.statusBar().showMessage(message, 4000)
        except Exception:
            logger.debug("tree_sidebar hint failed", exc_info=True)


__all__ = ["TreeSidebar"]
