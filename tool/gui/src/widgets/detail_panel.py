"""Right-side detail panel container: switches form by selected node kind."""
from __future__ import annotations

import contextlib
import logging
from typing import Any

from PySide6.QtCore import Qt, QSettings, Signal
from PySide6.QtGui import QUndoStack
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QMenu,
    QPushButton,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from src.backend.ai import AiApiConfig

logger = logging.getLogger(__name__)
from src.application.settings import APP_NAME, ORG_NAME
from src.backend.course_adapter import CourseAdapter
from src.backend.lesson_presets import FUNCTIONAL_TEMPLATES
from src.icons import icon
from src.widgets.metadata_form import MetadataForm
from src.widgets.lesson_blueprint import LessonBlueprint
from src.widgets.lesson_editor import LessonEditor

#: Per-kind QSettings keys remembering the user's last manual collapse choice.
_META_COLLAPSE_KEYS = {
    "lesson": "edit/meta_collapsed_lesson",
    "node": "edit/meta_collapsed_node",
}


def build_teacher_widget(
    adapter: CourseAdapter,
    section: dict[str, Any],
    unit: dict[str, Any],
    lesson: dict[str, Any],
    parent: QWidget,
    undo_stack: QUndoStack | None,
    ai_config: AiApiConfig | None,
) -> QWidget:
    """Construct the teacher-view widget for a lesson based on its template.

    Used by ``DetailPanel.show_teacher_lesson`` so the template dispatch
    lives in one place. The caller is responsible for connecting
    ``widget.changed`` to the appropriate change-listener and for wrapping
    the widget in a ``QScrollArea`` if desired.
    """
    from src.teacher.sublesson_flow import SubLessonFlowWidget
    from src.teacher.template_editors import (
        ListeningTeacherWidget,
        MasteryTeacherWidget,
        ReadingTeacherWidget,
    )

    template = lesson.get("template", "legacy")
    if template in ("listening",):
        widget: QWidget = ListeningTeacherWidget(adapter, section, unit, lesson, parent, undo_stack, ai_config)
    elif template in ("reading",):
        widget = ReadingTeacherWidget(adapter, section, unit, lesson, parent, undo_stack, ai_config)
    elif template in ("mastery",):
        widget = MasteryTeacherWidget(adapter, section, unit, lesson, parent, undo_stack, ai_config)
    else:
        widget = SubLessonFlowWidget(adapter, section, unit, lesson, parent, undo_stack, ai_config)
    return widget


