"""Unified Workspace Widget: material, AI Orbit, design, outline, import.

P1: empty-state banner, default focus by project type, tab/splitter persistence,
auto-switch to knowledge after extraction, and add-to-orbit without drag.
"""
from __future__ import annotations

from typing import Any

from PySide6.QtCore import Qt, QSettings, QByteArray, QTimer, Signal
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QScrollArea,
    QSplitter,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from src.backend.grounded_stats import format_pool_summary
from src.widgets.ai_orbit import AiOrbitWidget
from src.widgets.flow_layout import FlowLayout
from src.widgets.knowledge_bubble import KnowledgeBubble
from src.theme import current_palette

_BUBBLE_POOL_LIMIT = 200
_BUBBLE_DEBOUNCE_MS = 60
_TIPS_DISMISSED_KEY = "workshop/canvas_tips_dismissed"
_UI_PREFIX = "workshop/ui"


def _bubble_key(resource_type: str, entry: dict, chapter_index: int = -1) -> str:
    """Stable id for bubble pool reconcile (prefer entry id, else term+chapter)."""
    eid = entry.get("id")
    if eid:
        return f"{resource_type}:{eid}"
    term = entry.get("term") or entry.get("title") or ""
    return f"{resource_type}:{chapter_index}:{term}"


class UnifiedWorkspaceWidget(QWidget):
    """Non-step-by-step authoring canvas for one textbook/AI project."""

    design_focus_requested = Signal()

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

        self._build_ui()
        self._wire_signals()
        self._init_orbit_params()
        self.refresh_bubble_pool()
        self._apply_default_focus()
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

        self.splitter = QSplitter(Qt.Orientation.Horizontal, self)

        # --- LEFT -----------------------------------------------------------
        left_widget = QWidget()
        left_lay = QVBoxLayout(left_widget)
        left_lay.setContentsMargins(6, 6, 6, 6)

        self.left_tabs = QTabWidget()

        self._source_page = self.import_panel._stack.widget(0)
        self._knowledge_page = self.import_panel._stack.widget(1)
        self._import_page = self.import_panel._stack.widget(2)

        self.import_panel._stack.removeWidget(self._source_page)
        src_title = "教材与章节 (可选)" if self._blank else "教材与章节"
        self.left_tabs.addTab(self._source_page, src_title)

        if hasattr(self.import_panel, "_design_btn"):
            self.import_panel._design_btn.setVisible(False)
        self.import_panel._stack.removeWidget(self._knowledge_page)
        kn_title = "知识点审校 (可选)" if self._blank else "知识点审校"
        self.left_tabs.addTab(self._knowledge_page, kn_title)

        bubble_pool_widget = QWidget()
        bp_lay = QVBoxLayout(bubble_pool_widget)
        bp_lay.setContentsMargins(0, 0, 0, 0)
        self._bubble_desc = QLabel(
            "勾选审校表中的知识点后，会出现在这里。拖入中间 AI 轨道可聚焦生成："
        )
        self._bubble_desc.setWordWrap(True)
        self._bubble_desc.setStyleSheet("font-size: 11px; opacity: 0.8; margin: 4px;")
        bp_lay.addWidget(self._bubble_desc)

        orbit_row = QHBoxLayout()
        self._add_to_orbit_btn = QPushButton("将选中词加入轨道")
        self._add_to_orbit_btn.setToolTip(
            "把知识点审校表中当前选中的行加入中间 AI 轨道（无需拖拽）"
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
        self.left_tabs.addTab(bubble_pool_widget, "气泡池")

        left_lay.addWidget(self.left_tabs)
        self.splitter.addWidget(left_widget)

        # --- MIDDLE ---------------------------------------------------------
        self.orbit_widget = AiOrbitWidget(self)
        self.splitter.addWidget(self.orbit_widget)

        # --- RIGHT ----------------------------------------------------------
        right_widget = QWidget()
        right_lay = QVBoxLayout(right_widget)
        right_lay.setContentsMargins(6, 6, 6, 6)

        self.right_tabs = QTabWidget()
        self.right_tabs.addTab(self.review_panel, "结构大纲")
        self.right_tabs.addTab(self.design_panel, "对话与高级")
        self.import_panel._stack.removeWidget(self._import_page)
        self.right_tabs.addTab(self._import_page, "章节导入")

        right_lay.addWidget(self.right_tabs)
        self.splitter.addWidget(right_widget)

        # L2-5: prefer center + right; left thinner (blank projects collapse further).
        self.splitter.setStretchFactor(0, 1)
        self.splitter.setStretchFactor(1, 2)
        self.splitter.setStretchFactor(2, 3)
        layout.addWidget(self.splitter, 1)

        self._left_collapsed = False
        self._left_widget = left_widget

    def _build_banner(self) -> QFrame:
        banner = QFrame()
        banner.setObjectName("canvasBanner")
        pal = current_palette()
        banner.setStyleSheet(
            f"QFrame#canvasBanner {{"
            f"  background-color: {pal.get('ai_card_bg', '#1F232C')};"
            f"  border: 1px solid {pal.get('ai_accent_border', '#1F727E')};"
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
                "空白项目：填写主题 → 点核心生成（Ctrl+Enter）\n"
                "对话 / 附件 / 模板点「对话与高级…」"
            )
            # L2-1: blank projects start with a narrow left column.
            QTimer.singleShot(0, lambda: self.set_left_collapsed(True))
        self._update_focus_summary()

    # ------------------------------------------------------------------ focus / banner
    def _apply_default_focus(self) -> None:
        """Initial tabs before restore_ui_state (restore may override)."""
        has_draft = bool(self.design_panel.has_draft())
        has_knowledge = self._knowledge_row_count() > 0
        has_chapters = self._chapter_count() > 0

        if self._blank:
            self.left_tabs.setCurrentIndex(2)
            # L2-2: always prefer 结构大纲 on the right (empty state until draft).
            self.right_tabs.setCurrentIndex(0)
            self._bubble_desc.setText(
                "空白 AI 项目：在中间设参并生成；教材知识点提取后可拖入轨道聚焦。"
            )
            return

        if not has_chapters:
            self.left_tabs.setCurrentIndex(0)
        elif has_knowledge:
            self.left_tabs.setCurrentIndex(1)
        else:
            self.left_tabs.setCurrentIndex(0)

        # Outline is the result surface; chat is opt-in via Orbit.
        self.right_tabs.setCurrentIndex(0)

    def _tips_dismissed(self) -> bool:
        s = QSettings("Turna", "CourseEditor")
        return bool(s.value(_TIPS_DISMISSED_KEY, False))

    def _dismiss_banner(self) -> None:
        s = QSettings("Turna", "CourseEditor")
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
                "下一步：在中间填写「主题」，点「AI 核心」生成；"
                "生成后右侧「结构大纲」审阅导入。需要对话时点「对话与高级…」。"
            )
        if self._chapter_count() == 0:
            return "下一步：在左侧选择或拖入教材文件，勾选章节后提取知识点。"
        if self._knowledge_row_count() == 0:
            return "下一步：在「知识点审校」提取并核对词汇，或直接在中间生成课程。"
        return (
            "下一步：可把气泡拖入中间轨道聚焦生成，或直接点「AI 核心」；"
            "生成后在右侧「结构大纲」试做并导入。"
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
        """Persist left/right tab indices and splitter sizes for this project."""
        if not self._project_id:
            return
        s = QSettings("Turna", "CourseEditor")
        s.setValue(self._settings_key("left_tab"), self.left_tabs.currentIndex())
        s.setValue(self._settings_key("right_tab"), self.right_tabs.currentIndex())
        s.setValue(self._settings_key("splitter"), self.splitter.saveState())

    def restore_ui_state(self) -> None:
        """Restore tabs/splitter if previously saved; keep defaults otherwise."""
        if not self._project_id:
            return
        s = QSettings("Turna", "CourseEditor")
        left = s.value(self._settings_key("left_tab"), None)
        right = s.value(self._settings_key("right_tab"), None)
        if left is not None:
            try:
                idx = int(left)
                if 0 <= idx < self.left_tabs.count():
                    self.left_tabs.setCurrentIndex(idx)
            except (TypeError, ValueError):
                pass
        if right is not None:
            try:
                idx = int(right)
                if 0 <= idx < self.right_tabs.count():
                    self.right_tabs.setCurrentIndex(idx)
            except (TypeError, ValueError):
                pass
        state = s.value(self._settings_key("splitter"))
        if isinstance(state, QByteArray) and not state.isEmpty():
            self.splitter.restoreState(state)
        elif state is not None:
            # Some platforms return bytes
            try:
                ba = QByteArray(state)
                if not ba.isEmpty():
                    self.splitter.restoreState(ba)
            except Exception:
                pass

    # ------------------------------------------------------------------ public
    def _update_focus_summary(self) -> None:
        """Refresh orbit strip: focused bubbles or full project pool."""
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

    def focus_design_chat(self) -> None:
        self.right_tabs.setCurrentWidget(self.design_panel)
        self.design_focus_requested.emit()

    def focus_outline(self) -> None:
        self.right_tabs.setCurrentWidget(self.review_panel)

    def focus_import(self) -> None:
        self.right_tabs.setCurrentWidget(self._import_page)

    def focus_knowledge(self) -> None:
        self.left_tabs.setCurrentIndex(1)

    def add_selected_to_orbit(self) -> None:
        """Add review-table selected rows to the orbit (keyboard-friendly)."""
        rows = self.import_panel._review_table.selected_rows()
        if not rows:
            # Fall back to all checked rows when nothing selected.
            rows = [r for r in self.import_panel._review_table._model.rows if r.checked]
        added = 0
        for row in rows:
            before = len(self.orbit_widget.dropped_items)
            self.orbit_widget.add_knowledge_point(row.entry, row.resource_type)
            if len(self.orbit_widget.dropped_items) > before:
                added += 1
        if added:
            # Nudge user toward orbit.
            self.orbit_widget.prompt_label.setText(
                f"已投入 {len(self.orbit_widget.dropped_items)} 个知识点，AI 将定向生成课时"
            )

    def schedule_bubble_refresh(self) -> None:
        """Debounce bubble pool rebuild (many rows_changed in a short window)."""
        self._bubble_refresh_timer.start()

    def flush_bubble_refresh(self) -> None:
        """Run pending bubble refresh immediately (tests / before teardown)."""
        self._bubble_refresh_timer.stop()
        self.refresh_bubble_pool()

    def refresh_bubble_pool(self) -> None:
        """Incremental reconcile of bubble widgets by stable key (P2)."""
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
                "可点「将选中词加入轨道」或拖入中间："
            )
        elif not self._blank:
            self._bubble_desc.setText(
                "勾选审校表中的知识点后，会出现在这里。"
                "可点「将选中词加入轨道」或拖入中间 AI 轨道："
            )

    # ------------------------------------------------------------------ slots
    def _on_rows_changed(self) -> None:
        # Debounce pool rebuild; tab switch / banner update stay immediate.
        self.schedule_bubble_refresh()
        count = self._knowledge_row_count()
        # First time knowledge appears while still on material tab → jump to 审校.
        if (
            not self._auto_switched_to_knowledge
            and not self._had_knowledge_rows
            and count > 0
            and self.left_tabs.currentIndex() == 0
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
        self.focus_outline()
        self._update_banner()

    def set_left_collapsed(self, collapsed: bool) -> None:
        """L2-1: shrink left column for blank projects (still reachable)."""
        self._left_collapsed = collapsed
        sizes = self.splitter.sizes()
        if not sizes or len(sizes) < 3:
            total = max(self.width(), 900)
            if collapsed:
                self.splitter.setSizes(
                    [max(120, total // 10), total * 4 // 10, total * 5 // 10]
                )
            else:
                self.splitter.setSizes(
                    [total // 4, total * 3 // 8, total * 3 // 8]
                )
            return
        total = sum(sizes) or 900
        if collapsed:
            self.splitter.setSizes(
                [max(100, total // 12), total * 5 // 12, total // 2]
            )
        else:
            self.splitter.setSizes(
                [total // 4, total * 3 // 8, total * 3 // 8]
            )

    def focus_left_tab(self, index: int) -> None:
        if self._left_collapsed:
            self.set_left_collapsed(False)
        if 0 <= index < self.left_tabs.count():
            self.left_tabs.setCurrentIndex(index)

    def focus_right_tab(self, index: int) -> None:
        if 0 <= index < self.right_tabs.count():
            self.right_tabs.setCurrentIndex(index)
