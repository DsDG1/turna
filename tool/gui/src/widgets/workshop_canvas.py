"""WorkshopCanvas: the four-stage workshop canvas (素材 / 知识 / 草稿 / 导入).

Replaces the three-column :class:`~src.widgets.unified_workspace.UnifiedWorkspaceWidget`.
Each stage now owns the whole surface instead of sharing a three-pane splitter,
so 草稿 can give the chat the full width — the reason the old layout had to
clamp the chip strip to 48 px and squeeze the chat into a stacked tab.

Everything that is *data* is carried over unchanged: bubble-pool reconcile,
the generate chain, the focus summary, per-project UI state, banner copy. Only
the shell and the stage navigation are new.
"""
from __future__ import annotations

import logging
from typing import Any

from PySide6.QtCore import Qt, QSettings, QTimer, Signal
from PySide6.QtWidgets import (
    QDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSplitter,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from src.application.settings import APP_NAME, ORG_NAME
from src.backend.grounded_stats import format_pool_summary
from src.theme import current_palette
from src.theme_tokens import BRAND_TEAL
from src.widgets.ai_orbit import AiOrbitWidget
from src.widgets.flow_layout import FlowLayout
from src.widgets.knowledge_bubble import KnowledgeBubble

logger = logging.getLogger(__name__)

_BUBBLE_POOL_LIMIT = 200
_BUBBLE_DEBOUNCE_MS = 60
_TIPS_DISMISSED_KEY = "workshop/canvas_tips_dismissed"
_UI_PREFIX = "workshop/ui"

#: Stage ids, in header-checklist order. Persisted by name (not index) so
#: reordering stages cannot silently point a saved session at the wrong page.
STAGE_MATERIAL = "material"
STAGE_KNOWLEDGE = "knowledge"
STAGE_DRAFT = "draft"
STAGE_IMPORT = "import"
STAGES = (STAGE_MATERIAL, STAGE_KNOWLEDGE, STAGE_DRAFT, STAGE_IMPORT)

#: Stages that own the textbook-extraction panel; leaving them while extraction
#: runs needs a confirmation.
_EXTRACTION_STAGES = (STAGE_MATERIAL, STAGE_KNOWLEDGE)


def _bubble_key(resource_type: str, entry: dict, chapter_index: int = -1) -> str:
    """Stable id for bubble pool reconcile (prefer entry id, else term+chapter)."""
    eid = entry.get("id")
    if eid:
        return f"{resource_type}:{eid}"
    term = entry.get("term") or entry.get("title") or ""
    return f"{resource_type}:{chapter_index}:{term}"


class WorkshopCanvas(QWidget):
    """Four-stage authoring canvas for one textbook/AI project.

    Stage surfaces:
      * 素材 — the textbook import source page (file pick / drop / chapters)
      * 知识 — knowledge review page + the bubble pool side panel
      * 草稿 — param band (AI orbit) + full-width design chat
      * 导入 — structural outline + section import

    Constructor signature and the public helpers the window drives
    (``save_ui_state`` / ``flush_bubble_refresh`` / ``focus_*``) are the
    compatibility surface; see WorkshopWindow for the shell that hosts it.
    """

    design_focus_requested = Signal()
    #: Emitted with the new stage id whenever the canvas switches stage.
    stage_changed = Signal(str)

    def __init__(
        self,
        adapter: Any,
        import_panel: Any,
        design_panel: Any,
        review_panel: Any,
        parent: QWidget | None = None,
        *,
        blank: bool = False,
        project_id: str = "",
    ) -> None:
        super().__init__(parent)
        self.adapter = adapter
        self.import_panel = import_panel
        self.design_panel = design_panel
        self.review_panel = review_panel
        self._blank = blank
        self._project_id = project_id or ""
        self._had_knowledge_rows = False
        self._auto_switched_to_knowledge = False
        self._bubble_widgets: dict[str, KnowledgeBubble] = {}
        self._bubble_refresh_timer = QTimer(self)
        self._bubble_refresh_timer.setSingleShot(True)
        self._bubble_refresh_timer.setInterval(_BUBBLE_DEBOUNCE_MS)
        self._bubble_refresh_timer.timeout.connect(self.refresh_bubble_pool)
        self._pool_popup: QDialog | None = None
        self._stage = STAGE_MATERIAL

        self._build_ui()
        self._wire_signals()
        self._init_orbit_params()
        self.refresh_bubble_pool()
        self._apply_default_stage()
        self.restore_ui_state()
        self._update_banner()
        # Snapshot whether knowledge already exists (resume).
        self._had_knowledge_rows = self._knowledge_row_count() > 0

    # ------------------------------------------------------------------ UI
    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self._banner = self._build_banner()
        layout.addWidget(self._banner)

        self._stages = QStackedWidget()
        self._stage_widgets: dict[str, QWidget] = {}

        # 摘页手术: grab all three page references BEFORE removing any of them.
        # removeWidget() re-indexes the stack, so fetching page 2 after two
        # removals silently returns None.
        self._source_page = self.import_panel._stack.widget(0)
        self._knowledge_page = self.import_panel._stack.widget(1)
        self._import_page = self.import_panel._stack.widget(2)
        for page in (self._source_page, self._knowledge_page, self._import_page):
            self.import_panel._stack.removeWidget(page)

        self._add_stage(STAGE_MATERIAL, self._build_material_stage())
        self._add_stage(STAGE_KNOWLEDGE, self._build_knowledge_stage())
        self._add_stage(STAGE_DRAFT, self._build_draft_stage())
        self._add_stage(STAGE_IMPORT, self._build_import_stage())
        layout.addWidget(self._stages, 1)

    def _add_stage(self, name: str, widget: QWidget) -> None:
        self._stage_widgets[name] = widget
        self._stages.addWidget(widget)

    @staticmethod
    def _page_shell(page: QWidget) -> QWidget:
        """Re-parent a page ripped out of ``TextbookImportDialog._stack``."""
        holder = QWidget()
        lay = QVBoxLayout(holder)
        lay.setContentsMargins(0, 0, 0, 0)
        lay.addWidget(page)
        return holder

    def _build_material_stage(self) -> QWidget:
        stage = QWidget()
        lay = QVBoxLayout(stage)
        lay.setContentsMargins(6, 6, 6, 6)
        lay.addWidget(self._page_shell(self._source_page))
        return stage

    def _build_knowledge_stage(self) -> QWidget:
        stage = QWidget()
        lay = QVBoxLayout(stage)
        lay.setContentsMargins(6, 6, 6, 6)

        if hasattr(self.import_panel, "_design_btn"):
            self.import_panel._design_btn.setVisible(False)

        self._knowledge_splitter = QSplitter(
            Qt.Orientation.Horizontal, stage
        )
        self._knowledge_splitter.addWidget(self._page_shell(self._knowledge_page))
        self._knowledge_splitter.addWidget(self._build_pool_panel())
        # ~70% review page, ~30% pool side panel.
        self._knowledge_splitter.setStretchFactor(0, 7)
        self._knowledge_splitter.setStretchFactor(1, 3)
        lay.addWidget(self._knowledge_splitter)
        return stage

    def _build_pool_panel(self) -> QWidget:
        panel = QWidget()
        bp_lay = QVBoxLayout(panel)
        bp_lay.setContentsMargins(4, 0, 0, 0)
        self._bubble_desc = QLabel("勾选审校表中的知识点后，会出现在这里。")
        self._bubble_desc.setWordWrap(True)
        self._bubble_desc.setStyleSheet("font-size: 11px; opacity: 0.8; margin: 4px;")
        bp_lay.addWidget(self._bubble_desc)

        orbit_row = QHBoxLayout()
        self._add_to_orbit_btn = QPushButton("将选中词加入轨道")
        self._add_to_orbit_btn.setToolTip(
            "把知识点审校表中当前选中的行加入 AI 轨道（无需拖拽）"
        )
        self._add_to_orbit_btn.clicked.connect(self.add_selected_to_orbit)
        orbit_row.addWidget(self._add_to_orbit_btn)
        orbit_row.addStretch(1)
        bp_lay.addLayout(orbit_row)

        self.bubble_pool_area = QScrollArea()
        self.bubble_pool_area.setWidgetResizable(True)
        self.bubble_pool_area.setFrameShape(QScrollArea.Shape.NoFrame)
        self.bubble_pool_container = QWidget()
        self.bubble_pool_layout = FlowLayout(self.bubble_pool_container, spacing=8)
        self.bubble_pool_area.setWidget(self.bubble_pool_container)
        bp_lay.addWidget(self.bubble_pool_area, 1)
        return panel

    def _build_draft_stage(self) -> QWidget:
        stage = QWidget()
        lay = QVBoxLayout(stage)
        lay.setContentsMargins(6, 6, 6, 6)
        lay.setSpacing(6)

        self.orbit_widget = AiOrbitWidget(stage)
        # Cross-stage dragging is impossible, so the pool is reachable as a
        # modeless popover whose chips can still be dragged into the band.
        self._pool_popup_btn = QPushButton("气泡池＋")
        self._pool_popup_btn.setToolTip(
            "打开气泡池弹层：把里面的气泡拖入上方轨道聚焦生成"
        )
        self._pool_popup_btn.clicked.connect(self._open_pool_popup)
        self.orbit_widget.add_action_widget(self._pool_popup_btn)
        lay.addWidget(self.orbit_widget)
        lay.addWidget(self.design_panel, 1)
        return stage

    def _build_import_stage(self) -> QWidget:
        stage = QWidget()
        lay = QVBoxLayout(stage)
        lay.setContentsMargins(6, 6, 6, 6)

        self._import_splitter = QSplitter(Qt.Orientation.Horizontal, stage)
        self._import_splitter.addWidget(self.review_panel)
        self._import_splitter.addWidget(self._page_shell(self._import_page))
        # ~55% outline, ~45% import.
        self._import_splitter.setStretchFactor(0, 55)
        self._import_splitter.setStretchFactor(1, 45)
        lay.addWidget(self._import_splitter)
        return stage

    def _build_banner(self) -> QFrame:
        banner = QFrame()
        banner.setObjectName("canvasBanner")
        pal = current_palette()
        banner.setStyleSheet(
            f"QFrame#canvasBanner {{"
            f"  background-color: {pal.get('ai_card_bg', '#1F232C')};"
            f"  border: 1px solid {pal.get('ai_accent_border', BRAND_TEAL)};"
            f"  border-radius: 8px;"
            f"}}"
        )
        row = QHBoxLayout(banner)
        row.setContentsMargins(10, 6, 10, 6)
        self._banner_label = QLabel("")
        self._banner_label.setWordWrap(True)
        self._banner_label.setStyleSheet("border: none; font-size: 12px;")
        row.addWidget(self._banner_label, 1)
        dismiss = QPushButton("知道了")
        dismiss.setFlat(True)
        dismiss.clicked.connect(self._dismiss_banner)
        row.addWidget(dismiss)
        banner.setVisible(False)
        return banner

    def _wire_signals(self) -> None:
        self.orbit_widget.generate_requested.connect(self._on_generate_clicked)
        self.orbit_widget.chat_requested.connect(self.focus_design_chat)
        self.orbit_widget.focus_changed.connect(self._update_focus_summary)
        self.import_panel._review_table.rows_changed.connect(self._on_rows_changed)
        self.design_panel.busy_changed.connect(self._on_design_busy)
        self.design_panel.draft_ready.connect(self._on_draft_ready)

    def _init_orbit_params(self) -> None:
        params = self.design_panel._controller.params
        self.orbit_widget.apply_params(params)

        for item in params.get("dropped_bubbles", []) or []:
            entry = item.get("entry")
            rtype = item.get("resource_type")
            if entry and rtype:
                self.orbit_widget.add_knowledge_point(entry, rtype)

        if self._blank:
            self.orbit_widget.set_empty_hint(
                "空白项目：填写主题 → 点核心生成（Ctrl+Enter）· "
                "需要对话 / 附件 / 模板时看下方聊天"
            )
        self._update_focus_summary()

    # ------------------------------------------------------------------ stages
    def _apply_default_stage(self) -> None:
        """Initial stage before restore_ui_state (restore may override)."""
        if self._blank:
            self.set_stage(STAGE_DRAFT, force=True)
            self._bubble_desc.setText(
                "空白 AI 项目：直接设参生成；教材知识点提取后可加入轨道聚焦。"
            )
            return
        if self._knowledge_row_count() > 0:
            self.set_stage(STAGE_KNOWLEDGE, force=True)
        else:
            self.set_stage(STAGE_MATERIAL, force=True)

    def current_stage(self) -> str:
        return self._stage

    def stage_widget(self, name: str) -> QWidget | None:
        return self._stage_widgets.get(name)

    def set_stage(self, name: str, *, force: bool = False) -> bool:
        """Switch the canvas to *name*; returns False when the leave was vetoed.

        Leaving 素材 / 知识 while textbook extraction runs asks first — the old
        three-pane canvas could simply keep the page on screen, a stage switch
        cannot.
        """
        if name not in self._stage_widgets or name == self._stage:
            return name == self._stage
        if not force and not self._confirm_leave_stage(self._stage, name):
            return False
        self._stage = name
        self._stages.setCurrentWidget(self._stage_widgets[name])
        self._update_banner()
        self.stage_changed.emit(name)
        return True

    def focus_stage(self, name: str) -> bool:
        """User-facing navigation (header lights, checklist, 「查看大纲 →」)."""
        return self.set_stage(name)

    def _confirm_leave_stage(self, current: str, target: str) -> bool:
        """Mirror of WorkshopWindow._confirm_leave_if_panel_busy for switches."""
        if current not in _EXTRACTION_STAGES or target in _EXTRACTION_STAGES:
            return True
        controller = getattr(self.import_panel, "_controller", None)
        if not getattr(controller, "is_busy", False):
            return True
        reply = QMessageBox.question(
            self,
            "仍在提取知识点",
            "正在提取知识点，离开会中断本次提取。是否继续？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if reply != QMessageBox.StandardButton.Yes:
            return False
        controller.cancel()
        return True

    def focus_left_tab(self, index: int) -> None:
        """Compat shim for the pre-stage window (0=素材, 1=知识)."""
        self.set_stage(STAGE_MATERIAL if index == 0 else STAGE_KNOWLEDGE)

    def focus_right_tab(self, index: int) -> None:
        """Compat shim: the outline and section import both live in 导入 now."""
        del index
        self.set_stage(STAGE_IMPORT)

    def focus_design_chat(self) -> None:
        self.set_stage(STAGE_DRAFT)
        self.design_focus_requested.emit()

    def focus_outline(self) -> None:
        self.set_stage(STAGE_IMPORT)

    def focus_import(self) -> None:
        self.set_stage(STAGE_IMPORT)

    def focus_knowledge(self) -> None:
        self.set_stage(STAGE_KNOWLEDGE)

    # ------------------------------------------------------------------ pool popover
    def _checked_rows(self) -> list:
        try:
            return [r for r in self.import_panel._review_table._model.rows if r.checked]
        except Exception:
            return []

    def _open_pool_popup(self) -> None:
        """Modeless pool popover over the draft stage.

        Modal would block dragging bubbles into the orbit, which is the whole
        point of the popover.
        """
        rows = self._checked_rows()
        if self._pool_popup is not None:
            self._pool_popup.close()
            self._pool_popup = None
        dlg = QDialog(self)
        dlg.setWindowTitle("气泡池 · 拖入上方轨道")
        dlg.setModal(False)
        lay = QVBoxLayout(dlg)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        holder = QWidget()
        flow = FlowLayout(holder, spacing=8)
        shown = rows[:_BUBBLE_POOL_LIMIT]
        for row in shown:
            flow.addWidget(
                KnowledgeBubble(row.entry, row.resource_type, parent=holder)
            )
        scroll.setWidget(holder)
        lay.addWidget(
            QLabel(f"已勾选 {len(rows)} 个知识点（显示前 {len(shown)} 个），拖入轨道聚焦生成：")
        )
        lay.addWidget(scroll, 1)
        add_all = QPushButton("全部加入轨道")
        add_all.setEnabled(bool(shown))
        add_all.clicked.connect(
            lambda: (self._add_rows_to_orbit(shown), dlg.close())
        )
        lay.addWidget(add_all)
        dlg.finished.connect(self._on_pool_popup_finished)
        self._pool_popup = dlg
        dlg.show()
        dlg.raise_()

    def _on_pool_popup_finished(self, _code: int = 0) -> None:
        self._pool_popup = None

    # ------------------------------------------------------------------ banner
    def _tips_dismissed(self) -> bool:
        s = QSettings(ORG_NAME, APP_NAME)
        return bool(s.value(_TIPS_DISMISSED_KEY, False))

    def _dismiss_banner(self) -> None:
        s = QSettings(ORG_NAME, APP_NAME)
        s.setValue(_TIPS_DISMISSED_KEY, True)
        self._banner.setVisible(False)

    def _banner_message(self) -> str:
        if self._tips_dismissed():
            return ""
        has_draft = bool(self.design_panel.has_draft())
        if has_draft:
            return ""
        if self._blank:
            return (
                "下一步：在上方参数带填「主题」并点「AI 核心」生成；"
                "生成后到「导入」阶段审阅结构大纲。需要对话时看下方聊天区。"
            )
        if self._chapter_count() == 0:
            return "下一步：在「素材」选择或拖入教材文件，勾选章节后提取知识点。"
        if self._knowledge_row_count() == 0:
            return "下一步：在「知识」提取并核对词汇，或直接到「草稿」生成课程。"
        return (
            "下一步：可把气泡加入轨道聚焦生成，或直接点「AI 核心」；"
            "生成后到「导入」阶段审阅并导入。"
        )

    def _update_banner(self) -> None:
        msg = self._banner_message()
        if msg:
            self._banner_label.setText(msg)
            self._banner.setVisible(True)
        else:
            self._banner.setVisible(False)

    def _chapter_count(self) -> int:
        try:
            return len(self.import_panel._controller.chapters or [])
        except Exception:
            return 0

    def _knowledge_row_count(self) -> int:
        try:
            return len(self.import_panel._review_table._model.rows)
        except Exception:
            return 0

    # ------------------------------------------------------------------ UI state
    def _settings_key(self, leaf: str) -> str:
        pid = self._project_id or "_default"
        return f"{_UI_PREFIX}/{pid}/{leaf}"

    def save_ui_state(self) -> None:
        """Persist the current stage for this project.

        The old ``left_tab`` / ``right_tab`` / ``splitter`` keys are abandoned
        (not migrated): a saved tab index has no meaning in a stage layout, and
        restoring it would drop the user on an unrelated page.
        """
        if not self._project_id:
            return
        s = QSettings(ORG_NAME, APP_NAME)
        s.setValue(self._settings_key("stage"), self._stage)

    def restore_ui_state(self) -> None:
        """Restore the stage if previously saved; keep the default otherwise."""
        if not self._project_id:
            return
        s = QSettings(ORG_NAME, APP_NAME)
        stage = s.value(self._settings_key("stage"), None)
        if isinstance(stage, str) and stage in self._stage_widgets:
            self.set_stage(stage, force=True)

    # ------------------------------------------------------------------ public
    def _update_focus_summary(self) -> None:
        """Refresh the orbit band: focused bubbles or the full project pool."""
        if self.orbit_widget.dropped_items:
            entries = []
            for item in self.orbit_widget.dropped_items:
                entry = dict(item.get("entry") or {})
                rtype = item.get("resource_type") or "word"
                kind = "grammar" if rtype == "grammarPoint" else rtype
                entry["_kind"] = kind
                entries.append(entry)
            self.orbit_widget.set_focus_summary(
                format_pool_summary(entries, focused=True)
            )
            return
        pool = self.design_panel._controller.resource_pool
        self.orbit_widget.set_focus_summary(
            format_pool_summary(pool, focused=False)
        )

    def _add_rows_to_orbit(self, rows: list) -> int:
        """Add *rows* to the orbit, returning how many were new."""
        added = 0
        for row in rows:
            before = len(self.orbit_widget.dropped_items)
            self.orbit_widget.add_knowledge_point(row.entry, row.resource_type)
            if len(self.orbit_widget.dropped_items) > before:
                added += 1
        if added:
            self.orbit_widget.prompt_label.setText(
                f"已投入 {len(self.orbit_widget.dropped_items)} 个知识点，AI 将定向生成课时"
            )
        return added

    def add_selected_to_orbit(self) -> None:
        """Add review-table selected rows to the orbit (keyboard-friendly)."""
        rows = self.import_panel._review_table.selected_rows()
        if not rows:
            # Fall back to all checked rows when nothing selected.
            rows = [r for r in self.import_panel._review_table._model.rows if r.checked]
        self._add_rows_to_orbit(rows)

    def schedule_bubble_refresh(self) -> None:
        """Debounce bubble pool rebuild (many rows_changed in a short window)."""
        self._bubble_refresh_timer.start()

    def flush_bubble_refresh(self) -> None:
        """Run pending bubble refresh immediately (tests / before teardown)."""
        self._bubble_refresh_timer.stop()
        self.refresh_bubble_pool()

    def refresh_bubble_pool(self) -> None:
        """Incremental reconcile of bubble widgets by stable key."""
        rows = self.import_panel._review_table._model.rows
        checked = [r for r in rows if r.checked]
        shown = checked[:_BUBBLE_POOL_LIMIT]
        target: dict[str, Any] = {}
        for row in shown:
            key = _bubble_key(row.resource_type, row.entry, row.chapter_index)
            # Prefer first occurrence if duplicate keys.
            target.setdefault(key, row)

        # Remove obsolete bubbles.
        for key in list(self._bubble_widgets.keys()):
            if key not in target:
                w = self._bubble_widgets.pop(key)
                self.bubble_pool_layout.removeWidget(w)
                w.deleteLater()

        # Add missing bubbles (keep existing widget instances).
        for key, row in target.items():
            if key in self._bubble_widgets:
                continue
            bubble = KnowledgeBubble(
                data=row.entry,
                resource_type=row.resource_type,
                parent=self.bubble_pool_container,
                show_close=False,
            )
            self._bubble_widgets[key] = bubble
            self.bubble_pool_layout.addWidget(bubble)

        extra = len(checked) - len(shown)
        if extra > 0:
            self._bubble_desc.setText(
                f"已显示前 {_BUBBLE_POOL_LIMIT} 个勾选知识点（另有 {extra} 个未展示）。"
                "可点「将选中词加入轨道」或在草稿阶段用「气泡池＋」："
            )
        elif not self._blank:
            self._bubble_desc.setText(
                "勾选审校表中的知识点后，会出现在这里。"
                "可点「将选中词加入轨道」或拖入草稿阶段的轨道："
            )

    # ------------------------------------------------------------------ slots
    def _on_rows_changed(self) -> None:
        # Debounce pool rebuild; stage switch / banner update stay immediate.
        self.schedule_bubble_refresh()
        count = self._knowledge_row_count()
        # First time knowledge appears while still on 素材 → jump to 知识.
        if (
            not self._auto_switched_to_knowledge
            and not self._had_knowledge_rows
            and count > 0
            and self._stage == STAGE_MATERIAL
        ):
            self.focus_knowledge()
            self._auto_switched_to_knowledge = True
        if count > 0:
            self._had_knowledge_rows = True
        self._update_banner()
        # Pool may have grown after extraction — refresh summary when not focused.
        if not self.orbit_widget.dropped_items:
            # Re-read project pool into controller when knowledge changes.
            self.design_panel.refresh_pool_from_project()
            self._update_focus_summary()

    def _on_generate_clicked(self) -> None:
        op = self.orbit_widget.params_dict()
        topic = op["topic"]
        level = op["level"]
        units = op["unit_count"]
        lessons = op["lessons_per_unit"]
        template = op["template"]
        whisper = op["extra_instructions"]
        gen_mode = op["generation_mode"]

        controller = self.design_panel._controller

        if self.orbit_widget.dropped_items:
            focused_pool = []
            for item in self.orbit_widget.dropped_items:
                entry = item["entry"]
                rtype = item["resource_type"]
                kind = "grammar" if rtype == "grammarPoint" else rtype
                focused_pool.append({**entry, "_kind": kind})
            controller.set_resource_pool(focused_pool)
            terms = [e.get("term") or e.get("title") or "" for e in focused_pool]
            if not topic:
                topic = f"聚焦学习: {', '.join(t for t in terms[:3] if t)}"
                if len(terms) > 3:
                    topic += " 等"
        else:
            self.design_panel.refresh_pool_from_project()
            if not topic:
                topic = controller.params.get("topic") or "基础会话"

        # Keep design-panel hidden mirrors in sync (chat path / tests).
        self.design_panel.apply_orbit_params(
            {
                "topic": topic,
                "level": level,
                "unit_count": units,
                "lessons_per_unit": lessons,
                "template": template,
                "extra_instructions": whisper,
                "generation_mode": gen_mode,
            }
        )

        # Advanced panel fields (brief / skip / genre) still on design panel.
        brief = ""
        skip_fix = False
        skip_explain = False
        use_genre = False
        if hasattr(self.design_panel, "_brief_edit"):
            brief = self.design_panel._brief_edit.text().strip()
        if hasattr(self.design_panel, "_skip_fix_check"):
            skip_fix = self.design_panel._skip_fix_check.isChecked()
        if hasattr(self.design_panel, "_skip_explain_check"):
            skip_explain = self.design_panel._skip_explain_check.isChecked()
        if hasattr(self.design_panel, "_template_bar"):
            use_genre = bool(self.design_panel._template_bar.is_genre_enabled())

        controller.set_params(
            topic=topic,
            level=level,
            unit_count=units,
            lessons_per_unit=lessons,
            template=template,
            extra_instructions=whisper,
            design_brief=brief,
            generation_mode=gen_mode,
            pipeline_skip_fix=skip_fix,
            pipeline_skip_explain=skip_explain,
            use_genre_batch=use_genre,
            dropped_bubbles=list(self.orbit_widget.dropped_items),
        )
        controller.generate()

    def _on_design_busy(self, busy: bool, stage_text: str) -> None:
        self.orbit_widget.set_busy(busy, stage_text)

    def _on_draft_ready(self) -> None:
        self.review_panel.refresh()
        # The outline is the result surface, and it now lives in 导入.
        self.focus_outline()
        self._update_banner()