class DetailPanel(QWidget):
    """Container that shows the metadata form + content editor for a node.

    W3 layout: ``ViewHeader`` (node title + breadcrumb + kind pill +
    保存/AI编辑/重命名/⋮ actions) on top, then ``编辑 | 预览 | JSON`` tabs.
    The 编辑 tab holds the original ``splitter`` (MetadataForm | content).
    The legacy ``breadcrumb`` / ``title`` labels stay updated for
    compatibility but are hidden — the ViewHeader renders them now.
    """

    tree_changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        from src.widgets.json_editor import JsonEditor
        from src.widgets.ui.badges import Pill
        from src.widgets.ui.buttons import TurnaButton
        from src.widgets.ui.containers import ViewHeader

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # --- ViewHeader: title + breadcrumb + kind pill + actions --------
        self.view_header = ViewHeader("编辑", self)
        self.kind_pill = Pill("", parent=self.view_header)
        self.kind_pill.setVisible(False)
        # Insert the pill right after the breadcrumb context (index 2 =
        # before the stretch + action group).
        self.view_header.layout().insertWidget(2, self.kind_pill)

        self.hdr_save_btn = TurnaButton(
            "保存", variant="primary", size="sm", icon_name="save"
        )
        self.hdr_save_btn.setToolTip("保存课程（Ctrl+S）")
        self.hdr_save_btn.clicked.connect(self._on_header_save)
        self.hdr_ai_btn = TurnaButton(
            "AI 编辑", variant="secondary", size="sm", icon_name="sparkles"
        )
        self.hdr_ai_btn.clicked.connect(self._on_header_ai_edit)
        self.hdr_rename_btn = TurnaButton(
            "", variant="ghost", size="sm", icon_name="pencil"
        )
        self.hdr_rename_btn.setToolTip("重命名（F2）")
        self.hdr_rename_btn.clicked.connect(self._on_header_rename)
        self.hdr_more_btn = TurnaButton(
            "", variant="ghost", size="sm", icon_name="more-horizontal"
        )
        self.hdr_more_btn.setToolTip("更多节点操作")
        self.hdr_more_btn.clicked.connect(self._on_header_more)
        for btn in (
            self.hdr_save_btn,
            self.hdr_ai_btn,
            self.hdr_rename_btn,
            self.hdr_more_btn,
        ):
            self.view_header.add_action(btn)
        layout.addWidget(self.view_header)

        # Legacy labels — kept updated for compat, hidden since W3.
        self.breadcrumb = QLabel("编辑内容")
        self.breadcrumb.setObjectName("breadcrumbLabel")
        self.breadcrumb.setVisible(False)
        layout.addWidget(self.breadcrumb)

        self.title = QLabel("选择左侧节点开始编辑")
        self.title.setObjectName("titleLabel")
        self.title.setVisible(False)
        layout.addWidget(self.title)

        # --- 编辑 | 预览 | JSON tabs --------------------------------------
        self.detail_tabs = QTabWidget(self)
        self.detail_tabs.setObjectName("DetailTabs")
        self.detail_tabs.setDocumentMode(True)

        edit_page = QWidget(self.detail_tabs)
        edit_col = QVBoxLayout(edit_page)
        edit_col.setContentsMargins(16, 16, 16, 16)
        edit_col.setSpacing(10)

        # W4: the 属性 form sits under a collapsible header instead of a
        # permanent inner splitter — the content editor gets the full width,
        # and there is one less divider to fight with (the outer
        # tree|detail splitter remains). Lessons start collapsed (content
        # is the main task), sections/units start expanded; the user's
        # last choice is remembered per kind in QSettings.
        self._meta_collapsed = False
        self.meta_toggle = QPushButton("属性")
        self.meta_toggle.setObjectName("MetaCollapseHeader")
        self.meta_toggle.setToolTip("展开 / 收起属性表单（ID · 名称 · 描述 · 先修 · 语法关联）")
        self.meta_toggle.setCursor(Qt.CursorShape.PointingHandCursor)
        self.meta_toggle.clicked.connect(self._on_meta_toggle_clicked)
        edit_col.addWidget(self.meta_toggle)

        self.form = MetadataForm(title="")
        edit_col.addWidget(self.form)

        self.content_host = QWidget()
        self.content_layout = QVBoxLayout(self.content_host)
        self.content_layout.setContentsMargins(0, 0, 0, 0)
        self.content_layout.setSpacing(12)
        edit_col.addWidget(self.content_host, 1)
        self.detail_tabs.addTab(edit_page, "编辑")

        self.preview_tab = QWidget(self.detail_tabs)
        self._preview_layout = QVBoxLayout(self.preview_tab)
        self._preview_layout.setContentsMargins(0, 0, 0, 0)
        self._preview_layout.setSpacing(0)
        self.detail_tabs.addTab(self.preview_tab, "预览")

        self.json_tab = QWidget(self.detail_tabs)
        json_col = QVBoxLayout(self.json_tab)
        json_col.setContentsMargins(12, 12, 12, 12)
        json_col.setSpacing(8)
        json_hint = QLabel("直接编辑节点 JSON — id 不可修改；应用会走撤销栈。")
        json_hint.setWordWrap(True)
        json_col.addWidget(json_hint)
        self.json_editor = JsonEditor(self.json_tab)
        json_col.addWidget(self.json_editor, 1)
        json_bar = QHBoxLayout()
        json_bar.addStretch(1)
        self.json_format_btn = TurnaButton("格式化", variant="ghost", size="sm")
        self.json_format_btn.clicked.connect(self.json_editor.format)
        self.json_apply_btn = TurnaButton(
            "应用 JSON", variant="primary", size="sm", icon_name="check"
        )
        self.json_apply_btn.clicked.connect(self._apply_json)
        json_bar.addWidget(self.json_format_btn)
        json_bar.addWidget(self.json_apply_btn)
        json_col.addLayout(json_bar)
        self.detail_tabs.addTab(self.json_tab, "JSON")

        layout.addWidget(self.detail_tabs, 1)

        self.adapter: CourseAdapter | None = None
        self.ai_config: AiApiConfig = AiApiConfig()
        self._current_content_widget: QWidget | None = None
        self._resource_listener = self._on_resources_changed
        self._meta_connection = None
        # W3 aux-tab state: (adapter, kind, node_id, node_dict) for the
        # preview / JSON tabs, plus per-node "built-for" keys so in-progress
        # preview answers and JSON edits survive tab switches.
        self._node_context: tuple | None = None
        self._aux_node_key: tuple[str, str] | None = None
        self._preview_built_for: tuple[str, str] | None = None
        self._json_built_for: tuple[str, str] | None = None
        self.detail_tabs.currentChanged.connect(self._on_tab_changed)
        self._update_header_actions()

    def clear_content(self) -> None:
        while self.content_layout.count():
            child = self.content_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()
        self._current_content_widget = None

    def _attach_adapter(self, adapter: CourseAdapter) -> None:
        """Swap the resource-change listener to the new adapter (A3)."""
        if self.adapter is adapter and adapter is not None:
            return
        if self.adapter is not None:
            self.adapter.remove_resource_listener(self._resource_listener)
        self.adapter = adapter
        if adapter is not None:
            adapter.add_resource_listener(self._resource_listener)

    def _inject_form_undo_stack(self) -> None:
        """Give the metadata form access to the shared undo stack and wire its
        metadata_changed signal to tree_changed so the tree title updates."""
        stack = getattr(self, "undo_stack", None)
        self.form.undo_stack = stack
        if self._meta_connection is not None:
            try:
                self.form.metadata_changed.disconnect(self._meta_connection)
            except (TypeError, RuntimeError):
                logger.debug("widgets/detail_panel.py:120 best-effort step failed", exc_info=True)
            self._meta_connection = None
        self._meta_connection = self.form.metadata_changed.connect(self.tree_changed.emit)

    def _on_resources_changed(self) -> None:
        """Resource lists changed; refresh the current content widget's
        reference dropdowns in place instead of reloading the whole node."""
        widget = self._current_content_widget
        if widget is None:
            return
        refresh = getattr(widget, "refresh_references", None)
        if callable(refresh):
            try:
                refresh()
            except Exception:
                logger.exception("refresh_references failed for %r", widget)

    def show_node(self, adapter: CourseAdapter, node_ref: tuple[str, str]) -> None:
        self._attach_adapter(adapter)
        self._inject_form_undo_stack()
        kind, node_id = node_ref
        self.clear_content()
        self._prepare_for_node(node_ref)
        self._apply_meta_collapsed(kind)
        try:
            if kind == "section":
                section = adapter.find_section(node_id)
                self.form.show_section(adapter, section)
                self.title.setText(section.get("name", node_id))
                self.breadcrumb.setText("编辑内容  ›  Section")
                self._node_context = (adapter, kind, node_id, section)
                self._sync_view_header(
                    kind, section.get("name", node_id), [section.get("name", "")]
                )
            elif kind == "unit":
                _section, unit = adapter.find_unit(node_id)
                self.form.show_unit(adapter, unit)
                self.title.setText(unit.get("name", node_id))
                self.breadcrumb.setText(
                    f"编辑内容  ›  {_section.get('name', '')}  ›  Unit"
                )
                self._node_context = (adapter, kind, node_id, unit)
                self._sync_view_header(
                    kind,
                    unit.get("name", node_id),
                    [_section.get("name", ""), unit.get("name", "")],
                )
            elif kind == "lesson":
                section, unit, lesson = adapter.find_lesson(node_id)
                self.form.show_lesson(adapter, lesson)
                self.title.setText(lesson.get("name", node_id))
                self.breadcrumb.setText(
                    f"编辑内容  ›  {section.get('name', '')}  /  "
                    f"{unit.get('name', '')}  /  {lesson.get('name', '')}"
                )
                self._node_context = (adapter, kind, node_id, lesson)
                self._sync_view_header(
                    kind,
                    lesson.get("name", node_id),
                    [
                        section.get("name", ""),
                        unit.get("name", ""),
                        lesson.get("name", ""),
                    ],
                )
                container = self._build_lesson_content(adapter, section, unit, lesson)
                self.content_layout.addWidget(container)
        except KeyError:
            self._node_context = None
            self.title.setText(f"未找到节点: {node_id}")
            self.breadcrumb.setText("编辑内容")
            self._sync_view_header(kind, f"未找到节点: {node_id}", [])
            return
        self._update_header_actions()

    # --- lesson view toggle (蓝图 / 高级编辑) ---------------------------

    def _build_lesson_content(
        self,
        adapter: CourseAdapter,
        section: dict[str, Any],
        unit: dict[str, Any],
        lesson: dict[str, Any],
    ) -> QWidget:
        """Build the lesson content host with a 蓝图/高级编辑 view toggle.

        Functional templates (listening/reading/mastery) default to the
        blueprint; others default to the advanced LessonEditor. Both views
        read from the same lesson dict so they stay in sync across toggles.
        """
        container = QWidget()
        v = QVBoxLayout(container)
        v.setContentsMargins(0, 0, 0, 0)
        v.setSpacing(8)

        template = lesson.get("template", "legacy")
        self._lesson_view_mode = "blueprint" if template in FUNCTIONAL_TEMPLATES else "advanced"
        self._lesson_context = (adapter, section, unit, lesson)

        bar = QHBoxLayout()
        bar.setContentsMargins(0, 0, 0, 0)
        bar.setSpacing(6)
        self._blueprint_btn = QPushButton("蓝图")
        self._advanced_btn = QPushButton("高级编辑")
        # Segmented pair — the :checked state is styled in shell QSS so the
        # active view is actually visible (plain QPushButtons showed none).
        self._blueprint_btn.setObjectName("LessonViewToggle")
        self._advanced_btn.setObjectName("LessonViewToggle")
        self._blueprint_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self._advanced_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self._blueprint_btn.setCheckable(True)
        self._advanced_btn.setCheckable(True)
        self._blueprint_btn.setChecked(self._lesson_view_mode == "blueprint")
        self._advanced_btn.setChecked(self._lesson_view_mode == "advanced")
        self._blueprint_btn.clicked.connect(self._on_blueprint_view_clicked)
        self._advanced_btn.clicked.connect(self._on_advanced_view_clicked)
        bar.addWidget(self._blueprint_btn)
        bar.addWidget(self._advanced_btn)
        bar.addStretch()
        v.addLayout(bar)

        self._lesson_view_host = QWidget()
        self._lesson_view_layout = QVBoxLayout(self._lesson_view_host)
        self._lesson_view_layout.setContentsMargins(0, 0, 0, 0)
        v.addWidget(self._lesson_view_host, 1)

        self._render_lesson_view()
        return container

    def _on_blueprint_view_clicked(self) -> None:
        self._set_lesson_view("blueprint")

    def _on_advanced_view_clicked(self) -> None:
        self._set_lesson_view("advanced")

    def _set_lesson_view(self, mode: str) -> None:
        if mode == self._lesson_view_mode:
            # Clicking the already-active toggle flips its checkable state
            # off — re-assert the pair so exactly one stays lit.
            self._blueprint_btn.setChecked(mode == "blueprint")
            self._advanced_btn.setChecked(mode == "advanced")
            return
        self._lesson_view_mode = mode
        self._blueprint_btn.setChecked(mode == "blueprint")
        self._advanced_btn.setChecked(mode == "advanced")
        self._render_lesson_view()

    def _render_lesson_view(self) -> None:
        while self._lesson_view_layout.count():
            child = self._lesson_view_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()
        adapter, _section, _unit, lesson = self._lesson_context
        if self._lesson_view_mode == "blueprint":
            widget = LessonBlueprint(
                adapter, lesson, undo_stack=getattr(self, "undo_stack", None), read_only=False
            )
            widget.changed.connect(self.tree_changed.emit)
        else:
            widget = LessonEditor(adapter, lesson)
        self._lesson_view_layout.addWidget(widget)
        self._current_content_widget = widget

    def show_teacher_lesson(
        self,
        adapter: CourseAdapter,
        section: dict[str, Any],
        unit: dict[str, Any],
        lesson: dict[str, Any],
    ) -> None:
        """Show the teacher-view widget for this lesson's template."""
        from PySide6.QtWidgets import QScrollArea

        self._attach_adapter(adapter)
        self._inject_form_undo_stack()
        self.clear_content()
        self._prepare_for_node(("lesson", lesson.get("id", "")))
        self._apply_meta_collapsed("lesson")
        self.form.show_lesson(adapter, lesson)
        self.title.setText(lesson.get("name", lesson.get("id", "")))
        self.breadcrumb.setText(
            f"编辑内容  ›  {section.get('name', '')}  /  "
            f"{unit.get('name', '')}  /  {lesson.get('name', '')}"
        )
        self._node_context = (adapter, "lesson", lesson.get("id", ""), lesson)
        self._sync_view_header(
            "lesson",
            lesson.get("name", lesson.get("id", "")),
            [section.get("name", ""), unit.get("name", ""), lesson.get("name", "")],
        )
        self._update_header_actions()

        undo_stack = getattr(self, "undo_stack", None)
        ai_config = getattr(self, "ai_config", None)
        widget = build_teacher_widget(
            adapter, section, unit, lesson, self, undo_stack, ai_config
        )

        widget.changed.connect(self.tree_changed.emit)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(widget)
        self.content_layout.addWidget(scroll)
        self._current_content_widget = widget

    # --- W4: collapsible 属性 section ------------------------------------

    def _on_meta_toggle_clicked(self) -> None:
        self._set_meta_collapsed(not self._meta_collapsed)

    def _apply_meta_collapsed(self, kind: str) -> None:
        """Set the collapse state for a freshly shown node.

        Falls back to the user's remembered choice for this kind, then to
        the per-kind default (lessons collapsed — content is the main task;
        sections/units expanded — metadata is all they have).
        """
        collapsed = self._load_meta_collapsed(kind)
        if collapsed is None:
            collapsed = kind == "lesson"
        self._set_meta_collapsed(collapsed, persist=False)

    def _set_meta_collapsed(self, collapsed: bool, *, persist: bool = True) -> None:
        self._meta_collapsed = collapsed
        self.form.setVisible(not collapsed)
        self.meta_toggle.setIcon(
            icon("chevron-right" if collapsed else "chevron-down", size=14, role="secondary")
        )
        if not persist:
            return
        ctx = self._node_context
        key = _META_COLLAPSE_KEYS["lesson" if (ctx and ctx[1] == "lesson") else "node"]
        with contextlib.suppress(Exception):
            QSettings(ORG_NAME, APP_NAME).setValue(key, collapsed)

    @staticmethod
    def _load_meta_collapsed(kind: str) -> bool | None:
        """Remembered collapse choice for *kind* (None = never chosen)."""
        key = _META_COLLAPSE_KEYS["lesson" if kind == "lesson" else "node"]
        with contextlib.suppress(Exception):
            val = QSettings(ORG_NAME, APP_NAME).value(key, None)
            if isinstance(val, bool):
                return val
            if isinstance(val, str):
                return val.lower() in ("true", "1", "yes")
        return None

    def reveal_metadata(self) -> None:
        """Expand the 属性 section and focus the name field (F2 rename)."""
        if self._meta_collapsed:
            self._set_meta_collapsed(False)
        self.form.focus_name()

    # --- W3: ViewHeader + aux tabs (预览 / JSON) -------------------------

    def _prepare_for_node(self, node_ref: tuple[str, str]) -> None:
        """Reset aux-tab state when a *different* node is selected.

        Switching nodes returns the user to the 编辑 tab and invalidates
        the preview/JSON "built-for" keys so the next visit rebuilds from
        the new node. Re-rendering the same node (e.g. after JSON apply)
        keeps the current tab and any in-progress aux content.
        """
        key = (node_ref[0], node_ref[1])
        if key == self._aux_node_key:
            return
        self._aux_node_key = key
        self._preview_built_for = None
        self._json_built_for = None
        self.detail_tabs.setCurrentIndex(0)

    def _sync_view_header(
        self,
        kind: str,
        title: str,
        crumbs: list[str],
    ) -> None:
        """Mirror node identity into the ViewHeader (title/crumbs/pill)."""
        self.view_header.set_title(title or "编辑")
        self.view_header.set_breadcrumb(crumbs)
        if kind == "lesson":
            tmpl = ""
            if self._node_context is not None:
                tmpl = str(self._node_context[3].get("template", "") or "")
            from src.backend.lesson_content import TEMPLATE_COLORS, TEMPLATE_LABELS

            label = TEMPLATE_LABELS.get(tmpl, tmpl or "lesson")
            self.kind_pill.set_color(
                TEMPLATE_COLORS.get(tmpl, TEMPLATE_COLORS.get("legacy", "#888888"))
            )
            self.kind_pill.setText(label)
            self.kind_pill.setVisible(True)
        elif kind in ("section", "unit"):
            self.kind_pill.set_variant("muted")
            self.kind_pill.setText(kind)
            self.kind_pill.setVisible(True)
        else:
            self.kind_pill.setVisible(False)

    def _update_header_actions(self) -> None:
        has_node = self._node_context is not None
        self.hdr_ai_btn.setEnabled(has_node)
        self.hdr_rename_btn.setEnabled(has_node)
        self.hdr_more_btn.setEnabled(has_node)

    def _status_msg(self, text: str, ms: int = 5000) -> None:
        try:
            self.window().statusBar().showMessage(text, ms)
        except Exception:
            logger.debug("detail_panel status failed", exc_info=True)

    def _on_header_save(self) -> None:
        action = getattr(self.window(), "save_action", None)
        if action is not None:
            action.trigger()

    def _on_header_ai_edit(self) -> None:
        ctx = self._node_context
        handler = getattr(self.window(), "_on_ai_edit", None)
        if ctx is not None and callable(handler):
            handler(ctx[1], ctx[2])

    def _on_header_rename(self) -> None:
        ctx = self._node_context
        handler = getattr(self.window(), "_on_rename_requested", None)
        if ctx is not None and callable(handler):
            handler(ctx[1], ctx[2])

    def _on_header_more(self) -> None:
        ctx = self._node_context
        tree = getattr(self.window(), "tree", None)
        if ctx is None or tree is None:
            return
        _adapter, kind, node_id, _node = ctx
        menu = QMenu(self)
        if kind == "lesson":
            menu.addAction("复制 Lesson", lambda: tree._duplicate_lessons([node_id]))
            menu.addAction("删除 Lesson", lambda: tree._delete_lesson(node_id))
        elif kind == "unit":
            menu.addAction("新建 Lesson", lambda: tree._new_lesson(node_id))
            menu.addAction("删除 Unit", lambda: tree._delete_unit(node_id))
        elif kind == "section":
            menu.addAction("新建 Unit", lambda: tree._new_unit(node_id))
            menu.addAction("删除 Section", lambda: tree._delete_section(node_id))
        if not menu.isEmpty():
            menu.exec(self.hdr_more_btn.mapToGlobal(self.hdr_more_btn.rect().bottomLeft()))

    def _on_tab_changed(self, index: int) -> None:
        if index == 1:
            self._render_preview_tab()
        elif index == 2:
            self._render_json_tab()

    def _clear_layout(self, layout: QVBoxLayout) -> None:
        while layout.count():
            child = layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.setParent(None)
                widget.deleteLater()

    def _render_preview_tab(self) -> None:
        ctx = self._node_context
        key = (ctx[1], ctx[2]) if ctx is not None else None
        if key == self._preview_built_for and self._preview_layout.count():
            return
        self._clear_layout(self._preview_layout)
        if ctx is None or ctx[1] != "lesson":
            from src.widgets.ui.containers import EmptyState

            self._preview_layout.addWidget(
                EmptyState(
                    icon_name="eye",
                    title="预览仅适用于课时节点",
                    description="在课程树中选中一个 Lesson，即可在这里试做题目。",
                    parent=self.preview_tab,
                ),
                1,
            )
        else:
            from PySide6.QtWidgets import QScrollArea

            from src.teacher.preview_window import LessonPreviewWidget

            adapter, _kind, _node_id, lesson = ctx
            scroll = QScrollArea(self.preview_tab)
            scroll.setWidgetResizable(True)
            scroll.setFrameShape(QScrollArea.Shape.NoFrame)
            scroll.setWidget(LessonPreviewWidget(adapter, lesson, scroll))
            self._preview_layout.addWidget(scroll, 1)
        self._preview_built_for = key

    def _render_json_tab(self) -> None:
        ctx = self._node_context
        if ctx is None:
            self.json_editor.setPlainText("")
            self.json_apply_btn.setEnabled(False)
            self._json_built_for = None
            return
        key = (ctx[1], ctx[2])
        # Same node still shown → keep in-progress JSON edits untouched.
        if key == self._json_built_for:
            return
        self.json_editor.set_json(ctx[3])
        self.json_apply_btn.setEnabled(True)
        self._json_built_for = key

    def _apply_json(self) -> None:
        ctx = self._node_context
        undo_stack = getattr(self, "undo_stack", None)
        if ctx is None or undo_stack is None:
            self._status_msg("没有可应用的节点")
            return
        adapter, kind, node_id, _node = ctx
        try:
            data = self.json_editor.to_json()
        except ValueError as exc:
            self._status_msg(str(exc))
            return
        if not isinstance(data, dict):
            self._status_msg("JSON 必须是对象（{…}）")
            return
        from src.application.commands import ReplaceNodeDataCommand

        try:
            cmd = ReplaceNodeDataCommand(adapter, kind, node_id, data)
        except ValueError as exc:
            self._status_msg(str(exc))
            return
        cmd.signals.changed.connect(self.tree_changed.emit)
        undo_stack.push(cmd)
        self._status_msg("已应用 JSON 修改（Ctrl+Z 可撤销）")
        # Re-render the 编辑 tab through the host's normal (teacher-aware)
        # path so the form reflects the applied data.
        win = self.window()
        resel = getattr(win, "_on_node_selected", None)
        if callable(resel) and getattr(win, "_current_node_ref", None) == (kind, node_id):
            try:
                resel((kind, node_id))
            except Exception:
                logger.debug("detail_panel re-select failed", exc_info=True)
